import { describe, expect, it, vi } from 'vitest';
import { issueToken, isValidInstallId, verifyToken } from '../src/auth.js';
import { isLlmConfigured, isSttConfigured, loadConfig } from '../src/config.js';
import { fetchWithRetry } from '../src/http.js';
import { OpenAiProvider, chatCompletionsUrl, isOfficialOpenAi, toOpenAiMessages } from '../src/providers/llm/openai.js';
import { BraveSearchProvider, stripTags } from '../src/providers/search/brave.js';
import { buildSsml, escapeXml } from '../src/providers/tts/azure.js';
import { getWeather, normaliseCity } from '../src/tools/weather.js';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const UUID = '123e4567-e89b-42d3-a456-426614174000';

describe('auth tokens', () => {
  it('round-trips and rejects tampering / expiry / other secrets', () => {
    const t = issueToken('s', UUID, 1000);
    expect(verifyToken('s', t, 100, 1050)).toBe(UUID);
    expect(verifyToken('other', t, 100, 1050)).toBeNull();
    expect(verifyToken('s', t, 100, 2000)).toBeNull();
    expect(verifyToken('s', t.replace(/.$/, (c) => (c === 'A' ? 'B' : 'A')), 100, 1050)).toBeNull();
    expect(verifyToken('s', 'garbage', 100, 1050)).toBeNull();
    expect(isValidInstallId('not-a-uuid')).toBe(false);
  });
});

describe('config', () => {
  it('nothing configured by default', () => {
    const c = loadConfig({});
    expect(isLlmConfigured(c)).toBe(false);
    expect(isSttConfigured(c)).toBe(false);
    expect(c.port).toBe(8080);
  });
  it('LLM needs provider, key and model', () => {
    expect(isLlmConfigured(loadConfig({ LLM_PROVIDER: 'anthropic', LLM_API_KEY: 'k' }))).toBe(false);
    expect(isLlmConfigured(loadConfig({ LLM_PROVIDER: 'anthropic', LLM_API_KEY: 'k', LLM_MODEL: 'm' }))).toBe(true);
    expect(loadConfig({ LLM_PROVIDER: 'bogus' }).llm.provider).toBe('none');
  });
});

describe('fetchWithRetry', () => {
  it('retries 5xx then succeeds', async () => {
    const f = vi.fn().mockResolvedValueOnce(new Response('', { status: 503 })).mockResolvedValueOnce(json({ ok: 1 }));
    const r = await fetchWithRetry(f as unknown as typeof fetch, 'https://x', {}, { baseDelayMs: 1 });
    expect(r.status).toBe(200);
    expect(f).toHaveBeenCalledTimes(2);
  });
  it('network failure → upstream_error', async () => {
    const f = vi.fn().mockRejectedValue(new TypeError('fetch failed'));
    await expect(fetchWithRetry(f as unknown as typeof fetch, 'https://x', {}, { retries: 1, baseDelayMs: 1 })).rejects.toMatchObject({ code: 'upstream_error' });
  });
  it('timeout → upstream_timeout', async () => {
    const f = vi.fn((_u: string, init: RequestInit) => new Promise<Response>((_r, rej) => init.signal!.addEventListener('abort', () => rej(Object.assign(new Error('aborted'), { name: 'AbortError' })))));
    await expect(fetchWithRetry(f as unknown as typeof fetch, 'https://x', {}, { retries: 0, timeoutMs: 10 })).rejects.toMatchObject({ code: 'upstream_timeout' });
  });
});

describe('Brave search', () => {
  it('sends the documented request and maps results', async () => {
    const f = vi.fn().mockResolvedValue(
      json({ web: { results: [{ title: '<strong>Akhbar</strong>', url: 'https://hespress.com/a', description: 'desc &amp; more', extra_snippets: ['e1'], page_age: '2026-11-15T08:00:00' }, { title: 'no url' }] } }),
    );
    const p = new BraveSearchProvider('KEY', f as unknown as typeof fetch);
    const r = await p.search('akhbar', { freshness: 'pd', country: 'MA' });
    const [url, init] = f.mock.calls[0] as [string, RequestInit];
    expect(url).toMatch(/^https:\/\/api\.search\.brave\.com\/res\/v1\/web\/search\?/);
    expect(url).toContain('freshness=pd');
    expect(url).toContain('country=MA');
    expect((init.headers as Record<string, string>)['X-Subscription-Token']).toBe('KEY');
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ title: 'Akhbar', url: 'https://hespress.com/a', date: '2026-11-15T08:00:00' });
    expect(r[0]!.snippet).toContain('desc & more');
  });
  it('HTTP error becomes upstream_error without leaking the body', async () => {
    const f = vi.fn().mockResolvedValue(new Response('secret echo of user text', { status: 401 }));
    const err = await new BraveSearchProvider('K', f as unknown as typeof fetch).search('q').catch((e: unknown) => e);
    expect(err).toMatchObject({ code: 'upstream_error' });
    expect(String((err as Error).message)).not.toContain('secret');
  });
  it('stripTags', () => expect(stripTags('<b>a</b> &quot;b&quot; &#39;c&#39;')).toBe('a "b" \'c\''));
});

describe('weather (Open-Meteo)', () => {
  it('geocodes then fetches the forecast', async () => {
    const f = vi
      .fn()
      .mockResolvedValueOnce(json({ results: [{ name: 'Tangier', country: 'Morocco', latitude: 35.76, longitude: -5.83 }] }))
      .mockResolvedValueOnce(json({ current: { temperature_2m: 19.5, weather_code: 3, is_day: 1 }, daily: { temperature_2m_max: [22], temperature_2m_min: [14] } }));
    const w = await getWeather('Tanja', f as unknown as typeof fetch);
    expect((f.mock.calls[0] as [string])[0]).toContain('name=Tangier');
    expect(w.current.description_en).toBe('overcast');
    expect(w.today?.max_c).toBe(22);
    expect(w.source.url).toContain('open-meteo.com');
  });
  it('unknown place → 404 bad_request', async () => {
    const f = vi.fn().mockResolvedValue(json({}));
    await expect(getWeather('Atlantis', f as unknown as typeof fetch)).rejects.toMatchObject({ status: 404 });
  });
  it('normaliseCity handles Darija/Arabic aliases', () => {
    expect(normaliseCity('Casa')).toBe('Casablanca');
    expect(normaliseCity('مراكش')).toBe('Marrakesh');
    expect(normaliseCity('Ifrane')).toBe('Ifrane');
  });
});

describe('Azure TTS SSML', () => {
  it('escapes user text', () => {
    expect(escapeXml(`<a href="x">&'`)).toBe('&lt;a href=&quot;x&quot;&gt;&amp;&apos;');
    const ssml = buildSsml({ text: 'سلام <script>', language: 'ar-MA' }, 'ar-MA-JamalNeural');
    expect(ssml).toContain('ar-MA-JamalNeural');
    expect(ssml).toContain('&lt;script&gt;');
    expect(ssml).not.toContain('<script>');
  });
});

describe('toOpenAiMessages', () => {
  it('maps tool calls and tool results', () => {
    const out = toOpenAiMessages('sys', [
      { role: 'user', content: [{ type: 'text', text: 'hi' }] },
      { role: 'assistant', content: [{ type: 'tool_use', id: 'c1', name: 'web_search', input: { query: 'q' } }] },
      { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'c1', content: 'res' }] },
    ]);
    expect(out[0]).toEqual({ role: 'system', content: 'sys' });
    expect(out[2]).toMatchObject({ role: 'assistant', content: null, tool_calls: [{ id: 'c1', function: { name: 'web_search', arguments: '{"query":"q"}' } }] });
    expect(out[3]).toEqual({ role: 'tool', tool_call_id: 'c1', content: 'res' });
  });
});

describe('OpenAI-compatible endpoints', () => {
  it('builds the right chat/completions URL', () => {
    expect(chatCompletionsUrl('https://api.openai.com')).toBe('https://api.openai.com/v1/chat/completions');
    expect(chatCompletionsUrl('https://api.openai.com/')).toBe('https://api.openai.com/v1/chat/completions');
    expect(chatCompletionsUrl('https://api.openai.com/v1')).toBe('https://api.openai.com/v1/chat/completions');
    expect(chatCompletionsUrl('https://api.groq.com/openai')).toBe('https://api.groq.com/openai/v1/chat/completions');
    expect(chatCompletionsUrl('https://generativelanguage.googleapis.com/v1beta/openai/')).toBe(
      'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    );
  });

  it('only official OpenAI gets max_completion_tokens', () => {
    expect(isOfficialOpenAi('https://api.openai.com')).toBe(true);
    expect(isOfficialOpenAi('https://generativelanguage.googleapis.com/v1beta/openai/')).toBe(false);
    expect(isOfficialOpenAi('not a url')).toBe(false);
  });

  it('sends a Gemini-shaped request (url, max_tokens, reasoning_effort, bearer key)', async () => {
    let seenUrl = '';
    let seenBody: Record<string, unknown> = {};
    let seenAuth = '';
    const fake = (async (url: string, init: { body: string; headers: Record<string, string> }) => {
      seenUrl = url;
      seenBody = JSON.parse(init.body) as Record<string, unknown>;
      seenAuth = init.headers.authorization;
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: '{"ok":true}' } }] }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }) as unknown as typeof fetch;
    const p = new OpenAiProvider(
      { apiKey: 'k', model: 'gemini-3.8-flash', baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/', timeoutMs: 5000, reasoningEffort: 'low' },
      fake,
    );
    const r = await p.complete({ system: 's', messages: [{ role: 'user', content: [{ type: 'text', text: 'salam' }] }], tools: [], maxTokens: 123 });
    expect(seenUrl).toBe('https://generativelanguage.googleapis.com/v1beta/openai/chat/completions');
    expect(seenBody.max_tokens).toBe(123);
    expect(seenBody.max_completion_tokens).toBeUndefined();
    expect(seenBody.reasoning_effort).toBe('low');
    expect(seenAuth).toBe('Bearer k');
    expect(r.stopReason).toBe('end');
  });
});
