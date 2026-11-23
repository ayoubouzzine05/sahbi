import type { ChatRequest } from './schema.js';

/**
 * Cheap token estimate. Arabic script tokenises worse than Latin, so it is weighted higher.
 * This is only used for trimming, never billing.
 */
export function estimateTokens(text: string): number {
  let arabic = 0;
  for (const ch of text) if (/[\u0600-\u06FF]/.test(ch)) arabic++;
  const latin = text.length - arabic;
  return Math.ceil(latin / 4 + arabic / 2) + 4;
}

/** Keeps the newest turns that fit in the budget; always starts with a user turn. */
export function trimHistory(history: ChatRequest['history'], budget: number): ChatRequest['history'] {
  const kept: ChatRequest['history'] = [];
  let used = 0;
  for (let i = history.length - 1; i >= 0; i--) {
    const t = estimateTokens(history[i]!.text);
    if (used + t > budget) break;
    used += t;
    kept.unshift(history[i]!);
  }
  while (kept.length && kept[0]!.role !== 'user') kept.shift();
  return kept;
}

/** The user-chosen robot name, sanitised for the prompt (default MIMO / ميمو). */
export function robotNameForPrompt(name: string | undefined): string {
  const clean = (name ?? '').replace(/[\n\r"{}<>]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 30);
  return clean ? `"${clean}"` : '"MIMO" (ميمو)';
}

export function fillPrompt(template: string, req: ChatRequest): string {
  const s = req.settings;
  const replyLang = { darija: 'darija (Moroccan Arabic)', ar: 'ar (Modern Standard Arabic)', fr: 'fr (French)', en: 'en (English)' }[s.reply_language];
  const memory =
    req.memory && req.memory.facts.length
      ? `- Things the user asked you to remember (use naturally, do not recite):\n${req.memory.facts.map((f) => `  - ${f.replace(/\n/g, ' ')}`).join('\n')}`
      : '- Memory: disabled or empty. Do not pretend to remember past sessions.';
  const summary = req.summary ? `- Summary of earlier conversation: ${req.summary.replace(/\n/g, ' ')}` : '';
  return template
    .replace(/<!--[\s\S]*?-->\n?/, '')
    .replace('{{ROBOT_NAME}}', robotNameForPrompt(s.robot_name))
    .replace('{{HUMOR}}', s.humor.toFixed(1))
    .replace('{{FORMALITY}}', s.formality)
    .replace('{{USER_NAME}}', s.user_name ? `"${s.user_name}"` : '"sahbi" / "صاحبي" (no name given)')
    .replace('{{REPLY_LANGUAGE}}', replyLang)
    .replace('{{DISPLAY_SCRIPT}}', s.reply_language === 'darija' ? (s.darija_script === 'latin' ? 'latin (Arabizi)' : 'arabic') : 'native script of the language')
    .replace('{{LOCAL_TIME}}', req.client.local_time ?? 'unknown')
    .replace('{{APP_STATE}}', req.client.app_state ?? 'none')
    .replace('{{MEMORY}}', memory)
    .replace('{{SUMMARY}}', summary)
    .trim();
}

export function promptVersion(template: string): string {
  return /prompt-version:\s*([\w.-]+)/.exec(template)?.[1] ?? 'unknown';
}
