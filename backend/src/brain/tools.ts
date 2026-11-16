import type { ToolDef } from '../providers/llm/types.js';
import { REPLY_TOOL_JSON_SCHEMA } from './schema.js';

export const REPLY_TOOL: ToolDef = {
  name: 'sahbi_reply',
  description: 'Deliver the final answer to the user. Must be called exactly once at the end of every turn.',
  input_schema: REPLY_TOOL_JSON_SCHEMA as unknown as Record<string, unknown>,
};

export const WEB_SEARCH_TOOL: ToolDef = {
  name: 'web_search',
  description: 'Search the web for current information. Returns numbered results (id, title, url, snippet, date). Cite ids in sahbi_reply.source_ids.',
  input_schema: {
    type: 'object',
    required: ['query'],
    properties: {
      query: { type: 'string', description: 'Search query. Prefer French or English keywords for Moroccan news.' },
      freshness: { type: 'string', enum: ['pd', 'pw', 'pm', 'py'], description: 'pd=24h, pw=7 days, pm=31 days, py=1 year' },
      country: { type: 'string', description: '2-letter country code, e.g. MA' },
    },
  },
};

export const WEATHER_TOOL: ToolDef = {
  name: 'get_weather',
  description: 'Current weather and today min/max for a city (Open-Meteo).',
  input_schema: { type: 'object', required: ['city'], properties: { city: { type: 'string' } } },
};
