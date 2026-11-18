@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/core/theme.dart';
import 'package:sahbi/features/face/robot_face.dart';
import 'package:sahbi/features/personality/emotion.dart';

/// Goldens are rendered by the Flutter test engine (Ahem font, software
/// rasteriser). Generated on Linux; regenerate with
///   flutter test --update-goldens test/golden
/// when the face design changes intentionally.
void main() {
  for (final e in Emotion.values) {
    testWidgets('face ${e.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(240, 240));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: SahbiColors.background,
            child: RobotFace(
              animate: false,
              inputs: FaceInputs(emotion: e, intensity: 1),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(RobotFace),
        matchesGoldenFile('goldens/face_${e.name}.png'),
      );
    });
  }

  // Dashboard mode: only eyes, brows and mouth over the whole screen.
  for (final e in [Emotion.neutral, Emotion.happy, Emotion.sad]) {
    testWidgets('full-screen face ${e.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(200, 400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RobotFace(
            animate: false,
            fullScreen: true,
            inputs: FaceInputs(emotion: e, intensity: 1),
          ),
        ),
      );
      await expectLater(
        find.byType(RobotFace),
        matchesGoldenFile('goldens/face_full_${e.name}.png'),
      );
    });
  }
}
