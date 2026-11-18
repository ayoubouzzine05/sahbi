# Dependencies

All versions were added with `flutter pub add` / `npm install`, and are the resolved versions from `pubspec.lock` and `backend/package-lock.json` on 2026-11-16. Licences were read from each package's LICENSE file in the local pub cache or `node_modules`.

## Flutter app (runtime)

| Package | Version | Licence | Why |
|---|---|---|---|
| flutter, flutter_localizations | SDK 3.50.0 | BSD-3-Clause | framework, l10n delegates |
| material_ui | 1.11.1 | BSD-3-Clause | Material widgets (the decoupled successor of `package:flutter/material.dart` in Flutter 3.50) |
| flutter_riverpod | 3.5.0 | MIT | state management |
| go_router | 18.1.4 | BSD-3-Clause | navigation (StatefulShellRoute) |
| intl | 0.20.3 | BSD-3-Clause | ARB localisation, dates |
| http | 1.6.0 | BSD-3-Clause | backend client, SSE streaming |
| speech_to_text | 7.5.0 | BSD-3-Clause | on-device STT (Android SpeechRecognizer) |
| flutter_tts | 4.2.5 | MIT | on-device TTS |
| record | 7.2.0 | BSD-3-Clause | mic capture for cloud STT |
| permission_handler | 13.0.2 | MIT | mic/notification permission flow |
| just_audio | 0.10.6 | Apache-2.0 | local playback |
| audio_service | 0.18.19 | MIT | media session, notification, mediaPlayback foreground service |
| audio_session | 0.2.4 | MIT | audio focus, ducking, interruptions |
| url_launcher | 6.3.3 | BSD-3-Clause | Spotify / YouTube Music deep links, source links |
| connectivity_plus | 7.3.2 | BSD-3-Clause | network change events (reachability is checked separately via `/v1/health`) |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | install token, memory encryption key (Android Keystore-backed) |
| shared_preferences | 2.5.6 | BSD-3-Clause | settings, music library index |
| cryptography | 2.9.0 | Apache-2.0 | AES-256-GCM for the memory store |
| path_provider | 2.1.6 | BSD-3-Clause | app documents dir for the encrypted memory blob |
| camera | 0.12.2 | BSD-3-Clause | live camera mode: preview + ~1 JPEG/s sent to Gemini Live |
| web_socket_channel | 3.0.3 | BSD-3-Clause | Gemini Live WebSocket (ephemeral token, BidiGenerateContentConstrained) |
| flutter_pcm_sound | 3.3.3 | Unlicense (public domain) | plays the 24 kHz PCM voice that Gemini Live streams back |
| wakelock_plus | 1.8.2 | BSD-3-Clause | keeps the screen on while the face dashboard / live camera is visible |

## Flutter app (dev)

| Package | Version | Licence |
|---|---|---|
| flutter_test, integration_test | SDK | BSD-3-Clause |
| flutter_lints | 6.0.0 | BSD-3-Clause |
| stream_channel | 2.1.4 | BSD-3-Clause | fake WebSocket in LiveSession tests |

## Deliberately not used

- **Drift + SQLCipher.** The spec suggested them for memory. I used a single AES-256-GCM-encrypted JSON blob instead (key in flutter_secure_storage), because the data is small (≤ 30 facts sent to the AI, ≤ 200 history items) and it avoids a native SQLCipher build. See FEATURES.md.
- **BLE plugin** (flutter_blue_plus etc.). There is no hardware yet. `BleTransport` takes a `BleLink` adapter instead.
- **Spotify App Remote SDK.** Not bundled. It requires a Spotify developer app and the proprietary SDK AAR. Deep links are used instead.

## Backend (`backend/`)

| Package | Version | Licence | Kind |
|---|---|---|---|
| fastify | 5.12.8 | MIT | runtime |
| @fastify/cors | 11.4.3 | MIT | runtime |
| @fastify/rate-limit | 11.2.2 | MIT | runtime |
| zod | 4.6.7 | MIT | runtime (reply schema validation) |
| typescript | 6.0.3 | Apache-2.0 | dev |
| eslint, @eslint/js, typescript-eslint | 10.15.0 / 10.0.1 / 8.73.0 | MIT | dev |
| vitest | 4.1.12 | MIT | dev |
| tsx | 4.23.15 | MIT | dev |
| @types/node | 26.6.6 | MIT | dev |

The LLM, search, STT and TTS providers are called over plain HTTPS with `fetch` (Node ≥ 20). No vendor SDKs are used.
