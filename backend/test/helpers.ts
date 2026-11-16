import { loadConfig, type Config } from '../src/config.js';
import type { Deps } from '../src/server.js';
import type { LlmResponse } from '../src/providers/llm/types.js';
import { ScriptedLlm } from '../src/providers/llm/scripted.js';
import type { SearchProvider, SearchResult } from '../src/providers/search/types.js';
import type { WeatherReport } from '../src/tools/weather.js';

export const PROMPT =
  '<!-- prompt-version: 9.9.9 -->\nYou are Sahbi. Language: {{REPLY_LANGUAGE}}. Script: {{DISPLAY_SCRIPT}}. Time: {{LOCAL_TIME}}. Humor {{HUMOR}} {{FORMALITY}} {{USER_NAME}} {{APP_STATE}}\n{{MEMORY}}\n{{SUMMARY}}';

export function config(env: Record<string, string> = {}): Config {
  return loadConfig({ AUTH_SECRET: 'test-secret-test-secret', ...env });
}

export function replyCall(input: Record<string, unknown>, id = 'r1'): LlmResponse {
  return { content: [{ type: 'tool_use', id, name: 'sahbi_reply', input }], stopReason: 'tool_use' };
}

export const goodReply = {
  display_text: 'سلام! أنا صاحبي.',
  tts_text: 'سلام! أنا صاحبي.',
  language: 'darija',
  emotion: 'happy',
  intensity: 0.7,
  actions: [],
};

export class FakeSearch implements SearchProvider {
  readonly name = 'fake';
  queries: string[] = [];
  constructor(private readonly results: SearchResult[] | Error) {}
  async search(q: string): Promise<SearchResult[]> {
    this.queries.push(q);
    if (this.results instanceof Error) throw this.results;
    return this.results;
  }
}

export const fakeWeather = async (city: string): Promise<WeatherReport> => ({
  location: { name: city, latitude: 33.57, longitude: -7.59 },
  current: { temperature_c: 21, weather_code: 1, description_en: 'mainly clear' },
  source: { title: `Open-Meteo forecast — ${city}`, url: 'https://open-meteo.com/en/docs#latitude=33.57&longitude=-7.59' },
});

export function deps(over: Partial<Deps> & { script?: LlmResponse[] } = {}): Deps & { llm: ScriptedLlm | null } {
  const { script, ...rest } = over;
  return {
    config: config({ LLM_PROVIDER: 'openai', LLM_MODEL: 'test-model', LLM_API_KEY: 'k' }),
    llm: new ScriptedLlm(script ?? [replyCall(goodReply)]),
    search: null,
    stt: null,
    tts: null,
    weather: fakeWeather,
    promptTemplate: PROMPT,
    logger: false,
    ...rest,
  } as Deps & { llm: ScriptedLlm | null };
}

/** Parses an SSE body into [{event, data}]. */
export function parseSse(body: string): Array<{ event: string; data: unknown }> {
  return body
    .split('\n\n')
    .filter((b) => b.trim())
    .map((block) => {
      const ev = /^event: (.+)$/m.exec(block)?.[1] ?? '';
      const data = /^data: (.+)$/m.exec(block)?.[1] ?? 'null';
      return { event: ev, data: JSON.parse(data) as unknown };
    });
}
