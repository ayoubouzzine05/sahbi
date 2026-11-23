import { describe, expect, it } from 'vitest';
import { ChatRequestSchema, dropUnknownFaceActions, REPLY_TOOL_JSON_SCHEMA, ReplySchema } from '../src/brain/schema.js';
import { goodReply } from './helpers.js';

describe('ReplySchema', () => {
  it('accepts a valid reply and defaults arrays', () => {
    const r = ReplySchema.parse({ ...goodReply, actions: undefined });
    expect(r.actions).toEqual([]);
    expect(r.source_ids).toEqual([]);
  });
  it.each([
    ['empty display_text', { display_text: '  ' }],
    ['bad language', { language: 'de' }],
    ['bad emotion', { emotion: 'ecstatic' }],
    ['intensity > 1', { intensity: 1.5 }],
    ['unknown action', { actions: [{ type: 'launch_rocket' }] }],
    ['volume level out of range', { actions: [{ type: 'set_volume', level: 3 }] }],
  ])('rejects %s', (_n, patch) => {
    expect(ReplySchema.safeParse({ ...goodReply, ...patch }).success).toBe(false);
  });
  it('JSON schema for the tool stays in sync with zod enums', () => {
    expect(REPLY_TOOL_JSON_SCHEMA.properties.language.enum).toEqual(['darija', 'ar', 'fr', 'en']);
    expect(REPLY_TOOL_JSON_SCHEMA.properties.emotion.enum).toEqual(['neutral', 'happy', 'sad', 'curious', 'surprised', 'sleepy', 'angry']);
    const zodTypes = ['music.play', 'music.pause', 'music.resume', 'music.stop', 'music.next', 'music.previous', 'set_volume', 'translate', 'set_reply_language', 'image.show', 'face.play'];
    expect(REPLY_TOOL_JSON_SCHEMA.properties.actions.items.properties.type.enum).toEqual(zodTypes);
    for (const t of zodTypes) {
      const sample: Record<string, unknown> = { type: t };
      if (t === 'translate') Object.assign(sample, { source_text: 'a', target_language: 'en', translation: 'b' });
      if (t === 'set_reply_language') sample.language = 'fr';
      if (t === 'image.show') sample.query = 'Chefchaouen';
      if (t === 'face.play') sample.animation = 'hands_up';
      expect(ReplySchema.safeParse({ ...goodReply, actions: [sample] }).success, t).toBe(true);
    }
  });

  it('face.play only accepts known animations', () => {
    const ok = ReplySchema.safeParse({ ...goodReply, actions: [{ type: 'face.play', animation: 'drink' }] });
    expect(ok.success).toBe(true);
    const bad = ReplySchema.safeParse({ ...goodReply, actions: [{ type: 'face.play', animation: 'fly' }] });
    expect(bad.success).toBe(false);
    const cleaned = ReplySchema.safeParse(
      dropUnknownFaceActions({ ...goodReply, actions: [{ type: 'face.play', animation: 'fly' }, { type: 'music.pause' }] }),
    );
    expect(cleaned.success).toBe(true);
    expect(cleaned.success && cleaned.data.actions.map((a) => a.type)).toEqual(['music.pause']);
  });
});

describe('ChatRequestSchema', () => {
  it('applies defaults', () => {
    const r = ChatRequestSchema.parse({ message: 'salam' });
    expect(r.settings.reply_language).toBe('darija');
    expect(r.history).toEqual([]);
  });
  it('enforces size limits', () => {
    expect(ChatRequestSchema.safeParse({ message: 'x'.repeat(2001) }).success).toBe(false);
    expect(ChatRequestSchema.safeParse({ message: 'hi', history: Array(41).fill({ role: 'user', text: 'a' }) }).success).toBe(false);
    expect(ChatRequestSchema.safeParse({ message: 'hi', memory: { facts: Array(31).fill('f') } }).success).toBe(false);
  });
});
