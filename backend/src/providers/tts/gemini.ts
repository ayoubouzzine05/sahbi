import { expectGoogleOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { generateContentUrl } from '../llm/gemini.js';
import { ServiceError } from '../../errors.js';
import type { TtsProvider, TtsRequest } from './types.js';

/**
 * Prebuilt Gemini voices by perceived gender, checked against Google's
 * Chirp 3 HD voice table (https://cloud.google.com/text-to-speech/docs/chirp3-hd).
 */
export const GEMINI_VOICES = {
  male: ['Puck', 'Charon', 'Fenrir', 'Orus', 'Achird', 'Algenib', 'Alnilam', 'Enceladus', 'Iapetus', 'Rasalgethi', 'Sadachbia', 'Sadaltager', 'Schedar', 'Umbriel', 'Zubenelgenubi', 'Algieba'],
  female: ['Aoede', 'Kore', 'Leda', 'Zephyr', 'Achernar', 'Autonoe', 'Callirrhoe', 'Despina', 'Erinome', 'Gacrux', 'Laomedeia', 'Pulcherrima', 'Sulafat', 'Vindemiatrix'],
} as const;
/** Algenib = the voice the user picked (live voice "C"); the fallback TTS keeps the same timbre. */
export const DEFAULT_GEMINI_VOICE = { male: 'Algenib', female: 'Aoede' } as const;

export function geminiVoiceFor(req: Pick<TtsRequest, 'voice' | 'gender'>): string {
  const all: readonly string[] = [...GEMINI_VOICES.male, ...GEMINI_VOICES.female];
  if (req.voice && all.includes(req.voice)) return req.voice;
  return DEFAULT_GEMINI_VOICE[req.gender ?? 'male'];
}

/** Delivery hint; Moroccan Darija is not in Google's TTS language table, so the accent is best-effort. */
export function speechStyle(language: string, gender: 'male' | 'female' = 'male'): string {
  return language.startsWith('ar')
    ? `Read this aloud like a young ${gender === 'female' ? 'woman' : 'man'} from Casablanca chatting with a friend, in a natural Moroccan Darija accent (not Modern Standard Arabic), warm, relaxed and lively`
    : 'Read this aloud in a warm, relaxed and lively conversational tone';
}

/**
 * NOT sent to the model: measured live on 2026-11-16 with gemini-3.8-flash-tts,
 * a "style:\ntext" prompt made the voice read the English instruction aloud
 * (16.9 s of audio for a 2.5 s sentence). Only the exact words are sent; kept
 * for reference and tests.
 */
export function ttsPrompt(text: string, language: string, gender: 'male' | 'female' = 'male'): string {
  return `${speechStyle(language, gender)}:\n${text}`;
}

/**
 * Gemini TTS through `generateContent` with `responseModalities: ["AUDIO"]`
 * (https://ai.google.dev/gemini-api/docs/speech-generation). The Interactions
 * endpoint rejects AI Studio "AQ." auth keys with 401 (seen live on
 * 2026-11-18), while generateContent accepts them, so generateContent is used.
 * Output: inline audio, either WAV or raw 16-bit PCM (`audio/L16;rate=24000`).
 */
export class GeminiTtsProvider implements TtsProvider {
  readonly name = 'gemini';
  constructor(
    private readonly opts: { apiKey: string; baseUrl: string; model: string; timeoutMs: number; maxRateLimitWaitMs?: number },
    private readonly fetchImpl: FetchLike = fetch,
    private readonly sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
  ) {}

  async synthesize(req: TtsRequest): Promise<{ audio: Buffer; contentType: string }> {
    const body = {
      contents: [{ role: 'user', parts: [{ text: req.text }] }],
      generationConfig: {
        responseModalities: ['AUDIO'],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: geminiVoiceFor(req) } } },
      },
    };
    const call = () =>
      fetchWithRetry(
        this.fetchImpl,
        generateContentUrl(this.opts.baseUrl, this.opts.model),
        { method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': this.opts.apiKey }, body: JSON.stringify(body) },
        { timeoutMs: this.opts.timeoutMs, retries: 1 },
      );
    let res = await call();
    // The free TTS tier allows only a few sentences per minute. When Google
    // says the quota frees up soon, wait for it (same voice, a little later)
    // instead of failing; otherwise report rate_limited so the app can retry.
    if (res.status === 429) {
      const wait = await retryDelayMs(res);
      const max = this.opts.maxRateLimitWaitMs ?? 6000;
      if (wait !== null && wait <= max) {
        await this.sleep(wait + 250);
        res = await call();
      }
      if (res.status === 429) throw new ServiceError('rate_limited', 'TTS free quota is busy, try again in a few seconds', 429);
    }
    await expectGoogleOk(res, 'TTS');
    const json = (await res.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ inlineData?: { mimeType?: string; data?: string } }> } }>;
    };
    const part = (json.candidates?.[0]?.content?.parts ?? []).find((p) => typeof p.inlineData?.data === 'string');
    if (!part?.inlineData?.data) throw new ServiceError('upstream_error', 'TTS response had no audio', 502);
    const bytes = Buffer.from(part.inlineData.data, 'base64');
    if (bytes.subarray(0, 4).toString('ascii') === 'RIFF') return { audio: bytes, contentType: 'audio/wav' };
    const rate = Number(/rate=(\d+)/i.exec(part.inlineData.mimeType ?? '')?.[1] ?? 24000) || 24000;
    return { audio: pcmToWav(bytes, rate), contentType: 'audio/wav' };
  }
}

/** Wraps raw 16-bit mono PCM in a WAV header (in case the API returns headerless PCM). */
export function pcmToWav(pcm: Buffer, sampleRate: number): Buffer {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0, 'ascii');
  h.writeUInt32LE(36 + pcm.length, 4);
  h.write('WAVE', 8, 'ascii');
  h.write('fmt ', 12, 'ascii');
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22);
  h.writeUInt32LE(sampleRate, 24);
  h.writeUInt32LE(sampleRate * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write('data', 36, 'ascii');
  h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

/** Google's RetryInfo.retryDelay ("12s", "1.5s") from a 429 body, in ms. */
export async function retryDelayMs(res: Response): Promise<number | null> {
  try {
    const j = (await res.json()) as { error?: { details?: Array<{ '@type'?: string; retryDelay?: string }> } };
    const d = (j.error?.details ?? []).find((x) => typeof x.retryDelay === 'string')?.retryDelay;
    const m = d ? /^(\d+(?:\.\d+)?)s$/.exec(d) : null;
    return m ? Math.round(Number(m[1]) * 1000) : null;
  } catch {
    return null;
  }
}

