import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/features/face/face_painter.dart';
import 'package:sahbi/features/personality/emotion_animation_mapper.dart';
import 'package:sahbi/features/personality/emotion.dart';
import 'package:sahbi/features/personality/personality_responses.dart';
import 'package:sahbi/features/personality/shake.dart';

/// Feeds [seconds] of 50 Hz samples: gravity on z plus [motion](t) on x.
int shakes(
  ShakeDetector d,
  double seconds,
  double Function(double t) motion, {
  double start = 0,
}) {
  var n = 0;
  for (var i = 0; i < seconds * 50; i++) {
    final t = start + i / 50;
    if (d.add(
      motion(t),
      0.3,
      9.81,
      Duration(microseconds: (t * 1e6).round()),
    )) {
      n++;
    }
  }
  return n;
}

void main() {
  group('ShakeDetector', () {
    test('a phone lying still or walking around never shakes', () {
      expect(shakes(ShakeDetector(), 5, (_) => 0), 0);
      expect(
        shakes(ShakeDetector(), 10, (t) => 3.5 * math.sin(2 * math.pi * 2 * t)),
        0,
      );
    });

    test('one bump (phone put down hard) is not a shake', () {
      expect(
        shakes(ShakeDetector(), 3, (t) => (t > 1 && t < 1.06) ? 25 : 0),
        0,
      );
    });

    test('a real shake (4 Hz, strong) is detected within a second', () {
      final d = ShakeDetector();
      expect(shakes(d, 1, (t) => 20 * math.sin(2 * math.pi * 4 * t)), 1);
    });

    test('long shaking fires at most once per cooldown', () {
      final n = shakes(
        ShakeDetector(),
        4.5,
        (t) => 22 * math.sin(2 * math.pi * 4 * t),
      );
      expect(n, inInclusiveRange(2, 3));
    });
  });

  group('ShakeMood', () {
    late DateTime now;
    ShakeMood mood() => ShakeMood(clock: () => now, random: math.Random(1));
    setUp(() => now = DateTime(2026, 11, 21, 12));

    test('dizzy → annoyed → angry, then stays angry', () {
      final m = mood();
      final r1 = m.onShake();
      expect(r1.level, 1);
      expect(r1.line.emotion, Emotion.surprised);
      expect(ShakeLines.dizzy, contains(r1.line));
      now = now.add(const Duration(seconds: 5));
      final r2 = m.onShake();
      expect(r2.level, 2);
      expect(r2.line.emotion, Emotion.angry);
      now = now.add(const Duration(seconds: 5));
      expect(m.onShake().level, 3);
      now = now.add(const Duration(seconds: 5));
      final r4 = m.onShake();
      expect(r4.level, 3);
      expect(r4.line.intensity, 1);
      expect(r4.dizzyFor < r1.dizzyFor, isTrue);
    });

    test('calms down after 30 s without shaking', () {
      final m = mood()..onShake();
      now = now.add(const Duration(seconds: 5));
      m.onShake();
      now = now.add(const Duration(seconds: 31));
      expect(m.onShake().level, 1);
    });

    test('shaken awake: grumpy wake-up line, then escalates', () {
      final m = mood();
      final r = m.onShake(asleep: true);
      expect(r.woken, isTrue);
      expect(ShakeLines.woken, contains(r.line));
      now = now.add(const Duration(seconds: 3));
      expect(m.onShake().level, 2);
    });

    test('never the same line twice in a row', () {
      final m = mood();
      Line? last;
      for (var i = 0; i < 30; i++) {
        now = now.add(const Duration(seconds: 40)); // always level 1
        final l = m.onShake().line;
        expect(l, isNot(same(last)));
        last = l;
      }
    });

    test('every line has all languages filled', () {
      for (final l in [
        ...ShakeLines.levels.expand((x) => x),
        ...ShakeLines.woken,
      ]) {
        for (final s in [l.darijaAr, l.darijaLatin, l.msa, l.fr, l.en]) {
          expect(s.trim(), isNotEmpty);
        }
      }
    });
  });

  group('ShakeWatcher', () {
    test('reacts once per shake, only when enabled and active', () async {
      final ctrl = StreamController<(double, double, double)>.broadcast();
      var enabled = false;
      var calls = 0;
      final done = Completer<void>();
      final w = ShakeWatcher(
        events: () => ctrl.stream,
        enabled: () => enabled,
        onShake: () async {
          calls++;
          await done.future;
        },
        detector: _AlwaysShake(),
      );
      ctrl.add((0, 0, 9.8));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0, reason: 'not active yet');
      w.setActive(true);
      ctrl.add((0, 0, 9.8));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0, reason: 'disabled (setting off / live camera)');
      enabled = true;
      ctrl
        ..add((0, 0, 9.8))
        ..add((0, 0, 9.8));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: 'no new reaction while still reacting');
      done.complete();
      await Future<void>.delayed(Duration.zero);
      ctrl.add((0, 0, 9.8));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      w.setActive(false);
      expect(w.active, isFalse);
      ctrl.add((0, 0, 9.8));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      await ctrl.close();
    });

    test('a missing accelerometer just stays silent', () async {
      final w = ShakeWatcher(
        events: () => Stream.error(Exception('no sensor')),
        enabled: () => true,
        onShake: () async {},
      )..setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(w.active, isFalse);
    });
  });

  testWidgets('dizzy face paints spiral eyes without errors', (tester) async {
    for (final full in [false, true]) {
      await tester.pumpWidget(
        CustomPaint(
          size: const Size(300, 300),
          painter: FacePainter(
            FaceFrame(
              params: const EmotionAnimationMapper()
                  .map(Emotion.angry, 1)
                  .params,
              time: 1.3,
              dizzy: 0.8,
              fullScreen: full,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

class _AlwaysShake extends ShakeDetector {
  @override
  bool add(double x, double y, double z, Duration t) => true;
}
