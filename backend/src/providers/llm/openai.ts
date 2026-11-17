import { expectOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { ServiceError } from '../../errors.js';
import type { Block, LlmMessage, LlmProvider, LlmRequest, LlmResponse } from './types.js';

type OaMessage =
  | { role: 'system' | 'user'; content: string }
  | { role: 'assistant'; content: string | null; tool_calls?: Array<{ id: string; type: 'function'; function: { name: string; arguments: string } }> }
  | { role: 'tool'; tool_call_id: string; content: string };

/** Maps the neutral conversation to the OpenAI Chat Completions format. */
export function toOpenAiMessages(system: string, messages: LlmMessage[]): OaMessage[] {
  const out: OaMessage[] = [{ role: 'system', content: system }];
  for (const m of messages) {
    if (m.role === 'user') {
      const results = m.content.filter((b): b is Extract<Block, { type: 'tool_result' }> => b.type === 'tool_result');
      for (const r of results) out.push({ role: 'tool', tool_call_id: r.tool_use_id, content: r.content });
      const text = m.content.filter((b) => b.type === 'text').map((b) => (b as { text: string }).text).join('\n');
      if (text) out.push({ role: 'user', content: text });
    } else {
      const text = m.content.filter((b) => b.type === 'text').map((b) => (b as { text: string }).text).join('\n');
      const calls = m.content
        .filter((b): b is Extract<Block, { type: 'tool_use' }> => b.type === 'tool_use')
        .map((b) => ({ id: b.id, type: 'function' as const, function: { name: b.name, arguments: JSON.stringify(b.input) } }));
      out.push({ role: 'assistant', content: text || null, ...(calls.length ? { tool_calls: calls } : {}) });
    }
  }
  return out;
}

/**
 * Chat Completions URL for a base URL.
 * - `https://api.openai.com`                                   → `/v1/chat/completions`
 * - `https://api.groq.com/openai`                              → `/v1/chat/completions`
 * - versioned bases such as `https://api.openai.com/v1` or Gemini's
 *   `https://generativelanguage.googleapis.com/v1beta/openai/` → `/chat/completions`
 */
export function chatCompletionsUrl(baseUrl: string): string {
  const base = baseUrl.replace(/\/+$/, '');
  return /\/v\d+[a-z0-9]*(\/openai)?$/i.test(base) ? `${base}/chat/completions` : `${base}/v1/chat/completions`;
}

/** True for OpenAI itself; compatible gateways (Gemini, Groq, OpenRouter…) get `max_tokens`. */
export function isOfficialOpenAi(baseUrl: string): boolean {
  try {
    return new URL(baseUrl).hostname === 'api.openai.com';
  } catch {
    return false;
  }
}

/** OpenAI Chat Completions adapter (also works with compatible gateways via LLM_BASE_URL). */
export class OpenAiProvider implements LlmProvider {
  readonly name = 'openai';
  constructor(
    private readonly opts: { apiKey: string; model: string; baseUrl: string; timeoutMs: number; reasoningEffort?: string },
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async complete(req: LlmRequest): Promise<LlmResponse> {
    const body = {
      model: this.opts.model,
      // OpenAI deprecated max_tokens for max_completion_tokens; compatible gateways
      // (e.g. Gemini's OpenAI layer) document max_tokens.
      ...(isOfficialOpenAi(this.opts.baseUrl) ? { max_completion_tokens: req.maxTokens } : { max_tokens: req.maxTokens }),
      ...(this.opts.reasoningEffort ? { reasoning_effort: this.opts.reasoningEffort } : {}),
      messages: toOpenAiMessages(req.system, req.messages),
      ...(req.tools.length
        ? { tools: req.tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.input_schema } })) }
        : {}),
    };
    const res = await fetchWithRetry(
      this.fetchImpl,
      chatCompletionsUrl(this.opts.baseUrl),
      { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${this.opts.apiKey}` }, body: JSON.stringify(body) },
      { timeoutMs: this.opts.timeoutMs },
    );
    await expectOk(res, 'LLM');
    const json = (await res.json()) as {
      choices?: Array<{ finish_reason?: string; message?: { content?: string | null; tool_calls?: Array<{ id: string; function: { name: string; arguments: string } }> } }>;
    };
    const choice = json.choices?.[0];
    if (!choice?.message) throw new ServiceError('upstream_error', 'LLM response had no message');
    const content: Block[] = [];
    if (choice.message.content) content.push({ type: 'text', text: choice.message.content });
    for (const c of choice.message.tool_calls ?? []) {
      let input: Record<string, unknown>;
      try {
        input = JSON.parse(c.function.arguments) as Record<string, unknown>;
      } catch {
        input = { __invalid_json: true };
      }
      content.push({ type: 'tool_use', id: c.id, name: c.function.name, input });
    }
    const fr = choice.finish_reason;
    return { content, stopReason: fr === 'tool_calls' ? 'tool_use' : fr === 'stop' ? 'end' : fr === 'length' ? 'max_tokens' : 'other' };
  }
}
