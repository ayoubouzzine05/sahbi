import { describe, expect, it } from 'vitest';
import { parseReact, reactSystem, ReactRequestSchema } from '../src/brain/react.js';

const img = 'a'.repeat(200);

describe('vision react', () => {
  it('parses a reaction and fills defaults', () => {
    const r = parseReact('```json\n{"react": true, "reaction": "scared", "subject_en": "spider", "display_text": "Aaaa! B3ed menni!", "tts_text": "آآآ! بعد مني!"}\n```');
    expect(r).toMatchObject({ react: true, reaction: 'scared', subject_en: 'spider', emotion: 'surprised', intensity: 0.7 });
  });

  it('scared never shows an angry face', () => {
    expect(parseReact('{"react": true, "reaction": "scared", "display_text": "aaa!", "emotion": "angry"}').emotion).toBe('surprised');
  });

  it('anything unclear means no reaction', () => {
    expect(parseReact('{"react": false}')).toEqual({ react: false });
    expect(parseReact('{"react": true, "reaction": "dance", "display_text": "x"}')).toEqual({ react: false });
    expect(parseReact('{"react": true, "reaction": "wow"}')).toEqual({ react: false });
    expect(parseReact('not json')).toEqual({ react: false });
  });

  it('clamps intensity and long text', () => {
    const r = parseReact(JSON.stringify({ react: true, reaction: 'love', display_text: 'x'.repeat(500), intensity: 7 }));
    expect(r.intensity).toBe(1);
    expect(r.display_text?.length).toBe(160);
    expect(r.tts_text).toBe(r.display_text);
  });

  it('prompt: language, mood, recent subjects, privacy', () => {
    const req = ReactRequestSchema.parse({ image: img, reply_language: 'darija', darija_script: 'latin', mood: 'sulking', recent: ['cat'], robot_name: 'Zizou' });
    const s = reactSystem(req);
    expect(s).toContain('Zizou');
    expect(s).toContain('Arabizi');
    expect(s).toContain('sulking');
    expect(s).toContain('cat');
    expect(s).toContain('never say who a person is');
    expect(s).not.toContain('{{');
  });

  it('rejects a missing image', () => {
    expect(ReactRequestSchema.safeParse({ image: '' }).success).toBe(false);
  });
});
