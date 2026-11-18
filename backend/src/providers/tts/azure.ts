import { expectOk, fetchWithRetry, type FetchLike } from '../../http.js';
import type { TtsProvider, TtsRequest } from './types.js';

export function escapeXml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

/** Voices verified in Azure "Language and voice support" docs (checked 2026-11-16). */
export const AZURE_VOICES: Record<string, string[]> = {
  'ar-MA': ['ar-MA-JamalNeural', 'ar-MA-MounaNeural'],
};

export function buildSsml(req: TtsRequest, voice: string): string {
  const pct = (v: number | undefined) => `${Math.round(((v ?? 1) - 1) * 100)}%`;
  return (
    `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${escapeXml(req.language)}">` +
    `<voice name="${escapeXml(voice)}"><prosody rate="${pct(req.rate)}" pitch="${pct(req.pitch)}">${escapeXml(req.text)}</prosody></voice></speak>`
  );
}

/** Azure Neural TTS REST: POST https://{region}.tts.speech.microsoft.com/cognitiveservices/v1 */
export class AzureTtsProvider implements TtsProvider {
  readonly name = 'azure';
  constructor(
    private readonly key: string,
    private readonly region: string,
    private readonly defaultVoice: string,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async synthesize(req: TtsRequest): Promise<{ audio: Buffer; contentType: string }> {
    const voice = req.voice || (req.gender === 'female' ? 'ar-MA-MounaNeural' : req.gender === 'male' ? 'ar-MA-JamalNeural' : this.defaultVoice);
    const res = await fetchWithRetry(this.fetchImpl, `https://${this.region}.tts.speech.microsoft.com/cognitiveservices/v1`, {
      method: 'POST',
      headers: {
        'Ocp-Apim-Subscription-Key': this.key,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
        'User-Agent': 'sahbi-backend',
      },
      body: buildSsml(req, voice),
    });
    await expectOk(res, 'TTS');
    return { audio: Buffer.from(await res.arrayBuffer()), contentType: 'audio/mpeg' };
  }
}
