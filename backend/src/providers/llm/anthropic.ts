import { expectOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { ServiceError } from '../../errors.js';
import type { Block, LlmProvider, LlmRequest, LlmResponse } from './types.js';

/**
 * Anthropic Messages API adapter (https://docs.anthropic.com/en/api/messages).
 * Model name comes from LLM_MODEL; nothing is hard-coded.
 */
export class AnthropicProvider implements LlmProvider {
  readonly name = 'anthropic';
  constructor(
    private readonly opts: { apiKey: string; model: string; baseUrl: string; timeoutMs: number },
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async complete(req: LlmRequest): Promise<LlmResponse> {
    const body = {
      model: this.opts.model,
      max_tokens: req.maxTokens,
      system: req.system,
      messages: req.messages.map((m) => ({
        role: m.role,
        content: m.content.map((b) => (b.type === 'image' ? { type: 'image', source: { type: 'base64', media_type: b.mime, data: b.data } } : b)),
      })),
      ...(req.tools.length ? { tools: req.tools } : {}),
    };
    const res = await fetchWithRetry(
      this.fetchImpl,
      `${this.opts.baseUrl.replace(/\/$/, '')}/v1/messages`,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-api-key': this.opts.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify(body),
      },
      { timeoutMs: this.opts.timeoutMs },
    );
    await expectOk(res, 'LLM');
    const json = (await res.json()) as { content?: unknown[]; stop_reason?: string };
    if (!Array.isArray(json.content)) throw new ServiceError('upstream_error', 'LLM response had no content');
    const content: Block[] = [];
    for (const raw of json.content as Array<Record<string, unknown>>) {
      if (raw.type === 'text' && typeof raw.text === 'string') content.push({ type: 'text', text: raw.text });
      if (raw.type === 'tool_use' && typeof raw.id === 'string' && typeof raw.name === 'string') {
        content.push({ type: 'tool_use', id: raw.id, name: raw.name, input: (raw.input as Record<string, unknown>) ?? {} });
      }
    }
    const stop = json.stop_reason === 'tool_use' ? 'tool_use' : json.stop_reason === 'end_turn' ? 'end' : json.stop_reason === 'max_tokens' ? 'max_tokens' : 'other';
    return { content, stopReason: stop };
  }
}
