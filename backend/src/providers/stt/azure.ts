import { expectOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { ServiceError } from '../../errors.js';
import type { SttProvider, SttResult } from './types.js';

/**
 * Azure Speech "short audio" REST API (<= 60 s, WAV/PCM 16 kHz mono or OGG/Opus).
 * https://learn.microsoft.com/azure/ai-services/speech-service/rest-speech-to-text-short
 */
export class AzureSttProvider implements SttProvider {
  readonly name = 'azure';
  constructor(
    private readonly key: string,
    private readonly region: string,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async transcribe(audio: Buffer, contentType: string, language: string): Promise<SttResult> {
    const url = `https://${this.region}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=${encodeURIComponent(language)}&format=simple`;
    const res = await fetchWithRetry(this.fetchImpl, url, {
      method: 'POST',
      headers: { 'Ocp-Apim-Subscription-Key': this.key, 'Content-Type': contentType, Accept: 'application/json' },
      body: new Uint8Array(audio),
    });
    await expectOk(res, 'STT');
    const json = (await res.json()) as { RecognitionStatus?: string; DisplayText?: string };
    if (json.RecognitionStatus === 'NoMatch' || json.RecognitionStatus === 'InitialSilenceTimeout') return { text: '', language };
    if (json.RecognitionStatus !== 'Success') throw new ServiceError('upstream_error', `STT status ${json.RecognitionStatus ?? 'unknown'}`);
    return { text: json.DisplayText ?? '', language };
  }
}
