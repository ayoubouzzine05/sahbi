export interface SttResult {
  text: string;
  language: string;
}
export interface SttProvider {
  readonly name: string;
  transcribe(audio: Buffer, contentType: string, language: string): Promise<SttResult>;
}
