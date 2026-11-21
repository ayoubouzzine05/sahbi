import { expectGoogleOk, fetchWithRetry, type FetchLike } from './http.js';
import { ServiceError } from './errors.js';
import { robotNameForPrompt } from './brain/context.js';
import { DEFAULT_GEMINI_VOICE } from './providers/tts/gemini.js';

/**
 * Live camera/voice mode via the Gemini Live API (client-to-server with
 * ephemeral tokens, https://ai.google.dev/gemini-api/docs/ephemeral-tokens).
 * The backend mints a single-use token whose BidiGenerateContentSetup is
 * locked server-side (model, system prompt, voice), so the API key never
 * reaches the app and the app cannot change the prompt.
 */
export interface LiveOptions {
  robotName?: string;
  userName?: string;
  gender?: 'male' | 'female';
  replyLanguage?: 'darija' | 'ar' | 'fr' | 'en';
}

export interface LiveToken {
  token: string;
  model: string;
  ws_url: string;
  voice: string;
  expires_at: string;
  new_session_expires_at: string;
}

export const LIVE_WS_URL =
  'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained';

export function livePrompt(o: LiveOptions): string {
  const lang = {
    darija: 'Moroccan Darija (as spoken in Casablanca/Rabat; NOT Modern Standard Arabic, NOT Egyptian or Levantine). French words are fine.',
    ar: 'Modern Standard Arabic.',
    fr: 'French.',
    en: 'English.',
  }[o.replyLanguage ?? 'darija'];
  const user = (o.userName ?? '').replace(/[\n\r"{}<>]/g, ' ').trim().slice(0, 40);
  return [
    `Your name is ${robotNameForPrompt(o.robotName)}. You are a friendly Moroccan little robot companion (a real robot, not "in the phone"; never say you live in a phone). The user named you; when they say your name they are talking to you.`,
    'This is a continuous conversation, like two friends together: keep the conversation going naturally, react to what they say, and sometimes ask a short follow-up question. The user does not need to repeat your name.',
    'You are in LIVE CAMERA mode: you receive the phone camera as a stream of images (about one per second) plus the user\'s voice. Describe and explain what you actually see when the user asks (objects, text, plants, food, homework, devices...). If the image is dark, blurry or you cannot tell, say so honestly and ask them to move closer or add light. Never invent details you cannot see.',
    `Speak ${lang}`,
    'Darija style: short spoken sentences like a Moroccan friend. Use دابا، بزاف، شنو/آش، فين، كيفاش، علاش، بغيت، كاين/ماكاينش، مزيان، زوين، واخا، واش، غادي، ماعرفتش، ديال، شوية. Never use fus7a words like الآن، كثيرا، ماذا، أين، كيف، لماذا، أريد، يوجد.',
    user ? `Call the user "${user}".` : 'Call the user صاحبي.',
    'Keep answers to 1-3 sentences unless asked for more. Be warm and a bit funny, never rude. For medicine, dangerous chemicals, electricity or anything risky, add a short safety note and suggest asking a professional.',
    'TAPS: when you get a picture together with a text starting with "TAP", the user touched an object on the screen and the turquoise ring in that picture marks it. Without waiting for a question, say what the marked object is and explain it in 2-3 short sentences (what it is, what it is used for, one interesting or useful fact). If you cannot tell what it is, say so and ask them to move closer.',
    'You cannot browse the web or control the phone in this mode; if asked, say that the normal chat can do it.',
  ].join('\n');
}

export async function createLiveToken(
  opts: { apiKey: string; baseUrl: string; model: string; timeoutMs: number },
  o: LiveOptions,
  fetchImpl: FetchLike = fetch,
  now: Date = new Date(),
): Promise<LiveToken> {
  const voice = DEFAULT_GEMINI_VOICE[o.gender ?? 'male'];
  const expire = new Date(now.getTime() + 30 * 60_000).toISOString();
  const newSession = new Date(now.getTime() + 2 * 60_000).toISOString();
  const base = opts.baseUrl.replace(/\/+$/, '').replace(/\/v1beta(\/openai)?$/i, '');
  const body = {
    uses: 1,
    expireTime: expire,
    newSessionExpireTime: newSession,
    bidiGenerateContentSetup: {
      model: `models/${opts.model}`,
      generationConfig: {
        responseModalities: ['AUDIO'],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } },
      },
      systemInstruction: { parts: [{ text: livePrompt(o) }] },
      inputAudioTranscription: {},
      outputAudioTranscription: {},
      // Audio+video sessions are limited to ~2 min without compression.
      contextWindowCompression: { slidingWindow: {} },
    },
  };
  // Lock exactly these fields; the rest (sessionResumption handle,
  // realtimeInputConfig) comes from the app's setup message so a dropped
  // connection can be resumed. Same mask format as Google's SDK.
  const tokenBody = { ...body, fieldMask: fieldMaskFor(body.bidiGenerateContentSetup) };
  const res = await fetchWithRetry(
    fetchImpl,
    `${base}/v1beta/auth_tokens`,
    { method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': opts.apiKey }, body: JSON.stringify(tokenBody) },
    { timeoutMs: opts.timeoutMs, retries: 1 },
  );
  await expectGoogleOk(res, 'Live token');
  const json = (await res.json()) as { name?: string };
  if (!json.name) throw new ServiceError('upstream_error', 'Live token response had no token', 502);
  return { token: json.name, model: opts.model, ws_url: LIVE_WS_URL, voice, expires_at: expire, new_session_expires_at: newSession };
}

/**
 * Field mask over the locked setup, two levels deep, as built by
 * google-genai's tokens._get_field_masks (e.g. "generationConfig.speechConfig").
 */
export function fieldMaskFor(setup: Record<string, unknown>): string {
  const out: string[] = [];
  for (const [k, v] of Object.entries(setup)) {
    if (v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length) {
      for (const kk of Object.keys(v)) out.push(`${k}.${kk}`);
    } else out.push(k);
  }
  return out.join(',');
}
