import { ServiceError } from '../../errors.js';
import { expectGoogleOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { generateContentUrl } from '../llm/gemini.js';
import type { SttProvider, SttResult } from './types.js';

/**
 * Speech recognition with Gemini audio understanding (generateContent with
 * inline audio, https://ai.google.dev/gemini-api/docs/audio). Free with the
 * same key as the chat, and far better at Moroccan Darija than the phone's
 * built-in recogniser. The audio is sent inline and never stored.
 */
export class GeminiSttProvider implements SttProvider {
  readonly name = 'gemini';
  constructor(
    private readonly opts: { apiKey: string; baseUrl: string; models: string[]; timeoutMs: number },
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async transcribe(audio: Buffer, contentType: string, language: string): Promise<SttResult> {
    const body = {
      systemInstruction: { parts: [{ text: sttInstruction(language) }] },
      contents: [
        {
          role: 'user',
          parts: [{ inlineData: { mimeType: normaliseMime(contentType), data: audio.toString('base64') } }, { text: 'Transcribe this recording.' }],
        },
      ],
      generationConfig: { temperature: 0, maxOutputTokens: 600, thinkingConfig: { thinkingLevel: 'MINIMAL' } },
    };
    let lastErr: unknown;
    for (const [i, model] of this.opts.models.entries()) {
      const last = i === this.opts.models.length - 1;
      try {
        let res = await this.call(model, body);
        // Some models reject the MINIMAL thinking level: retry once without it.
        if (res.status === 400) {
          const { thinkingConfig: _drop, ...gc } = body.generationConfig; // eslint-disable-line @typescript-eslint/no-unused-vars
          res = await this.call(model, { ...body, generationConfig: gc });
        }
        if (!last && (res.status === 404 || res.status === 429 || res.status >= 500)) {
          lastErr = new ServiceError('upstream_error', `STT returned HTTP ${res.status}`, 502);
          continue;
        }
        await expectGoogleOk(res, 'STT');
        const json = (await res.json()) as { candidates?: Array<{ content?: { parts?: Array<{ text?: string; thought?: boolean }> } }> };
        const text = (json.candidates?.[0]?.content?.parts ?? [])
          .filter((p) => !p.thought)
          .map((p) => p.text ?? '')
          .join('');
        return { text: cleanTranscript(text), language };
      } catch (err) {
        lastErr = err;
        if (last) throw err;
      }
    }
    throw lastErr instanceof Error ? lastErr : new ServiceError('upstream_error', 'STT unavailable', 502);
  }

  private call(model: string, body: unknown): Promise<Response> {
    return fetchWithRetry(
      this.fetchImpl,
      generateContentUrl(this.opts.baseUrl, model),
      { method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': this.opts.apiKey }, body: JSON.stringify(body) },
      { timeoutMs: this.opts.timeoutMs, retries: 0 },
    );
  }
}

export function sttInstruction(language: string): string {
  const fr = language.startsWith('fr');
  const en = language.startsWith('en');
  return [
    'You are a speech-to-text engine for a Moroccan home robot. Output ONLY the exact words spoken, nothing else: no quotes, no translation, no comments, no answer to the question.',
    fr || en
      ? `The speaker mostly uses ${fr ? 'French' : 'English'}, maybe mixed with Moroccan Darija.`
      : 'The speaker mostly uses Moroccan Darija (Moroccan Arabic), often mixed with French, sometimes Spanish, English or Standard Arabic.',
    'Write Darija and Arabic words in Arabic script the way Moroccans write them (e.g. "شنو", "كيداير", "بغيت", "دابا", "واش", "فين"). Write French, English and Spanish words in Latin script.',
    'Keep names as heard. If there is no intelligible speech (silence, noise, music only), output an empty answer.',
  ].join('\n');
}

function normaliseMime(ct: string): string {
  const c = ct.toLowerCase();
  if (c.includes('wav') || c === 'audio/x-wav') return 'audio/wav';
  if (c.includes('ogg') || c.includes('opus')) return 'audio/ogg';
  if (c.includes('mp4') || c.includes('m4a') || c.includes('aac')) return 'audio/aac';
  if (c.includes('mpeg') || c.includes('mp3')) return 'audio/mp3';
  return 'audio/wav';
}

/** Strips wrappers some models add ("Transcript:", quotes) and "no speech" notes. */
export function cleanTranscript(t: string): string {
  let s = t.trim().replace(/^(transcript(ion)?|النص)\s*[:：]\s*/i, '');
  s = s.replace(/^["“«]+|["”»]+$/g, '').trim();
  if (/^\(?\[?\s*(no speech|silence|inaudible|empty|music|noise|لا يوجد كلام|صمت)[^\])]*\]?\)?\.?$/i.test(s)) return '';
  return s;
}
