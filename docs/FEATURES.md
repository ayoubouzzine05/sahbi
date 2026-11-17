# Features

Legend:
- **Implemented**: code complete and covered by automated tests that ran in this environment.
- **Implemented, device-unverified**: code complete, but it depends on Android or real services that could not be run here (no device or emulator, no API keys).
- **Partial** / **Not implemented**: as stated.

Nothing in this file has been checked on a real phone (see STATUS.md). The integration test passes on an emulator.

## Face and personality

| Feature | State |
|---|---|
| CustomPainter robot face: white rounded body, dark visor, eyes, lids, pupils, brows, mouth, cheeks | Implemented (golden tests for 6 emotions) |
| 10 interpolated emotions (neutral, happy, sad, curious, surprised, sleepy, angry, listening, speaking, music) | Implemented |
| Blinking, breathing, idle gaze, touch/drag-to-look, tap to talk, long-press | Implemented (widget tests) |
| Idle behaviours (sleepy after inactivity, random glances, surprise) | Implemented, toggle in Settings |
| Mouth sync | **Approximate.** It follows TTS word-boundary callbacks when the engine provides them, otherwise a synthetic syllable envelope. **Not true lip-sync** |
| Procedural zellige/khatem patterns (background, cards, loader) | Implemented. Original, drawn in code |
| Personality engine modules: EmotionDetector, EmotionAnimationMapper, ConversationContext, PersonalityResponses, VoiceState machine, IdleBehavior, MusicState | Implemented with unit tests |
| Landscape "desk mode" (big face plus side controls) | Implemented, device-unverified |

## Language

| Feature | State |
|---|---|
| UI in Arabic (default, RTL), French, English via ARB (211 keys) | Implemented. Every screen renders in all 3 locales in widget tests |
| Reply language: Darija, MSA, French, English. Darija in Arabic script or Arabizi | Implemented (setting, sent to the LLM prompt) |
| Arabizi normalisation (3=ع, 7=ح, 9=ق, 5/kh=خ, 2=ء), code-switching | Implemented in the local parser (68 phrase cases) |
| `tts_text` always in Arabic script for Darija/ar | Enforced by the backend schema and prompt. The app speaks `tts_text` (tested) |
| Darija **recognition quality** | **Not verified.** It depends on the device recogniser or Azure ar-MA |

## Voice

| Feature | State |
|---|---|
| On-device STT (Android SpeechRecognizer via speech_to_text) | Implemented, device-unverified |
| Cloud STT through the backend (`record` → `/v1/stt`, Azure ar-MA or OpenAI) | Implemented, device-unverified; backend route tested with mocks |
| On-device TTS (flutter_tts) and cloud TTS (Azure ar-MA-JamalNeural / MounaNeural) | Implemented, device-unverified |
| Fallback order cloud → device → typed, per-mode settings, sticky failure | Implemented (unit tests) |
| Push-to-talk, tap face, "Sme3 lia", stop / interrupt / barge-in | Implemented. Stop cancels both speech and a pending AI request (tested) |
| Mic permission rationale, denied and permanently-denied handling | Implemented, device-unverified |
| Music ducking while Sahbi speaks | Implemented (tested with a fake engine) |
| Foreground wake phrase | **Not implemented.** No wake-word engine is bundled. The toggle is disabled and shows the reason |

## AI brain, search, tools

| Feature | State |
|---|---|
| Backend `/v1/chat` over SSE, Anthropic or OpenAI adapter, model from env | Implemented; tested with a scripted LLM. **No real LLM call made** (no key) |
| Strict reply schema `{display_text, tts_text, language, emotion, intensity, actions[]}`, validated, one retry | Implemented (backend tests) |
| Actions executed locally with **real** results shown (music, volume, language) | Implemented (tests: failures reported as failures) |
| Web search (Brave) with numbered, id-checked citations and confirmed/unconfirmed badge; source chips | Implemented. Backend and UI tested. **No live Brave call made** |
| Tavily / SerpAPI | Not implemented (Brave only) |
| Weather via Open-Meteo (`get_weather` tool, `/v1/weather`) | Implemented and tested with mocks. Live forecast host unreachable from the sandbox |
| Translate (structured action → translation card) | Implemented |
| Long conversations: rolling context plus server-side summarise | Implemented |
| Anonymous install token, rate limit, body limits, CORS, no message bodies in logs | Implemented (backend tests) |
| Local command parser (offline): music, volume, stop, listen, language, script, open screens, remember | Implemented (68 phrase cases) |

## Music

| Feature | State |
|---|---|
| Local files and folders via Storage Access Framework (no storage permission) | Implemented, device-unverified (Kotlin channel not compiled here) |
| Playback with just_audio plus audio_service (notification, lock screen, mediaPlayback foreground service) | Implemented, device-unverified |
| CC0 demo tracks (generated, see ASSETS_LICENSES.md) | Implemented (asset test) |
| Show active output (speaker, wired, Bluetooth name) | Implemented, device-unverified |
| Open the system output switcher | Implemented, device-unverified:<br>• API 34+: MediaRouter2 `showSystemOutputSwitcher()`<br>• API 30–33: SystemUI media-output broadcast. **Non-public and best-effort**; the app can't confirm it opened<br>• Older: Bluetooth settings |
| System media volume control | Implemented, device-unverified |
| Spotify / YouTube Music deep links | Implemented, device-unverified |
| Spotify App Remote (full external playback control) | **Not implemented.** Proprietary SDK not bundled; flag off. SAHBI does **not** control other apps' playback beyond deep links and system volume |

## Memory and privacy

| Feature | State |
|---|---|
| Consent screen (facts and history separately); nothing stored without consent | Implemented (tests) |
| Encrypted local storage | Implemented as an **AES-256-GCM encrypted blob** with the key in flutter_secure_storage (Keystore). **Deviation:** not Drift + SQLCipher; see DEPENDENCIES.md for why |
| View, edit, delete, delete all (rotates key), export JSON (SAF save dialog) | Implemented (store tests); export UI device-unverified |
| Facts sent to the AI only with consent | Implemented (tested) |
| Privacy settings (send to AI on/off, cloud voice on/off) | Implemented |

## Offline mode

| Feature | State |
|---|---|
| connectivity_plus plus a real `/v1/health` reachability check drive the banner | Implemented |
| Offline replies labelled offline, with a reason (AI off, no backend URL, no internet, server unreachable, AI not configured) | Implemented (unit and widget tests) |
| Face, idle, commands, settings, memory and local music work offline | Implemented |

## Robot link

| Feature | State |
|---|---|
| `RobotTransport` interface, LocalPhoneTransport, SimulatedRobotTransport (debug screen) | Implemented (tests) |
| Protocol v1: codec, safety limits, BLE framing, CRC, handshake, watchdog | Implemented (tests). See ROBOT_PROTOCOL.md |
| BleTransport / WifiTransport | Skeletons behind the "Robot (experimental)" flag. **No hardware exists; no BLE plugin** |

## Interfaces (swappable, mockable)

| Spec interface | Where |
|---|---|
| `LlmProvider` | `backend/src/providers/llm/types.ts` (anthropic, openai, scripted for tests) |
| `SearchProvider` | `backend/src/providers/search/types.ts` (brave). The app renders results in `lib/features/search` |
| `SttProvider` / `TtsProvider` | app: `lib/features/voice/voice_types.dart` (device and cloud); backend: `providers/stt`, `providers/tts` |
| `MusicProvider` | app: `MusicEngine` in `lib/features/music/music_models.dart` (audio_service handler; fake in tests) plus `StreamingLinks` |
| `RobotTransport` | `lib/features/robot_link/robot_transport.dart` |

## Known limitations

- Nothing is verified on a real phone. APKs are built in GitHub Actions and the integration test passes on an emulator, so the Kotlin channel compiles, but its behaviour on hardware is untested.
- The launcher icon is still the Flutter default and must be replaced before release.
- Debug builds allow cleartext HTTP so the emulator can reach `http://10.0.2.2:8080`. Release builds require HTTPS.
- Goldens were rendered on Linux and may differ slightly on other host OSes; regenerate with `--update-goldens`.
