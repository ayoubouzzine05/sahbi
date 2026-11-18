import { describe, expect, it } from 'vitest';
import { GeminiProvider, generateContentUrl, thinkingLevel, toGeminiContents } from '../src/providers/llm/gemini.js';
import type { LlmMessage } from '../src/providers/llm/types.js';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const opts = { apiKey: 'AQ.AbKEY', model: 'gemini-3.8-flash', baseUrl: 'https://generativelanguage.googleapis.com', timeoutMs: 5000, reasoningEffort: 'low' };

describe('gemini helpers', () => {
  it('builds the native generateContent URL from any Google base', () => {
    const u = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent';
    expect(generateContentUrl('https://generativelanguage.googleapis.com', 'gemini-3.8-flash')).toBe(u);
    expect(generateContentUrl('https://generativelanguage.googleapis.com/', 'gemini-3.8-flash')).toBe(u);
    expect(generateContentUrl('https://generativelanguage.googleapis.com/v1beta/openai/', 'gemini-3.8-flash')).toBe(u);
  });
  it('maps reasoning effort to thinking levels', () => {
    expect(thinkingLevel('low')).toBe('LOW');
    expect(thinkingLevel('minimal')).toBe('MINIMAL');
    expect(thinkingLevel('')).toBeUndefined();
    expect(thinkingLevel('bogus')).toBeUndefined();
  });
  it('maps tool turns with names, ids and thought signatures', () => {
    const msgs: LlmMessage[] = [
      { role: 'user', content: [{ type: 'text', text: 'jaw?' }] },
      { role: 'assistant', content: [{ type: 'tool_use', id: 'c1', name: 'get_weather', input: { city: 'Rabat' }, signature: 'SIG' }] },
      { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'c1', content: '{"t":20}' }, { type: 'text', text: 'w daba?' }] },
    ];
    expect(toGeminiContents(msgs)).toEqual([
      { role: 'user', parts: [{ text: 'jaw?' }] },
      { role: 'model', parts: [{ functionCall: { name: 'get_weather', args: { city: 'Rabat' }, id: 'c1' }, thoughtSignature: 'SIG' }] },
      { role: 'user', parts: [{ functionResponse: { name: 'get_weather', id: 'c1', response: { result: '{"t":20}' } } }, { text: 'w daba?' }] },
    ]);
  });
});

describe('GeminiProvider', () => {
  it('sends the key in x-goog-api-key (works with AQ. auth keys), system instruction, tools and thinking level', async () => {
    let url = '';
    let headers: Record<string, string> = {};
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- loose view of the JSON request body
    let body: Record<string, any> = {};
    const fake = (async (u: string, init: RequestInit) => {
      url = u;
      headers = init.headers as Record<string, string>;
      body = JSON.parse(init.body as string);
      return json({ candidates: [{ finishReason: 'STOP', content: { role: 'model', parts: [{ text: 'thinking…', thought: true }, { text: '{"display_text":"salam"}' }] } }] });
    }) as unknown as typeof fetch;
    const r = await new GeminiProvider(opts, fake).complete({
      system: 'SYS',
      messages: [{ role: 'user', content: [{ type: 'text', text: 'salam' }] }],
      tools: [{ name: 'web_search', description: 'd', input_schema: { type: 'object', properties: { q: { type: 'string' } } } }],
      maxTokens: 321,
    });
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent');
    expect(headers['x-goog-api-key']).toBe('AQ.AbKEY');
    expect(headers.authorization).toBeUndefined();
    expect(body.systemInstruction).toEqual({ parts: [{ text: 'SYS' }] });
    expect(body.tools[0].functionDeclarations[0].name).toBe('web_search');
    expect(body.tools[0].functionDeclarations[0].parametersJsonSchema.type).toBe('object');
    expect(body.generationConfig).toEqual({ maxOutputTokens: 321, thinkingConfig: { thinkingLevel: 'LOW' } });
    expect(r).toEqual({ content: [{ type: 'text', text: '{"display_text":"salam"}' }], stopReason: 'end' });
  });

  it('returns function calls with their thought signature and a generated id when absent', async () => {
    const fake = (async () =>
      json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ functionCall: { name: 'get_weather', args: { city: 'Fes' } }, thoughtSignature: 'S1' }] } }] })) as unknown as typeof fetch;
    const r = await new GeminiProvider(opts, fake).complete({ system: 's', messages: [{ role: 'user', content: [{ type: 'text', text: 'x' }] }], tools: [], maxTokens: 10 });
    expect(r.stopReason).toBe('tool_use');
    const b = r.content[0] as { type: string; name: string; input: unknown; signature?: string; id: string };
    expect(b).toMatchObject({ type: 'tool_use', name: 'get_weather', input: { city: 'Fes' }, signature: 'S1' });
    expect(b.id).toMatch(/^gc_/);
  });

  it('maps MAX_TOKENS and reports blocked prompts / HTTP errors without echoing bodies', async () => {
    const mt = (async () => json({ candidates: [{ finishReason: 'MAX_TOKENS', content: { parts: [{ text: '{"dis' }] } }] })) as unknown as typeof fetch;
    expect((await new GeminiProvider(opts, mt).complete({ system: 's', messages: [], tools: [], maxTokens: 1 })).stopReason).toBe('max_tokens');
    const blocked = (async () => json({ promptFeedback: { blockReason: 'SAFETY' } })) as unknown as typeof fetch;
    await expect(new GeminiProvider(opts, blocked).complete({ system: 's', messages: [], tools: [], maxTokens: 1 })).rejects.toThrow('LLM blocked the prompt');
    const bad = (async () => json({ error: { message: 'API key not valid. secret user text' } }, 400)) as unknown as typeof fetch;
    await expect(new GeminiProvider(opts, bad).complete({ system: 's', messages: [], tools: [], maxTokens: 1 })).rejects.toThrow('LLM returned HTTP 400');
  });
});
