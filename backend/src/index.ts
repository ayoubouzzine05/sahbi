import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isLlmConfigured, isSearchConfigured, isSttConfigured, isTtsConfigured, loadConfig } from './config.js';
import { AnthropicProvider } from './providers/llm/anthropic.js';
import { OpenAiProvider } from './providers/llm/openai.js';
import type { LlmProvider } from './providers/llm/types.js';
import { BraveSearchProvider } from './providers/search/brave.js';
import { AzureSttProvider } from './providers/stt/azure.js';
import { OpenAiSttProvider } from './providers/stt/openai.js';
import { AzureTtsProvider } from './providers/tts/azure.js';
import { buildServer } from './server.js';
import { getWeather } from './tools/weather.js';

const config = loadConfig();
const here = dirname(fileURLToPath(import.meta.url));
const promptTemplate = readFileSync(join(here, '..', 'prompts', 'sahbi.md'), 'utf8');

let llm: LlmProvider | null = null;
if (isLlmConfigured(config)) {
  const opts = { apiKey: config.llm.apiKey, model: config.llm.model, baseUrl: config.llm.baseUrl, timeoutMs: config.llm.timeoutMs };
  llm = config.llm.provider === 'anthropic' ? new AnthropicProvider(opts) : new OpenAiProvider(opts);
}

const app = await buildServer({
  config,
  llm,
  search: isSearchConfigured(config) ? new BraveSearchProvider(config.search.apiKey) : null,
  stt: isSttConfigured(config)
    ? config.stt.provider === 'azure'
      ? new AzureSttProvider(config.stt.azureKey, config.stt.azureRegion)
      : new OpenAiSttProvider(config.stt.openaiKey, config.stt.openaiModel)
    : null,
  tts: isTtsConfigured(config) ? new AzureTtsProvider(config.tts.azureKey, config.tts.azureRegion, config.tts.defaultVoice) : null,
  weather: (city) => getWeather(city),
  promptTemplate,
});

try {
  await app.listen({ port: config.port, host: config.host });
} catch (err) {
  console.error(err);
  process.exit(1);
}
