import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../src/build-server.js';
import { PROACTIVE_INSTRUCTION, PROACTIVE_USER_TURN, runChat, type ChatEvent } from '../src/brain/chat.js';
import { ChatRequestSchema, ReplySchema } from '../src/brain/schema.js';
import { livePrompt } from '../src/live.js';
import { WikimediaImages, isPhoto } from '../src/providers/images/wikimedia.js';
import { ScriptedLlm } from '../src/providers/llm/scripted.js';
import type { FetchLike } from '../src/http.js';
import { PROMPT, deps, fakeWeather, goodReply, replyCall } from './helpers.js';

const UUID = '123e4567-e89b-42d3-a456-426614174000';

describe('proactive turns', () => {
  it('adds the proactive instruction, replaces the user turn and offers only the reply tool', async () => {
    const llm = new ScriptedLlm([replyCall(goodReply)]);
    const events: ChatEvent[] = [];
    const req = ChatRequestSchema.parse({ message: '.', mode: 'proactive' });
    for await (const e of runChat(req, { llm, search: null, weather: fakeWeather, promptTemplate: PROMPT, tokenBudget: 3000, maxOutputTokens: 500 })) events.push(e);
    expect(events.some((e) => e.type === 'final')).toBe(true);
    const sent = llm.requests[0]!;
    expect(sent.system).toContain(PROACTIVE_INSTRUCTION);
    expect(sent.tools.map((t) => t.name)).toEqual(['sahbi_reply']);
    expect(sent.messages.at(-1)!.content.at(-1)).toMatchObject({ type: 'text', text: PROACTIVE_USER_TURN });
  });

  it('normal chat keeps search and weather tools and defaults mode to chat', async () => {
    const req = ChatRequestSchema.parse({ message: 'salam' });
    expect(req.mode).toBe('chat');
    const llm = new ScriptedLlm([replyCall(goodReply)]);
    for await (const _ of runChat(req, { llm, search: null, weather: fakeWeather, promptTemplate: PROMPT, tokenBudget: 3000, maxOutputTokens: 500 })) void _;
    expect(llm.requests[0]!.tools.length).toBeGreaterThan(1);
    expect(llm.requests[0]!.system).not.toContain('Proactive turn');
  });
});

describe('image.show action', () => {
  it('validates a query', () => {
    expect(ReplySchema.safeParse({ ...goodReply, actions: [{ type: 'image.show', query: 'Hassan II Mosque' }] }).success).toBe(true);
    expect(ReplySchema.safeParse({ ...goodReply, actions: [{ type: 'image.show', query: '  ' }] }).success).toBe(false);
  });
});

describe('live prompt', () => {
  it('never places the robot in a phone and explains taps and continuous talk', () => {
    const p = livePrompt({ robotName: 'Zizou' });
    expect(p).not.toMatch(/living in the user's phone/);
    expect(p).toMatch(/never say you live in a phone/);
    expect(p).toMatch(/TAP/);
    expect(p).toMatch(/continuous conversation/);
  });
});

const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });

describe('WikimediaImages', () => {
  it('merges Wikipedia lead images then Commons files, keeps only bitmaps, de-duplicates', async () => {
    const urls: string[] = [];
    const fake: FetchLike = async (input) => {
      const url = String(input);
      urls.push(url);
      if (url.includes('commons.wikimedia.org')) {
        return json({
          query: {
            pages: [
              { index: 2, title: 'File:Chef 2.jpg', imageinfo: [{ thumburl: 'https://upload.wikimedia.org/c/800px-Chef_2.jpg', mime: 'image/jpeg', descriptionurl: 'https://commons.wikimedia.org/wiki/File:Chef_2.jpg' }] },
              { index: 1, title: 'File:Map.svg', imageinfo: [{ thumburl: 'https://upload.wikimedia.org/c/800px-Map.svg.png', mime: 'image/svg+xml' }] },
              { index: 3, title: 'File:Clip.webm', imageinfo: [{ thumburl: 'https://upload.wikimedia.org/c/Clip.webm.jpg', mime: 'video/webm' }] },
            ],
          },
        });
      }
      if (url.startsWith('https://en.')) {
        return json({ query: { pages: [{ index: 1, title: 'Chefchaouen', fullurl: 'https://en.wikipedia.org/wiki/Chefchaouen', thumbnail: { source: 'https://upload.wikimedia.org/a/800px-Chef.jpg', width: 800, height: 600 } }] } });
      }
      // fr: same file as en at another size -> duplicate
      return json({ query: { pages: [{ index: 1, title: 'Chefchaouen', fullurl: 'https://fr.wikipedia.org/wiki/Chefchaouen', thumbnail: { source: 'https://upload.wikimedia.org/a/640px-Chef.jpg' } }] } });
    };
    const r = await new WikimediaImages(fake).search('Chefchaouen');
    expect(r.map((x) => x.url)).toEqual(['https://upload.wikimedia.org/a/800px-Chef.jpg', 'https://upload.wikimedia.org/c/800px-Chef_2.jpg']);
    expect(r[0]).toMatchObject({ source: 'Wikipedia', page: 'https://en.wikipedia.org/wiki/Chefchaouen' });
    expect(r[1]).toMatchObject({ source: 'Wikimedia Commons', title: 'Chef 2' });
    expect(urls.some((u) => u.startsWith('https://fr.'))).toBe(true);
  });

  it('accepts thumb.wikimedia.org thumbnails with query strings', () => {
    expect(isPhoto('https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a6/Lion.jpg/960px-Lion.jpg?utm_source=en.wikipedia.org')).toBe(true);
    expect(isPhoto('https://upload.wikimedia.org/x/800px-Flag.svg.png')).toBe(true);
    expect(isPhoto('https://upload.wikimedia.org/x/Map.svg')).toBe(false);
    expect(isPhoto('https://evil.example/x.jpg')).toBe(false);
  });

  it('uses Arabic Wikipedia for Arabic queries and survives upstream errors', async () => {
    const urls: string[] = [];
    const fake: FetchLike = async (input) => {
      urls.push(String(input));
      return new Response('nope', { status: 503 });
    };
    expect(await new WikimediaImages(fake).search('صومعة حسان')).toEqual([]);
    expect(urls.some((u) => u.startsWith('https://ar.wikipedia.org'))).toBe(true);
  });
});

describe('GET /v1/images', () => {
  let app: FastifyInstance;
  afterEach(async () => app?.close());

  async function token(a: FastifyInstance): Promise<string> {
    const r = await a.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } });
    return (r.json() as { token: string }).token;
  }

  it('returns images, needs auth, validates q, and reports not configured', async () => {
    app = buildServer({ ...deps(), images: async (q: string) => [{ url: 'https://upload.wikimedia.org/x.jpg', title: q }] });
    expect((await app.inject({ method: 'GET', url: '/v1/images?q=cat' })).statusCode).toBe(401);
    const t = await token(app);
    const ok = await app.inject({ method: 'GET', url: '/v1/images?q=cat', headers: { authorization: `Bearer ${t}` } });
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toEqual({ images: [{ url: 'https://upload.wikimedia.org/x.jpg', title: 'cat' }] });
    expect((await app.inject({ method: 'GET', url: '/v1/images?q=', headers: { authorization: `Bearer ${t}` } })).statusCode).toBe(400);
    await app.close();
    app = buildServer({ ...deps(), images: null });
    const t2 = await token(app);
    const nc = await app.inject({ method: 'GET', url: '/v1/images?q=cat', headers: { authorization: `Bearer ${t2}` } });
    expect(nc.statusCode).toBe(503);
  });
});
