import { describe, expect, it } from 'vitest';
import { computeVerification, extractJson, runChat, summarise, type ChatEvent } from '../src/brain/chat.js';
import { estimateTokens, fillPrompt, promptVersion, trimHistory } from '../src/brain/context.js';
import { ChatRequestSchema } from '../src/brain/schema.js';
import { ServiceError } from '../src/errors.js';
import { ScriptedLlm } from '../src/providers/llm/scripted.js';
import type { LlmResponse } from '../src/providers/llm/types.js';
import { FakeSearch, PROMPT, fakeWeather, goodReply, replyCall } from './helpers.js';

const req = (message = 'salam', extra: Record<string, unknown> = {}) => ChatRequestSchema.parse({ message, ...extra });

async function run(script: LlmResponse[], opts: { search?: FakeSearch | null; message?: string } = {}) {
  const llm = new ScriptedLlm(script);
  const events: ChatEvent[] = [];
  let error: unknown;
  try {
    for await (const e of runChat(req(opts.message), {
      llm,
      search: opts.search ?? null,
      weather: fakeWeather,
      promptTemplate: PROMPT,
      tokenBudget: 3000,
      maxOutputTokens: 500,
    })) events.push(e);
  } catch (e) {
    error = e;
  }
  const final = events.find((e) => e.type === 'final');
  return { llm, events, error, final: final?.type === 'final' ? final.reply : undefined };
}

const search = (n: number) =>
  new FakeSearch(
    Array.from({ length: n }, (_, i) => ({ title: `T${i}`, url: `https://site${i}.ma/a`, snippet: 's', date: '2026-11-15' })),
  );

describe('runChat', () => {
  it('returns a validated final reply', async () => {
    const { final, events } = await run([replyCall(goodReply)]);
    expect(events[0]).toEqual({ type: 'status', phase: 'thinking' });
    expect(final?.display_text).toBe(goodReply.display_text);
    expect(final?.verification).toBe('none');
    expect(final?.sources).toEqual([]);
  });

  it('retries exactly once on invalid output, feeding back the error', async () => {
    const { final, llm, events } = await run([replyCall({ ...goodReply, emotion: 'ecstatic' }), replyCall(goodReply, 'r2')]);
    expect(final).toBeDefined();
    expect(events.some((e) => e.type === 'status' && e.phase === 'retrying')).toBe(true);
    const lastMsg = llm.requests[1]!.messages.at(-1)!;
    expect(lastMsg.content[0]).toMatchObject({ type: 'tool_result', tool_use_id: 'r1', is_error: true });
  });

  it('fails with invalid_output after a second invalid reply', async () => {
    const { error } = await run([replyCall({ ...goodReply, language: 'x' }), replyCall({ ...goodReply, language: 'y' })]);
    expect(error).toBeInstanceOf(ServiceError);
    expect((error as ServiceError).code).toBe('invalid_output');
  });

  it('accepts JSON in plain text as a fallback', async () => {
    const { final } = await run([{ content: [{ type: 'text', text: `Here: ${JSON.stringify(goodReply)}` }], stopReason: 'end' }]);
    expect(final?.emotion).toBe('happy');
  });

  it('search: numbers results, cites only referenced ids, confirms with 2+ domains', async () => {
    const s = search(3);
    const { final, events } = await run(
      [
        { content: [{ type: 'tool_use', id: 's1', name: 'web_search', input: { query: 'akhbar lmaghrib', freshness: 'pd' } }], stopReason: 'tool_use' },
        replyCall({ ...goodReply, source_ids: [1, 3], sources_agree: true }),
      ],
      { search: s },
    );
    expect(s.queries).toEqual(['akhbar lmaghrib']);
    expect(events.some((e) => e.type === 'status' && e.phase === 'searching')).toBe(true);
    expect(final?.sources.map((x) => x.id)).toEqual([1, 3]);
    expect(final?.verification).toBe('confirmed');
    expect(final?.used_tools).toEqual(['web_search']);
  });

  it('search with a single source is unconfirmed; invented ids are dropped', async () => {
    const { final } = await run(
      [
        { content: [{ type: 'tool_use', id: 's1', name: 'web_search', input: { query: 'q' } }], stopReason: 'tool_use' },
        replyCall({ ...goodReply, source_ids: [1, 99] }),
      ],
      { search: search(1) },
    );
    expect(final?.sources.map((x) => x.id)).toEqual([1]);
    expect(final?.verification).toBe('unconfirmed');
  });

  it('search not configured: tells the model and flags search_unavailable', async () => {
    const { final, llm } = await run([
      { content: [{ type: 'tool_use', id: 's1', name: 'web_search', input: { query: 'q' } }], stopReason: 'tool_use' },
      replyCall(goodReply),
    ]);
    expect(final?.search_unavailable).toBe(true);
    const toolResult = llm.requests[1]!.messages.at(-1)!.content[0];
    expect(toolResult).toMatchObject({ type: 'tool_result', is_error: true });
    expect(JSON.stringify(toolResult)).toContain('search_not_configured');
  });

  it('search failure is reported, not hidden', async () => {
    const { final } = await run(
      [
        { content: [{ type: 'tool_use', id: 's1', name: 'web_search', input: { query: 'q' } }], stopReason: 'tool_use' },
        replyCall(goodReply),
      ],
      { search: new FakeSearch(new ServiceError('upstream_timeout', 't', 504)) },
    );
    expect(final?.search_unavailable).toBe(true);
  });

  it('weather adds a data source that is always shown', async () => {
    const { final, events } = await run([
      { content: [{ type: 'tool_use', id: 'w1', name: 'get_weather', input: { city: 'Casablanca' } }], stopReason: 'tool_use' },
      replyCall(goodReply),
    ]);
    expect(events.some((e) => e.type === 'status' && e.phase === 'weather')).toBe(true);
    expect(final?.sources).toHaveLength(1);
    expect(final?.sources[0]!.kind).toBe('data');
    expect(final?.verification).toBe('data');
  });

  it('gives up after too many tool steps', async () => {
    const loop: LlmResponse = { content: [{ type: 'tool_use', id: 'w', name: 'get_weather', input: { city: 'Rabat' } }], stopReason: 'tool_use' };
    const { error } = await run([loop, loop, loop, loop, loop, loop]);
    expect((error as ServiceError).code).toBe('invalid_output');
  });

  it('merges consecutive same-role turns (Anthropic alternation)', async () => {
    const llm = new ScriptedLlm([replyCall(goodReply)]);
    const r = ChatRequestSchema.parse({ message: 'b', history: [{ role: 'user', text: 'a' }] });
    for await (const _ of runChat(r, { llm, search: null, weather: fakeWeather, promptTemplate: PROMPT, tokenBudget: 3000, maxOutputTokens: 100 })) void _;
    expect(llm.requests[0]!.messages).toHaveLength(1);
    expect(llm.requests[0]!.messages[0]!.content).toHaveLength(2);
  });
});

describe('helpers', () => {
  it('extractJson', () => {
    expect(extractJson('blah {"a":1} blah')).toEqual({ a: 1 });
    expect(extractJson('no json')).toBeUndefined();
    expect(extractJson('{broken')).toBeUndefined();
  });
  it('computeVerification', () => {
    const web = (d: string, id: number) => ({ id, title: 't', url: `https://${d}/x`, kind: 'web' as const });
    expect(computeVerification([], undefined, false)).toBe('none');
    expect(computeVerification([], undefined, true)).toBe('unconfirmed');
    expect(computeVerification([web('a.ma', 1), web('www.a.ma', 2)], true, true)).toBe('unconfirmed');
    expect(computeVerification([web('a.ma', 1), web('b.ma', 2)], false, true)).toBe('unconfirmed');
    expect(computeVerification([web('a.ma', 1), web('b.ma', 2)], undefined, true)).toBe('confirmed');
  });
  it('trimHistory keeps the newest turns within budget', () => {
    const h = Array.from({ length: 20 }, (_, i) => ({ role: (i % 2 ? 'assistant' : 'user') as 'user' | 'assistant', text: `turn ${i} ${'x'.repeat(200)}` }));
    const t = trimHistory(h, 300);
    expect(t.length).toBeLessThan(20);
    expect(t.at(-1)!.text.startsWith('turn 19')).toBe(true);
    expect(estimateTokens('abcd')).toBeGreaterThan(0);
  });
  it('fillPrompt substitutes settings and never leaves placeholders', () => {
    const p = fillPrompt(PROMPT, req('x', { settings: { reply_language: 'fr', darija_script: 'latin' }, client: { local_time: '2026-11-16T10:00' } }));
    expect(p).toContain('fr (French)');
    expect(p).toContain('native script');
    expect(p).not.toMatch(/\{\{/);
  });
  it('promptVersion reads the header comment; the comment is stripped from the prompt', () => {
    expect(promptVersion(PROMPT)).toBe('9.9.9');
    expect(promptVersion('no header')).toBe('unknown');
    expect(fillPrompt(PROMPT, req())).not.toContain('prompt-version');
  });
  it('memory facts only appear when sent (consent is enforced by the app)', () => {
    expect(fillPrompt(PROMPT, req())).toContain('Do not pretend to remember');
    expect(fillPrompt(PROMPT, req('x', { memory: { facts: ['likes atay'] } }))).toContain('likes atay');
  });
  it('the shipped prompt fills every placeholder', async () => {
    const { readFileSync } = await import('node:fs');
    const real = readFileSync(new URL('../prompts/sahbi.md', import.meta.url), 'utf8');
    expect(promptVersion(real)).not.toBe('unknown');
    expect(fillPrompt(real, req('x', { summary: 's', memory: { facts: ['f'] } }))).not.toMatch(/\{\{[A-Z_]+\}\}/);
  });
  it('summarise returns text and rejects empty output', async () => {
    const ok = new ScriptedLlm([{ content: [{ type: 'text', text: 'User likes tea.' }], stopReason: 'end' }]);
    expect(await summarise(ok, undefined, [{ role: 'user', text: 'I like tea' }], 500)).toBe('User likes tea.');
    const empty = new ScriptedLlm([{ content: [], stopReason: 'end' }]);
    await expect(summarise(empty, undefined, [{ role: 'user', text: 'x' }], 500)).rejects.toBeInstanceOf(ServiceError);
  });
});
