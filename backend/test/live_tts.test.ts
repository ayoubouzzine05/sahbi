import { describe, expect, it } from 'vitest';
import { buildServer } from '../src/build-server.js';
import { fillPrompt, robotNameForPrompt } from '../src/brain/context.js';
import { ChatRequestSchema } from '../src/brain/schema.js';
import { isLiveConfigured, isTtsConfigured, loadConfig } from '../src/config.js';
import { LIVE_WS_URL, createLiveToken, livePrompt } from '../src/live.js';
import { GeminiTtsProvider, geminiVoiceFor, pcmToWav } from '../src/providers/tts/gemini.js';
import { PROMPT_TEMPLATE } from '../src/prompt.generated.js';
import { toGeminiContents } from '../src/providers/llm/gemini.js';
import { toOpenAiMessages } from '../src/providers/llm/openai.js';
import { deps } from './helpers.js';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const UUID = '123e4567-e89b-42d3-a456-426614174000';

describe('robot name + Darija prompt', () => {
  it('fills the user-chosen robot name, sanitised, with a default', () => {
    expect(robotNameForPrompt('Zizou')).toBe('"Zizou"');
    expect(robotNameForPrompt(' a"b{{X}}\nc ')).toBe('"a b X c"');
    expect(robotNameForPrompt(undefined)).toContain('صاحبي');
    const req = ChatRequestSchema.parse({ message: 'salam', settings: { robot_name: 'Bobo' } });
    const p = fillPrompt(PROMPT_TEMPLATE, req);
    expect(p).toContain('Your name is "Bobo"');
    expect(p).not.toContain('{{');
  });
  it('the real prompt carries the Darija rules', () => {
    for (const w of ['دابا', 'بزاف', 'واش', 'ماعرفتش', 'NOT Modern Standard Arabic']) expect(PROMPT_TEMPLATE).toContain(w);
  });
});

describe('config: Gemini TTS + Live', () => {
  it('a Gemini key turns on Gemini TTS and Live automatically', () => {
    const c = loadConfig({ LLM_API_KEY: 'AQ.x' });
    expect(c.tts.provider).toBe('gemini');
    expect(isTtsConfigured(c)).toBe(true);
    expect(isLiveConfigured(c)).toBe(true);
    expect(c.live.model).toBe('gemini-3.8-live');
  });
  it('can be switched off; non-Gemini setups stay off', () => {
    expect(isTtsConfigured(loadConfig({ LLM_API_KEY: 'AQ.x', TTS_PROVIDER: 'none' }))).toBe(false);
    expect(isLiveConfigured(loadConfig({ LLM_API_KEY: 'AQ.x', LIVE_ENABLED: 'false' }))).toBe(false);
    const oa = loadConfig({ LLM_PROVIDER: 'openai', LLM_API_KEY: 'k', LLM_MODEL: 'm' });
    expect(isTtsConfigured(oa)).toBe(false);
    expect(isLiveConfigured(oa)).toBe(false);
  });
});

describe('GeminiTtsProvider', () => {
  it('picks voices by gender and accepts known names only', () => {
    expect(geminiVoiceFor({ gender: 'male' })).toBe('Puck');
    expect(geminiVoiceFor({ gender: 'female' })).toBe('Aoede');
    expect(geminiVoiceFor({})).toBe('Puck');
    expect(geminiVoiceFor({ voice: 'Charon', gender: 'female' })).toBe('Charon');
    expect(geminiVoiceFor({ voice: 'Hacker', gender: 'female' })).toBe('Aoede');
  });
  it('calls generateContent with AUDIO modality and returns WAV', async () => {
    let url = '';
    let body: Record<string, any> = {}; // eslint-disable-line @typescript-eslint/no-explicit-any
    let key = '';
    const fake = (async (u: string, init: RequestInit) => {
      url = u;
      body = JSON.parse(init.body as string);
      key = (init.headers as Record<string, string>)['x-goog-api-key']!;
      return json({ candidates: [{ content: { parts: [{ inlineData: { mimeType: 'audio/L16;codec=pcm;rate=24000', data: Buffer.alloc(480).toString('base64') } }] } }] });
    }) as unknown as typeof fetch;
    const p = new GeminiTtsProvider({ apiKey: 'AQ.k', baseUrl: 'https://generativelanguage.googleapis.com', model: 'gemini-3.8-flash-tts', timeoutMs: 5000 }, fake);
    const out = await p.synthesize({ text: 'سلام', language: 'ar-MA', gender: 'male' });
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash-tts:generateContent');
    expect(key).toBe('AQ.k');
    expect(body.generationConfig.responseModalities).toEqual(['AUDIO']);
    expect(body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName).toBe('Puck');
    expect(body.contents[0].parts[0].text.endsWith(':\nسلام')).toBe(true);
    expect(out.contentType).toBe('audio/wav');
    expect(out.audio.subarray(0, 4).toString('ascii')).toBe('RIFF');
    expect(out.audio.length).toBe(44 + 480);
    expect(out.audio.readUInt32LE(24)).toBe(24000);
  });
  it('passes WAV through, reads the PCM rate, rejects empty responses', async () => {
    const wav = pcmToWav(Buffer.alloc(10), 24000);
    const w = (async () => json({ candidates: [{ content: { parts: [{ inlineData: { mimeType: 'audio/wav', data: wav.toString('base64') } }] } }] })) as unknown as typeof fetch;
    const p = new GeminiTtsProvider({ apiKey: 'k', baseUrl: 'https://g', model: 'm', timeoutMs: 5000 }, w);
    expect((await p.synthesize({ text: 'x', language: 'fr-FR' })).audio.equals(wav)).toBe(true);
    const r16 = (async () => json({ candidates: [{ content: { parts: [{ inlineData: { mimeType: 'audio/L16;rate=16000', data: Buffer.alloc(100).toString('base64') } }] } }] })) as unknown as typeof fetch;
    const o16 = await new GeminiTtsProvider({ apiKey: 'k', baseUrl: 'https://g', model: 'm', timeoutMs: 5000 }, r16).synthesize({ text: 'x', language: 'ar-MA' });
    expect(o16.audio.readUInt32LE(24)).toBe(16000);
    const empty = (async () => json({ candidates: [] })) as unknown as typeof fetch;
    await expect(new GeminiTtsProvider({ apiKey: 'k', baseUrl: 'https://g', model: 'm', timeoutMs: 5000 }, empty).synthesize({ text: 'x', language: 'ar-MA' })).rejects.toThrow('no audio');
    const unauth = (async () => json({ error: { status: 'UNAUTHENTICATED', message: 'API key not valid.' } }, 401)) as unknown as typeof fetch;
    await expect(new GeminiTtsProvider({ apiKey: 'k', baseUrl: 'https://g', model: 'm', timeoutMs: 5000 }, unauth).synthesize({ text: 'x', language: 'ar-MA' })).rejects.toThrow('UNAUTHENTICATED: API key not valid.');
  });
});

describe('camera photo in chat', () => {
  it('schema accepts one base64 JPEG and rejects junk', () => {
    const ok = ChatRequestSchema.safeParse({ message: 'chno hada?', image: { mime: 'image/jpeg', data: Buffer.alloc(64).toString('base64') } });
    expect(ok.success).toBe(true);
    expect(ChatRequestSchema.safeParse({ message: 'x', image: { mime: 'image/gif', data: 'AAAAAAAAAAAAAAAAAAAA' } }).success).toBe(false);
    expect(ChatRequestSchema.safeParse({ message: 'x', image: { mime: 'image/jpeg', data: 'not base64 !!!!!!!!' } }).success).toBe(false);
  });
  it('Gemini receives the photo as inlineData before the text', () => {
    const c = toGeminiContents([{ role: 'user', content: [{ type: 'image', mime: 'image/jpeg', data: 'QUJD' }, { type: 'text', text: 'chno hada?' }] }]);
    expect(c[0]!.parts[0]).toEqual({ inlineData: { mimeType: 'image/jpeg', data: 'QUJD' } });
    expect(c[0]!.parts[1]).toEqual({ text: 'chno hada?' });
  });
  it('text-only adapters say they cannot see instead of pretending', () => {
    const m = toOpenAiMessages('sys', [{ role: 'user', content: [{ type: 'image', mime: 'image/jpeg', data: 'QUJD' }, { type: 'text', text: 'chno hada?' }] }]);
    expect(JSON.stringify(m)).toContain('cannot see images');
    expect(JSON.stringify(m)).not.toContain('QUJD');
  });
  it('the chat route accepts a photo-sized body and the model gets the image', async () => {
    const d = deps();
    const app = buildServer(d);
    const tok = (await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } })).json().token as string;
    const r = await app.inject({
      method: 'POST',
      url: '/v1/chat',
      headers: { authorization: `Bearer ${tok}` },
      payload: { message: 'chno hada?', image: { mime: 'image/jpeg', data: Buffer.alloc(300_000).toString('base64') } },
    });
    expect(r.statusCode).toBe(200);
    const sent = d.llm!.requests[0]!.messages.at(-1)!.content;
    expect(sent[0]!.type).toBe('image');
  });
});

describe('Live ephemeral tokens', () => {
  it('locks model, voice, prompt and compression into a single-use token', async () => {
    let url = '';
    let body: Record<string, any> = {}; // eslint-disable-line @typescript-eslint/no-explicit-any
    const fake = (async (u: string, init: RequestInit) => {
      url = u;
      body = JSON.parse(init.body as string);
      return json({ name: 'auth_tokens/abc123' });
    }) as unknown as typeof fetch;
    const now = new Date('2026-11-18T10:00:00Z');
    const t = await createLiveToken({ apiKey: 'AQ.k', baseUrl: 'https://generativelanguage.googleapis.com/', model: 'gemini-3.8-live', timeoutMs: 5000 }, { robotName: 'Zizou', gender: 'female' }, fake, now);
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/auth_tokens');
    expect(body.uses).toBe(1);
    expect(body.expireTime).toBe('2026-11-18T10:30:00.000Z');
    expect(body.newSessionExpireTime).toBe('2026-11-18T10:02:00.000Z');
    const setup = body.bidiGenerateContentSetup;
    expect(setup.model).toBe('models/gemini-3.8-live');
    expect(setup.generationConfig.responseModalities).toEqual(['AUDIO']);
    expect(setup.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName).toBe('Aoede');
    expect(setup.systemInstruction.parts[0].text).toContain('"Zizou"');
    expect(setup.contextWindowCompression).toEqual({ slidingWindow: {} });
    expect(setup.sessionResumption).toBeUndefined();
    expect(body.fieldMask).toBe(
      'model,generationConfig.responseModalities,generationConfig.speechConfig,systemInstruction.parts,inputAudioTranscription,outputAudioTranscription,contextWindowCompression.slidingWindow',
    );
    expect(t).toMatchObject({ token: 'auth_tokens/abc123', ws_url: LIVE_WS_URL, voice: 'Aoede', model: 'gemini-3.8-live' });
    expect(JSON.stringify(t)).not.toContain('AQ.k');
  });
  it('the live prompt is honest about what it sees and speaks Darija', () => {
    const p = livePrompt({});
    expect(p).toContain('LIVE CAMERA');
    expect(p).toContain('Never invent details');
    expect(p).toContain('Moroccan Darija');
  });
  it('route: auth required, 503 when not configured, token otherwise', async () => {
    const off = buildServer(deps());
    const tok = (await off.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } })).json().token as string;
    const h = { authorization: `Bearer ${tok}` };
    expect((await off.inject({ method: 'POST', url: '/v1/live/token', payload: {} })).statusCode).toBe(401);
    expect((await off.inject({ method: 'POST', url: '/v1/live/token', headers: h, payload: {} })).statusCode).toBe(503);
    expect((await off.inject({ method: 'GET', url: '/v1/health' })).json().services.live).toEqual({ configured: false, provider: 'none' });

    const seen: unknown[] = [];
    const on = buildServer(deps({ live: async (o) => (seen.push(o), { token: 't', model: 'm', ws_url: LIVE_WS_URL, voice: 'Puck', expires_at: 'e', new_session_expires_at: 'n' }) }));
    const tok2 = (await on.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_id: UUID } })).json().token as string;
    const r = await on.inject({ method: 'POST', url: '/v1/live/token', headers: { authorization: `Bearer ${tok2}` }, payload: { robot_name: 'Bobo' } });
    expect(r.statusCode).toBe(200);
    expect(r.json().token).toBe('t');
    expect(r.headers['cache-control']).toBe('no-store');
    expect(seen[0]).toMatchObject({ robotName: 'Bobo', gender: 'male', replyLanguage: 'darija' });
    expect((await on.inject({ method: 'POST', url: '/v1/live/token', headers: { authorization: `Bearer ${tok2}` }, payload: { gender: 'robot' } })).statusCode).toBe(400);
    expect((await on.inject({ method: 'GET', url: '/v1/health' })).json().services.live.configured).toBe(true);
  });
});
