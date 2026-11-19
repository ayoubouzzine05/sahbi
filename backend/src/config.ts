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
  /** /v1/chat may carry one camera photo. */
  chatBodyLimitBytes: number;
  llm: {
    provider: 'anthropic' | 'openai' | 'gemini' | 'none';
    model: string;
    apiKey: string;
    baseUrl: string;
    timeoutMs: number;
    /** Gemini only: models tried after `model` (LLM_FALLBACK_MODELS, comma-separated; 'none' disables). */
    fallbackModels: string[];
    maxOutputTokens: number;
    /** Optional OpenAI-style reasoning_effort (e.g. 'low'); sent only when set. */
    reasoningEffort: string;
  };
  search: { provider: 'brave' | 'gemini' | 'free' | 'none'; apiKey: string; geminiModels: string[]; youtubeApiKey: string; pipedInstances: string[] };
  stt: { provider: 'azure' | 'openai' | 'none'; azureKey: string; azureRegion: string; openaiKey: string; openaiModel: string };
  tts: { provider: 'azure' | 'gemini' | 'none'; azureKey: string; azureRegion: string; defaultVoice: string; geminiModel: string };
  live: { model: string; enabled: boolean };
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

/** Gemini through its native API (https://ai.google.dev/api/generate-content). */
export const GEMINI_PRESET = {
  baseUrl: 'https://generativelanguage.googleapis.com',
  // All free-tier models per https://ai.google.dev/gemini-api/docs/pricing (checked 2026-11-18).
  // gemini-3.8-flash answered 503 repeatedly on the live deploy, hence a chain.
  model: 'gemini-4-hydrogen',
  fallbackModels: ['gemini-3.5-flash-lite', 'gemini-3.8-flash'],
  timeoutMs: 20000, // per model; the app waits ~45 s per request
  reasoningEffort: 'low',
  ttsModel: 'gemini-3.8-flash-tts', // free tier (pricing page, 2026-11-18)
  liveModel: 'gemini-3.8-live', // free tier (pricing page, 2026-11-18)
  // Google Search grounding is free (500 RPD shared) only on 2.5 Flash / Flash-Lite (pricing page, 2026-11-19).
  // 2.5 models are 'no longer available to new users' (Google 404, 2026-11-19); 3.x is tried after them.
  searchModels: ['gemini-2.5-flash-lite', 'gemini-2.5-flash', 'gemini-3.5-flash-lite'],
  maxOutputTokens: 4096, // thinking tokens count towards output
} as const;

/**
 * Gemini is selected by LLM_PROVIDER=gemini, or automatically when no provider
 * is set and the key looks like a Google key (standard "AIza…" or the auth keys
 * "AQ.…" that AI Studio issues since 2026-05-28), so a one-field
 * deploy (just LLM_API_KEY) works. Explicit LLM_* values always win.
 */
function usesGemini(env: NodeJS.ProcessEnv): boolean {
  const p = str(env, 'LLM_PROVIDER').toLowerCase();
  const key = str(env, 'LLM_API_KEY');
  return p === 'gemini' || (p === '' && (key.startsWith('AIza') || key.startsWith('AQ.')));
}

/** Stable per-deployment secret derived from the LLM key when AUTH_SECRET is unset
 *  (serverless instances must agree on it; rotating the key rotates tokens). */
export function derivedAuthSecret(apiKey: string): string {
  return apiKey ? createHash('sha256').update(`sahbi-auth-v1:${apiKey}`).digest('hex') : '';
}

function fallbackModels(env: NodeJS.ProcessEnv, gemini: boolean): string[] {
  const raw = str(env, 'LLM_FALLBACK_MODELS');
  if (raw.toLowerCase() === 'none') return [];
  if (raw) return raw.split(',').map((m) => m.trim()).filter(Boolean);
  return gemini ? [...GEMINI_PRESET.fallbackModels] : [];
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const gemini = usesGemini(env);
  const llmProvider = gemini ? 'gemini' : oneOf(str(env, 'LLM_PROVIDER', 'none'), ['anthropic', 'openai', 'none'] as const, 'none');
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
    chatBodyLimitBytes: int(env, 'CHAT_BODY_LIMIT_BYTES', 1536 * 1024),
    llm: {
      provider: llmProvider,
      model: str(env, 'LLM_MODEL', gemini ? GEMINI_PRESET.model : ''),
      apiKey: str(env, 'LLM_API_KEY'),
      baseUrl: str(env, 'LLM_BASE_URL', defaultBase),
      timeoutMs: int(env, 'LLM_TIMEOUT_MS', gemini ? GEMINI_PRESET.timeoutMs : 30000),
      fallbackModels: fallbackModels(env, gemini),
      maxOutputTokens: int(env, 'LLM_MAX_OUTPUT_TOKENS', gemini ? GEMINI_PRESET.maxOutputTokens : 800),
      reasoningEffort: str(env, 'LLM_REASONING_EFFORT', gemini ? GEMINI_PRESET.reasoningEffort : ''),
    },
    search: {
      // Default: Brave when its key exists, else free Wikipedia + GDELT (no key). 'gemini' = Google Search grounding (not free for new accounts).
      provider: oneOf(
        str(env, 'SEARCH_PROVIDER', str(env, 'BRAVE_SEARCH_API_KEY') ? 'brave' : 'free'),
        ['brave', 'gemini', 'free', 'none'] as const,
        'none',
      ),
      apiKey: str(env, 'BRAVE_SEARCH_API_KEY'),
      geminiModels: str(env, 'GEMINI_SEARCH_MODELS', GEMINI_PRESET.searchModels.join(','))
        .split(',')
        .map((m) => m.trim())
        .filter(Boolean),
      youtubeApiKey: str(env, 'YOUTUBE_API_KEY'),
      // Public Piped API instances for keyless YouTube search ('none' disables).
      pipedInstances:
        str(env, 'PIPED_INSTANCES', 'https://api.piped.private.coffee') === 'none'
          ? []
          : str(env, 'PIPED_INSTANCES', 'https://api.piped.private.coffee')
              .split(',')
              .map((s) => s.trim())
              .filter((s) => /^https:\/\//.test(s)),
    },
    stt: {
      provider: oneOf(str(env, 'STT_PROVIDER', 'none'), ['azure', 'openai', 'none'] as const, 'none'),
      azureKey,
      azureRegion,
      openaiKey: str(env, 'OPENAI_STT_API_KEY'),
      openaiModel: str(env, 'OPENAI_STT_MODEL'),
    },
    tts: {
      // Gemini TTS is used automatically with a Gemini LLM key unless TTS_PROVIDER says otherwise.
      provider: oneOf(str(env, 'TTS_PROVIDER', gemini ? 'gemini' : 'none'), ['azure', 'gemini', 'none'] as const, 'none'),
      azureKey,
      azureRegion,
      defaultVoice: str(env, 'AZURE_TTS_VOICE', 'ar-MA-JamalNeural'),
      geminiModel: str(env, 'GEMINI_TTS_MODEL', GEMINI_PRESET.ttsModel),
    },
    live: {
      // Live camera/voice mode (Gemini Live API through ephemeral tokens). Gemini only.
      model: str(env, 'GEMINI_LIVE_MODEL', GEMINI_PRESET.liveModel),
      enabled: gemini && str(env, 'LIVE_ENABLED', 'true') !== 'false',
    },
    contextTokenBudget: int(env, 'CONTEXT_TOKEN_BUDGET', 3000),
  };
}

export function isLlmConfigured(c: Config): boolean {
  return c.llm.provider !== 'none' && c.llm.apiKey !== '' && c.llm.model !== '';
}
export function isSearchConfigured(c: Config): boolean {
  if (c.search.provider === 'brave') return c.search.apiKey !== '';
  if (c.search.provider === 'free') return true;
  return c.search.provider === 'gemini' && c.llm.provider === 'gemini' && c.llm.apiKey !== '' && c.search.geminiModels.length > 0;
}
export function isSttConfigured(c: Config): boolean {
  if (c.stt.provider === 'azure') return c.stt.azureKey !== '' && c.stt.azureRegion !== '';
  if (c.stt.provider === 'openai') return c.stt.openaiKey !== '' && c.stt.openaiModel !== '';
  return false;
}
export function isTtsConfigured(c: Config): boolean {
  if (c.tts.provider === 'gemini') return c.llm.provider === 'gemini' && c.llm.apiKey !== '' && c.tts.geminiModel !== '';
  return c.tts.provider === 'azure' && c.tts.azureKey !== '' && c.tts.azureRegion !== '';
}

export function isLiveConfigured(c: Config): boolean {
  return c.live.enabled && c.llm.provider === 'gemini' && c.llm.apiKey !== '' && c.live.model !== '';
}
