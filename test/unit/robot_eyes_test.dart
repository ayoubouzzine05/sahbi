import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/face/face_act.dart';
import 'package:sahbi/features/live/scene_watcher.dart';
import 'package:sahbi/features/vision/robot_eyes.dart';

SceneSignature sig({int? blobX, int blobY = 6, int base = 60}) {
  final s = Uint8List(sceneSigW * sceneSigH)
    ..fillRange(0, sceneSigW * sceneSigH, base);
  if (blobX != null) {
    for (var y = blobY - 1; y <= blobY + 1; y++) {
      for (var x = blobX - 1; x <= blobX + 1; x++) {
        s[y * sceneSigW + x] = 220;
      }
    }
  }
  return s;
}

/// A PNG frame: grey, with an optional white square ([x] 0..1).
Future<Uint8List> frame({double? x, int shade = 90}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
    const Rect.fromLTWH(0, 0, 160, 120),
    Paint()..color = Color.fromARGB(255, shade, shade, shade),
  );
  if (x != null) {
    c.drawRect(
      Rect.fromLTWH(x * 160 - 20, 40, 40, 40),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }
  final img = await rec.endRecording().toImage(160, 120);
  final b = await img.toByteData(format: ui.ImageByteFormat.png);
  return b!.buffer.asUint8List();
}

class FakeCam implements EyeCamera {
  FakeCam(this.frames);
  final List<Uint8List> frames;
  int i = 0, opens = 0, closes = 0;
  bool canOpen = true;
  @override
  Future<bool> open() async {
    opens++;
    return canOpen;
  }

  @override
  Future<Uint8List?> grab() async => frames[i++ % frames.length];
  @override
  Future<void> close() async => closes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('motionGaze', () {
    test(
      'a hand on the user\'s right (image left) → robot looks to screen right',
      () {
        final g = motionGaze(sig(), sig(blobX: 2))!;
        expect(g.dx, greaterThan(0.5));
        final h = motionGaze(sig(), sig(blobX: 13))!;
        expect(h.dx, lessThan(-0.5));
      },
    );

    test('up/down follows too', () {
      expect(motionGaze(sig(), sig(blobX: 8, blobY: 1))!.dy, lessThan(0));
      expect(motionGaze(sig(), sig(blobX: 8, blobY: 10))!.dy, greaterThan(0));
    });

    test('no motion, a light change or the whole phone moving → nothing', () {
      expect(motionGaze(sig(), sig()), isNull);
      expect(motionGaze(sig(), sig(base: 140)), isNull, reason: 'exposure');
      final noisy = Uint8List.fromList([
        for (var i = 0; i < 192; i++) i.isEven ? 10 : 250,
      ]);
      expect(motionGaze(sig(), noisy), isNull, reason: 'everything changed');
    });
  });

  test('reactions map to face skits', () {
    expect(reactionAct('scared'), FaceAct.scared);
    expect(reactionAct('hello'), FaceAct.handsUp);
    expect(reactionAct('love'), FaceAct.love);
    expect(reactionAct('yummy'), FaceAct.eat);
    expect(reactionAct('drink'), FaceAct.drink);
    expect(reactionAct('wow'), FaceAct.sparkle);
    expect(reactionAct('funny'), isNull);
    expect(reactionAct(null), isNull);
  });

  group('RobotEyes', () {
    late DateTime now;
    setUp(() => now = DateTime(2026, 11, 16, 12));

    RobotEyes make(
      FakeCam cam, {
      bool Function()? busy,
      List<Offset>? gazes,
      List<Uint8List>? reacts,
      int limit = 150,
    }) => RobotEyes(
      camera: cam,
      clock: () => now,
      busy: busy ?? () => false,
      onGaze: (g) => gazes?.add(g),
      onReact: (j) async => reacts?.add(j),
      interval: const Duration(days: 1), // ticks driven by the test
      dailyLimit: limit,
    );

    test('opens only when wanted and closes when the face is hidden', () async {
      final cam = FakeCam([await frame()]);
      final e = make(cam);
      e.setFaceWants(true);
      await Future<void>.delayed(Duration.zero);
      expect(e.active, isTrue);
      e.setForeground(false);
      await Future<void>.delayed(Duration.zero);
      expect(e.active, isFalse);
      expect(cam.closes, 1);
      e.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(e.active, isTrue);
      e.setFaceWants(false);
      await Future<void>.delayed(Duration.zero);
      expect(e.active, isFalse);
      e.dispose();
    });

    test(
      'eyes follow movement; a new thing held still → one reaction',
      () async {
        final empty = await frame();
        final shown = await frame(x: 0.2);
        final cam = FakeCam([empty, shown, shown, shown, shown, shown]);
        final gazes = <Offset>[], reacts = <Uint8List>[];
        final e = make(cam, gazes: gazes, reacts: reacts);
        await e.setWanted(true);
        for (var k = 0; k < 6; k++) {
          now = now.add(const Duration(seconds: 1));
          await e.tick();
        }
        expect(gazes, isNotEmpty);
        expect(gazes.first.dx, greaterThan(0));
        expect(reacts, hasLength(1));
        expect(e.latestFrame(), isNotNull);
        now = now.add(const Duration(seconds: 10));
        expect(e.latestFrame(), isNull, reason: 'old frames are not used');
        e.dispose();
      },
    );

    test(
      'no reaction while the robot is busy, or past the daily limit',
      () async {
        final a = await frame(), b = await frame(x: 0.7);
        final reacts = <Uint8List>[];
        var busy = true;
        final e = make(
          FakeCam([a, b, b, b, b]),
          busy: () => busy,
          reacts: reacts,
          limit: 1,
        );
        await e.setWanted(true);
        for (var k = 0; k < 5; k++) {
          now = now.add(const Duration(seconds: 1));
          await e.tick();
        }
        expect(reacts, isEmpty);
        e.dispose();
      },
    );

    test('camera that cannot open: not active, marked failed', () async {
      final cam = FakeCam([await frame()])..canOpen = false;
      final e = make(cam);
      await e.setWanted(true);
      expect(e.active, isFalse);
      expect(e.failed, isTrue);
      e.dispose();
    });
  });
}
