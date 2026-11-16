import { expectOk, fetchWithRetry, type FetchLike } from '../../http.js';
import type { SttProvider, SttResult } from './types.js';

/** OpenAI audio transcription endpoint; model from OPENAI_STT_MODEL. */
export class OpenAiSttProvider implements SttProvider {
  readonly name = 'openai';
  constructor(
    private readonly key: string,
    private readonly model: string,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async transcribe(audio: Buffer, contentType: string, language: string): Promise<SttResult> {
    const form = new FormData();
    const ext = contentType.includes('ogg') ? 'ogg' : contentType.includes('mp4') || contentType.includes('m4a') ? 'm4a' : 'wav';
    form.append('file', new Blob([new Uint8Array(audio)], { type: contentType }), `audio.${ext}`);
    form.append('model', this.model);
    const iso = language.split('-')[0];
    if (iso) form.append('language', iso);
    const res = await fetchWithRetry(this.fetchImpl, 'https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { authorization: `Bearer ${this.key}` },
      body: form,
    });
    await expectOk(res, 'STT');
    const json = (await res.json()) as { text?: string };
    return { text: json.text ?? '', language };
  }
}
