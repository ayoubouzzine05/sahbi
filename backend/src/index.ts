// Entrypoint for `node dist/index.js` (Docker/Render) and for Vercel's zero-config
// Fastify support, which needs the entrypoint to import fastify itself.
import type { FastifyInstance } from 'fastify';
import { isLiveConfigured, isLlmConfigured, isSearchConfigured, isSttConfigured, isTtsConfigured, loadConfig } from './config.js';
import { createLiveToken } from './live.js';
import { GeminiTtsProvider } from './providers/tts/gemini.js';
import { AnthropicProvider } from './providers/llm/anthropic.js';
import { GeminiProvider } from './providers/llm/gemini.js';
import { OpenAiProvider } from './providers/llm/openai.js';
import type { LlmProvider } from './providers/llm/types.js';
import { BraveSearchProvider } from './providers/search/brave.js';
import { YoutubeFinder } from './providers/music/youtube.js';
import { FreeWebSearchProvider } from './providers/search/free.js';
import { GeminiGroundedSearchProvider } from './providers/search/gemini.js';
import { AzureSttProvider } from './providers/stt/azure.js';
import { OpenAiSttProvider } from './providers/stt/openai.js';
import { AzureTtsProvider } from './providers/tts/azure.js';
import { PROMPT_TEMPLATE } from './prompt.generated.js';
import { buildServer } from './build-server.js';
import { getWeather } from './tools/weather.js';

const config = loadConfig();
const promptTemplate = PROMPT_TEMPLATE;

let llm: LlmProvider | null = null;
if (isLlmConfigured(config)) {
  const opts = { apiKey: config.llm.apiKey, model: config.llm.model, baseUrl: config.llm.baseUrl, timeoutMs: config.llm.timeoutMs };
  const reasoningEffort = config.llm.reasoningEffort || undefined;
  llm =
    config.llm.provider === 'anthropic'
      ? new AnthropicProvider(opts)
      : config.llm.provider === 'gemini'
        ? new GeminiProvider({ ...opts, reasoningEffort, fallbackModels: config.llm.fallbackModels })
        : new OpenAiProvider({ ...opts, reasoningEffort });
}

const geminiKey = config.llm.provider === 'gemini' && config.llm.apiKey ? config.llm.apiKey : '';
const search = !isSearchConfigured(config)
  ? null
  : config.search.provider === 'brave'
    ? new BraveSearchProvider(config.search.apiKey)
    : config.search.provider === 'gemini' && geminiKey
      ? new GeminiGroundedSearchProvider({ apiKey: geminiKey, baseUrl: config.llm.baseUrl, models: config.search.geminiModels, timeoutMs: 25000 })
      : new FreeWebSearchProvider();
const youtube = new YoutubeFinder({
  apiKey: config.search.youtubeApiKey || undefined,
  gemini: geminiKey ? { apiKey: geminiKey, baseUrl: config.llm.baseUrl, models: [config.llm.model, ...config.llm.fallbackModels] } : undefined,
});

const app: FastifyInstance = buildServer({
  config,
  llm,
  search,
  youtube: youtube.mode === 'none' ? null : (q: string) => youtube.findWithStats(q),
  youtubeMode: youtube.mode,
  stt: isSttConfigured(config)
    ? config.stt.provider === 'azure'
      ? new AzureSttProvider(config.stt.azureKey, config.stt.azureRegion)
      : new OpenAiSttProvider(config.stt.openaiKey, config.stt.openaiModel)
    : null,
  tts: !isTtsConfigured(config)
    ? null
    : config.tts.provider === 'gemini'
      ? new GeminiTtsProvider({ apiKey: config.llm.apiKey, baseUrl: config.llm.baseUrl, model: config.tts.geminiModel, timeoutMs: 20000 })
      : new AzureTtsProvider(config.tts.azureKey, config.tts.azureRegion, config.tts.defaultVoice),
  live: isLiveConfigured(config)
    ? (o) => createLiveToken({ apiKey: config.llm.apiKey, baseUrl: config.llm.baseUrl, model: config.live.model, timeoutMs: 15000 }, o)
    : null,
  weather: (city) => getWeather(city),
  promptTemplate,
});

// No top-level await here: Vercel's launcher hangs (60 s, then 500) when the
// module awaits anything before calling listen().
app.listen({ port: config.port, host: config.host }).catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
