import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/face/face_act.dart';
import 'package:sahbi/features/personality/companion_controller.dart';
import 'package:sahbi/features/personality/temper.dart';
import 'package:sahbi/features/personality/temper_lines.dart';

/// Random that never triggers the optional "ask please" / mood refusals.
class _NoRandom implements math.Random {
  @override
  double nextDouble() => 0.99;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => true;
}

/// Random that always triggers them.
class _AllRandom extends _NoRandom {
  @override
  double nextDouble() => 0.0;
}

void main() {
  var now = DateTime(2026, 11, 16, 12);
  Temper make([math.Random? r]) =>
      Temper(clock: () => now, random: r ?? _NoRandom());
  void wait(int ms) => now = now.add(Duration(milliseconds: ms));

  setUp(() => now = DateTime(2026, 11, 16, 12));

  group('pokes', () {
    test('one poke now and then is just a squish', () {
      final t = make();
      for (var i = 0; i < 6; i++) {
        expect(t.poke(), PokeReaction.squish);
        wait(8000);
      }
      expect(t.mood, 'ok');
    });

    test('poking again and again: annoyed, then sulking, then ignored', () {
      final t = make();
      final got = <PokeReaction>[];
      for (var i = 0; i < 12 && !t.sulking; i++) {
        got.add(t.poke());
        wait(300);
      }
      expect(got, contains(PokeReaction.annoyed));
      expect(got.last, PokeReaction.sulk);
      expect(t.sulking, isTrue);
      expect(t.mood, 'sulking');
      expect(t.poke(), PokeReaction.ignore);
      expect(t.moodForBrain, contains('SULKING'));
    });

    test('rapid taps count as poking (not tap-to-talk)', () {
      final t = make();
      t.poke();
      expect(t.poking, isFalse);
      wait(400);
      t.poke();
      wait(400);
      t.poke();
      expect(t.poking, isTrue);
      wait(4000);
      expect(t.poking, isFalse);
    });

    test('the sulk ends by itself and the temper calms down', () {
      final t = make();
      while (!t.sulking) {
        t.poke();
        wait(200);
      }
      wait(31000);
      expect(t.sulking, isFalse);
      wait(120000);
      expect(t.mood, 'ok');
      expect(t.moodForBrain, isNull);
    });
  });

  group('words', () {
    test('insults aimed at him make him sulk', () {
      for (final s in [
        'nta 7mar',
        'a sahbi nta bhim',
        'ya mkelkh',
        '7mar!',
        'you are dumb',
        't es nul',
        'نتا حمار',
        'sir t9awed',
      ]) {
        final t = make();
        expect(t.heard(s), TemperChange.insulted, reason: s);
        expect(t.sulking, isTrue, reason: s);
      }
    });

    test('normal sentences with those words are not insults', () {
      for (final s in [
        'chft wa7d lkelb f zen9a',
        'had lfilm khayb bzaf',
        'chno howa l7mar f lfrancais',
        'le match était nul',
        'kifach ndir atay',
      ]) {
        expect(make().heard(s), TemperChange.none, reason: s);
      }
    });

    test('sorry / kanbghik ends the sulk', () {
      for (final s in ['sme7 li', 'smh lia a sahbi', 'pardon', 'kanbghik']) {
        final t = make();
        t.heard('nta 7mar');
        expect(t.heard(s), TemperChange.madeUp, reason: s);
        expect(t.sulking, isFalse, reason: s);
        expect(t.mood, 'ok', reason: s);
      }
      expect(make().heard('sme7 li'), TemperChange.none);
    });

    test('petting: about two strokes to forgive a sulk', () {
      final t = make();
      t.heard('nta 7mar');
      expect(t.pet(), isFalse);
      expect(t.pet(), isTrue);
      expect(t.sulking, isFalse);
    });
  });

  group('skits asked by voice', () {
    test('calm: does it', () {
      expect(make().decide(FaceAct.handsUp, 'haz ydik'), SkitDecision.play);
    });

    test('sulking: refuses everything, even love', () {
      final t = make();
      t.heard('ya bhim');
      expect(
        t.decide(FaceAct.handsUp, 'haz ydik 3afak'),
        SkitDecision.refuseSulking,
      );
      expect(t.decide(FaceAct.love, 'love'), SkitDecision.refuseSulking);
    });

    test('just ate / drank: full', () {
      final t = make();
      t.played(FaceAct.eat);
      t.played(FaceAct.drink);
      wait(60000);
      expect(t.decide(FaceAct.eat, 'kol'), SkitDecision.full);
      expect(t.decide(FaceAct.drink, 'chrob atay'), SkitDecision.quenched);
      wait(200000);
      expect(t.decide(FaceAct.eat, 'kol'), SkitDecision.play);
    });

    test('sometimes wants the magic word, then "3afak" does it', () {
      final t = make(_AllRandom());
      expect(t.decide(FaceAct.dance, 'chte7'), SkitDecision.askPlease);
      expect(t.pleaseFollowUp('kifach'), isNull);
      expect(t.pleaseFollowUp('3afak'), FaceAct.dance);
      expect(t.pleaseFollowUp('3afak'), isNull);
      // Saying it politely the first time always works when calm.
      expect(t.decide(FaceAct.dance, 'chte7 3afak'), SkitDecision.play);
    });

    test('annoyed: may refuse unless asked politely', () {
      final t = make(_AllRandom());
      t.shaken();
      t.shaken();
      expect(t.mood, 'annoyed');
      expect(t.decide(FaceAct.handsUp, 'haz ydik'), SkitDecision.refuseMood);
      expect(t.decide(FaceAct.handsUp, 'haz ydik 3afak'), SkitDecision.play);
    });

    test('every refusal has a line in every language', () {
      for (final d in SkitDecision.values) {
        final l = TemperLines.forDecision(d);
        if (d == SkitDecision.play) {
          expect(l, isNull);
          continue;
        }
        for (final s in [l!.darijaAr, l.darijaLatin, l.msa, l.fr, l.en]) {
          expect(s.trim(), isNotEmpty);
        }
      }
    });
  });

  group('CompanionController', () {
    test('sulking turns the face away; making up brings it back', () {
      final c = CompanionController(temper: make());
      c.temper.heard('nta 7mar');
      c.startSulkFace();
      expect(c.lookAt, isNotNull);
      expect(c.lookAt!.dx.abs(), greaterThan(0.9));
      c.temper.heard('sme7 li');
      c.madeUp();
      expect(c.lookAt, isNull);
      expect(c.act, FaceAct.love);
      c.dispose();
    });

    test('petting while sulking: still sulking, then made up', () {
      final c = CompanionController(temper: make());
      c.temper.heard('ya bhim');
      c.startSulkFace();
      expect(c.pet(), 'stillSulking');
      expect(c.pet(), 'madeUp');
      expect(c.act, FaceAct.love);
      expect(c.pet(), 'happy');
      c.dispose();
    });

    test('poke squashes the eyes; when sulking it only says hmph', () {
      final c = CompanionController(temper: make());
      expect(c.poke(), PokeReaction.squish);
      expect(c.act, FaceAct.squish);
      c.temper.heard('7mar');
      expect(c.poke(), PokeReaction.ignore);
      expect(c.act, FaceAct.suspicious);
      c.dispose();
    });
  });
}
