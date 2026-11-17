# Assets and licences

All visual design in SAHBI is original: the robot face, the body shape, the colours, and the procedural zellige/khatem patterns, which are drawn in code by `lib/core/zellige.dart` and `lib/features/face/face_painter.dart`. **No image, sound, character, logo or code from LivingAI/AIBI or any other product is used.** AIBI Pocket was a conceptual inspiration only (phone-sized companion with an expressive face).

| Asset | Path | Author | Licence |
|---|---|---|---|
| Tajawal Regular / Medium / Bold | `assets/fonts/Tajawal-*.ttf` | Boutros International (2018) | SIL Open Font License 1.1, full text in `assets/fonts/OFL-Tajawal.txt`. Source: github.com/google/fonts `ofl/tajawal` |
| "Atlas Breeze (demo)" | `assets/audio/sahbi_demo_atlas_breeze.wav` | Generated for this project by `tool/gen_demo_audio.py` (numpy synthesis, no samples) | CC0 1.0 (public domain dedication) |
| "Medina Steps (demo)" | `assets/audio/sahbi_demo_medina_steps.wav` | Generated for this project by `tool/gen_demo_audio.py` | CC0 1.0 |
| Robot face, zellige patterns, app UI | code (CustomPainter) | SAHBI project | same as project source |
| Launcher icon | `android/app/src/main/res/mipmap-*` | Flutter template default | BSD-3-Clause (Flutter). **Replace with an original SAHBI icon before release** |

No copyrighted music is bundled. Users' own files are opened through Android's Storage Access Framework and are never copied off the device.

Third-party code dependencies and their licences are listed in `docs/DEPENDENCIES.md`.
