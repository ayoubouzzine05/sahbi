import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../src/server.js';
import { config, deps, goodReply, parseSse, replyCall } from './helpers.js';

const UUID = '123e4567-e89b-42d3-a456-426614174000';
let app: FastifyInstance | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

async function tokenFor(a: FastifyInstance): Promise<string> {
  const r = await a.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } });
  expect(r.statusCode).toBe(200);
  return (r.json() as { token: string }).token;
}

describe('server', () => {
  it('health reports exactly what is configured', async () => {
    app = await buildServer(deps({ config: config(), llm: null }));
    const h = (await app.inject({ method: 'GET', url: '/v1/health' })).json() as { services: Record<string, { configured: boolean }> };
    expect(h.services.llm!.configured).toBe(false);
    expect(h.services.search!.configured).toBe(false);
    expect(h.services.weather!.configured).toBe(true);
    expect(h.services.stt!.configured).toBe(false);
    expect(h.services.tts!.configured).toBe(false);
  });

  it('auth: rejects bad install ids and missing tokens', async () => {
    app = await buildServer(deps());
    expect((await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: 'x' } })).statusCode).toBe(400);
    const r = await app.inject({ method: 'POST', url: '/v1/chat', payload: { message: 'salam' } });
    expect(r.statusCode).toBe(401);
    expect(r.json()).toMatchObject({ error: { code: 'unauthorized' } });
  });

  it('chat streams status, deltas and a final reply over SSE', async () => {
    app = await buildServer(deps({ script: [replyCall(goodReply)] }));
    const token = await tokenFor(app);
    const r = await app.inject({ method: 'POST', url: '/v1/chat', headers: { authorization: `Bearer ${token}` }, payload: { message: 'salam' } });
    expect(r.statusCode).toBe(200);
    expect(r.headers['content-type']).toContain('text/event-stream');
    const events = parseSse(r.body);
    expect(events[0]).toEqual({ event: 'status', data: { phase: 'thinking' } });
    const text = events.filter((e) => e.event === 'delta').map((e) => (e.data as { text: string }).text).join('');
    expect(text).toBe(goodReply.display_text);
    expect(events.at(-1)!.event).toBe('final');
  });

  it('chat with no LLM configured → 503 not_configured (no fake answer)', async () => {
    app = await buildServer(deps({ config: config(), llm: null }));
    const token = await tokenFor(app);
    const r = await app.inject({ method: 'POST', url: '/v1/chat', headers: { authorization: `Bearer ${token}` }, payload: { message: 'salam' } });
    expect(r.statusCode).toBe(503);
    expect(r.json()).toMatchObject({ error: { code: 'not_configured' } });
  });

  it('invalid model output twice → SSE error event invalid_output', async () => {
    app = await buildServer(deps({ script: [replyCall({ ...goodReply, intensity: 9 }), replyCall({ ...goodReply, intensity: 9 })] }));
    const token = await tokenFor(app);
    const r = await app.inject({ method: 'POST', url: '/v1/chat', headers: { authorization: `Bearer ${token}` }, payload: { message: 'salam' } });
    const events = parseSse(r.body);
    expect(events.at(-1)).toMatchObject({ event: 'error', data: { code: 'invalid_output' } });
  });

  it('validates request bodies and size limits', async () => {
    app = await buildServer(deps({ config: config({ LLM_PROVIDER: 'openai', LLM_MODEL: 'm', LLM_API_KEY: 'k', JSON_BODY_LIMIT_BYTES: '2048' }) }));
    const token = await tokenFor(app);
    const h = { authorization: `Bearer ${token}` };
    expect((await app.inject({ method: 'POST', url: '/v1/chat', headers: h, payload: { message: '' } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: '/v1/chat', headers: h, payload: { message: 'x'.repeat(5000) } })).statusCode).toBe(413);
  });

  it('rate limits per install token', async () => {
    app = await buildServer(deps({ config: config({ RATE_LIMIT_PER_MINUTE: '3' }), llm: null }));
    const token = await tokenFor(app);
    const codes: number[] = [];
    for (let i = 0; i < 5; i++) {
      codes.push((await app.inject({ method: 'GET', url: '/v1/weather?city=Rabat', headers: { authorization: `Bearer ${token}` } })).statusCode);
    }
    expect(codes).toContain(429);
  });

  it('weather route works without any key', async () => {
    app = await buildServer(deps({ config: config(), llm: null }));
    const token = await tokenFor(app);
    const r = await app.inject({ method: 'GET', url: '/v1/weather?city=Casa', headers: { authorization: `Bearer ${token}` } });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ location: { name: 'Casa' } });
  });

  it('stt/tts not configured → 503', async () => {
    app = await buildServer(deps({ config: config(), llm: null }));
    const token = await tokenFor(app);
    const h = { authorization: `Bearer ${token}` };
    expect((await app.inject({ method: 'POST', url: '/v1/tts', headers: h, payload: { text: 'salam' } })).statusCode).toBe(503);
    expect((await app.inject({ method: 'POST', url: '/v1/stt', headers: { ...h, 'content-type': 'audio/wav' }, payload: Buffer.alloc(100) })).statusCode).toBe(503);
  });

  it('CORS is closed unless origins are configured', async () => {
    app = await buildServer(deps({ config: config(), llm: null }));
    const r = await app.inject({ method: 'GET', url: '/v1/health', headers: { origin: 'https://evil.example' } });
    expect(r.headers['access-control-allow-origin']).toBeUndefined();
  });
});
