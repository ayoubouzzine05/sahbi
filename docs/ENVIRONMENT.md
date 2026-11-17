# Build environment (inspected, 2026-11-16)

Everything below was observed with real commands in the build sandbox. Nothing is assumed.

## Initial state (before setup)

| Check | Result |
|---|---|
| OS | Debian GNU/Linux 13 (trixie), kernel 6.1, x86_64 |
| CPU / RAM / swap | 2 vCPU, **1982 MB RAM, no swap** |
| Disk | 25 GB root |
| `flutter --version` / `dart --version` | **not installed** |
| `java -version` | OpenJDK **11**. Too old: Android Gradle Plugin needs JDK 17+ |
| `ANDROID_HOME` / `sdkmanager` | **not set / not installed** |
| `adb devices` | **adb not installed. No device or emulator** (no KVM, no GPU) |
| Node / npm | v20.20.2 / 10.8.2 |
| Network | works (pub.dev, npm, dl.google.com, Open-Meteo geocoding reachable) |

## Toolchain installed for this build

Everything was installed under `~/.cache/sdk`, which is **not persistent** in this sandbox. It was lost once during the work and Flutter was reinstalled.

| Tool | Version | Source |
|---|---|---|
| Flutter | 3.50.0 stable (framework ab2912035e, 2026-11-09) | storage.googleapis.com flutter_infra_release |
| Dart | 3.14.0 | bundled with Flutter |
| JDK | Temurin 17.0.21+9 | adoptium |
| Android cmdline-tools | `commandlinetools-linux-15859902_latest` | dl.google.com |
| Android SDK | platform-tools 37.0.1, platforms android-36 (plus 35 and 37.0 auto-installed by Gradle), build-tools 36.0.0, NDK 28.2.13676358 | sdkmanager |
| Gradle / AGP | Gradle 9.5.0 wrapper, AGP 9.3.1 (Flutter template defaults) | |

`/home/user/sahbi_env.sh` exports `JAVA_HOME`, `ANDROID_HOME`, `PUB_CACHE`, `GRADLE_USER_HOME` and `PATH` for these tools.

## Consequences

- **No device or emulator**: nothing was run on Android. All device behaviour (STT, TTS, audio routing, permissions, notifications) is **NOT VERIFIED**. See TEST_PLAN.md.
- **The APK build could not complete in 2 GB RAM.** Five attempts were made (details in STATUS.md):
  - The Gradle daemon and the Dart `frontend_server` kernel compiler (about 1.3 GB RSS by itself) do not fit together.
  - The build either OOM-froze the sandbox or was stopped by a memory watchdog.
  - The attempts did find and fix one real error: `permission_handler_android` requires `compileSdk = 37`.
- Low-memory Gradle settings were used **only** in the sandbox's `$GRADLE_USER_HOME/gradle.properties`. The project's `android/gradle.properties` keeps Flutter's normal defaults (`-Xmx8G`) for CI and dev machines.
- No Docker in the sandbox, so `backend/Dockerfile` was not built.
- `api.open-meteo.com` (forecast host) timed out from the sandbox, while `geocoding-api.open-meteo.com` answered 200. Live weather is NOT VERIFIED here. The weather code is covered by tests with mocked HTTP.

## Recommended environment to finish verification

Any machine with ≥ 8 GB RAM, Flutter stable ≥ 3.50, JDK 17, Android SDK 36 and 37, plus a physical Android 8+ phone (ideally one with Arabic (Morocco) speech recognition installed) or an x86_64 emulator with KVM. The GitHub Actions workflow in `.github/workflows/android.yml` (ubuntu-latest, 16 GB) is set up to build both APKs and run the integration test on an emulator.


## CI environment (GitHub Actions, verified 2026-11-17)

- `ubuntu-latest`, Temurin **JDK 21** (AGP lint needs it), Flutter stable via subosito/flutter-action.
- Run 44157728254: format, analyze, tests, debug, release and arm64 APKs, `latest` release, and integration test on an API 34 emulator. All green.
