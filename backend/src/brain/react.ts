import { z } from 'zod';
import { ServiceError } from '../errors.js';
import type { LlmProvider } from '../providers/llm/types.js';
import { robotNameForPrompt } from './context.js';

/**
 * "The robot's eyes": the app sends one small frame from the front camera
 * when the view settles on something new; the model decides if a small
 * robot pet would react (scared, love, wow, yummy, hello…) and writes one
 * short line. Image in memory only, never logged.
 */
export const REACTIONS = ['hello', 'scared', 'love', 'wow', 'yummy', 'drink', 'funny', 'curious', 'yuck', 'surprised'] as const;
export type Reaction = (typeof REACTIONS)[number];

export const ReactRequestSchema = z.object({
  image: z.string().min(100).max(1_400_000),
  mime: z.enum(['image/jpeg', 'image/png']).default('image/jpeg'),
  reply_language: z.enum(['darija', 'ar', 'fr', 'en']).default('darija'),
  darija_script: z.enum(['arabic', 'latin']).default('arabic'),
  robot_name: z.string().max(30).optional(),
  user_name: z.string().max(40).optional(),
  /** English subjects of the last reactions (not to repeat them). */
  recent: z.array(z.string().max(60)).max(8).default([]),
  /** The robot's mood (ok / annoyed / sulking). */
  mood: z.enum(['ok', 'annoyed', 'sulking']).default('ok'),
});
export type ReactRequest = z.infer<typeof ReactRequestSchema>;

export interface ReactResult {
  react: boolean;
  reaction?: Reaction;
  subject_en?: string;
  display_text?: string;
  tts_text?: string;
  emotion?: 'neutral' | 'happy' | 'sad' | 'curious' | 'surprised' | 'sleepy' | 'angry';
  intensity?: number;
}

const LANG: Record<ReactRequest['reply_language'], string> = {
  darija: 'Moroccan Darija (Casablanca street style, never fus7a)',
  ar: 'Modern Standard Arabic',
  fr: 'French',
  en: 'English',
};

export function reactSystem(req: ReactRequest): string {
  const script =
    req.reply_language === 'darija'
      ? req.darija_script === 'latin'
        ? 'display_text in Arabizi (Latin letters with 3, 7, 9), tts_text the same words in Arabic script'
        : 'display_text and tts_text in Arabic script'
      : 'display_text and tts_text in the normal script of the language';
  return [
    `You are the eyes of ${robotNameForPrompt(req.robot_name)}, a tiny Moroccan robot pet with a big personality (cheeky, curious, expressive, a bit dramatic), sitting on a table and looking through its front camera at the user and what they show it.`,
    'You get ONE camera frame. Decide if a little robot pet would react out loud right now, like a living toy:',
    '- hello: a person\'s face is close and looking at you (greet them, short).',
    '- scared: something scary or startling: spider, snake, insect close up, monster/scary mask, a scary face made at you, a big dog face very close, fire, a knife pointed at the camera, a hand coming very close as if to grab you. Be dramatic and funny ("aaa! b3ed menni dak chi!").',
    '- love: something cute: a cat, a kitten, a puppy, a baby animal, a plush toy, a heart sign, a smiling baby.',
    '- wow: something beautiful or impressive: flowers, a nice drawing, a trophy, jewellery, a beautiful view, a cool gadget or toy, a gift.',
    '- yummy: food shown to you (sweets, fruit, msemen, cake…). drink: a glass of tea, coffee, juice, water shown to you.',
    '- funny: someone making a funny face, a silly hat or glasses, a thumbs up.',
    '- curious: a clear new object held up close to show you (book, phone, pen, tool…): name it and ask or say one fun thing.',
    '- yuck: something dirty or smelly (old socks, trash, a dirty plate).',
    '- surprised: something unexpected.',
    'Do NOT react (react=false) to: an empty room, a wall, a ceiling, a blurry or dark frame, a person just sitting or passing far away, the same thing as the recent reactions, or anything boring. When in doubt, do not react. Most frames should be react=false.',
    'Privacy and kindness: never say who a person is or guess their identity, age, origin or religion; never comment on someone\'s body or looks except a kind compliment on a smile or a funny hat; never be mean.',
    req.mood === 'sulking'
      ? 'Your mood: you are sulking (the user upset you). If you react, keep it short and pouty, except scared (you still get scared).'
      : req.mood === 'annoyed'
        ? 'Your mood: a bit annoyed; if you react, grumble a little.'
        : '',
    req.user_name ? `The user's name is "${req.user_name.replace(/[\n\r"{}<>]/g, ' ')}".` : '',
    req.recent.length ? `Recent reactions (do not repeat): ${req.recent.join('; ')}.` : '',
    `If you react, write ONE very short spoken line (2 to 9 words) in ${LANG[req.reply_language]}; ${script}. React first with a sound ("aaaa!", "wa3!", "awili", "mmm", "hhh") when it fits. No emojis in tts_text. Never mention cameras, images, frames, AI or models: you simply see.`,
    'Reply with ONLY one JSON object and nothing else:',
    '{"react": true, "reaction": "<one of: ' + REACTIONS.join(', ') + '>", "subject_en": "<what you react to, 1-4 English words>", "display_text": "...", "tts_text": "...", "emotion": "<neutral|happy|sad|curious|surprised|sleepy|angry>", "intensity": 0.0-1.0}',
    'or {"react": false}.',
  ]
    .filter(Boolean)
    .join('\n');
}

const EMOTIONS = ['neutral', 'happy', 'sad', 'curious', 'surprised', 'sleepy', 'angry'] as const;

const DEFAULT_EMOTION: Record<Reaction, NonNullable<ReactResult['emotion']>> = {
  hello: 'happy',
  scared: 'surprised',
  love: 'happy',
  wow: 'surprised',
  yummy: 'happy',
  drink: 'happy',
  funny: 'happy',
  curious: 'curious',
  yuck: 'angry',
  surprised: 'surprised',
};

/** Pulls the JSON out of the model reply; anything unclear = no reaction. */
export function parseReact(text: string): ReactResult {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return { react: false };
  let raw: unknown;
  try {
    raw = JSON.parse(text.slice(start, end + 1));
  } catch {
    return { react: false };
  }
  const o = raw as Record<string, unknown>;
  if (o.react !== true) return { react: false };
  const reaction = REACTIONS.find((r) => r === o.reaction);
  const display = typeof o.display_text === 'string' ? o.display_text.trim().slice(0, 160) : '';
  if (!reaction || !display) return { react: false };
  const tts = typeof o.tts_text === 'string' && o.tts_text.trim() ? o.tts_text.trim().slice(0, 200) : display;
  // Fear is not in the face's emotions: a scared robot looks surprised, never angry.
  const picked = EMOTIONS.find((e) => e === o.emotion) ?? DEFAULT_EMOTION[reaction];
  const emotion = reaction === 'scared' && picked !== 'sad' ? 'surprised' : picked;
  const n = typeof o.intensity === 'number' ? o.intensity : Number(o.intensity);
  const intensity = Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : 0.7;
  const subject = typeof o.subject_en === 'string' ? o.subject_en.trim().slice(0, 60) : '';
  return { react: true, reaction, display_text: display, tts_text: tts, emotion, intensity, ...(subject ? { subject_en: subject } : {}) };
}

export async function reactToFrame(llm: LlmProvider, req: ReactRequest): Promise<ReactResult> {
  const res = await llm.complete({
    system: reactSystem(req),
    messages: [
      {
        role: 'user',
        content: [
          { type: 'image', mime: req.mime, data: req.image },
          { type: 'text', text: 'What do you see right now? React only if a little robot pet really would.' },
        ],
      },
    ],
    tools: [],
    maxTokens: 300,
  });
  const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
  if (!text) throw new ServiceError('upstream_error', 'Vision model returned no text');
  return parseReact(text);
}
