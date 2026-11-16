export interface TtsRequest {
  text: string;
  voice?: string;
  language: string;
  /** relative rate, 0.5 .. 2.0 */
  rate?: number;
  /** relative pitch, 0.5 .. 2.0 */
  pitch?: number;
}
export interface TtsProvider {
  readonly name: string;
  synthesize(req: TtsRequest): Promise<{ audio: Buffer; contentType: string }>;
}
