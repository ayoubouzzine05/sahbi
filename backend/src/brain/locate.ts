import { z } from 'zod';
import { ServiceError } from '../errors.js';
import type { LlmProvider } from '../providers/llm/types.js';

/**
 * "Which object does the user mean?" for the camera screens: either the
 * object under a tap, or the object a hand/finger is pointing at. The model
 * returns Gemini's documented object-detection format, `box_2d` =
 * [ymin, xmin, ymax, xmax] normalised to 0-1000; this module turns it into a
 * 0..1 box the app can draw. Works with any LLM provider that accepts images.
 */
export const LocateRequestSchema = z.object({
  /** Base64 image, no data: prefix. The app sends an upright PNG/JPEG. */
  image: z.string().min(100).max(1_400_000),
  mime: z.enum(['image/jpeg', 'image/png']).default('image/jpeg'),
  /** Tap position on the image, 0..1 from the top-left. Absent = look for a pointing finger. */
  tap: z.object({ x: z.number().min(0).max(1), y: z.number().min(0).max(1) }).optional(),
  /** Language of the label. */
  language: z.enum(['ar', 'fr', 'en']).default('ar'),
});
export type LocateRequest = z.infer<typeof LocateRequestSchema>;

export interface LocateResult {
  found: boolean;
  /** Short object name in the requested language (Darija in Arabic script for 'ar'). */
  label?: string;
  /** English name (more reliable; used to tell the live model what was selected). */
  name_en?: string;
  /** 0..1 from the top-left: left, top, right, bottom. */
  box?: { left: number; top: number; right: number; bottom: number };
  /** 'tap' or 'pointing' (what selected the object). */
  by: 'tap' | 'pointing';
}

const LANG: Record<LocateRequest['language'], string> = {
  ar: 'the everyday word Moroccans say in Darija, in Arabic script, using common French loanwords when that is what people say (e.g. cup = كاس, phone = تيليفون, pen = ستيلو, keyboard = كلافيي, mouse = سوري, apple = تفاحة, remote = تيليكوموند)',
  fr: 'French',
  en: 'English',
};

export function locateSystem(language: LocateRequest['language']): string {
  return [
    'You locate ONE object in a camera photo for a small robot companion.',
    'Reply with ONLY one JSON object and nothing else:',
    '{"found": true, "name_en": "<object name in English, 1-3 words>", "label": "<the same name translated>", "box_2d": [ymin, xmin, ymax, xmax]}',
    'Identify the object carefully first (name_en), then translate that exact name for label.',
    'or {"found": false}.',
    'box_2d uses integers normalised to 0-1000 over the whole image, (0,0) = top-left.',
    'Box the whole object tightly. Never box a hand, a finger, a person or the background unless that is clearly what is meant.',
    `label = ${LANG[language]}.`,
  ].join('\n');
}

export function locateInstruction(req: Pick<LocateRequest, 'tap'>): string {
  if (req.tap) {
    const y = Math.round(req.tap.y * 1000);
    const x = Math.round(req.tap.x * 1000);
    return `The user tapped the photo at point [y=${y}, x=${x}] (0-1000). Find the single object under or closest to that point and box it. If the point is on empty wall, floor, sky or blur, reply {"found": false}.`;
  }
  return 'Is a hand or finger pointing at, touching, or holding up a specific object? If yes, box THAT object (not the hand). If no hand is pointing at anything, reply {"found": false}.';
}

/** Pulls the first JSON object out of a model reply (tolerates ```json fences). */
export function parseLocate(text: string, by: LocateResult['by'], tap?: { x: number; y: number }): LocateResult {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return { found: false, by };
  let raw: unknown;
  try {
    raw = JSON.parse(text.slice(start, end + 1));
  } catch {
    return { found: false, by };
  }
  const o = raw as { found?: unknown; label?: unknown; name_en?: unknown; box_2d?: unknown };
  if (o.found !== true || !Array.isArray(o.box_2d) || o.box_2d.length !== 4) return { found: false, by };
  const n = o.box_2d.map((v) => (typeof v === 'number' ? v : Number(v)));
  if (n.some((v) => !Number.isFinite(v))) return { found: false, by };
  const clamp = (v: number) => Math.min(1, Math.max(0, v / 1000));
  const [ymin, xmin, ymax, xmax] = n.map(clamp) as [number, number, number, number];
  const box = { left: Math.min(xmin, xmax), top: Math.min(ymin, ymax), right: Math.max(xmin, xmax), bottom: Math.max(ymin, ymax) };
  // Too small to be a real box, or the whole frame (nothing specific).
  const w = box.right - box.left;
  const h = box.bottom - box.top;
  if (w < 0.02 || h < 0.02 || w * h > 0.97) return { found: false, by };
  // A tap must land in (or near) the returned box, otherwise the model picked something else.
  if (tap) {
    const m = 0.08;
    if (tap.x < box.left - m || tap.x > box.right + m || tap.y < box.top - m || tap.y > box.bottom + m) return { found: false, by };
  }
  const label = typeof o.label === 'string' ? o.label.trim().slice(0, 40) : '';
  const nameEn = typeof o.name_en === 'string' ? o.name_en.trim().slice(0, 40) : '';
  return { found: true, by, box, ...(label ? { label } : {}), ...(nameEn ? { name_en: nameEn } : {}) };
}

export async function locateObject(llm: LlmProvider, req: LocateRequest): Promise<LocateResult> {
  const by = req.tap ? 'tap' : 'pointing';
  const res = await llm.complete({
    system: locateSystem(req.language),
    messages: [
      {
        role: 'user',
        content: [
          { type: 'image', mime: req.mime, data: req.image },
          { type: 'text', text: locateInstruction(req) },
        ],
      },
    ],
    tools: [],
    maxTokens: 512,
  });
  const text = res.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
  if (!text) throw new ServiceError('upstream_error', 'Vision model returned no text');
  return parseLocate(text, by, req.tap);
}
