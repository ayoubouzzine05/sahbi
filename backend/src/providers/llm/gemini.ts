import { expectOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { ServiceError } from '../../errors.js';
import type { Block, LlmMessage, LlmProvider, LlmRequest, LlmResponse } from './types.js';

/**
 * Native Gemini API adapter (POST /v1beta/models/{model}:generateContent,
 * key in the `x-goog-api-key` header).
 *
 * Why native and not the OpenAI-compatible layer: since 2026-05-28 AI Studio
 * issues "auth keys" (prefix `AQ.`), and there are reports that these keys are
 * rejected on `/v1beta/openai/` with `Authorization: Bearer` while working on
 * the native endpoint. Reference: https://ai.google.dev/api/generate-content
 */
type GPart =
  | { text: string; thought?: boolean; thoughtSignature?: string }
  | { functionCall: { name: string; args?: Record<string, unknown>; id?: string }; thoughtSignature?: string }
  | { functionResponse: { name: string; response: Record<string, unknown>; id?: string } };
interface GContent {
  role: 'user' | 'model';
  parts: GPart[];
}

export const GEMINI_DEFAULT_BASE = 'https://generativelanguage.googleapis.com';

export function generateContentUrl(baseUrl: string, model: string): string {
  const base = baseUrl.replace(/\/+$/, '').replace(/\/v1beta(\/openai)?$/i, '');
  return `${base}/v1beta/models/${encodeURIComponent(model)}:generateContent`;
}

/** Maps reasoning effort ('low', 'medium'…) to Gemini 3 thinking levels. */
export function thinkingLevel(effort?: string): string | undefined {
  const e = (effort ?? '').trim().toUpperCase();
  return ['MINIMAL', 'LOW', 'MEDIUM', 'HIGH', 'XHIGH'].includes(e) ? e : undefined;
}

/** Maps the neutral conversation to Gemini `contents`. */
export function toGeminiContents(messages: LlmMessage[]): GContent[] {
  const names = new Map<string, string>();
  const out: GContent[] = [];
  for (const m of messages) {
    const parts: GPart[] = [];
    for (const b of m.content) {
      if (b.type === 'text') {
        if (b.text) parts.push({ text: b.text });
      } else if (b.type === 'tool_use') {
        names.set(b.id, b.name);
        parts.push({ functionCall: { name: b.name, args: b.input, id: b.id }, ...(b.signature ? { thoughtSignature: b.signature } : {}) });
      } else {
        const name = names.get(b.tool_use_id) ?? 'tool';
        parts.push({ functionResponse: { name, id: b.tool_use_id, response: b.is_error ? { error: b.content } : { result: b.content } } });
      }
    }
    if (parts.length) out.push({ role: m.role === 'assistant' ? 'model' : 'user', parts });
  }
  return out;
}

let callSeq = 0;

export class GeminiProvider implements LlmProvider {
  readonly name = 'gemini';
  constructor(
    private readonly opts: {
      apiKey: string;
      model: string;
      baseUrl: string;
      timeoutMs: number;
      reasoningEffort?: string;
      /** Tried in order when a model is overloaded (429/5xx), times out, or is unknown (404). */
      fallbackModels?: string[];
    },
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  /** Primary model first, then distinct fallbacks. */
  get models(): string[] {
    return [...new Set([this.opts.model, ...(this.opts.fallbackModels ?? [])].filter(Boolean))];
  }

  /**
   * One attempt per model (no same-model retries): on the free tier a busy
   * model tends to stay busy for a while, so moving on answers faster.
   * Auth/request errors (400/401/403) stop immediately — another model won't help.
   */
  private async post(body: unknown): Promise<Response> {
    const models = this.models;
    let lastErr: unknown;
    for (const [i, model] of models.entries()) {
      const last = i === models.length - 1;
      try {
        const res = await fetchWithRetry(
          this.fetchImpl,
          generateContentUrl(this.opts.baseUrl, model),
          { method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': this.opts.apiKey }, body: JSON.stringify(body) },
          { timeoutMs: this.opts.timeoutMs, retries: 0 },
        );
        if (!last && (res.status === 429 || res.status === 404 || res.status >= 500)) {
          lastErr = new ServiceError('upstream_error', `LLM returned HTTP ${res.status}`, 502);
          continue;
        }
        return res;
      } catch (err) {
        lastErr = err;
        if (last) throw err;
      }
    }
    throw lastErr instanceof Error ? lastErr : new ServiceError('upstream_error', 'LLM unavailable', 502);
  }

  async complete(req: LlmRequest): Promise<LlmResponse> {
    const level = thinkingLevel(this.opts.reasoningEffort);
    const body = {
      systemInstruction: { parts: [{ text: req.system }] },
      contents: toGeminiContents(req.messages),
      ...(req.tools.length
        ? { tools: [{ functionDeclarations: req.tools.map((t) => ({ name: t.name, description: t.description, parametersJsonSchema: t.input_schema })) }] }
        : {}),
      generationConfig: { maxOutputTokens: req.maxTokens, ...(level ? { thinkingConfig: { thinkingLevel: level } } : {}) },
    };
    const res = await this.post(body);
    await expectOk(res, 'LLM');
    const json = (await res.json()) as {
      candidates?: Array<{ finishReason?: string; content?: { parts?: Array<Record<string, unknown>> } }>;
      promptFeedback?: { blockReason?: string };
    };
    const cand = json.candidates?.[0];
    if (!cand) throw new ServiceError('upstream_error', json.promptFeedback?.blockReason ? 'LLM blocked the prompt' : 'LLM response had no candidates');
    const content: Block[] = [];
    let pendingSig: string | undefined;
    for (const p of cand.content?.parts ?? []) {
      const sig = typeof p.thoughtSignature === 'string' ? p.thoughtSignature : undefined;
      if (p.thought === true) {
        pendingSig = sig ?? pendingSig; // never surface thoughts; keep a signature if one is attached
        continue;
      }
      const fc = p.functionCall as { name?: string; args?: Record<string, unknown>; id?: string } | undefined;
      if (fc?.name) {
        const signature = sig ?? pendingSig;
        pendingSig = undefined;
        content.push({ type: 'tool_use', id: fc.id || `gc_${Date.now().toString(36)}_${++callSeq}`, name: fc.name, input: fc.args ?? {}, ...(signature ? { signature } : {}) });
      } else if (typeof p.text === 'string' && p.text) {
        content.push({ type: 'text', text: p.text });
      }
    }
    const fr = cand.finishReason;
    const stopReason = content.some((b) => b.type === 'tool_use') ? 'tool_use' : fr === 'STOP' ? 'end' : fr === 'MAX_TOKENS' ? 'max_tokens' : 'other';
    return { content, stopReason };
  }
}
