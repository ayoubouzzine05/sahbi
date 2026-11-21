import { describe, expect, it } from 'vitest';
import { loadConfig, isSttConfigured } from '../src/config.js';
import { GeminiProvider } from '../src/providers/llm/gemini.js';
import { GeminiSttProvider, cleanTranscript, sttInstruction } from '../src/providers/stt/gemini.js';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const ok = (text: string) => json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text }] } }] });
const base = { apiKey: 'AQ.k', baseUrl: 'https://g', timeoutMs: 3000, reasoningEffort: 'low' };
const modelOf = (u: string) => decodeURIComponent(/models\/([^:]+):/.exec(u)![1]!);
const req = { system: 's', messages: [{ role: 'user' as const, content: [{ type: 'text' as const, text: 'salam' }] }], tools: [], maxTokens: 100 };

/** fetch that answers each model after a delay; aborts are honoured. */
function slowFetch(plan: Record<string, { ms: number; res: () => Response }>, calls: string[], aborted: string[]) {
  return ((u: string, init?: RequestInit) => {
    const m = modelOf(u);
    calls.push(m);
    return new Promise<Response>((resolve, reject) => {
      const t = setTimeout(() => resolve(plan[m]!.res()), plan[m]!.ms);
      init?.signal?.addEventListener('abort', () => {
        clearTimeout(t);
        aborted.push(m);
        const e = new Error('aborted');
        e.name = 'AbortError';
        reject(e);
      });
    });
  }) as unknown as typeof fetch;
}

describe('hedged chat requests (slow first model)', () => {
  it('starts the next model after hedgeMs; the first good answer wins and the slow one is aborted', async () => {
    const calls: string[] = [];
    const aborted: string[] = [];
    const f = slowFetch({ slow: { ms: 2000, res: () => ok('slow') }, fast: { ms: 30, res: () => ok('fast') } }, calls, aborted);
    const p = new GeminiProvider({ ...base, model: 'slow', fallbackModels: ['fast'], hedgeMs: 100 }, f);
    const t0 = Date.now();
    const r = await p.complete(req);
    expect(Date.now() - t0).toBeLessThan(1000);
    expect(r.content).toEqual([{ type: 'text', text: 'fast' }]);
    expect(calls).toEqual(['slow', 'fast']);
    expect(aborted).toEqual(['slow']);
    expect(p.lastModel).toBe('fast');
  });

  it('no hedge when the first model answers in time', async () => {
    const calls: string[] = [];
    const f = slowFetch({ a: { ms: 20, res: () => ok('A') }, b: { ms: 20, res: () => ok('B') } }, calls, []);
    const p = new GeminiProvider({ ...base, model: 'a', fallbackModels: ['b'], hedgeMs: 500 }, f);
    expect((await p.complete(req)).content).toEqual([{ type: 'text', text: 'A' }]);
    expect(calls).toEqual(['a']);
  });

  it('a 503 fails over at once; when every model fails the last error is returned', async () => {
    const calls: string[] = [];
    const f = slowFetch({ a: { ms: 5, res: () => json({}, 503) }, b: { ms: 5, res: () => ok('B') } }, calls, []);
    const p = new GeminiProvider({ ...base, model: 'a', fallbackModels: ['b'], hedgeMs: 5000 }, f);
    expect((await p.complete(req)).content).toEqual([{ type: 'text', text: 'B' }]);
    const all = slowFetch({ a: { ms: 5, res: () => json({}, 503) }, b: { ms: 5, res: () => json({}, 429) } }, [], []);
    await expect(new GeminiProvider({ ...base, model: 'a', fallbackModels: ['b'], hedgeMs: 5000 }, all).complete(req)).rejects.toThrow(/429/);
  });

  it('a 400 is not retried on other models', async () => {
    const calls: string[] = [];
    const f = slowFetch({ a: { ms: 5, res: () => json({ error: {} }, 400) }, b: { ms: 5, res: () => ok('B') } }, calls, []);
    await expect(new GeminiProvider({ ...base, model: 'a', fallbackModels: ['b'], hedgeMs: 5000 }, f).complete(req)).rejects.toThrow(/400/);
    expect(calls).toEqual(['a']);
  });

  it('probe times every model in parallel and reports errors without user content', async () => {
    const f = slowFetch({ a: { ms: 5, res: () => ok('ok') }, b: { ms: 5, res: () => json({ error: { status: 'RESOURCE_EXHAUSTED', message: 'quota' } }, 429) } }, [], []);
    const r = await new GeminiProvider({ ...base, model: 'a', fallbackModels: ['b'] }, f).probe();
    expect(r.map((x) => [x.model, x.status])).toEqual([
      ['a', 200],
      ['b', 429],
    ]);
    expect(r[1]!.detail).toContain('RESOURCE_EXHAUSTED');
  });
});

describe('Gemini speech recognition', () => {
  it('sends the WAV inline with a Darija instruction and returns the cleaned text', async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- loose view of the JSON request body
    let body: Record<string, any> = {};
    let model = '';
    const f = (async (u: string, init?: RequestInit) => {
      model = modelOf(u);
      body = JSON.parse(init!.body as string);
      return ok('Transcript: "شنو الجو اليوم ف كازا؟"');
    }) as unknown as typeof fetch;
    const p = new GeminiSttProvider({ apiKey: 'AQ.k', baseUrl: 'https://g', models: ['lite', 'big'], timeoutMs: 3000 }, f);
    const r = await p.transcribe(Buffer.from('RIFF....WAVEfmt '), 'audio/wav', 'ar-MA');
    expect(r.text).toBe('شنو الجو اليوم ف كازا؟');
    expect(model).toBe('lite');
    expect(body.contents[0].parts[0].inlineData).toEqual({ mimeType: 'audio/wav', data: Buffer.from('RIFF....WAVEfmt ').toString('base64') });
    expect(body.systemInstruction.parts[0].text).toContain('Moroccan Darija');
    expect(body.generationConfig.temperature).toBe(0);
  });

  it('falls back to the next model on 429 and retries without MINIMAL thinking on 400', async () => {
    const seen: string[] = [];
    const f = (async (u: string, init?: RequestInit) => {
      const m = modelOf(u);
      const b = JSON.parse(init!.body as string);
      seen.push(`${m}:${b.generationConfig.thinkingConfig ? 'min' : 'none'}`);
      if (m === 'lite') return json({ error: { status: 'RESOURCE_EXHAUSTED' } }, 429);
      if (b.generationConfig.thinkingConfig) return json({ error: { status: 'INVALID_ARGUMENT' } }, 400);
      return ok('bonjour labas');
    }) as unknown as typeof fetch;
    const p = new GeminiSttProvider({ apiKey: 'k', baseUrl: 'https://g', models: ['lite', 'big'], timeoutMs: 3000 }, f);
    expect((await p.transcribe(Buffer.alloc(100), 'audio/wav', 'fr-FR')).text).toBe('bonjour labas');
    expect(seen).toEqual(['lite:min', 'big:min', 'big:none']);
  });

  it('cleans "no speech" answers and adapts the instruction to French/English', () => {
    expect(cleanTranscript('(no speech)')).toBe('');
    expect(cleanTranscript('[Silence]')).toBe('');
    expect(cleanTranscript('«واش نتا هنا؟»')).toBe('واش نتا هنا؟');
    expect(sttInstruction('fr-FR')).toContain('mostly uses French');
    expect(sttInstruction('ar-MA')).toContain('mostly uses Moroccan Darija');
  });

  it('is the default STT with a Gemini key; hedging defaults to 5 s', () => {
    const c = loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k' });
    expect(c.stt.provider).toBe('gemini');
    expect(isSttConfigured(c)).toBe(true);
    expect(c.llm.hedgeMs).toBe(5000);
    expect(loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k', LLM_HEDGE_MS: '0' }).llm.hedgeMs).toBe(0);
    expect(loadConfig({ AUTH_SECRET: 'x'.repeat(20) }).stt.provider).toBe('none');
  });
});
