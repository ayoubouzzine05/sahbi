# Status (2026-11-18)

DONE = implemented and verified by commands run here. PARTIAL = part done. NOT DONE = missing. NOT VERIFIED = written but could not be run here; the reason is given.

## Verification runs (real output observed)

| Command | Result |
|---|---|
| `flutter pub get`, `flutter gen-l10n` | OK |
| `dart format --set-exit-if-changed lib test integration_test` | clean |
| `flutter analyze` | **No issues found** |
| Follow-up 3 (local, this sandbox) | `flutter analyze` clean, format clean, unit **251/251** (before photo mode), `chat_controller_test` 30/30 (with photo mode), robot_face + search_sources 10/10, golden 13/13. `app_shell_test`: the Dart compiler crashed (out of RAM) locally; it **passed in GitHub Actions** (Android run 44418906637, "Unit, widget and golden tests" step). A later full unit run stalled here and was stopped at 20 min; CI is the reference |
| Backend follow-up 3 | `npm run lint`, `npm run typecheck`, `npm run build` OK, **87/87** tests |
| `flutter test` (unit + widget + golden), M0–M8 | **258 passed, 0 failed** (full run with `--concurrency=1`; default concurrency can stall this 2-CPU sandbox while loading, but each folder passes) |
| Note | One full `flutter test` run stalled while *loading* test files (stuck at `loading robot_face_test.dart`) and was stopped at 900 s. Each file then passed on its own, and the next full run passed in 19 s. Not reproduced; recorded for transparency |
| `cd backend && npm ci && npm run lint && npm test && npm run build` | OK. **73 tests passed**, eslint + tsc (src and tests) clean, `npm audit --omit=dev`: 0 vulnerabilities |
| CI smoke step from `backend.yml`, replayed locally | `grep '"llm":{"configured":false'` matches the real health JSON; unauthenticated `/v1/chat` → 401. OK |
| Backend runtime smoke (`node dist/index.js`, no keys) | `GET /v1/health` 200 with every service `configured:false` except weather; `POST /v1/auth/anonymous` returned a 94-char token; `POST /v1/chat` → **503 not_configured**; without a token → **401** |
| Live weather through the backend | `/v1/weather?city=Casa` → 502 `upstream_error`. Geocoding answered 200, but `api.open-meteo.com` timed out from the sandbox (curl also timed out). **NOT VERIFIED** live |
| `flutter build apk --debug` | Failed in this sandbox (RAM, see below). **Built successfully in GitHub Actions**, run 44157728254 (commit `d7353e7`) |
| `flutter build apk --release` | **Built in GitHub Actions** (same run): `sahbi-universal.apk` 62,132,059 bytes and `sahbi-arm64.apk` (`--split-per-abi`, arm64) 23,212,833 bytes. **DEBUG-SIGNED** (no keystore secrets). Published at `github.com/ayoubouzzine05/sahbi/releases/tag/latest`. arm64 sha256 `f75d8076…5b6862` |
| `flutter test integration_test` | **PASSED** on an Android API 34 x86_64 emulator in GitHub Actions (same run, `integration-test` job) |
| CI: format, analyze, all unit/widget/golden tests on GitHub (Ubuntu, Flutter stable) | **PASSED**. The Linux-generated goldens also match on the CI runner |
| `docker build backend` | No Docker in the sandbox; **built successfully in GitHub Actions** (Backend run 44159622121) |

### APK build attempts (2 GB RAM, no swap)

1. Gradle daemon crashed while auto-installing NDK 28.2 (`Gradle build daemon disappeared unexpectedly`). The sandbox froze.
2. The NDK was pre-installed with sdkmanager. Gradle got to configuration and printed a **real error: `permission_handler_android` requires compileSdk 37**. **Fixed** (`compileSdk = 37`). A memory watchdog then stopped it.
3. With smaller JVM settings it reached `:audio_service:compileDebugJavaWithJavac` and failed with `Metaspace`.
4. Rebalanced the heap; it compiled most plugin modules (126 s) and was stopped by the watchdog. An orphaned Dart `frontend_server` (**1.3 GB RSS**) was found afterwards.
5. Gradle plus `frontend_server` together exhausted RAM (MemAvailable about 38 MB for about 50 min). Stopped.

Conclusion: the build needs a machine with more memory. It was then built on the GitHub Actions runner. The first CI run built the debug APK, but the release build failed in `:url_launcher_android:lintVitalAnalyzeRelease`: AGP's lint crashed with `NoSuchMethodError: List.removeLast()`, a JDK 21 API, on JDK 17. Fixed by running CI on JDK 21 (bytecode target stays 17). The second run passed everything.

Still **not verified on a real phone**: microphone and voice, SAF file picking, output switcher, notification and foreground service, and the face on real hardware. The Kotlin platform channel now **compiles** (APK built), but its behaviour is untested.

## Requirements

| # | Requirement (spec §) | Status | Evidence |
|---|---|---|---|
| 1 | Environment inspected, docs/ENVIRONMENT.md (§1) | DONE | docs/ENVIRONMENT.md |
| 2 | No unverified claims; STATUS with NOT VERIFIED (§1) | DONE | this file |
| 3 | "Service not configured" states, labelled offline replies (§1.4) | DONE | chat_controller_test (5 offline reasons), app_shell_test, backend 503 smoke |
| 4 | Packages via `flutter pub add`; versions from docs (§1.6) | DONE | pubspec.lock, DEPENDENCIES.md |
| 5 | Flutter, Android only, minSdk 26, Riverpod, go_router, ARB ar/fr/en (§2) | DONE | `android/app/build.gradle.kts`, `lib/app.dart`, `lib/l10n` |
| 6 | Feature-first folders incl. search (§2) | DONE | `lib/features/{face,personality,voice,brain,search,music,chat,memory,settings,robot_link}` |
| 7 | Interfaces LlmProvider, SearchProvider, SttProvider, TtsProvider, MusicProvider, RobotTransport (§2) | DONE | FEATURES.md "Interfaces" (MusicProvider = `MusicEngine`) |
| 8 | docs/DEPENDENCIES.md with licences (§2) | DONE | docs/DEPENDENCIES.md |
| 9 | Visual design, zellige patterns, original assets (§3) | DONE | goldens, ASSETS_LICENSES.md |
| 10 | Face with blink, gaze, touch-follow, breathing; 10 emotions (§3) | DONE (host) / NOT VERIFIED on device | robot_face_test, goldens, personality_test |
| 11 | Mouth sync documented as approximate (§3) | DONE | FEATURES.md, ROBOT_PROTOCOL.md |
| 12 | Darija Arabic script and Arabizi, French code-switching (§4) | DONE (parser) / NOT VERIFIED (recognition quality) | command_parser_test (68) |
| 13 | On-device STT and TTS (§5) | NOT VERIFIED | code in `lib/features/voice`; compiles into the APK; needs a real phone |
| 14 | Cloud STT and TTS via backend, Azure ar-MA (§5) | NOT VERIFIED | backend routes tested with mocks; no Azure key |
| 15 | Fallback cloud → device → typed (§5) | DONE (logic) | voice_controller_test |
| 16 | Push-to-talk, tap face, "Sme3 lia", stop/interrupt (§5) | DONE (logic) / NOT VERIFIED on device | voice and chat tests; interrupt bug found and fixed |
| 17 | Optional wake phrase, flag off (§5) | NOT DONE (by design) | toggle disabled with a visible reason (`AppConfig.wakeWordAvailable = false`) |
| 18 | Mic rationale and denied handling (§5) | NOT VERIFIED | `lib/features/voice/mic_flow.dart`; TEST_PLAN items 1–3 |
| 19 | LLM reply schema, validate, retry once (§6) | DONE | backend schema.test, brain.test |
| 20 | Backend proxy: SSE, provider env, token, rate limit, size limits, CORS, health, no bodies in logs (§6) | DONE | server.test (10), providers.test; runtime smoke |
| 21 | Real LLM answers (§6) | **VERIFIED (live, 2026-11-18)** | Deployed on Vercel Hobby at `https://sahbi-sigma.vercel.app` with the user's Gemini auth key (`AQ.`), native API, model chain `gemini-4-hydrogen` → `gemini-3.5-flash-lite` → `gemini-3.8-flash` (3.8-flash returned 503 repeatedly). From the sandbox: `/v1/health` → llm configured (gemini); `/v1/chat` "salam sahbi, kidayr? chno smitek?" streamed Darija deltas + a valid final JSON (emotion happy) in 4.1 s; "kifach l jaw lyoum f Casablanca?" ran the weather tool (Open-Meteo) and answered in Darija in 8.7 s. The APK with this URL built in CI; **not verified on the user's phone yet** |
| 22 | Search with sources, citations, verification (§7) | DONE (mocked) / NOT VERIFIED live | brain.test, search_sources_test; Brave only (Tavily/SerpAPI NOT DONE) |
| 23 | Weather via Open-Meteo (§7) | DONE (mocked) / NOT VERIFIED live | providers.test; live forecast host unreachable here |
| 24 | Translate (§7) | DONE | schema action plus translation card |
| 25 | Music: SAF local files, just_audio + audio_service, FGS + POST_NOTIFICATIONS (§8) | NOT VERIFIED | music_controller_test (logic); Kotlin not compiled |
| 26 | Active output plus system output switcher (§8) | NOT VERIFIED | MainActivity.kt; API 30–33 path is non-public, best-effort |
| 27 | Spotify / YT Music deep links (§8) | NOT VERIFIED | `streaming_links.dart` |
| 28 | Optional Spotify App Remote behind flag (§8) | NOT DONE | SDK not bundled; flag off |
| 29 | CC0 demo tracks plus ASSETS_LICENSES.md (§8) | DONE | asset test, ASSETS_LICENSES.md |
| 30 | Chat UI (§9) | DONE (host) | app_shell_test (send, offline label, routes) |
| 31 | Local command parser, ≥ 60 tested phrases (§9) | DONE | 68 phrase cases |
| 32 | Personality engine modules with tests (§10) | DONE | personality_test |
| 33 | Encrypted memory, consent, view/edit/delete/export (§11) | PARTIAL | AES-GCM blob instead of Drift+SQLCipher (documented deviation); memory_store_test |
| 34 | Privacy settings (§11) | DONE (host) | settings routes render (app_shell_test) |
| 35 | Offline mode with connectivity_plus + /v1/health (§12) | DONE (logic) / NOT VERIFIED on device | chat tests, banner widget test |
| 36 | Robot link: Local, Simulated, BLE/Wi-Fi skeletons, ROBOT_PROTOCOL.md (§13) | DONE | robot_protocol_test (25), docs/ROBOT_PROTOCOL.md |
| 37 | BLE permissions requested only in Robot settings (§13) | NOT DONE (deferred) | BLUETOOTH_SCAN not declared because nothing scans yet; documented |
| 38 | Settings screen, all §14 sections plus hidden debug screen (§14) | DONE (host) | all sections present; routes render in ar/fr/en |
| 39 | Unit tests (§15) | DONE | 258 Flutter tests, 73 backend tests |
| 40 | Widget tests: face, chat, settings, RTL (§15) | DONE | robot_face_test, app_shell_test, search_sources_test |
| 41 | Golden tests per emotion (§15) | DONE | all 10 emotions, reviewed visually; rendered on Linux |
| 42 | Backend tests with mocked providers (§15) | DONE | 53 passing |
| 43 | Integration test, main flow (§15) | DONE (emulator) | passed on API 34 emulator in GitHub Actions |
| 44 | Manual device checklist (§15) | DONE (written) / all items NOT RUN | docs/TEST_PLAN.md |
| 45 | CI android.yml plus backend workflow; keystore via secrets (§15) | DONE | android.yml and backend.yml (lint, 53 tests, build, smoke, docker) green on GitHub; keystore path not exercised (no secrets) |
| 46 | Debug APK (§15) | DONE (CI) | built in GitHub Actions; uploaded as artifact `sahbi-debug-apk` |
| 47 | Release APK (§15) | DONE (CI), **debug-signed** | universal and arm64 APKs in the `latest` release; store signing needs keystore secrets |
| 48 | Milestones committed (§16) | DONE | `git log` |
| 49 | README, backend/README, API_KEYS, FEATURES, STATUS, ENVIRONMENT, ASSETS_LICENSES (§17) | DONE | files present |
| 50 | Screenshots from a real run (§17) | NOT DONE | no device run; golden PNGs are test renders, not screenshots |

## Follow-up 3 (2026-11-18): Darija, live camera, face dashboard, male voice, custom name, wake by name

| # | Item | Status | Evidence |
|---|---|---|---|
| F3.1 | Stronger Moroccan Darija: prompt v1.1.0 with explicit Darija vocabulary/grammar rules, banned Egyptian/Levantine/Gulf/fus7a markers, bad→good examples; `tts_text` stays Darija in Arabic script | DONE (prompt) / **NOT VERIFIED** on real replies | backend test checks the rules are in the prompt; quality depends on the model |
| F3.2 | Live camera ("7el camera", "chouf hadi", camera button): camera ≈1 JPEG/s + mic PCM 16 kHz → Gemini Live (`gemini-3.8-live`), voice answer 24 kHz PCM, captions, barge-in, goAway/session resumption, 10-min free-quota guard. **Fallback photo mode**: if Google refuses the live session, the same screen keeps the camera and a 📸 button sends one JPEG with the normal chat (`/v1/chat` `image`, Gemini `inlineData`); the answer is shown and spoken | DONE (code + unit tests) / **NOT VERIFIED** on a phone. Against Google: `/v1/live/token` returned **401 UNAUTHENTICATED** with the user's AI Studio `AQ.` key (seen 2026-11-18), so live video does **not** work with that key; photo mode is untested live because the key then stopped working for chat too (see below) | `/v1/live/token` (single-use ephemeral token, locked model/prompt/voice, `fieldMask` as in google-genai's SDK), LiveSession protocol tests with a fake socket, 3 backend tests |
| F3.3 | Dashboard = full-screen face (eyes, brows, mouth only), controls fade after 6 s and stay tappable, no tab bar on home, keep-screen-on setting | DONE (host) | 3 new goldens `face_full_*.png` (reviewed), app_shell_test |
| F3.4 | Male voice by default: cloud TTS via Gemini TTS (`Puck`, female `Aoede`) or Azure Jamal/Mouna; live voice male; device TTS picks a voice named "male" or lowers pitch ×0.8; Settings male/female picker | DONE (code) / **NOT VERIFIED** | The Interactions TTS endpoint answered 401 to the `AQ.` key, so TTS now uses `generateContent` with `responseModalities:["AUDIO"]` (PCM → WAV). That call also got 401, at a moment when **chat with the same key failed with 401 too**, so the key itself was rejected. Never heard a Gemini voice from here. pickGenderVoice test, 2 GeminiTtsProvider tests |
| F3.5 | Custom robot name: Settings field, persisted, sent as `robot_name` to chat and live prompts, used in UI and offline "who are you" | DONE | AppSettings tests, widget test (name shown + persisted), backend prompt test |
| F3.6 | Wake by name while the app is open: on-device recogniser in short sessions, Arabic/Latin phonetic matching ("Zizou" = "زيزو"), "name" → opens mic, "name + question" → sends it; pauses while talking, in background and in live camera | DONE (logic + tests) / **NOT VERIFIED** on a phone | 12 matcher/controller tests. Known limits: some phones beep each time listening restarts; uses battery; needs the mic permission |

### Google key status (2026-11-18, observed through the deployed backend)

| Call | Result |
|---|---|
| `POST /v1/live/token` (Google `auth_tokens`) | 502 ← Google **401 UNAUTHENTICATED "API key not valid"** |
| `POST /v1/tts` via Interactions API | 502 ← Google 401 |
| `POST /v1/tts` via `generateContent` (commit `8703e00`) | 502 ← Google 401 |
| `POST /v1/chat` (worked earlier the same day) | SSE `error` "LLM returned HTTP 401" |

So the `AQ.` key stopped being accepted for everything. Google's forum has many reports of `AQ.` keys returning 401 `ACCESS_TOKEN_TYPE_UNSUPPORTED` (one says it happens after renaming a key; a fresh key that is never renamed works). Fix for the user: create a new key in AI Studio, do not rename it, put it in Vercel → Settings → Environment Variables → `LLM_API_KEY`, then redeploy. Nothing in the app has to change.

## Bugs found and fixed by testing in this pass

- Follow-up 3: the phonetic matcher collapsed "Zizou" to one consonant (repeats separated by a vowel were merged) and "look" became "lok" after normalisation, so the English camera phrase was missed; a refused Live connection reported "closed" twice. All three were caught by the new tests and fixed.
- Follow-up 3: in the big full-screen face the eye glow showed hard clip edges (seen in the golden). It is now blurred from the visible eye shape.
- Follow-up 3: an ephemeral token with a locked setup and **no** `fieldMask` makes Google ignore the app's whole setup message, which would have broken session resumption. A `fieldMask` is now sent.

- **Arabic (default) and French UI threw "No MaterialLocalizations found"** in the navigation bar. Cause: the generated `L10n.localizationsDelegates` serves the legacy material type. Fixed by using material_ui's delegates.
- TTS `interrupt()` left `speak()` pending forever. An interrupted cloud utterance then fell back to device TTS and started talking again. `interrupt` could also block on a busy engine.
- Face: sad brows were drawn angry (sign error); the eye glow was clipped into visible boxes; TalkBack saw 4 bogus scroll actions.
- Status pills overflowed with French labels; ZelligeCard hid ListTile ripples.
- **Chat could hang:** a new message sent while the AI request was still pending left the old `send()` waiting forever (a cancelled subscription never fires onDone), with a permanent "thinking" bubble. Awaiting the cancel of the `async*` stream could also block the *new* message. Fixed with explicit release plus a generation counter; 3 regression tests fail on the old code and pass now.
- **The stop button was dead while Sahbi was thinking.** It only interrupted speech, not the AI request. It now calls `ChatController.stop()`.
- The README example "tla3 sout" (raise volume, Arabizi) was not recognised, although the Arabic-script طلع was. Added to the parser with tests.
- `compileSdk` had to be 37 for `permission_handler_android`.

## Sleeping free-tier backend

The free Render plan sleeps after 15 min. Before this change, the 6 s health check marked the server unreachable and the AI was skipped. Now an unreachable server triggers `ConnectivityMonitor.wake()`, a 90 s health check with a "waking the server…" bubble, and only then an honest offline reply. Covered by 5 chat tests (wake → AI answer, still down → offline, woke but no key, stop while waking, no wake for other reasons) and 3 connectivity tests.

## Missing credentials

`LLM_PROVIDER`/`LLM_MODEL`/`LLM_API_KEY`, `BRAVE_SEARCH_API_KEY`, `AZURE_SPEECH_KEY`/`AZURE_SPEECH_REGION`, a production `AUTH_SECRET`, and the Android release keystore secrets. See API_KEYS.md.
