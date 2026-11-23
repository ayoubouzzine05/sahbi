import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/behavior/behavior_models.dart';
import 'package:sahbi/features/behavior/initiative_scheduler.dart';
import 'package:sahbi/features/behavior/mimo_behavior_engine.dart';

/// Always "yes" for random rolls (initiative chance, game choice index 0).
class _Lucky implements math.Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => true;
}

void main() {
  late DateTime now;
  DateTime clock() => now;
  bool quiet(int h) => h >= 23 || h < 8;

  MimoBehaviorEngine engine({double chance = 0}) => MimoBehaviorEngine(
    scheduler: InitiativeScheduler(isQuiet: quiet, clock: clock),
    clock: clock,
    random: _Lucky(),
    initiativeChance: chance,
  );

  List<BodyCommand> run(MimoBehaviorEngine e, Duration d) {
    final out = <BodyCommand>[];
    for (var s = 0; s < d.inSeconds; s++) {
      now = now.add(const Duration(seconds: 1));
      out.addAll(e.tick());
    }
    return out;
  }

  setUp(() => now = DateTime(2026, 11, 16, 15));

  test('idle → bored after 5 min → sleepy after 9 min', () {
    final e = engine();
    run(e, const Duration(minutes: 5, seconds: 1));
    expect(e.state, MimoState.bored);
    expect(e.eyes.lid, greaterThan(0));
    run(e, const Duration(minutes: 4));
    expect(e.state, MimoState.sleepy);
    // Talking to it wakes it up.
    e.on(BehaviorEvent.userSpoke);
    run(e, const Duration(seconds: 2));
    expect(e.state, MimoState.idle);
  });

  test('movement makes it curious, calm brings it back', () {
    final e = engine();
    final cmds = e.on(BehaviorEvent.motion);
    expect(e.state, MimoState.curious);
    expect(cmds.whereType<SetMood>().single.eyes, EyeStyle.curious);
    run(e, const Duration(seconds: 21));
    expect(e.state, MimoState.idle);
  });

  test('wake word: listening + look at the user; conversation holds it', () {
    final e = engine();
    final cmds = e.on(BehaviorEvent.wake);
    expect(e.state, MimoState.listening);
    expect(cmds.whereType<LookAt>().single.x, 0);
    e.on(BehaviorEvent.conversationStart);
    run(e, const Duration(minutes: 6));
    expect(e.state, MimoState.listening, reason: 'never bored mid-talk');
    e.on(BehaviorEvent.conversationEnd);
    expect(e.state, MimoState.idle);
  });

  test('touch → playful for a while', () {
    final e = engine();
    e.on(BehaviorEvent.touched);
    expect(e.state, MimoState.playful);
    run(e, const Duration(seconds: 21));
    expect(e.state, MimoState.idle);
  });

  test('initiatives wait for quiet, respect the cooldown and the veto', () {
    final e = engine(chance: 1);
    var allowed = true;
    e.canAct = () => allowed;
    final first = run(
      e,
      const Duration(seconds: 89),
    ).whereType<TakeInitiative>();
    expect(first, isEmpty, reason: 'user was active less than 90 s ago');
    final got = run(e, const Duration(seconds: 2)).whereType<TakeInitiative>();
    expect(got, hasLength(1));
    // 3 min cooldown.
    expect(
      run(
        e,
        const Duration(minutes: 2, seconds: 50),
      ).whereType<TakeInitiative>(),
      isEmpty,
    );
    allowed = false;
    expect(
      run(e, const Duration(minutes: 1)).whereType<TakeInitiative>(),
      isEmpty,
    );
  });

  test('a game at most every 20 minutes', () {
    final e = engine(chance: 1);
    final kinds = <InitiativeKind>[];
    for (var i = 0; i < 6; i++) {
      e.on(BehaviorEvent.userSpoke); // keeps it from getting bored
      kinds.addAll(
        run(
          e,
          const Duration(minutes: 3, seconds: 5),
        ).whereType<TakeInitiative>().map((t) => t.kind),
      );
    }
    final games = kinds.where((k) => k != InitiativeKind.remark).length;
    expect(games, lessThanOrEqualTo(1)); // 6 × ~3 min < 20 min
    expect(kinds, isNotEmpty);
  });

  test('quiet hours: silent and drowsy', () {
    now = DateTime(2026, 11, 16, 23, 30);
    final e = engine(chance: 1);
    final cmds = run(e, const Duration(minutes: 3));
    expect(cmds.whereType<TakeInitiative>(), isEmpty);
    expect(e.state, MimoState.sleepy);
  });

  test('scheduler: hourly and daily caps', () {
    final s = InitiativeScheduler(
      isQuiet: (_) => false,
      clock: clock,
      minGap: Duration.zero,
      perHour: 2,
      perDay: 3,
    );
    s.record();
    s.record();
    expect(s.canSpeak(), isFalse);
    now = now.add(const Duration(hours: 1, minutes: 1));
    expect(s.canSpeak(), isTrue);
    s.record();
    now = now.add(const Duration(hours: 2));
    expect(s.canSpeak(), isFalse, reason: '3 today');
    now = now.add(const Duration(days: 1));
    expect(s.canSpeak(), isTrue);
  });
}
