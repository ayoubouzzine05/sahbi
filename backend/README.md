# SAHBI backend

A stateless Fastify + TypeScript proxy between the SAHBI app and the AI services. It holds every API key so the APK holds none, validates the model's output, runs the tools (web search, weather), and streams replies over SSE.

```
App ──HTTPS──▶ /v1/chat (SSE) ──▶ LLM (Anthropic | OpenAI)
                                 ├─▶ web_search (Brave)      → numbered sources, cited by id
                                 └─▶ get_weather (Open-Meteo, no key)
    ──────────▶ /v1/stt  ─▶ Azure Speech (ar-MA) | OpenAI transcription
    ──────────▶ /v1/tts  ─▶ Azure Neural TTS (ar-MA-JamalNeural / MounaNeural)
```

## Quick start (local)

```bash
cd backend
npm ci
cp .env.example .env      # fill in what you have; everything is optional
npm run dev               # tsx watch on http://0.0.0.0:8080
curl localhost:8080/v1/health
```

In the Android **emulator** the app reaches it at `http://10.0.2.2:8080`. Only debug builds allow cleartext HTTP (`android/app/src/debug/AndroidManifest.xml`); release builds need HTTPS. On a real phone, use your computer's LAN IP in a debug build, or deploy with HTTPS.

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | dev server with reload |
| `npm run build` | compile to `dist/` |
| `npm start` | run `dist/index.js` |
| `npm test` | vitest, all providers mocked (no network, no keys) |
| `npm run lint` | eslint + `tsc --noEmit` for `src` and `test` |

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/v1/health` | – | `{ok, version, prompt_version, services:{llm,search,weather,stt,tts:{configured,provider}}}` |
| POST | `/v1/auth/anonymous` | – | `{install_id: uuid}` → `{token}` (HMAC, 30-day TTL). Limited to 10/min |
| POST | `/v1/chat` | Bearer | SSE events: `status {phase}`, `delta {text}`, `final {reply}`, `error {code,message}` |
| POST | `/v1/summarize` | Bearer | compress older turns, so the app keeps context without the server storing anything |
| GET | `/v1/weather?city=` | Bearer | Open-Meteo geocoding + forecast |
| POST | `/v1/stt?lang=ar-MA` | Bearer | raw audio body (≤ 2 MB) → `{text}` |
| POST | `/v1/tts` | Bearer | `{text, language, voice?}` → audio/mpeg |

Error codes (JSON `{error:{code,message}}`): `not_configured` 503, `upstream_timeout` 504, `upstream_error` 502, `invalid_output` 502, `bad_request` 400, `unauthorized` 401, `rate_limited` 429, `server_error` 500.

## How a chat turn works

1. The system prompt is `prompts/sahbi.md`, filled with the user's settings (reply language, Darija script, humour, name, local time, consented memory facts, conversation summary). Its version is reported by `/v1/health`.
2. The model may call `web_search` or `get_weather`, up to 5 tool steps.
3. The final answer **must** be a `sahbi_reply` tool call: `{display_text, tts_text, language, emotion, intensity, actions[], source_ids[], sources_agree?}`. It is validated with zod. If invalid, the model gets exactly **one** retry with the validation error, then the turn fails with `invalid_output`. Nothing is made up on the server side.
4. `source_ids` that don't match a real search result are dropped. Verification is `confirmed` only with ≥ 2 distinct domains and `sources_agree !== false`; otherwise `unconfirmed`. Weather sources are labelled `data`.
5. No conversation state is stored. **Message bodies are never logged**: the request log contains method, path, status and latency only.

## Security

- Anonymous install tokens: `v1.<install uuid>.<iat>.<hmac-sha256>`, verified with a constant-time comparison.
- Rate limit per token (falls back to IP): `RATE_LIMIT_PER_MINUTE`, default 30.
- Body limits: JSON 64 KB, audio 2 MB.
- CORS is closed unless `CORS_ORIGINS` is set (the Android app doesn't need CORS).
- Upstream calls have timeouts and one retry on 5xx/network errors.

## Deploy on Vercel (free Hobby, no card)

Import the repo at https://vercel.com/new and set:
- Root Directory: `backend`
- Environment variable: `LLM_API_KEY` = a Gemini key

Vercel's zero-config Fastify support uses `src/index.ts`. The prompt is embedded in `src/prompt.generated.ts` (regenerate it with `npm run gen:prompt`; a test catches drift), so nothing is read from disk at runtime. `AUTH_SECRET` falls back to a value derived from `LLM_API_KEY`.

## Deploy on Render (free plan; sign-up may ask for a card)

Use [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/ayoubouzzine05/sahbi), which reads the root `render.yaml` (Gemini via its OpenAI-compatible API). See `docs/API_KEYS.md`.

The OpenAI adapter works with compatible endpoints:
- Versioned base URLs (such as Gemini's `/v1beta/openai/`) get `/chat/completions` appended; plain hosts get `/v1/chat/completions`.
- Only `api.openai.com` receives `max_completion_tokens`; other endpoints get `max_tokens`.
- `LLM_REASONING_EFFORT` is sent only when it is set.

## Deploy (container)

```bash
docker build -t sahbi-backend backend/
docker run -p 8080:8080 --env-file backend/.env sahbi-backend
```

It works on any container host: Cloud Run, Fly.io, Render, Railway, or a VPS. Put the keys in the host's secret manager (see `../docs/API_KEYS.md`) and serve over HTTPS (most hosts terminate TLS for you). Set `AUTH_SECRET`, or tokens reset on every restart.

## Verified in this environment

See `../docs/STATUS.md`. In short: `npm test` (53 tests), lint and build passed. The compiled server was started and `/v1/health`, auth, chat → 503 `not_configured` and 401 were checked with curl. **No real LLM/STT/TTS/search call has been made, because there are no keys. The Docker image has not been built here (no Docker in the sandbox).**
