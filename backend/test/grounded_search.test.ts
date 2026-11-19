import { describe, expect, it } from 'vitest';
import { buildServer } from '../src/build-server.js';
import { isSearchConfigured, loadConfig } from '../src/config.js';
import { GeminiGroundedSearchProvider, matchesQuery, parseGrounded, youtubeId } from '../src/providers/search/gemini.js';
import { deps } from './helpers.js';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const UUID = '123e4567-e89b-42d3-a456-426614174000';
const R = (n: number) => `https://vertexaisearch.cloud.google.com/grounding-api-redirect/AbC${n}`;

const grounded = (chunks: Array<[string, string]>, text = 'Facts.', queries = ['q1']) => ({
  candidates: [
    {
      content: { parts: [{ text }] },
      groundingMetadata: {
        webSearchQueries: queries,
        groundingChunks: chunks.map(([uri, title]) => ({ web: { uri, title } })),
        groundingSupports: chunks.map((_, i) => ({ segment: { text: `fact ${i}` }, groundingChunkIndices: [i] })),
      },
    },
  ],
});

describe('Gemini Google Search grounding provider', () => {
  it('sends google_search on the free 2.5 model and maps resolved sources + suggestion links', async () => {
    const calls: Array<{ url: string; body?: Record<string, unknown> }> = [];
    const fake = (async (u: string, init?: RequestInit) => {
      calls.push({ url: u, body: init?.body ? JSON.parse(init.body as string) : undefined });
      if (u.includes(':generateContent')) return json(grounded([[R(1), 'hespress.com'], [R(2), 'le360.ma']]));
      if (u === R(1)) return new Response(null, { status: 302, headers: { location: 'https://www.hespress.com/a-1' } });
      if (u === R(2)) return new Response(null, { status: 302, headers: { location: 'https://le360.ma/b-2' } });
      return new Response('nope', { status: 404 });
    }) as unknown as typeof fetch;
    const p = new GeminiGroundedSearchProvider({ apiKey: 'AQ.k', baseUrl: 'https://g', models: ['gemini-2.5-flash-lite'], timeoutMs: 5000 }, fake);
    const out = await p.search('akhbar lmghrib', { freshness: 'pd', country: 'MA' });
    expect(calls[0]!.url).toBe('https://g/v1beta/models/gemini-2.5-flash-lite:generateContent');
    expect(calls[0]!.body!.tools).toEqual([{ google_search: {} }]);
    expect(JSON.stringify(calls[0]!.body)).toContain('last 24 hours');
    expect(out.map((r) => r.url)).toEqual(['https://www.hespress.com/a-1', 'https://le360.ma/b-2', 'https://www.google.com/search?q=q1']);
    expect(out[0]!.snippet).toBe('fact 0');
    expect(out[2]!.kind).toBe('search');
  });

  it('falls back to the next model on 429 and surfaces 401 as is', async () => {
    const seen: string[] = [];
    const fake = (async (u: string) => {
      seen.push(u);
      if (u.includes('lite')) return json({ error: { status: 'RESOURCE_EXHAUSTED', message: 'quota' } }, 429);
      return json(grounded([['https://example.org/x', 'example.org']]));
    }) as unknown as typeof fetch;
    const p = new GeminiGroundedSearchProvider({ apiKey: 'k', baseUrl: 'https://g', models: ['gemini-2.5-flash-lite', 'gemini-2.5-flash'], timeoutMs: 5000 }, fake);
    const out = await p.search('x');
    expect(seen.some((u) => u.includes('gemini-2.5-flash:generateContent'))).toBe(true);
    expect(out[0]!.url).toBe('https://example.org/x');
    const unauth = (async () => json({ error: { status: 'UNAUTHENTICATED', message: 'API key not valid.' } }, 401)) as unknown as typeof fetch;
    const p2 = new GeminiGroundedSearchProvider({ apiKey: 'k', baseUrl: 'https://g', models: ['a', 'b'], timeoutMs: 5000 }, unauth);
    await expect(p2.search('x')).rejects.toThrow('401');
  });

  it('parses responses without grounding as no results', () => {
    const g = parseGrounded({ candidates: [{ content: { parts: [{ text: 'hi' }] } }] });
    expect(g.chunks).toEqual([]);
    expect(g.queries).toEqual([]);
  });
});

describe('YouTube search for in-app playback', () => {
  it('extracts ids from all YouTube URL forms', () => {
    expect(youtubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://youtu.be/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://m.youtube.com/watch?feature=x&v=dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://www.youtube.com/shorts/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://example.com/watch?v=dQw4w9WgXcQ')).toBeNull();
  });

  it('keeps grounded, embeddable videos; text-only ids must match the query', async () => {
    const A = 'AAAAAAAAAAA';
    const B = 'BBBBBBBBBBB'; // embedding disabled → oEmbed 401
    const C = 'CCCCCCCCCCC'; // only in model text, unrelated title → dropped
    const D = 'DDDDDDDDDDD'; // only in model text, matching title → kept
    const fake = (async (u: string) => {
      if (u.includes(':generateContent')) {
        return json(grounded([[R(1), 'youtube.com'], [R(2), 'youtube.com']], `See https://www.youtube.com/watch?v=${C} and https://youtu.be/${D}`));
      }
      if (u === R(1)) return new Response(null, { status: 302, headers: { location: `https://www.youtube.com/watch?v=${A}` } });
      if (u === R(2)) return new Response(null, { status: 302, headers: { location: `https://www.youtube.com/watch?v=${B}` } });
      if (u.startsWith('https://www.youtube.com/oembed')) {
        const id = decodeURIComponent(u).slice(-11);
        if (id === B) return new Response('Unauthorized', { status: 401 });
        const titles: Record<string, string> = { [A]: 'Official clip', [C]: 'Cooking pasta', [D]: 'Saad Lamjarred - Lm3allem' };
        return json({ title: titles[id], author_name: 'chan', thumbnail_url: 'https://i.ytimg.com/x.jpg' });
      }
      return new Response('nope', { status: 404 });
    }) as unknown as typeof fetch;
    const p = new GeminiGroundedSearchProvider({ apiKey: 'k', baseUrl: 'https://g', models: ['m'], timeoutMs: 5000 }, fake);
    const vids = await p.youtube('saad lamjarred lm3allem');
    expect(vids.map((v) => v.id)).toEqual([A, D]);
    expect(vids[0]).toMatchObject({ title: 'Official clip', author: 'chan', url: `https://www.youtube.com/watch?v=${A}` });
  });

  it('matchesQuery ignores case and accents', () => {
    expect(matchesQuery('Céline Dion', 'CELINE DION - Pour que tu m’aimes')).toBe(true);
    expect(matchesQuery('nass el ghiwane', 'Cooking pasta')).toBe(false);
  });

  it('route: needs auth, validates q, reports not configured, returns videos', async () => {
    const off = buildServer(deps());
    const tok = (await off.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } })).json().token as string;
    const h = { authorization: `Bearer ${tok}` };
    expect((await off.inject({ method: 'GET', url: '/v1/music/youtube?q=x' })).statusCode).toBe(401);
    expect((await off.inject({ method: 'GET', url: '/v1/music/youtube?q=x', headers: h })).statusCode).toBe(503);
    const on = buildServer({ ...deps(), youtube: async (q) => [{ id: 'AAAAAAAAAAA', title: q, author: '', thumbnail: '', url: '' }] });
    const tok2 = (await on.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } })).json().token as string;
    const h2 = { authorization: `Bearer ${tok2}` };
    expect((await on.inject({ method: 'GET', url: '/v1/music/youtube', headers: h2 })).statusCode).toBe(400);
    const r = await on.inject({ method: 'GET', url: '/v1/music/youtube?q=nass%20el%20ghiwane', headers: h2 });
    expect(r.statusCode).toBe(200);
    expect(r.json().videos[0].title).toBe('nass el ghiwane');
  });
});

describe('search configuration', () => {
  it('defaults to Gemini grounding with a Gemini key, Brave when its key exists', () => {
    const g = loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k' });
    expect(g.search.provider).toBe('gemini');
    expect(g.search.geminiModels[0]).toBe('gemini-2.5-flash-lite');
    expect(isSearchConfigured(g)).toBe(true);
    const b = loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k', BRAVE_SEARCH_API_KEY: 'bk' });
    expect(b.search.provider).toBe('brave');
    const none = loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k', SEARCH_PROVIDER: 'none' });
    expect(isSearchConfigured(none)).toBe(false);
  });
});
