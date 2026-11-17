# Test plan

## 1. Automated tests

| Suite | Location | What it covers | Last result (this sandbox) |
|---|---|---|---|
| Command parser | `test/unit/command_parser_test.dart` | 66 tests: Darija in Arabic script and Arabizi (3/7/9/5/2), French, English, code-switching, negatives that must *not* trigger | PASSED |
| Personality engine | `test/unit/personality_test.dart` | EmotionDetector, EmotionAnimationMapper (all 10 emotions, interpolation), VoiceState machine, IdleBehavior, ConversationContext, PersonalityResponses | PASSED |
| Brain models / backend client | `test/unit/brain_test.dart` | BrainReply schema validation, SSE parsing, error-code mapping | PASSED |
| Robot protocol | `test/unit/robot_protocol_test.dart` | CRC-16 check value, codec round-trip and rejection cases, safety limits, BLE fragmentation at MTU 23–247, out-of-order and interleaved reassembly, CRC corruption, simulator handshake, acks, 500 ms motor watchdog | PASSED |
| Memory store | `test/unit/memory_store_test.dart` | no storage without consent, encrypted at rest (no plaintext in the blob), persistence, wrong key reported, edit/delete/revoke, deleteAll rotates the key, caps, JSON export | PASSED |
| Music | `test/unit/music_controller_test.dart` | demo assets exist, play/pause/resume/stop report honestly, query matching, end of queue, engine errors, SAF import de-dup and persistence, system volume, output route, ducking | PASSED |
| Voice | `test/unit/voice_controller_test.dart` | STT fallback cloud → device → typed per mode, sticky cloud failure, locale per reply language, no_match and cancel, TTS cloud → device fallback, off mode, **interrupt completes and stays quiet**, replacement, barge-in | PASSED |
| Chat pipeline | `test/unit/chat_controller_test.dart` | 5 labelled offline reasons with no network call, local commands never reach the AI, memory consent, SSE stream → validated reply, TTS uses `tts_text`, request payload (memory only with consent), actions executed with real results, error/retry, invalid_output, missing final, 503, emotion → face, a new message or stop() while a request is stuck releases it (no hang, no stale "thinking" bubble) | PASSED |
| Face widget | `test/widget/robot_face_test.dart` | tap and long-press, accessibility (label, button, no phantom scroll actions), every emotion × state paints, animated ticker and drag-to-look | PASSED |
| App shell | `test/widget/app_shell_test.dart` | Arabic default is RTL, en/fr are LTR, tab navigation, chat input present, demo tracks listed, "backend not set" banner, offline reply labelled, **every route × ar/fr/en renders without exceptions (before and after scrolling)** | PASSED (7 tests) |
| Search UI | `test/widget/search_sources_test.dart` | numbered chips, confirmed/unconfirmed badge, data sources, "search unavailable" shown, non-http URLs not launchable | PASSED |
| Goldens | `test/golden/face_golden_test.dart` | all 10 emotions, `test/golden/goldens/*.png` (generated on Linux) | PASSED |
| Integration | `integration_test/app_flow_test.dart` | home face → chat (offline label, local command) → music → settings on a real device | **NOT RUN** (no device or emulator). Statically analysed only. CI runs it on an API 34 emulator |
| Backend | `backend/test/*.test.ts` | 53 tests: schema, chat loop (retry once, citation id filtering, verification levels, weather, step limit), auth tokens, config, fetch retry, Brave and Open-Meteo parsing, SSML escaping, HTTP routes (health, 401, SSE, 503, 400/413, 429, CORS) with mocked providers | PASSED |

Commands: `flutter analyze`, `flutter test`, `flutter test integration_test` (device needed), `cd backend && npm ci && npm run lint && npm test`.

## 2. Manual device checklist

Status values: PASSED / FAILED / NOT RUN, with date and device. **Nothing has been run on a device yet**, because no device or emulator was available in the build environment.

| # | Scenario | Expected | Status | Date / device |
|---|---|---|---|---|
| 1 | First launch, mic permission **granted** (tap face → rationale → allow) | listening ring, partial text appears | NOT RUN | |
| 2 | Mic permission **denied** once | friendly message, typed input focused, can retry | NOT RUN | |
| 3 | Mic permission **permanently denied** | "open settings" action opens the app's system settings | NOT RUN | |
| 4 | Device STT in Darija (ar-MA), French, English | recognised text reaches chat. Note the recognition *quality* for Darija | NOT RUN | |
| 5 | Phone without any recogniser | falls back to typed input with a visible reason | NOT RUN | |
| 6 | Device TTS ar / fr / en; Arabic voice missing | speaks, or shows "voice not installed" with a link to TTS settings | NOT RUN | |
| 7 | Cloud STT and TTS via the backend (Azure ar-MA) | works; when the backend is stopped, falls back to the device | NOT RUN | |
| 8 | Stop / interrupt while speaking ("wqef", stop button, new message) | speech stops at once and does not restart | NOT RUN | |
| 9 | Mouth movement while speaking | moves roughly with speech (approximate, not lip-sync) | NOT RUN | |
| 10 | Pick audio files and a folder (SAF), play, pause, next, notification controls, lock screen | works; no storage permission requested | NOT RUN | |
| 11 | Bluetooth speaker connected | active output shows its name; output switcher opens (API 34+: system switcher; 30–33: media panel, best-effort; older: Bluetooth settings) | NOT RUN | |
| 12 | Audio focus: incoming call, another music app, a navigation prompt | pauses or ducks and resumes correctly; Sahbi ducks its own music while speaking | NOT RUN | |
| 13 | Spotify / YouTube Music deep link, installed and not installed | opens the app or the web, or reports "not installed" | NOT RUN | |
| 14 | Airplane mode | offline banner, face and commands work, AI replies labelled offline | NOT RUN | |
| 15 | Backend reachable but no LLM key | "AI not configured" state, no fake replies | NOT RUN | |
| 16 | Web search question ("chno akhbar lyoum?") with a Brave key | answer with source chips; verification badge | NOT RUN | |
| 17 | Weather ("ch7al l7arara f Fes?") | real Open-Meteo data, "data" source chip | NOT RUN | |
| 18 | Memory: consent screen, "3qel 3la …", view, edit, delete, export JSON | works; nothing stored before consent | NOT RUN | |
| 19 | RTL: Arabic UI on a real device, long Arabic text, mixed Arabizi | mirrored layout, no clipped text | NOT RUN | |
| 20 | Low-end phone (2–3 GB RAM, Android 8) | face animation smooth enough, no jank in chat | NOT RUN | |
| 21 | Landscape desk mode | big face plus side controls | NOT RUN | |
| 22 | Settings → Debug: simulated robot connect, commands, motor watchdog | log shows acks; motor stops within 0.5 s | NOT RUN | |
| 23 | Android 13+ notification permission for media controls | asked when playback starts; playback works if denied | NOT RUN | |
