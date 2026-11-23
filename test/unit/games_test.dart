import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/brain/text_normalizer.dart';
import 'package:sahbi/features/games/game_bank.dart';
import 'package:sahbi/features/games/game_session.dart';

class _Fixed implements math.Random {
  _Fixed(this.i);
  final int i;
  @override
  int nextInt(int max) => i % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

void main() {
  group('bank', () {
    test('every answer key is reachable after normalisation', () {
      for (final r in GameBank.riddles) {
        expect(r.keys, isNotEmpty);
        for (final k in r.keys) {
          expect(normalizeText(k), isNotEmpty, reason: k);
        }
      }
      for (final t in GameBank.trivia) {
        expect(t.keys, hasLength(3));
        expect(t.correct, inInclusiveRange(0, 2));
      }
    });

    test('no trivia key picks two different choices', () {
      for (final t in GameBank.trivia) {
        final seen = <String, int>{};
        for (var i = 0; i < 3; i++) {
          for (final k in t.keys[i]) {
            final n = normalizeText(k);
            expect(
              seen[n] == null || seen[n] == i,
              isTrue,
              reason: '"$k" in ${t.question.en}',
            );
            seen[n] = i;
          }
        }
      }
    });
  });

  group('riddle', () {
    test('right answer in Arabizi, Arabic script and French', () {
      for (final said in ['s7ab', 'هو السحاب', 'c est le nuage !']) {
        final g = GameSession(random: _Fixed(0))..startRiddle();
        expect(g.awaitingAnswer, isTrue);
        final r = g.answer(said)!;
        expect(r.won, isTrue, reason: said);
        expect(g.awaitingAnswer, isFalse);
      }
    });

    test('two wrong tries reveal the answer; "ma3reftch" too', () {
      final g = GameSession(random: _Fixed(0))..startRiddle();
      final a = g.answer('chi tomobil')!;
      expect(a.over, isFalse);
      final b = g.answer('lma')!;
      expect(b.over, isTrue);
      expect(b.won, isFalse);
      expect(b.line.darijaLatin, contains('S-s7ab'));

      g.startRiddle();
      expect(g.answer('ma3reftch')!.over, isTrue);
    });

    test('no game waiting → normal brain', () {
      expect(GameSession().answer('s7ab'), isNull);
    });

    test('the question expires', () {
      var now = DateTime(2026, 11, 16, 12);
      final g = GameSession(random: _Fixed(0), clock: () => now)..startRiddle();
      now = now.add(const Duration(minutes: 2));
      expect(g.awaitingAnswer, isFalse);
      expect(g.answer('s7ab'), isNull);
    });
  });

  group('trivia', () {
    test('by name, by ordinal, wrong, unclear then reveal', () {
      // Bank item 0: Morocco's capital (Rabat).
      final g = GameSession(random: _Fixed(0));
      g.startTrivia();
      expect(g.answer('rbat')!.won, isTrue);
      g.startTrivia(); // different index → item 1 (spider, 8)
      expect(g.answer('tmenya')!.won, isTrue);
      g.startTrivia(); // back to item 0
      expect(g.answer('lwla')!.won, isTrue, reason: 'first choice');
      g.startTrivia();
      final wrong = g.answer('stta')!; // spider: six → wrong
      expect(wrong.won, isFalse);
      expect(wrong.over, isTrue);
      g.startTrivia();
      final unclear = g.answer('hmm')!;
      expect(unclear.over, isFalse);
      expect(g.answer('tanya')!.won, isFalse); // Rabat is first
    });
  });

  group('reaction', () {
    testWidgets('too early, then a timed tap, then too slow', (t) async {
      {
        var now = DateTime(2026, 11, 16, 12);
        final said = <String>[];
        final g = GameSession(random: _Fixed(0), clock: () => now)
          ..onReactionResult = (l) => said.add(l.en);
        g.startReaction();
        expect(g.reaction, ReactionPhase.waiting);
        g.tap();
        expect(g.reaction, ReactionPhase.early);
        expect(said.single, contains('too early'));

        g.startReaction();
        await t.pump(const Duration(milliseconds: 3600)); // 1.5 s + 2 s intro
        expect(g.reaction, ReactionPhase.now);
        now = now.add(const Duration(milliseconds: 280));
        g.tap();
        expect(g.reactionMs, 280);
        expect(said.last, contains('280 ms'));
        await t.pump(const Duration(seconds: 4));
        expect(g.reaction, ReactionPhase.off);

        g.startReaction();
        await t.pump(const Duration(seconds: 9));
        expect(said.last, contains('didn’t tap'));
        g.stop();
      }
    });
  });

  test('kindFor picks the asked game', () {
    final g = GameSession(random: _Fixed(0));
    expect(g.kindFor('7ajitek majitek'), GameKind.riddle);
    expect(g.kindFor('bghit quiz'), GameKind.trivia);
    expect(g.kindFor('nl3bo sor3a'), GameKind.reaction);
    expect(g.kindFor('حاجيتك'), GameKind.riddle);
  });
}
