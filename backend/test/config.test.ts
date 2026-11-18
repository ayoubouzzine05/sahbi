import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { GEMINI_PRESET, derivedAuthSecret, isLlmConfigured, loadConfig } from '../src/config.js';
import { PROMPT_TEMPLATE } from '../src/prompt.generated.js';

describe('Gemini one-key deploy', () => {
  it('an AIza… key alone configures Gemini', () => {
    const c = loadConfig({ LLM_API_KEY: 'AIzaTEST' });
    expect(c.llm.provider).toBe('openai');
    expect(c.llm.baseUrl).toBe(GEMINI_PRESET.baseUrl);
    expect(c.llm.model).toBe(GEMINI_PRESET.model);
    expect(c.llm.reasoningEffort).toBe('low');
    expect(c.llm.maxOutputTokens).toBe(4096);
    expect(isLlmConfigured(c)).toBe(true);
  });

  it('LLM_PROVIDER=gemini works with any key format', () => {
    const c = loadConfig({ LLM_PROVIDER: 'gemini', LLM_API_KEY: 'k' });
    expect(c.llm.baseUrl).toBe(GEMINI_PRESET.baseUrl);
    expect(isLlmConfigured(c)).toBe(true);
  });

  it('explicit LLM_* values win over the preset', () => {
    const c = loadConfig({ LLM_API_KEY: 'AIzaTEST', LLM_MODEL: 'other-model', LLM_MAX_OUTPUT_TOKENS: '900', LLM_REASONING_EFFORT: 'medium' });
    expect(c.llm.model).toBe('other-model');
    expect(c.llm.maxOutputTokens).toBe(900);
    expect(c.llm.reasoningEffort).toBe('medium');
  });

  it('an explicit OpenAI provider is never hijacked by the preset', () => {
    const c = loadConfig({ LLM_PROVIDER: 'openai', LLM_API_KEY: 'AIzaLooksLikeGoogle', LLM_MODEL: 'm' });
    expect(c.llm.baseUrl).toBe('https://api.openai.com');
  });

  it('non-Google keys without a provider stay unconfigured (no invented model)', () => {
    const c = loadConfig({ LLM_API_KEY: 'sk-something' });
    expect(c.llm.provider).toBe('none');
    expect(isLlmConfigured(c)).toBe(false);
  });
});

describe('AUTH_SECRET for serverless', () => {
  it('derives a stable secret from the LLM key when unset', () => {
    const a = loadConfig({ LLM_API_KEY: 'AIzaTEST' }).authSecret;
    const b = loadConfig({ LLM_API_KEY: 'AIzaTEST' }).authSecret;
    expect(a).toHaveLength(64);
    expect(a).toBe(b);
    expect(a).not.toContain('AIzaTEST');
    expect(loadConfig({ LLM_API_KEY: 'AIzaOTHER' }).authSecret).not.toBe(a);
  });
  it('explicit AUTH_SECRET wins; nothing set stays empty (ephemeral)', () => {
    expect(loadConfig({ LLM_API_KEY: 'AIzaTEST', AUTH_SECRET: 's' }).authSecret).toBe('s');
    expect(loadConfig({}).authSecret).toBe('');
    expect(derivedAuthSecret('')).toBe('');
  });
});

describe('embedded prompt', () => {
  it('matches prompts/sahbi.md (run npm run gen:prompt after editing it)', () => {
    expect(PROMPT_TEMPLATE).toBe(readFileSync(new URL('../prompts/sahbi.md', import.meta.url), 'utf8'));
  });
});
