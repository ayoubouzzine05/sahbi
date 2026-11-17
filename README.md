# SAHBI · صاحبي

**Sahbi ("my buddy") is a Moroccan AI pocket robot companion for Android.** The phone screen is the robot's face and the app is its brain. It talks in Darija (Arabic script or Arabizi), French and English, reacts with an animated face, plays your music, remembers what you allow it to, and keeps working offline with clearly labelled limits. A future physical robot can reuse the same brain over BLE or Wi-Fi.

> Inspired by the idea of pocket AI pets. The name, design, code, voice lines and assets are original.

**Status: see [`docs/STATUS.md`](docs/STATUS.md).** In short, the analyzer is clean, 250 Flutter tests and 53 backend tests pass, and the backend was smoke-tested. APKs are built by GitHub Actions. The integration test passes on an Android emulator, but the app has **not been tested on a real phone yet**.

**Download (Android 8+):** [sahbi-arm64.apk](https://github.com/ayoubouzzine05/sahbi/releases/latest/download/sahbi-arm64.apk) (most phones) · [sahbi-universal.apk](https://github.com/ayoubouzzine05/sahbi/releases/latest/download/sahbi-universal.apk). Debug-signed: allow "install unknown apps" for your browser.

## Repository layout

```
lib/
  core/            theme, zellige patterns, config, backend client (SSE), connectivity, platform channel
  features/
    face/          CustomPainter robot face + animation engine
    personality/   emotion detector & mapper, voice state machine, idle behaviour, offline lines
    voice/         device/cloud STT & TTS, fallback, mic permission flow
    brain/         reply schema, local command parser (Darija/Arabizi/fr/en)
    search/        source chips & verification badge
    chat/          chat pipeline (commands → AI → honest offline)
    music/         SAF library, just_audio + audio_service, output switcher, deep links
    memory/        consented, AES-GCM-encrypted local memory
    settings/      settings, privacy
    robot_link/    protocol v1, simulator, BLE/Wi-Fi skeletons
android/           Kotlin platform channel (SAF, audio output, volume, export)
backend/           Fastify + TypeScript proxy (LLM, search, weather, STT, TTS)
docs/              STATUS, FEATURES, ENVIRONMENT, TEST_PLAN, API_KEYS, ROBOT_PROTOCOL, DEPENDENCIES
```

## Requirements

- Flutter stable ≥ 3.50 (Dart 3.14), JDK 17, Android SDK with platforms 36 and 37, ≥ 8 GB RAM to build.
- An Android 8.0+ phone (API 26) or an emulator.
- Node.js ≥ 20 for the backend.

## Run the app

```bash
flutter pub get
flutter gen-l10n
flutter run                                   # debug, on a connected device/emulator
# point it at a backend at build time (or set the URL later in Settings → AI):
flutter run --dart-define=SAHBI_BACKEND_URL=http://10.0.2.2:8080
```

Without a backend, Sahbi still works: face, local commands ("ch3el lia chi music", "wqef", "tla3 sout"), local music and memory. AI replies are replaced by labelled offline lines.

## Build

```bash
flutter analyze && flutter test
flutter build apk --debug
flutter build apk --release   # uses android/key.properties if present, otherwise DEBUG-SIGNED (not for stores)
```

Release signing: create `android/key.properties` (never commit it):

```
storeFile=/absolute/path/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

CI (`.github/workflows/android.yml`) builds both APKs and writes `key.properties` from GitHub Secrets (see `docs/API_KEYS.md`).

## Backend

**Free AI in 2 minutes from a phone:** get a Gemini key at https://aistudio.google.com/apikey, then [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/ayoubouzzine05/sahbi). Paste the key, and put the Render URL in the app under Settings → AI.


```bash
cd backend && npm ci && cp .env.example .env && npm run dev
```

See [`backend/README.md`](backend/README.md). All API keys live in the backend environment. **The app contains no keys.**

## Tests

```bash
flutter test                      # unit + widget + golden
flutter test integration_test     # needs a device or emulator
cd backend && npm test
```

The manual device checklist is in [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md).

## Privacy

- Memory is opt-in (separate consent for facts and history), stored encrypted on the device, and can be viewed, edited, exported and deleted.
- Sending messages to the AI can be switched off.
- The backend is stateless and does not log message contents.

## Licences

Third-party packages: [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md). Fonts and audio: [`ASSETS_LICENSES.md`](ASSETS_LICENSES.md).
