import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/features/face/face_params.dart';
import 'package:sahbi/features/personality/conversation_context.dart';
import 'package:sahbi/features/personality/emotion.dart';
import 'package:sahbi/features/personality/emotion_animation_mapper.dart';
import 'package:sahbi/features/personality/emotion_detector.dart';
import 'package:sahbi/features/personality/idle_behavior.dart';
import 'package:sahbi/features/personality/personality_responses.dart';
import 'package:sahbi/features/personality/voice_state.dart';

void main() {
  group('EmotionDetector', () {
    const d = EmotionDetector();
    final table = <String, Emotion>{
      'hamdoullah ana fer7an lyoum': Emotion.happy,
      'شكرا بزاف، زوين': Emotion.happy,
      'merci, super!': Emotion.happy,
      'ana 7azin bzaf': Emotion.sad,
      'machi mzyan lyoum': Emotion.sad, // negation flips happy → sad
      'je suis triste': Emotion.sad,
      'ana m3assab': Emotion.angry,
      'WHY IS THIS BROKEN': Emotion.angry, // all caps
      'wow bssa7?!': Emotion.surprised,
      'fiya nn3as, bonne nuit': Emotion.sleepy,
      'kifach katkhdem?': Emotion.curious,
      'شنو هادا؟': Emotion.curious,
      'ok': Emotion.neutral,
      '': Emotion.neutral,
    };
    table.forEach((text, expected) {
      test(
        '"$text" → ${expected.name}',
        () => expect(d.detect(text).emotion, expected),
      );
    });

    test('ASCII words need word boundaries (top ≠ stop)', () {
      expect(d.detect('stop').emotion, Emotion.neutral);
    });

    test('words like "mcha" (went) do not trigger sadness', () {
      expect(d.detect('mcha l sou9').emotion, Emotion.neutral);
    });

    test('intensity stays within 0.3..1', () {
      for (final t in ['zwin zwin zwin zwin zwin!!!!!!', 'hmm', '😂😂😂']) {
        final i = d.detect(t).intensity;
        expect(i, inInclusiveRange(0.3, 1.0));
      }
    });

    test('fromLlm parses, clamps and falls back', () {
      expect(d.fromLlm('happy', 0.8).emotion, Emotion.happy);
      expect(d.fromLlm('HAPPY', 2).intensity, 1.0);
      expect(d.fromLlm('nonsense', null).emotion, Emotion.neutral);
      expect(d.fromLlm('sad', -1).intensity, 0.0);
      expect(d.fromLlm('sad', 0.5).source, 'llm');
    });
  });

  group('EmotionAnimationMapper', () {
    const m = EmotionAnimationMapper();
    test('every emotion maps to a face', () {
      for (final e in Emotion.values) {
        final s = m.map(e, 0.7);
        expect(s.params.eyeOpen, inInclusiveRange(0.0, 1.2), reason: e.name);
      }
    });
    test(
      'happy smiles, sad frowns, surprised opens eyes wider than neutral',
      () {
        final n = m.map(Emotion.neutral, 1).params;
        expect(
          m.map(Emotion.happy, 1).params.mouthCurve,
          greaterThan(n.mouthCurve),
        );
        expect(m.map(Emotion.sad, 1).params.mouthCurve, lessThan(n.mouthCurve));
        expect(
          m.map(Emotion.surprised, 1).params.eyeOpen,
          greaterThanOrEqualTo(n.eyeOpen),
        );
        expect(m.map(Emotion.sleepy, 1).params.eyeOpen, lessThan(n.eyeOpen));
      },
    );
    test('intensity moves the face further from neutral', () {
      final n = EmotionAnimationMapper.neutral;
      final lo = m.map(Emotion.happy, 0).params.distanceTo(n);
      final hi = m.map(Emotion.happy, 1).params.distanceTo(n);
      expect(hi, greaterThan(lo));
    });
    test('NaN / out-of-range intensity is safe', () {
      expect(() => m.map(Emotion.angry, double.nan), returnsNormally);
      expect(() => m.map(Emotion.angry, 9), returnsNormally);
    });
  });

  group('FaceParams.lerp', () {
    const a = FaceParams(eyeOpen: 0, mouthCurve: -1, accent: Color(0xFF000000));
    const b = FaceParams(eyeOpen: 1, mouthCurve: 1, accent: Color(0xFFFFFFFF));
    test('endpoints and midpoint', () {
      expect(FaceParams.lerp(a, b, 0).eyeOpen, 0);
      expect(FaceParams.lerp(a, b, 1).eyeOpen, 1);
      expect(FaceParams.lerp(a, b, 0.5).mouthCurve, closeTo(0, 1e-9));
      expect(
        FaceParams.lerp(a, b, 0.5).distanceTo(a),
        closeTo(FaceParams.lerp(a, b, 0.5).distanceTo(b), 1e-9),
      );
    });
  });

  group('VoiceStateMachine', () {
    test('normal turn: idle → listening → thinking → speaking → idle', () {
      final sm = VoiceStateMachine();
      sm.transition(VoiceState.listening);
      sm.transition(VoiceState.thinking);
      sm.transition(VoiceState.speaking);
      sm.transition(VoiceState.idle);
      expect(sm.state, VoiceState.idle);
    });
    test('interrupt: speaking → listening is legal', () {
      final sm = VoiceStateMachine(VoiceState.speaking);
      expect(sm.tryTransition(VoiceState.listening), isTrue);
    });
    test('listening → speaking is illegal', () {
      final sm = VoiceStateMachine(VoiceState.listening);
      expect(
        () => sm.transition(VoiceState.speaking),
        throwsA(isA<IllegalTransition>()),
      );
      expect(sm.tryTransition(VoiceState.speaking), isFalse);
      expect(sm.state, VoiceState.listening);
    });
    test('error recovers to idle', () {
      final sm = VoiceStateMachine();
      sm.transition(VoiceState.error, error: 'x');
      expect(sm.tryTransition(VoiceState.idle), isTrue);
    });
  });

  group('IdleBehavior', () {
    late DateTime now;
    IdleBehavior make({double rnd = 0.1}) =>
        IdleBehavior(clock: () => now, random: _FixedRandom(rnd));
    setUp(() => now = DateTime(2026, 1, 1, 12));

    test('chats by itself on schedule, yawns at 9 min, sleeps at 10 min', () {
      final i = make();
      final start = now;
      IdleAction at(Duration d) {
        now = start.add(d);
        return i.tick();
      }

      expect(at(const Duration(seconds: 44)), isNot(IdleAction.chatter));
      expect(at(const Duration(seconds: 45)), IdleAction.chatter);
      expect(at(const Duration(seconds: 46)), isNot(IdleAction.chatter));
      expect(at(const Duration(minutes: 2)), IdleAction.chatter);
      expect(at(const Duration(minutes: 3, seconds: 30)), IdleAction.chatter);
      expect(at(const Duration(minutes: 5, seconds: 30)), IdleAction.chatter);
      expect(at(const Duration(minutes: 8)), IdleAction.chatter);
      expect(at(const Duration(minutes: 9)), IdleAction.yawn);
      expect(at(const Duration(minutes: 10)), IdleAction.fallAsleep);
      expect(i.asleep, isTrue);
      expect(at(const Duration(minutes: 30)), IdleAction.none);
      expect(i.interact(), IdleAction.wakeUp);
      expect(i.asleep, isFalse);
    });
    test('missed chatter moments are skipped, not replayed', () {
      final i = make();
      now = now.add(const Duration(minutes: 4));
      expect(i.tick(), IdleAction.chatter); // one line, not three
      now = now.add(const Duration(seconds: 1));
      expect(i.tick(), isNot(IdleAction.chatter));
    });
    test('chatter off still sleeps after 10 min', () {
      final i = make()..chatterEnabled = false;
      now = now.add(const Duration(minutes: 2));
      expect(i.tick(), isNot(IdleAction.chatter));
      now = now.add(const Duration(minutes: 8));
      expect(i.tick(), IdleAction.fallAsleep);
    });
    test('an interaction restarts the chatter schedule', () {
      final i = make();
      now = now.add(const Duration(seconds: 45));
      expect(i.tick(), IdleAction.chatter);
      i.interact();
      now = now.add(const Duration(seconds: 45));
      expect(i.tick(), IdleAction.chatter);
    });
    test('looks around periodically when random allows', () {
      final i = make(rnd: 0.1);
      now = now.add(const Duration(seconds: 9));
      expect(i.tick(), IdleAction.lookAround);
      final j = make(rnd: 0.9);
      now = now.add(const Duration(seconds: 9));
      expect(j.tick(), IdleAction.none);
    });
    test('busy (listening/speaking/music) never sleeps and wakes up', () {
      final i = make()..chatterEnabled = false;
      now = now.add(const Duration(minutes: 11));
      expect(i.tick(), IdleAction.fallAsleep);
      expect(i.tick(busy: true), IdleAction.wakeUp);
      now = now.add(const Duration(seconds: 500));
      expect(i.tick(busy: true), IdleAction.none);
    });
    test('disabled does nothing', () {
      final i = make()..enabled = false;
      now = now.add(const Duration(minutes: 10));
      expect(i.tick(), IdleAction.none);
    });
  });

  group('ConversationContext', () {
    test('keeps the last N turns and queues older ones for summary', () {
      final c = ConversationContext(maxTurns: 4);
      for (var k = 0; k < 8; k++) {
        c.add(k.isEven ? 'user' : 'assistant', 'msg $k');
      }
      expect(c.turns.length, 4);
      expect(c.turns.first.text, 'msg 4');
      expect(c.pendingForSummary.length, 4);
      expect(c.needsSummary, isTrue);
      c.applySummary('summary');
      expect(c.summary, 'summary');
      expect(c.pendingForSummary, isEmpty);
    });
    test('char budget trims but keeps at least two turns', () {
      final c = ConversationContext(maxTurns: 50, maxChars: 10);
      c.add('user', 'a' * 20);
      c.add('assistant', 'b' * 20);
      c.add('user', 'c' * 20);
      expect(c.turns.length, 2);
    });
    test('blank messages ignored; clear resets everything', () {
      final c = ConversationContext();
      c.add('user', '   ');
      expect(c.turns, isEmpty);
      c.add('user', 'x');
      c.applySummary('s');
      c.clear();
      expect(c.turns, isEmpty);
      expect(c.summary, isNull);
    });
  });

  group('PersonalityResponses', () {
    final r = PersonalityResponses(random: math.Random(1));
    final intents = <String, OfflineIntent?>{
      'Salam Sahbi': OfflineIntent.greeting,
      'السلام عليكم': OfflineIntent.greeting,
      'Kif dayr?': OfflineIntent.howAreYou,
      'ça va?': OfflineIntent.howAreYou,
      'chkon nta?': OfflineIntent.whoAreYou,
      'chokran bzaf': OfflineIntent.thanks,
      'merci': OfflineIntent.thanks,
      '3awed lia chi nkta': OfflineIntent.joke,
      'bslama': OfflineIntent.bye,
      'kanbghik a sahbi': OfflineIntent.love,
      'chno hiya l3asima dyal fransa': null,
    };
    intents.forEach((text, want) {
      test('intent "$text" → $want', () => expect(r.detectIntent(text), want));
    });
    test('every intent has a line in all languages', () {
      for (final i in OfflineIntent.values) {
        final l = r.forIntent(i, DateTime(2026, 1, 1, 9));
        for (final lang in ['darija', 'ar', 'fr', 'en']) {
          expect(l.display(lang).trim(), isNotEmpty, reason: '$i/$lang');
          expect(l.tts(lang).trim(), isNotEmpty, reason: '$i/$lang');
        }
        expect(
          l.display('darija', latinDarija: true),
          isNot(contains(RegExp('[\u0600-\u06FF]'))),
        );
      }
    });
    test('darija TTS text is in Arabic script', () {
      final l = r.offlineFallback();
      expect(l.tts('darija'), contains(RegExp('[\u0600-\u06FF]')));
    });
    test('time-of-day greeting differs morning vs night', () {
      final morning = {
        for (var k = 0; k < 20; k++) r.greetingFor(DateTime(2026, 1, 1, 8)).en,
      };
      final night = {
        for (var k = 0; k < 20; k++) r.greetingFor(DateTime(2026, 1, 1, 23)).en,
      };
      expect(morning.intersection(night), isEmpty);
    });
    test('honest action lines exist', () {
      expect(PersonalityResponses.actionOk('Paused').en, contains('Paused'));
      expect(PersonalityResponses.actionFailed('no_tracks').en, isNotEmpty);
    });
  });
}

class _FixedRandom implements math.Random {
  _FixedRandom(this.v);
  final double v;
  @override
  double nextDouble() => v;
  @override
  int nextInt(int max) => (v * max).floor().clamp(0, max - 1);
  @override
  bool nextBool() => v >= 0.5;
}
