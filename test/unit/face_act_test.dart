import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/face/robot_face.dart';
import 'package:sahbi/features/brain/command_parser.dart';
import 'package:sahbi/features/face/face_act.dart';
import 'package:sahbi/features/personality/companion_controller.dart';
import 'package:sahbi/features/personality/emotion.dart';
import 'package:sahbi/features/personality/emotion_animation_mapper.dart';
import 'package:sahbi/features/personality/emotion_detector.dart';
import 'package:sahbi/features/personality/face_act_lines.dart';
import 'package:sahbi/features/personality/idle_behavior.dart';

void main() {
  const parser = CommandParser();
  String? act(String s) {
    final c = parser.parse(s);
    return c?.type == CommandType.faceAct ? c!.query : null;
  }

  group('voice commands → face skits', () {
    test('hands up in Darija (both scripts), French, English', () {
      for (final s in [
        'haz ydik',
        'hezz yeddik',
        'a sahbi hez ydik 3afak',
        'هز يديك',
        'ارفع يديك',
        'lève les mains',
        'hands up',
        'raise your hands',
      ]) {
        expect(act(s), 'hands_up', reason: s);
      }
    });

    test('eat / drink / peekaboo / love / dance / yawn', () {
      final cases = {
        'kol': 'eat',
        'kol chi haja': 'eat',
        'wach nta ji3an?': 'eat',
        'كول': 'eat',
        'mange': 'eat',
        'chrob atay': 'drink',
        'ochrob chi atay': 'drink',
        'اشرب أتاي': 'drink',
        'wach 3tchan': 'drink',
        'drink some water': 'drink',
        'ghmed 3inik': 'peekaboo',
        'غمض عينيك': 'peekaboo',
        'peekaboo': 'peekaboo',
        'kanbghik': 'love',
        'ana kanbghik bzaf': 'love',
        'كنبغيك': 'love',
        'je t\'aime': 'love',
        'chte7': 'dance',
        'yallah chte7 m3aya': 'dance',
        'شطح': 'dance',
        'wach na3s?': 'yawn',
        'are you tired': 'yawn',
      };
      cases.forEach((s, want) => expect(act(s), want, reason: s));
    });

    test('ordinary sentences are not skits', () {
      for (final s in [
        'kol nhar kanmchi lkhedma',
        'chno kla lyoum',
        'chouf hadi',
        'ch3el lmusic',
        'kifach ndir atay',
        'bghit nchrb atay m3a sahbi f lkhedma',
      ]) {
        expect(act(s), isNull, reason: s);
      }
    });
  });

  group('FaceAct', () {
    test('wire names round-trip (brain action face.play)', () {
      for (final a in FaceAct.values) {
        expect(FaceActInfo.fromWire(a.wire), a);
      }
      expect(FaceActInfo.fromWire('hands_up'), FaceAct.handsUp);
      expect(FaceActInfo.fromWire('fly'), isNull);
      expect(FaceActInfo.fromWire(3), isNull);
    });

    test('blends in and out: no change at the start and at the end', () {
      final base = const EmotionAnimationMapper()
          .map(Emotion.neutral, 0.5)
          .params;
      for (final a in FaceAct.values) {
        expect(actEnvelope(a, 0), 0, reason: a.name);
        expect(actEnvelope(a, 1), 0, reason: a.name);
        expect(applyAct(a, 1, 3, base).eyeOpen, closeTo(base.eyeOpen, 1e-9));
      }
      final love = actEyes(FaceAct.love, 0.5);
      expect(love.heart, 1);
      final what = actEyes(FaceAct.what, 0.5);
      expect(what.leftScale, greaterThan(1));
      expect(what.rightScale, lessThan(1));
      expect(actEyes(FaceAct.squish, 0.4).squashY, lessThan(1));
    });

    test('every spoken skit has a line in every language', () {
      for (final a in FaceActLines.spoken) {
        final l = FaceActLines.lineFor(a, math.Random(1))!;
        for (final t in [l.darijaAr, l.darijaLatin, l.msa, l.fr, l.en]) {
          expect(t.trim(), isNotEmpty, reason: a.name);
        }
      }
    });
  });

  group('CompanionController skits', () {
    test('play bumps the sequence so the face restarts it', () {
      final c = CompanionController();
      c.play(FaceAct.eat);
      expect(c.act, FaceAct.eat);
      expect(c.actSeq, 1);
      expect(c.acting, isTrue);
      c.play(FaceAct.eat);
      expect(c.actSeq, 2);
      c.dispose();
    });

    test('a real surprise shows "what?!" eyes; waking up does not', () {
      final c = CompanionController();
      c.show(const DetectedEmotion(Emotion.surprised, 0.8, source: 'llm'));
      expect(c.act, FaceAct.what);
      final d = CompanionController();
      d.show(const DetectedEmotion(Emotion.surprised, 0.5, source: 'idle'));
      expect(d.act, isNull);
      c.dispose();
      d.dispose();
    });

    test('touched while asleep → grumpy; called by name → surprised', () {
      var now = DateTime(2026, 11, 16, 12);
      IdleBehavior idle() => IdleBehavior(clock: () => now);
      final c = CompanionController(idle: idle());
      now = now.add(const Duration(minutes: 11));
      c.idle.tick();
      expect(c.idle.asleep, isTrue);
      c.interact(touch: true);
      expect(c.act, FaceAct.grumpy);
      expect(c.emotion, Emotion.angry);

      final d = CompanionController(idle: idle());
      now = now.add(const Duration(minutes: 11));
      d.idle.tick();
      d.interact();
      expect(d.act, isNull);
      expect(d.emotion, Emotion.surprised);
      c.dispose();
      d.dispose();
    });

    test('petting → heart eyes and happy', () {
      final c = CompanionController();
      c.pet();
      expect(c.act, FaceAct.love);
      expect(c.emotion, Emotion.happy);
      c.dispose();
    });
  });

  testWidgets('the animated face plays every skit without errors', (t) async {
    for (final full in [true, false]) {
      var seq = 0;
      for (final a in FaceAct.values) {
        seq++;
        await t.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 360,
              height: 640,
              child: RobotFace(
                fullScreen: full,
                inputs: FaceInputs(act: a, actSeq: seq),
              ),
            ),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 350));
        }
        expect(t.takeException(), isNull, reason: a.name);
      }
    }
    await t.pumpWidget(const SizedBox());
  });
}
