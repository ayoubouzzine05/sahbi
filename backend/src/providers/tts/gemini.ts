import { expectGoogleOk, fetchWithRetry, type FetchLike } from '../../http.js';
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
export const DEFAULT_GEMINI_VOICE = { male: 'Puck', female: 'Aoede' } as const;

export function geminiVoiceFor(req: Pick<TtsRequest, 'voice' | 'gender'>): string {
  const all: readonly string[] = [...GEMINI_VOICES.male, ...GEMINI_VOICES.female];
  if (req.voice && all.includes(req.voice)) return req.voice;
  return DEFAULT_GEMINI_VOICE[req.gender ?? 'male'];
}

/** Delivery hint; Moroccan Darija is not in Google's TTS language table, so the accent is best-effort. */
export function speechStyle(language: string): string {
  return language.startsWith('ar')
    ? 'Casual, warm and friendly Moroccan speaker talking to a friend in Moroccan Darija, natural conversational pace'
    : 'Casual, warm and friendly, natural conversational pace';
}

/**
 * Gemini TTS via the Interactions API, as documented in
 * https://ai.google.dev/gemini-api/docs/speech-generation (REST example):
 * POST /v1beta/interactions → steps[type=model_output].content[type=audio].data
 * (unary default = complete WAV, 24 kHz mono 16-bit).
 */
export class GeminiTtsProvider implements TtsProvider {
  readonly name = 'gemini';
  constructor(
    private readonly opts: { apiKey: string; baseUrl: string; model: string; timeoutMs: number },
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async synthesize(req: TtsRequest): Promise<{ audio: Buffer; contentType: string }> {
    const base = this.opts.baseUrl.replace(/\/+$/, '').replace(/\/v1beta(\/openai)?$/i, '');
    const body = {
      model: this.opts.model,
      input: [{ type: 'user_input', content: [{ type: 'text', text: req.text, annotations: [{ type: 'speech_metadata', style: speechStyle(req.language) }] }] }],
      response_format: { type: 'audio' },
      generation_config: { speech_config: [{ voice: geminiVoiceFor(req) }] },
    };
    const res = await fetchWithRetry(
      this.fetchImpl,
      `${base}/v1beta/interactions`,
      { method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': this.opts.apiKey }, body: JSON.stringify(body) },
      { timeoutMs: this.opts.timeoutMs, retries: 1 },
    );
    await expectGoogleOk(res, 'TTS');
    const json = (await res.json()) as { steps?: Array<{ type?: string; content?: Array<{ type?: string; data?: string; mime_type?: string }> }> };
    const audio = (json.steps ?? [])
      .filter((s) => s.type === 'model_output')
      .flatMap((s) => s.content ?? [])
      .filter((c) => c.type === 'audio' && typeof c.data === 'string')
      .pop();
    if (!audio?.data) throw new ServiceError('upstream_error', 'TTS response had no audio', 502);
    const bytes = Buffer.from(audio.data, 'base64');
    const isWav = bytes.subarray(0, 4).toString('ascii') === 'RIFF';
    return { audio: isWav ? bytes : pcmToWav(bytes, 24000), contentType: 'audio/wav' };
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
