import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../src/build-server.js';
import { locateInstruction, locateObject, locateSystem, parseLocate } from '../src/brain/locate.js';
import { livePrompt } from '../src/live.js';
import { ScriptedLlm } from '../src/providers/llm/scripted.js';
import type { LlmResponse } from '../src/providers/llm/types.js';
import { deps } from './helpers.js';

const UUID = '123e4567-e89b-42d3-a456-426614174000';
const text = (t: string): LlmResponse => ({ content: [{ type: 'text', text: t }], stopReason: 'end' });
const IMG = 'A'.repeat(200);

describe('parseLocate (Gemini box_2d → 0..1 box)', () => {
  it('converts [ymin,xmin,ymax,xmax] 0-1000 to left/top/right/bottom 0..1', () => {
    const r = parseLocate('```json\n{"found":true,"label":"كاس","box_2d":[100,200,500,600]}\n```', 'pointing');
    expect(r).toEqual({ found: true, by: 'pointing', label: 'كاس', box: { left: 0.2, top: 0.1, right: 0.6, bottom: 0.5 } });
  });
  it('rejects junk, not-found, tiny and whole-frame boxes', () => {
    expect(parseLocate('no idea', 'pointing').found).toBe(false);
    expect(parseLocate('{"found":false}', 'pointing').found).toBe(false);
    expect(parseLocate('{"found":true,"box_2d":[1,2,3]}', 'pointing').found).toBe(false);
    expect(parseLocate('{"found":true,"box_2d":[100,100,105,105]}', 'pointing').found).toBe(false);
    expect(parseLocate('{"found":true,"box_2d":[0,0,1000,1000]}', 'pointing').found).toBe(false);
  });
  it('a tap must fall in (or near) the box', () => {
    const j = '{"found":true,"label":"x","box_2d":[100,100,300,300]}';
    expect(parseLocate(j, 'tap', { x: 0.2, y: 0.2 }).found).toBe(true);
    expect(parseLocate(j, 'tap', { x: 0.9, y: 0.9 }).found).toBe(false);
  });
});

describe('locateObject', () => {
  it('sends the image plus a tap instruction in 0-1000 [y,x] and asks for Darija labels', async () => {
    const llm = new ScriptedLlm([text('{"found":true,"label":"ستيلو","box_2d":[400,450,600,550]}')]);
    const r = await locateObject(llm, { image: IMG, mime: 'image/png', tap: { x: 0.5, y: 0.5 }, language: 'ar' });
    expect(r.found).toBe(true);
    expect(r.by).toBe('tap');
    const sent = llm.requests[0]!;
    expect(sent.system).toContain('Darija');
    expect(sent.tools).toEqual([]);
    expect(sent.messages[0]!.content[0]).toMatchObject({ type: 'image', mime: 'image/png' });
    expect(sent.messages[0]!.content[1]).toMatchObject({ type: 'text', text: expect.stringContaining('[y=500, x=500]') });
  });
  it('without a tap it asks about a pointing hand', () => {
    expect(locateInstruction({})).toMatch(/pointing/);
    expect(locateSystem('fr')).toContain('French');
  });
});

describe('POST /v1/vision/locate', () => {
  let app: FastifyInstance | undefined;
  afterEach(async () => app?.close());
  async function token(a: FastifyInstance): Promise<string> {
    const r = await a.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } });
    return (r.json() as { token: string }).token;
  }
  it('needs auth, validates and returns the box', async () => {
    app = buildServer(deps({ script: [text('{"found":true,"label":"كاس","box_2d":[100,200,500,600]}')] }));
    expect((await app.inject({ method: 'POST', url: '/v1/vision/locate', payload: { image: IMG } })).statusCode).toBe(401);
    const h = { authorization: `Bearer ${await token(app)}` };
    expect((await app.inject({ method: 'POST', url: '/v1/vision/locate', headers: h, payload: { image: 'x' } })).statusCode).toBe(400);
    const ok = await app.inject({ method: 'POST', url: '/v1/vision/locate', headers: h, payload: { image: IMG, tap: { x: 0.4, y: 0.3 } } });
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toMatchObject({ found: true, label: 'كاس', by: 'tap' });
  });
  it('says not configured without an AI provider', async () => {
    app = buildServer({ ...deps(), llm: null });
    const h = { authorization: `Bearer ${await token(app)}` };
    const r = await app.inject({ method: 'POST', url: '/v1/vision/locate', headers: h, payload: { image: IMG } });
    expect(r.statusCode).toBe(503);
  });
});

describe('live prompt', () => {
  it('explains the POINT cue', () => {
    expect(livePrompt({})).toContain('POINT:');
  });
});
