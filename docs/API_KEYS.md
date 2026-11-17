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
| `TTS_PROVIDER`, `AZURE_TTS_VOICE` | cloud TTS | | default voice `ar-MA-JamalNeural` |

## Free AI: Google Gemini + Render (phone-only setup)

1. **Gemini key:** open https://aistudio.google.com/apikey, sign in with Google and create an API key. The free tier needs no card. On the free tier, Google may use prompts and answers to improve its products; a paid key opts out.
2. **Deploy:** open https://render.com/deploy?repo=https://github.com/ayoubouzzine05/sahbi and sign in (for example with GitHub). Render reads `render.yaml`, asks for `LLM_API_KEY` (paste the Gemini key), and deploys `backend/` on the **free** plan in Frankfurt.
3. **App:** in Settings → AI, set the backend URL to the service URL Render shows (`https://<name>.onrender.com`).
4. **Free plan behaviour:** the server sleeps after 15 min idle and wakes in about 1 min. The app shows "waking the server…" and waits up to 90 s before answering offline.

`render.yaml` sets these values:

| Key | Value |
|---|---|
| `LLM_PROVIDER` | `openai` |
| `LLM_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai/` |
| `LLM_MODEL` | `gemini-3.8-flash` |
| `LLM_REASONING_EFFORT` | `low` |
| `LLM_MAX_OUTPUT_TOKENS` | `4096` |

Change the model in Render → Environment. Free-tier rate limits are per project and shown in AI Studio.

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
