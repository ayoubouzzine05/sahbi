import { createHash } from 'node:crypto';
/**
 * Runtime configuration. Every value comes from environment variables
 * (see ../.env.example). Secrets are never logged and never returned by any route.
 */
export interface Config {
  port: number;
  host: string;
  authSecret: string;
  corsOrigins: string[];
  rateLimitPerMinute: number;
  jsonBodyLimitBytes: number;
  audioBodyLimitBytes: number;
  llm: {
    provider: 'anthropic' | 'openai' | 'none';
    model: string;
    apiKey: string;
    baseUrl: string;
    timeoutMs: number;
    maxOutputTokens: number;
    /** Optional OpenAI-style reasoning_effort (e.g. 'low'); sent only when set. */
    reasoningEffort: string;
  };
  search: { provider: 'brave' | 'none'; apiKey: string };
  stt: { provider: 'azure' | 'openai' | 'none'; azureKey: string; azureRegion: string; openaiKey: string; openaiModel: string };
  tts: { provider: 'azure' | 'none'; azureKey: string; azureRegion: string; defaultVoice: string };
  contextTokenBudget: number;
}

function str(env: NodeJS.ProcessEnv, key: string, fallback = ''): string {
  const v = env[key];
  return v === undefined || v.trim() === '' ? fallback : v.trim();
}

function int(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const v = Number.parseInt(str(env, key), 10);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

function oneOf<T extends string>(value: string, allowed: readonly T[], fallback: T): T {
  return (allowed as readonly string[]).includes(value) ? (value as T) : fallback;
}

/** Gemini through its OpenAI-compatible API (https://ai.google.dev/gemini-api/docs/openai). */
export const GEMINI_PRESET = {
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  model: 'gemini-3.8-flash', // free tier per https://ai.google.dev/gemini-api/docs/pricing (checked 2026-11-17)
  reasoningEffort: 'low',
  maxOutputTokens: 4096, // thinking tokens count towards output
} as const;

/**
 * Gemini is selected by LLM_PROVIDER=gemini, or automatically when no provider
 * is set and the key looks like a Google API key ("AIza…"), so a one-field
 * deploy (just LLM_API_KEY) works. Explicit LLM_* values always win.
 */
function usesGemini(env: NodeJS.ProcessEnv): boolean {
  const p = str(env, 'LLM_PROVIDER').toLowerCase();
  return p === 'gemini' || (p === '' && str(env, 'LLM_API_KEY').startsWith('AIza'));
}

/** Stable per-deployment secret derived from the LLM key when AUTH_SECRET is unset
 *  (serverless instances must agree on it; rotating the key rotates tokens). */
export function derivedAuthSecret(apiKey: string): string {
  return apiKey ? createHash('sha256').update(`sahbi-auth-v1:${apiKey}`).digest('hex') : '';
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const gemini = usesGemini(env);
  const llmProvider = gemini ? 'openai' : oneOf(str(env, 'LLM_PROVIDER', 'none'), ['anthropic', 'openai', 'none'] as const, 'none');
  const defaultBase = gemini ? GEMINI_PRESET.baseUrl : llmProvider === 'anthropic' ? 'https://api.anthropic.com' : 'https://api.openai.com';
  const azureRegion = str(env, 'AZURE_SPEECH_REGION');
  const azureKey = str(env, 'AZURE_SPEECH_KEY');
  return {
    port: int(env, 'PORT', 8080),
    host: str(env, 'HOST', '0.0.0.0'),
    authSecret: str(env, 'AUTH_SECRET') || derivedAuthSecret(str(env, 'LLM_API_KEY')),
    corsOrigins: str(env, 'CORS_ORIGINS')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    rateLimitPerMinute: int(env, 'RATE_LIMIT_PER_MINUTE', 30),
    jsonBodyLimitBytes: int(env, 'JSON_BODY_LIMIT_BYTES', 64 * 1024),
    audioBodyLimitBytes: int(env, 'AUDIO_BODY_LIMIT_BYTES', 2 * 1024 * 1024),
    llm: {
      provider: llmProvider,
      model: str(env, 'LLM_MODEL', gemini ? GEMINI_PRESET.model : ''),
      apiKey: str(env, 'LLM_API_KEY'),
      baseUrl: str(env, 'LLM_BASE_URL', defaultBase),
      timeoutMs: int(env, 'LLM_TIMEOUT_MS', 30000),
      maxOutputTokens: int(env, 'LLM_MAX_OUTPUT_TOKENS', gemini ? GEMINI_PRESET.maxOutputTokens : 800),
      reasoningEffort: str(env, 'LLM_REASONING_EFFORT', gemini ? GEMINI_PRESET.reasoningEffort : ''),
    },
    search: {
      provider: oneOf(str(env, 'SEARCH_PROVIDER', 'none'), ['brave', 'none'] as const, 'none'),
      apiKey: str(env, 'BRAVE_SEARCH_API_KEY'),
    },
    stt: {
      provider: oneOf(str(env, 'STT_PROVIDER', 'none'), ['azure', 'openai', 'none'] as const, 'none'),
      azureKey,
      azureRegion,
      openaiKey: str(env, 'OPENAI_STT_API_KEY'),
      openaiModel: str(env, 'OPENAI_STT_MODEL'),
    },
    tts: {
      provider: oneOf(str(env, 'TTS_PROVIDER', 'none'), ['azure', 'none'] as const, 'none'),
      azureKey,
      azureRegion,
      defaultVoice: str(env, 'AZURE_TTS_VOICE', 'ar-MA-JamalNeural'),
    },
    contextTokenBudget: int(env, 'CONTEXT_TOKEN_BUDGET', 3000),
  };
}

export function isLlmConfigured(c: Config): boolean {
  return c.llm.provider !== 'none' && c.llm.apiKey !== '' && c.llm.model !== '';
}
export function isSearchConfigured(c: Config): boolean {
  return c.search.provider === 'brave' && c.search.apiKey !== '';
}
export function isSttConfigured(c: Config): boolean {
  if (c.stt.provider === 'azure') return c.stt.azureKey !== '' && c.stt.azureRegion !== '';
  if (c.stt.provider === 'openai') return c.stt.openaiKey !== '' && c.stt.openaiModel !== '';
  return false;
}
export function isTtsConfigured(c: Config): boolean {
  return c.tts.provider === 'azure' && c.tts.azureKey !== '' && c.tts.azureRegion !== '';
}
