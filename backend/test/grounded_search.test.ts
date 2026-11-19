import { describe, expect, it } from 'vitest';
import { buildServer } from '../src/build-server.js';
import { isSearchConfigured, loadConfig } from '../src/config.js';
import { YoutubeFinder, matchesQuery, parseCandidates, youtubeId } from '../src/providers/music/youtube.js';
import { FreeWebSearchProvider } from '../src/providers/search/free.js';
import { GeminiGroundedSearchProvider, parseGrounded } from '../src/providers/search/gemini.js';
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

describe('YouTube finder for in-app playback', () => {
  it('extracts ids from all YouTube URL forms', () => {
    expect(youtubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://youtu.be/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://m.youtube.com/watch?feature=x&v=dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://www.youtube.com/shorts/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(youtubeId('https://example.com/watch?v=dQw4w9WgXcQ')).toBeNull();
  });

  it('Gemini suggestions are kept only when oEmbed confirms an embeddable video with the claimed song', async () => {
    const A = 'AAAAAAAAAAA'; // real, title matches the claim → kept
    const B = 'BBBBBBBBBBB'; // embedding disabled → oEmbed 401 → dropped
    const C = 'CCCCCCCCCCC'; // exists but is another video (invented id) → dropped
    const cands = {
      videos: [
        { url: `https://www.youtube.com/watch?v=${A}`, title: 'Lm3allem', artist: 'Saad Lamjarred' },
        { url: `https://youtu.be/${B}`, title: 'Enty', artist: 'Saad Lamjarred' },
        { url: `https://www.youtube.com/watch?v=${C}`, title: 'Ghaltana', artist: 'Saad Lamjarred' },
      ],
    };
    let body: Record<string, any> = {}; // eslint-disable-line @typescript-eslint/no-explicit-any
    let dataApiCalls = 0;
    const fake = (async (u: string, init?: RequestInit) => {
      if (u.includes(':generateContent')) {
        body = JSON.parse(init!.body as string);
        return json({ candidates: [{ content: { parts: [{ text: JSON.stringify(cands) }] } }] });
      }
      if (u.startsWith('https://www.googleapis.com/youtube/v3/')) {
        dataApiCalls++;
        return json({ error: { code: 403, message: 'YouTube Data API v3 has not been used in project 1 before or it is disabled.', status: 'PERMISSION_DENIED' } }, 403);
      }
      if (u.startsWith('https://www.youtube.com/oembed')) {
        const id = decodeURIComponent(u).slice(-11);
        if (id === B) return new Response('Unauthorized', { status: 401 });
        const titles: Record<string, string> = { [A]: 'Saad Lamjarred - LM3ALLEM (Exclusive Music Video)', [C]: 'Cooking pasta at home' };
        return json({ title: titles[id], author_name: 'Saad Lamjarred', thumbnail_url: 'https://i.ytimg.com/x.jpg' });
      }
      return new Response('nope', { status: 404 });
    }) as unknown as typeof fetch;
    const f = new YoutubeFinder({ gemini: { apiKey: 'AQ.k', baseUrl: 'https://g', models: ['gemini-4-hydrogen'] } }, fake);
    expect(f.mode).toBe('gemini-oembed');
    const vids = await f.find('ch3el lia lm3allem dyal saad lamjarred');
    expect(body.generationConfig.responseMimeType).toBe('application/json');
    expect(vids.map((v) => v.id)).toEqual([A]);
    expect(vids[0]).toMatchObject({ author: 'Saad Lamjarred', url: `https://www.youtube.com/watch?v=${A}` });
    // The Data API was tried once with the Gemini key, refused, and then skipped.
    const again = await f.findWithStats('saad lamjarred lm3allem');
    expect(dataApiCalls).toBe(1);
    expect(again.via).toBe('gemini-oembed');
    expect(again.dataApi).toContain('403');
  });

  it('uses the YouTube Data API when YOUTUBE_API_KEY is set', async () => {
    let url = '';
    const fake = (async (u: string) => {
      url = u;
      return json({ items: [{ id: { videoId: 'AAAAAAAAAAA' }, snippet: { title: 'Nass El Ghiwane &amp; co', channelTitle: 'NEG' } }, { id: {} }] });
    }) as unknown as typeof fetch;
    const f = new YoutubeFinder({ apiKey: 'yk' }, fake);
    const vids = await f.find('nass el ghiwane');
    expect(url).toContain('videoEmbeddable=true');
    expect(url).toContain('key=yk');
    expect(vids).toHaveLength(1);
    expect(vids[0]!.title).toBe('Nass El Ghiwane & co');
  });

  it('parses bare links when the model ignores JSON, and matchesQuery ignores case/accents', () => {
    expect(parseCandidates('try https://youtu.be/AAAAAAAAAAA').map((c) => c.id)).toEqual(['AAAAAAAAAAA']);
    expect(matchesQuery('Céline Dion', 'CELINE DION - Pour que tu m’aimes', 2)).toBe(true);
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

describe('free web search (Wikipedia + GDELT)', () => {
  it('queries two Wikipedia languages, adds GDELT headlines for fresh queries, skips rate-limit text', async () => {
    const urls: string[] = [];
    const fake = (async (u: string) => {
      urls.push(u);
      if (u.includes('ar.wikipedia.org')) return json({ query: { pages: [{ index: 1, title: 'سعد لمجرد', extract: 'مغني مغربي', fullurl: 'https://ar.wikipedia.org/wiki/x', revisions: [{ timestamp: '2026-11-01T00:00:00Z' }] }] } });
      if (u.includes('fr.wikipedia.org')) return json({ query: { pages: [{ index: 1, title: 'Saad Lamjarred', extract: 'Chanteur marocain', fullurl: 'https://fr.wikipedia.org/wiki/y' }] } });
      if (u.includes('gdeltproject')) return new Response(JSON.stringify({ articles: [{ title: 'Lamjarred new album', url: 'https://hespress.com/z', domain: 'hespress.com', seendate: '20261118T101500Z' }] }), { status: 200 });
      return new Response('nope', { status: 404 });
    }) as unknown as typeof fetch;
    const p = new FreeWebSearchProvider(fake);
    const out = await p.search('سعد لمجرد', { freshness: 'pw' });
    expect(urls.some((u) => u.includes('ar.wikipedia.org'))).toBe(true);
    expect(urls.some((u) => u.includes('fr.wikipedia.org'))).toBe(true);
    expect(out.map((r) => r.url)).toEqual(['https://hespress.com/z', 'https://ar.wikipedia.org/wiki/x', 'https://fr.wikipedia.org/wiki/y']);
    expect(out[0]!.date).toBe('2026-11-18');
    expect(out[0]!.snippet).toContain('Headline only');
    const limited = (async (u: string) =>
      u.includes('gdelt') ? new Response('Please limit requests to one every 5 seconds', { status: 200 }) : new Response('x', { status: 500 })) as unknown as typeof fetch;
    expect(await new FreeWebSearchProvider(limited).search('x', { freshness: 'pd' })).toEqual([]);
  });

  it('Latin queries use French and English Wikipedia and no GDELT without freshness', async () => {
    const urls: string[] = [];
    const fake = (async (u: string) => {
      urls.push(u);
      return json({ query: { pages: [] } });
    }) as unknown as typeof fetch;
    await new FreeWebSearchProvider(fake).search('Nass El Ghiwane');
    expect(urls.map((u) => new URL(u).hostname).sort()).toEqual(['en.wikipedia.org', 'fr.wikipedia.org']);
  });
});

describe('search configuration', () => {
  it('defaults to free search, Brave when its key exists, Gemini grounding only on request', () => {
    const g = loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k' });
    expect(g.search.provider).toBe('free');
    expect(loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k', SEARCH_PROVIDER: 'gemini' }).search.provider).toBe('gemini');
    expect(g.search.geminiModels[0]).toBe('gemini-2.5-flash-lite');
    expect(isSearchConfigured(g)).toBe(true);
    const b = loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k', BRAVE_SEARCH_API_KEY: 'bk' });
    expect(b.search.provider).toBe('brave');
    const none = loadConfig({ AUTH_SECRET: 'x'.repeat(20), LLM_API_KEY: 'AQ.k', SEARCH_PROVIDER: 'none' });
    expect(isSearchConfigured(none)).toBe(false);
  });
});
