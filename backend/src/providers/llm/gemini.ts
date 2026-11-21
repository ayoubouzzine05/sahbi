import { expectOk, type FetchLike } from '../../http.js';
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
  | { inlineData: { mimeType: string; data: string } }
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
      } else if (b.type === 'image') {
        parts.push({ inlineData: { mimeType: b.mime, data: b.data } });
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
      /** Start the next model in parallel when no answer after this many ms (0 = off). */
      hedgeMs?: number;
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
   * Hedged: when a model has not answered after `hedgeMs`, the next model is
   * started in parallel and the first good answer wins (the other request is
   * aborted). A failed model (429/404/5xx, timeout) fails over at once.
   * Auth/request errors (400/401/403) are returned as-is — another model won't help.
   */
  private post(body: unknown): Promise<Response> {
    const models = this.models;
    const hedgeMs = this.opts.hedgeMs ?? 0;
    const payload = JSON.stringify(body);
    return new Promise<Response>((resolve, reject) => {
      let next = 0;
      let inflight = 0;
      let done = false;
      let lastErr: unknown = new ServiceError('upstream_error', 'LLM unavailable', 502);
      let hedge: ReturnType<typeof setTimeout> | undefined;
      const ctrls = new Set<AbortController>();
      const failover = () => {
        if (done) return;
        if (!launch() && inflight === 0) {
          done = true;
          clearTimeout(hedge);
          reject(lastErr);
        }
      };
      const launch = (): boolean => {
        if (done || next >= models.length) return false;
        const model = models[next++]!;
        inflight++;
        const ctrl = new AbortController();
        ctrls.add(ctrl);
        const timer = setTimeout(() => ctrl.abort(), this.opts.timeoutMs);
        this.fetchImpl(generateContentUrl(this.opts.baseUrl, model), {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'x-goog-api-key': this.opts.apiKey },
          body: payload,
          signal: ctrl.signal,
        }).then(
          (res) => {
            clearTimeout(timer);
            inflight--;
            if (done) return;
            const retryable = res.status === 429 || res.status === 404 || res.status >= 500;
            if (retryable && (next < models.length || inflight > 0)) {
              lastErr = new ServiceError('upstream_error', `LLM returned HTTP ${res.status}`, 502);
              void res.body?.cancel().catch(() => undefined);
              failover();
              return;
            }
            this.lastModel = model;
            done = true;
            clearTimeout(hedge);
            for (const c of ctrls) if (c !== ctrl) c.abort();
            resolve(res);
          },
          (err: unknown) => {
            clearTimeout(timer);
            inflight--;
            if (done) return;
            const aborted = err instanceof Error && err.name === 'AbortError';
            lastErr = new ServiceError(aborted ? 'upstream_timeout' : 'upstream_error', aborted ? 'Upstream timed out' : 'Upstream unreachable', aborted ? 504 : 502);
            failover();
          },
        );
        clearTimeout(hedge);
        if (hedgeMs > 0 && next < models.length) hedge = setTimeout(() => launch(), hedgeMs);
        return true;
      };
      launch();
    });
  }

  /** Model that produced the last successful response (for diagnostics). */
  lastModel = '';

  /** Times a tiny request on every model in parallel (no user content). */
  async probe(): Promise<Array<{ model: string; status: number | string; ms: number; detail?: string }>> {
    const level = thinkingLevel(this.opts.reasoningEffort);
    const body = JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: 'Reply with the single word: ok' }] }],
      generationConfig: { maxOutputTokens: 256, ...(level ? { thinkingConfig: { thinkingLevel: level } } : {}) },
    });
    return Promise.all(
      this.models.map(async (model) => {
        const t0 = Date.now();
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), 30000);
        try {
          const res = await this.fetchImpl(generateContentUrl(this.opts.baseUrl, model), {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'x-goog-api-key': this.opts.apiKey },
            body,
            signal: ctrl.signal,
          });
          let detail: string | undefined;
          if (!res.ok) {
            try {
              const j = (await res.json()) as { error?: { status?: string; message?: string } };
              detail = [j.error?.status, j.error?.message?.slice(0, 120)].filter(Boolean).join(': ');
            } catch {
              /* not JSON */
            }
          } else {
            await res.arrayBuffer();
          }
          return { model, status: res.status, ms: Date.now() - t0, ...(detail ? { detail } : {}) };
        } catch (err) {
          return { model, status: err instanceof Error && err.name === 'AbortError' ? 'timeout' : 'error', ms: Date.now() - t0 };
        } finally {
          clearTimeout(timer);
        }
      }),
    );
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
