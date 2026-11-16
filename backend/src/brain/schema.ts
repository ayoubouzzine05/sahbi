import { z } from 'zod';

export const EMOTIONS = ['neutral', 'happy', 'sad', 'curious', 'surprised', 'sleepy', 'angry'] as const;
export const LANGUAGES = ['darija', 'ar', 'fr', 'en'] as const;

export const ActionSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('music.play'), query: z.string().max(200).optional(), source: z.enum(['local', 'spotify', 'youtube_music']).optional() }),
  z.object({ type: z.literal('music.pause') }),
  z.object({ type: z.literal('music.resume') }),
  z.object({ type: z.literal('music.stop') }),
  z.object({ type: z.literal('music.next') }),
  z.object({ type: z.literal('music.previous') }),
  z.object({ type: z.literal('set_volume'), level: z.number().min(0).max(1).optional(), delta: z.number().min(-1).max(1).optional() }),
  z.object({ type: z.literal('translate'), source_text: z.string().max(1000), target_language: z.string().max(20), translation: z.string().max(2000) }),
  z.object({ type: z.literal('set_reply_language'), language: z.enum(LANGUAGES) }),
]);
export type Action = z.infer<typeof ActionSchema>;

/** The output contract every LLM reply must satisfy (validated, retried once). */
export const ReplySchema = z.object({
  display_text: z.string().trim().min(1).max(2000),
  tts_text: z.string().trim().min(1).max(2000),
  language: z.enum(LANGUAGES),
  emotion: z.enum(EMOTIONS),
  intensity: z.number().min(0).max(1),
  actions: z.array(ActionSchema).max(5).default([]),
  source_ids: z.array(z.number().int().nonnegative()).max(10).default([]),
  sources_agree: z.boolean().optional(),
});
export type Reply = z.infer<typeof ReplySchema>;

/** JSON Schema of the sahbi_reply tool (kept in sync with ReplySchema by a unit test). */
export const REPLY_TOOL_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['display_text', 'tts_text', 'language', 'emotion', 'intensity', 'actions'],
  properties: {
    display_text: { type: 'string', description: 'Text shown in the chat bubble, in the configured script.' },
    tts_text: { type: 'string', description: 'Text for speech synthesis. Arabic script for darija/ar. No emojis, URLs or markdown.' },
    language: { type: 'string', enum: [...LANGUAGES] },
    emotion: { type: 'string', enum: [...EMOTIONS] },
    intensity: { type: 'number', minimum: 0, maximum: 1 },
    actions: {
      type: 'array',
      items: {
        type: 'object',
        required: ['type'],
        properties: {
          type: { type: 'string', enum: ['music.play', 'music.pause', 'music.resume', 'music.stop', 'music.next', 'music.previous', 'set_volume', 'translate', 'set_reply_language'] },
          query: { type: 'string' },
          source: { type: 'string', enum: ['local', 'spotify', 'youtube_music'] },
          level: { type: 'number', minimum: 0, maximum: 1 },
          delta: { type: 'number', minimum: -1, maximum: 1 },
          source_text: { type: 'string' },
          target_language: { type: 'string' },
          translation: { type: 'string' },
          language: { type: 'string', enum: [...LANGUAGES] },
        },
      },
    },
    source_ids: { type: 'array', items: { type: 'integer' }, description: 'ids of web_search results that support the answer' },
    sources_agree: { type: 'boolean' },
  },
} as const;

export const HistoryTurnSchema = z.object({ role: z.enum(['user', 'assistant']), text: z.string().max(4000) });

export const ChatRequestSchema = z.object({
  message: z.string().trim().min(1).max(2000),
  history: z.array(HistoryTurnSchema).max(40).default([]),
  summary: z.string().max(3000).optional(),
  settings: z
    .object({
      reply_language: z.enum(LANGUAGES).default('darija'),
      darija_script: z.enum(['arabic', 'latin']).default('arabic'),
      humor: z.number().min(0).max(1).default(0.6),
      formality: z.enum(['casual', 'polite']).default('casual'),
      user_name: z.string().max(40).optional(),
    })
    .default({ reply_language: 'darija', darija_script: 'arabic', humor: 0.6, formality: 'casual' }),
  /** Only sent by the app when the user consented to memory. */
  memory: z.object({ facts: z.array(z.string().max(300)).max(30) }).optional(),
  client: z.object({ local_time: z.string().max(60).optional(), app_state: z.string().max(300).optional() }).default({}),
});
export type ChatRequest = z.infer<typeof ChatRequestSchema>;

export function formatZodError(err: z.ZodError): string {
  return err.issues
    .slice(0, 6)
    .map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`)
    .join('; ');
}
