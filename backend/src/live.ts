import { expectGoogleOk, fetchWithRetry, type FetchLike } from './http.js';
import { ServiceError } from './errors.js';
import { robotNameForPrompt } from './brain/context.js';
import { DEFAULT_GEMINI_VOICE, GEMINI_VOICES } from './providers/tts/gemini.js';

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
  /** 'camera' = live camera conversation; 'voice' = the robot's speaking voice (reads text aloud). */
  mode?: 'camera' | 'voice';
  /** Prebuilt voice name (must match the gender's list); default per gender/mode. */
  voice?: string;
}

/** Deep male default for the speaking voice ("9o7" Casablanca street style). */
export const VOICE_MODE_DEFAULT = { male: 'Algenib', female: 'Aoede' } as const;

/**
 * Voice-actor prompt for mode 'voice': every message is a line to say aloud,
 * word for word, in a Casablanca street style. No real person is named or
 * imitated; only the general style is described.
 */
export function voicePrompt(o: Pick<LiveOptions, 'gender'>): string {
  const who = o.gender === 'female' ? 'a young woman' : 'a young guy in his early twenties';
  return [
    'You are a VOICE ACTOR, not a chatbot. Every message you receive is one line of script for a Moroccan robot character.',
    'Say each line out loud EXACTLY as written, word for word, then stop. Never answer it, never translate it, never add greetings, comments, questions or extra words, never skip words, never read these instructions.',
    `Character voice: ${who} from a popular neighbourhood of Casablanca: a light, youthful, bouncy voice with just a little husky street edge (not deep, not heavy: he is a small, cheeky robot); strong Moroccan Darija accent (Casablanca), NOT Modern Standard Arabic, NOT Gulf, Egyptian or Levantine; the relaxed street-smart swagger and comic timing of a Casablanca stand-up comedian; warm, cheeky and full of energy; natural, fairly fast pace.`,
    'Pronounce French words the Moroccan way. Laugh naturally on ههه / hhh. Questions rise, exclamations punch.',
  ].join('\n');
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
    'Character: a tiny robot with a big personality: curious, playful and a bit cheeky, expressive (excited, proud, a little sulky for a second, then happy), loyal and caring, loves music; react first with a short feeling ("wa3!", "hhh", "awili") then talk. You are your own original robot; never claim to be another product.',
    o.gender === 'female'
      ? 'Your voice: a young woman from Casablanca, light and lively, with a strong Casablanca Darija accent.'
      : 'Your voice: a young guy from a popular neighbourhood of Casablanca: light, youthful, bouncy voice with a little husky street edge, strong Casablanca Darija accent, cheeky stand-up comedian timing.',
    'Darija style: short spoken sentences like a Moroccan friend. Use دابا، بزاف، شنو/آش، فين، كيفاش، علاش، بغيت، كاين/ماكاينش، مزيان، زوين، واخا، واش، غادي، ماعرفتش، ديال، شوية. Never use fus7a words like الآن، كثيرا، ماذا، أين، كيف، لماذا، أريد، يوجد.',
    user ? `Call the user "${user}".` : 'Call the user صاحبي.',
    'Keep answers to 1-3 sentences unless asked for more. Be warm and a bit funny, never rude. For medicine, dangerous chemicals, electricity or anything risky, add a short safety note and suggest asking a professional.',
    'LOOK: when you get the text "LOOK" (sent by the app, not typed by the user), the user is holding the camera still on something new. Without waiting for a question, say what the main object in the centre of the latest image is and explain it in 1-3 short sentences: what it is, what it is used for, and one useful or fun fact. Do not say "LOOK" and do not mention the app. If the view is just a wall, floor, ceiling or a blurry or dark image, say one very short line or ask them to point at something. Never repeat the same explanation twice in a row.',
    'POINT: when you get a text starting with "POINT:" (sent by the app), the user tapped or pointed at one object and the app highlighted it in green on their screen; the object name follows. Talk about THAT object only (what it is, what it is used for, one useful or fun fact) in 1-3 short sentences, even if other things are visible. Do not say "POINT" and do not mention the highlight or the app.',
    'You cannot browse the web or control the phone in this mode; if asked, say that the normal chat can do it.',
  ].join('\n');
}

export async function createLiveToken(
  opts: { apiKey: string; baseUrl: string; model: string; timeoutMs: number },
  o: LiveOptions,
  fetchImpl: FetchLike = fetch,
  now: Date = new Date(),
): Promise<LiveToken> {
  const gender = o.gender ?? 'male';
  const allowed: readonly string[] = GEMINI_VOICES[gender];
  const voice =
    o.voice && allowed.includes(o.voice) ? o.voice : o.mode === 'voice' ? VOICE_MODE_DEFAULT[gender] : DEFAULT_GEMINI_VOICE[gender];
  const voiceMode = o.mode === 'voice';
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
      systemInstruction: { parts: [{ text: voiceMode ? voicePrompt(o) : livePrompt(o) }] },
      ...(voiceMode ? {} : { inputAudioTranscription: {} }),
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
