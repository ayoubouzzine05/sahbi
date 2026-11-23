import { ServiceError } from '../errors.js';
import type { Block, LlmMessage, LlmProvider } from '../providers/llm/types.js';
import type { SearchProvider } from '../providers/search/types.js';
import type { WeatherReport } from '../tools/weather.js';
import { fillPrompt, trimHistory } from './context.js';
import { type ChatRequest, dropUnknownFaceActions, formatZodError, type Reply, ReplySchema } from './schema.js';
import { REPLY_TOOL, WEATHER_TOOL, WEB_SEARCH_TOOL } from './tools.js';

export interface Source {
  id: number;
  title: string;
  url: string;
  date?: string;
  kind: 'web' | 'data' | 'search';
}

export type Verification = 'none' | 'data' | 'confirmed' | 'unconfirmed';

export interface FinalReply extends Omit<Reply, 'source_ids' | 'sources_agree'> {
  sources: Source[];
  verification: Verification;
  used_tools: string[];
  search_unavailable: boolean;
}

export type ChatEvent =
  | { type: 'status'; phase: 'thinking' | 'searching' | 'weather' | 'retrying' }
  | { type: 'final'; reply: FinalReply };

export interface BrainDeps {
  llm: LlmProvider;
  search: SearchProvider | null;
  weather: (city: string) => Promise<WeatherReport>;
  promptTemplate: string;
  tokenBudget: number;
  maxOutputTokens: number;
  maxSteps?: number;
}

function domainOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
}

/** Pulls a JSON object out of plain text (some models answer in text despite instructions). */
export function extractJson(text: string): unknown {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return undefined;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return undefined;
  }
}

export function computeVerification(cited: Source[], sourcesAgree: boolean | undefined, usedSearch: boolean): Verification {
  const web = cited.filter((s) => s.kind === 'web');
  if (web.length === 0) {
    if (usedSearch) return 'unconfirmed';
    return cited.length ? 'data' : 'none';
  }
  const domains = new Set(web.map((s) => domainOf(s.url)));
  return domains.size >= 2 && sourcesAgree !== false ? 'confirmed' : 'unconfirmed';
}

/**
 * Runs one chat turn: tool loop (search / weather), then a schema-validated reply.
 * Invalid output is retried exactly once with the validation error fed back to the model.
 */
/** Appended to the system prompt when the app asks for a proactive turn. */
export const PROACTIVE_INSTRUCTION = [
  '## Proactive turn',
  'The user has not said anything for a while; the app is open next to them. YOU start a short moment together, like a friend sitting nearby, to keep a good vibe.',
  'Pick ONE, different from your previous turns in the history: a short Moroccan-style joke or nokta, a light riddle (give the answer next time), a fun fact (Morocco, animals, space, food), a playful comment about the time of day, a question about their day, their plans or what they like, or a small challenge or game.',
  'One or two short sentences, warm and funny, never pushy. Never mention that the user is quiet, silent or absent (no "sakt", "ساكت", "fin nta", "wach nta hna", "are you there?") and do not say you are bored or alone: just start the joke, fact, riddle or question directly. No actions except image.show when a photo makes a fun fact better, or one face.play (e.g. dance, sparkle, suspicious) when it fits the line.',
].join('\n');

/** Stand-in user turn for a proactive request (the app sends no user words). */
export const PROACTIVE_USER_TURN = '(silence — the user has been quiet for a while; start something fun)';

export async function* runChat(req: ChatRequest, deps: BrainDeps): AsyncGenerator<ChatEvent> {
  const proactive = req.mode === 'proactive';
  const system = fillPrompt(deps.promptTemplate, req) + (proactive ? `\n\n${PROACTIVE_INSTRUCTION}` : '');
  const history = trimHistory(req.history, deps.tokenBudget);
  const messages: LlmMessage[] = history.map((t) => ({ role: t.role, content: [{ type: 'text', text: t.text }] }));
  // Anthropic requires alternating roles: merge consecutive same-role turns.
  const merged: LlmMessage[] = [];
  const userContent: Block[] = [
    ...(req.image ? [{ type: 'image' as const, mime: req.image.mime, data: req.image.data }] : []),
    { type: 'text' as const, text: proactive ? PROACTIVE_USER_TURN : req.message },
  ];
  for (const m of [...messages, { role: 'user' as const, content: userContent }]) {
    const last = merged[merged.length - 1];
    if (last && last.role === m.role) last.content.push(...m.content);
    else merged.push({ role: m.role, content: [...m.content] });
  }

  // A proactive line needs no web search (saves the free quota).
  const tools = proactive ? [REPLY_TOOL] : [REPLY_TOOL, WEB_SEARCH_TOOL, WEATHER_TOOL];
  const sources = new Map<number, Source>();
  const usedTools = new Set<string>();
  let searchUnavailable = false;
  let retried = false;
  const maxSteps = deps.maxSteps ?? 5;

  yield { type: 'status', phase: 'thinking' };

  for (let step = 0; step < maxSteps; step++) {
    const res = await deps.llm.complete({ system, messages: merged, tools, maxTokens: deps.maxOutputTokens });
    const toolUses = res.content.filter((b): b is Extract<Block, { type: 'tool_use' }> => b.type === 'tool_use');
    const replyCall = toolUses.find((t) => t.name === REPLY_TOOL.name);

    let candidate: unknown;
    let replyToolId: string | undefined;
    if (replyCall) {
      candidate = replyCall.input;
      replyToolId = replyCall.id;
    } else if (toolUses.length === 0) {
      const text = res.content.filter((b) => b.type === 'text').map((b) => (b as { text: string }).text).join('\n');
      candidate = extractJson(text);
      if (candidate === undefined) {
        if (retried) throw new ServiceError('invalid_output', 'Model did not return a structured reply', 502);
        retried = true;
        yield { type: 'status', phase: 'retrying' };
        merged.push({ role: 'assistant', content: res.content.length ? res.content : [{ type: 'text', text: '(empty)' }] });
        merged.push({ role: 'user', content: [{ type: 'text', text: 'Format error: you must call the sahbi_reply tool with your final answer. Do it now.' }] });
        continue;
      }
    }

    if (candidate !== undefined) {
      const parsed = ReplySchema.safeParse(dropUnknownFaceActions(candidate));
      if (parsed.success) {
        const reply = parsed.data;
        const cited = reply.source_ids.map((id) => sources.get(id)).filter((s): s is Source => !!s);
        // Weather data sources are always shown when weather was used, even if not cited.
        for (const s of sources.values()) if ((s.kind === 'data' || s.kind === 'search') && !cited.includes(s)) cited.push(s);
        const final: FinalReply = {
          display_text: reply.display_text,
          tts_text: reply.tts_text,
          language: reply.language,
          emotion: reply.emotion,
          intensity: reply.intensity,
          actions: reply.actions,
          sources: cited,
          verification: computeVerification(cited, reply.sources_agree, usedTools.has('web_search') && !searchUnavailable),
          used_tools: [...usedTools],
          search_unavailable: searchUnavailable,
        };
        yield { type: 'final', reply: final };
        return;
      }
      if (retried) throw new ServiceError('invalid_output', `Reply failed validation: ${formatZodError(parsed.error)}`, 502);
      retried = true;
      yield { type: 'status', phase: 'retrying' };
      merged.push({ role: 'assistant', content: res.content });
      const msg = `Validation error in sahbi_reply: ${formatZodError(parsed.error)}. Call sahbi_reply again with a corrected object.`;
      merged.push({
        role: 'user',
        content: replyToolId ? [{ type: 'tool_result', tool_use_id: replyToolId, content: msg, is_error: true }] : [{ type: 'text', text: msg }],
      });
      continue;
    }

    // Execute non-reply tools.
    merged.push({ role: 'assistant', content: res.content });
    const results: Block[] = [];
    for (const call of toolUses) {
      if (call.name === WEB_SEARCH_TOOL.name) {
        usedTools.add('web_search');
        yield { type: 'status', phase: 'searching' };
        const query = typeof call.input.query === 'string' ? call.input.query.slice(0, 300) : '';
        if (!deps.search) {
          searchUnavailable = true;
          results.push({ type: 'tool_result', tool_use_id: call.id, content: 'search_not_configured: internet search is not available on this server.', is_error: true });
          continue;
        }
        if (!query) {
          results.push({ type: 'tool_result', tool_use_id: call.id, content: 'error: empty query', is_error: true });
          continue;
        }
        try {
          const freshness = ['pd', 'pw', 'pm', 'py'].includes(String(call.input.freshness)) ? (call.input.freshness as 'pd') : undefined;
          const country = typeof call.input.country === 'string' && /^[A-Za-z]{2}$/.test(call.input.country) ? call.input.country.toUpperCase() : undefined;
          const found = await deps.search.search(query, { freshness, country });
          for (const r of found.filter((x) => x.kind === 'search')) {
            const id = sources.size + 1;
            sources.set(id, { id, title: r.title, url: r.url, kind: 'search' });
          }
          const lines = found.filter((x) => x.kind !== 'search').map((r) => {
            const id = sources.size + 1;
            sources.set(id, { id, title: r.title, url: r.url, ...(r.date ? { date: r.date } : {}), kind: 'web' });
            return JSON.stringify({ id, title: r.title, url: r.url, date: r.date ?? null, snippet: r.snippet });
          });
          results.push({ type: 'tool_result', tool_use_id: call.id, content: lines.length ? lines.join('\n') : 'no_results' });
        } catch (err) {
          searchUnavailable = true;
          results.push({ type: 'tool_result', tool_use_id: call.id, content: `search_failed: ${err instanceof ServiceError ? err.code : 'error'}`, is_error: true });
        }
      } else if (call.name === WEATHER_TOOL.name) {
        usedTools.add('get_weather');
        yield { type: 'status', phase: 'weather' };
        const city = typeof call.input.city === 'string' ? call.input.city.slice(0, 80) : '';
        try {
          const w = await deps.weather(city);
          const id = sources.size + 1;
          sources.set(id, { id, title: w.source.title, url: w.source.url, kind: 'data' });
          results.push({ type: 'tool_result', tool_use_id: call.id, content: JSON.stringify({ source_id: id, ...w }) });
        } catch (err) {
          results.push({ type: 'tool_result', tool_use_id: call.id, content: `weather_failed: ${err instanceof Error ? err.message : 'error'}`, is_error: true });
        }
      } else {
        results.push({ type: 'tool_result', tool_use_id: call.id, content: `unknown_tool: ${call.name}`, is_error: true });
      }
    }
    merged.push({ role: 'user', content: results });
  }
  throw new ServiceError('invalid_output', 'Too many tool steps without a final reply', 502);
}

/** Rolling summary of older turns, used by the app to keep context small. */
export async function summarise(llm: LlmProvider, previous: string | undefined, turns: ChatRequest['history'], maxTokens: number): Promise<string> {
  const transcript = turns.map((t) => `${t.role === 'user' ? 'User' : 'Sahbi'}: ${t.text}`).join('\n');
  const res = await llm.complete({
    system:
      'You compress conversations. Write a neutral summary (max 80 words, in English) of the facts, preferences and open threads. Do not add anything not present. Output only the summary text.',
    messages: [{ role: 'user', content: [{ type: 'text', text: `Previous summary: ${previous ?? '(none)'}\n\nNew turns:\n${transcript}` }] }],
    tools: [],
    maxTokens: Math.min(maxTokens, 300),
  });
  const text = res.content.filter((b) => b.type === 'text').map((b) => (b as { text: string }).text).join(' ').trim();
  if (!text) throw new ServiceError('invalid_output', 'Empty summary', 502);
  return text.slice(0, 2000);
}
