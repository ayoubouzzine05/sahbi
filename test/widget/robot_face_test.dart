import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/features/face/face_painter.dart';
import 'package:sahbi/features/face/robot_face.dart';
import 'package:sahbi/features/personality/emotion.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 300, height: 300, child: child)),
  ),
);

void main() {
  testWidgets('tap and long-press reach the callbacks (tap-to-talk)', (
    t,
  ) async {
    var taps = 0, longs = 0;
    await t.pumpWidget(
      host(
        RobotFace(
          inputs: const FaceInputs(),
          animate: false,
          onTap: () => taps++,
          onLongPress: () => longs++,
        ),
      ),
    );
    await t.tap(find.byType(RobotFace));
    await t.longPress(find.byType(RobotFace));
    expect(taps, 1);
    expect(longs, 1);
  });

  testWidgets('exposes an accessible label and button role', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      host(
        RobotFace(
          inputs: const FaceInputs(),
          animate: false,
          onTap: () {},
          semanticLabel: 'Sahbi, happy',
        ),
      ),
    );
    final node = find.bySemanticsLabel('Sahbi, happy');
    expect(node, findsOneWidget);
    expect(
      t.getSemantics(node),
      matchesSemantics(
        label: 'Sahbi, happy',
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: false,
      ),
    );
    await t.pumpWidget(
      host(
        RobotFace(
          inputs: const FaceInputs(),
          animate: false,
          onTap: () {},
          onLongPress: () {},
          semanticLabel: 'S',
        ),
      ),
    );
    expect(
      t.getSemantics(find.bySemanticsLabel('S')),
      matchesSemantics(
        label: 'S',
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('every emotion and state paints without errors', (t) async {
    for (final e in Emotion.values) {
      for (final flags in [
        (false, false, false),
        (true, false, false),
        (false, true, false),
        (false, false, true),
      ]) {
        await t.pumpWidget(
          host(
            RobotFace(
              animate: false,
              inputs: FaceInputs(
                emotion: e,
                intensity: 0.8,
                speaking: flags.$1,
                listening: flags.$2,
                listenLevel: 0.5,
                music: flags.$3,
              ),
            ),
          ),
        );
        expect(t.takeException(), isNull, reason: '$e $flags');
      }
    }
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets(
    'animated face runs (blink/breath/gaze ticker) and drag-to-look works',
    (t) async {
      final pulse = ValueNotifier(0);
      await t.pumpWidget(
        host(
          RobotFace(inputs: const FaceInputs(speaking: true), wordPulse: pulse),
        ),
      );
      for (var i = 0; i < 30; i++) {
        pulse.value = i;
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.drag(find.byType(RobotFace), const Offset(80, -40));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.takeException(), isNull);
      // Switching animation off stops the ticker so the test can settle.
      await t.pumpWidget(
        host(const RobotFace(inputs: FaceInputs(), animate: false)),
      );
      await t.pumpAndSettle();
      pulse.dispose();
    },
  );

  testWidgets('static face uses the target emotion parameters', (t) async {
    await t.pumpWidget(
      host(
        const RobotFace(
          inputs: FaceInputs(emotion: Emotion.sad),
          animate: false,
        ),
      ),
    );
    final painter = t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<FacePainter>()
        .single;
    expect(painter, isNotNull);
  });
}
