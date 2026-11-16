import type { LlmProvider, LlmRequest, LlmResponse } from './types.js';

/** Test double: returns queued responses in order and records requests. Never used in production wiring. */
export class ScriptedLlm implements LlmProvider {
  readonly name = 'scripted';
  readonly requests: LlmRequest[] = [];
  constructor(private readonly queue: LlmResponse[]) {}
  async complete(req: LlmRequest): Promise<LlmResponse> {
    this.requests.push(structuredClone(req));
    const next = this.queue.shift();
    if (!next) throw new Error('ScriptedLlm: queue exhausted');
    return next;
  }
}
