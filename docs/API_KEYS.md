# API keys and secrets

**Rule: no API key is ever placed in the Flutter app or the APK.** The app only knows the backend URL. Every provider key lives in the backend's environment: a `.env` file locally, or your host's secret manager in production. `.env`, keystores and `key.properties` are listed in `.gitignore`.

Every service is optional. Anything unset is reported as `configured: false` by `GET /v1/health`, and the app shows "service not configured" instead of faking it.

| Variable | Needed for | Where to get it | Notes |
|---|---|---|---|
| `AUTH_SECRET` | signing anonymous install tokens | generate: `openssl rand -hex 32` | **Set it in production.** If empty, an ephemeral secret is generated at start-up (a warning is logged), so tokens reset on every restart |
| `LLM_PROVIDER` | AI replies | `anthropic`, `openai` or `none` | |
| `LLM_MODEL` | AI replies | your provider's current model list (Anthropic: docs.anthropic.com → Models; OpenAI: platform.openai.com/docs/models) | **No default is hard-coded on purpose.** The model must support tool/function calling |
| `LLM_API_KEY` | AI replies | console.anthropic.com or platform.openai.com → API keys | |
| `LLM_BASE_URL` | optional | | OpenAI-compatible endpoint/proxy |
| `SEARCH_PROVIDER` / `BRAVE_SEARCH_API_KEY` | web search with sources | api-dashboard.search.brave.com | Header `X-Subscription-Token`. Only Brave is implemented (Tavily and SerpAPI are not) |
| *(none)* | weather | Open-Meteo | No key. Free for non-commercial use; check open-meteo.com terms for commercial use |
| `STT_PROVIDER` | cloud speech recognition | `azure`, `openai` or `none` | |
| `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION` | Azure STT + TTS | Azure portal → create a "Speech" resource → Keys and Endpoint | ar-MA STT and voices `ar-MA-JamalNeural` / `ar-MA-MounaNeural` are listed in Microsoft's language-support docs |
| `OPENAI_STT_API_KEY`, `OPENAI_STT_MODEL` | OpenAI transcription | platform.openai.com | choose a current transcription model |
| `TTS_PROVIDER`, `AZURE_TTS_VOICE`, `GEMINI_TTS_MODEL` | cloud TTS | | With a Gemini LLM key, TTS defaults to **Gemini** (`gemini-3.8-flash-tts`, free tier) with a **male** voice (`Puck`; female `Aoede`, chosen in app Settings). `TTS_PROVIDER=azure` uses Azure (`ar-MA-JamalNeural` male / `ar-MA-MounaNeural` female); `none` turns cloud TTS off. Moroccan Darija is not in Google's TTS language table, so the accent is best-effort |
| `GEMINI_LIVE_MODEL`, `LIVE_ENABLED` | live camera mode | (same Gemini key) | `/v1/live/token` mints single-use ephemeral tokens for `gemini-3.8-live` (free tier). Model, prompt and voice are locked in the token; the key never reaches the phone. `LIVE_ENABLED=false` disables it |

## Free AI without a card: Google Gemini + Vercel (phone-only setup)

1. **Gemini key:** open https://aistudio.google.com/apikey, sign in with Google and create an API key. No card needed, and Morocco is a supported region. On the free tier, Google may use prompts and answers to improve its products.
2. **Vercel (Hobby plan, free):**
   1. Open https://vercel.com/signup and choose "Continue with GitHub".
   2. Open https://vercel.com/new and import `sahbi`.
   3. Set **Root Directory** to `backend`.
   4. Add one environment variable, `LLM_API_KEY` = the Gemini key, and deploy.

   Vercel detects Fastify from `src/index.ts`. Hobby has no billing cycle: if you exceed the limits, features pause instead of charging.
3. **App:** the release APK already contains the URL (repo variable `SAHBI_BACKEND_URL`). Otherwise, in Settings → AI, set the backend URL to the project's **production domain** (`https://<project>.vercel.app`), not a deployment-specific preview URL. Preview URLs are behind Vercel Authentication.

Since 2026-05-28, AI Studio issues **auth keys** that start with `AQ.` (older standard keys start with `AIza`); both are recognised. The backend calls Gemini's **native** `generateContent` endpoint with the `x-goog-api-key` header, because auth keys have been reported to fail on the OpenAI-compatible `/v1beta/openai/` path. You can also set `LLM_PROVIDER=gemini` explicitly.

That one key is enough:
- An `AQ.…`/`AIza…` key without `LLM_PROVIDER` selects the Gemini preset (`backend/src/config.ts`): native API, model chain `gemini-4-hydrogen` → `gemini-3.5-flash-lite` → `gemini-3.8-flash` (all free tier; next model on 429/5xx/404/timeout, 20 s each; override with `LLM_MODEL` / `LLM_FALLBACK_MODELS`, or set `LLM_FALLBACK_MODELS=none`), thinking level low, 4096 output tokens. Any explicit `LLM_*` variable overrides it.
- When `AUTH_SECRET` is unset, it is derived from the key, so all serverless instances accept the same install tokens.

**Render (`render.yaml`)** also works, but its sign-up asked for a card, so it is not the default.

## Production storage

- **Fly.io:** `fly secrets set LLM_API_KEY=...`
- **Google Cloud Run:** Secret Manager → mount as env vars.
- **Render / Railway:** environment variables in the dashboard (marked secret).
- **Docker / VPS:** `docker run --env-file /etc/sahbi/backend.env ...` with the file `chmod 600`, outside the repo.

## Android signing (CI)

The release keystore is never committed. CI expects these GitHub Secrets:

| Secret | Content |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Without them, the release APK is **debug-signed and not for stores**. The workflow names the artifact accordingly.

## Rotation and leaks

The app has no keys to leak. If a backend key leaks, rotate it at the provider and update the host secret; no app update is needed. Rotating `AUTH_SECRET` invalidates all install tokens, and apps re-authenticate automatically on the next 401.
