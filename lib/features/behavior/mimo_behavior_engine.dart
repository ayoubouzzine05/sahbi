import 'dart:math' as math;

import 'behavior_models.dart';
import 'initiative_scheduler.dart';

/// MIMO's autonomous state machine. Pure Dart (clock and random injected),
/// no phone UI: it receives [BehaviorEvent]s and a 1 s [tick], and returns
/// [BodyCommand]s that any body can perform (the phone face today, a robot
/// with servos and a display later, through the robot protocol).
///
/// ```
///  idle ──motion──▶ curious ──20 s calm──▶ idle
///  idle ──5 min ignored──▶ bored ──9 min──▶ sleepy (asleep at 10 min)
///  touch / game ──▶ playful ──20 s / game over──▶ idle
///  "MIMO" / conversation / mic open ──▶ listening ──end──▶ idle
/// ```
///
/// When calm, it may take an initiative (remark, riddle, trivia, reaction
/// game) within the [InitiativeScheduler] limits; [canAct] lets the app veto
/// (music, live camera, app in background…).
class MimoBehaviorEngine {
  MimoBehaviorEngine({
    required this.scheduler,
    DateTime Function()? clock,
    math.Random? random,
    this.boredAfter = const Duration(minutes: 5),
    this.drowsyAfter = const Duration(minutes: 9),
    this.curiousFor = const Duration(seconds: 20),
    this.playfulFor = const Duration(seconds: 20),
    this.firstInitiativeAfter = const Duration(seconds: 90),
    this.initiativeChance = 0.04,
  }) : _clock = clock ?? DateTime.now,
       _r = random ?? math.Random() {
    final now = _clock();
    _since = now;
    _lastActivity = now;
    _lastMotion = now;
  }

  final InitiativeScheduler scheduler;
  final DateTime Function() _clock;
  final math.Random _r;
  final Duration boredAfter;
  final Duration drowsyAfter;
  final Duration curiousFor;
  final Duration playfulFor;

  /// Quiet time needed after the user's last activity before MIMO speaks.
  final Duration firstInitiativeAfter;

  /// Chance per calm second to take an initiative once allowed (≈ one
  /// every 25 s on average after the quiet time, then the cooldowns apply).
  final double initiativeChance;

  /// Extra veto from the app (music, live screen, background…).
  bool Function() canAct = _yes;
  static bool _yes() => true;

  MimoState _state = MimoState.idle;
  late DateTime _since;
  late DateTime _lastActivity;
  late DateTime _lastMotion;
  bool _conversation = false;
  bool _listening = false;
  bool _game = false;
  bool _asleep = false;

  MimoState get state => _state;
  EyeStyle get eyes => EyeStyle.of(_state);
  Duration get idleFor => _clock().difference(_lastActivity);

  List<BodyCommand> _go(MimoState s, [List<BodyCommand>? extra]) {
    final out = <BodyCommand>[...?extra];
    if (s != _state) {
      _state = s;
      _since = _clock();
      out.insert(0, SetMood(s, EyeStyle.of(s)));
    }
    return out;
  }

  /// The state the "background" facts call for (asleep, talking, game…).
  MimoState? _forced() {
    if (_asleep) return MimoState.sleepy;
    if (_listening || _conversation) return MimoState.listening;
    if (_game) return MimoState.playful;
    return null;
  }

  List<BodyCommand> on(BehaviorEvent e) {
    final now = _clock();
    switch (e) {
      case BehaviorEvent.wake:
        _lastActivity = now;
        _asleep = false;
        return _go(MimoState.listening, const [LookAt(0, 0, holdMs: 2500)]);
      case BehaviorEvent.userSpoke:
        _lastActivity = now;
      case BehaviorEvent.touched:
        _lastActivity = now;
        if (_forced() == null) {
          // A touch cheers MIMO up for a moment.
          return _go(MimoState.playful);
        }
      case BehaviorEvent.motion:
        _lastMotion = now;
        if (_forced() == null &&
            (_state == MimoState.idle || _state == MimoState.bored)) {
          return _go(MimoState.curious);
        }
      case BehaviorEvent.conversationStart:
        _conversation = true;
        _lastActivity = now;
      case BehaviorEvent.conversationEnd:
        _conversation = false;
        _lastActivity = now;
      case BehaviorEvent.listenStart:
        _listening = true;
        _lastActivity = now;
      case BehaviorEvent.listenEnd:
        _listening = false;
      case BehaviorEvent.gameStart:
        _game = true;
        _lastActivity = now;
      case BehaviorEvent.gameEnd:
        _game = false;
        _lastActivity = now;
      case BehaviorEvent.fellAsleep:
        _asleep = true;
      case BehaviorEvent.wokeUp:
        _asleep = false;
        _lastActivity = now;
    }
    final f = _forced();
    if (f != null) return _go(f);
    // Movement alone does not wake a drowsy MIMO (it would flap).
    if (e == BehaviorEvent.motion) return const [];
    if (_state == MimoState.listening || _state == MimoState.sleepy) {
      return _go(MimoState.idle);
    }
    if (_state == MimoState.playful && !_game && e == BehaviorEvent.gameEnd) {
      return _go(MimoState.idle);
    }
    return const [];
  }

  /// Once a second.
  List<BodyCommand> tick() {
    final now = _clock();
    final forced = _forced();
    if (forced != null) return _go(forced);
    final inState = now.difference(_since);
    final quiet = idleFor;
    switch (_state) {
      case MimoState.curious:
        if (now.difference(_lastMotion) >= curiousFor) {
          return _go(MimoState.idle);
        }
      case MimoState.playful:
        if (inState >= playfulFor) return _go(MimoState.idle);
      case MimoState.idle:
        if (quiet >= boredAfter) {
          return _go(MimoState.bored, const [PlaySkit('suspicious')]);
        }
        // Quiet hours: drowsy much sooner, and silent.
        if (scheduler.quietNow() && quiet >= const Duration(minutes: 2)) {
          return _go(MimoState.sleepy);
        }
      case MimoState.bored:
        if (quiet >= drowsyAfter) {
          return _go(MimoState.sleepy, const [PlaySkit('yawn')]);
        }
      case MimoState.sleepy:
        if (quiet < const Duration(minutes: 1) && !scheduler.quietNow()) {
          return _go(MimoState.idle);
        }
      case MimoState.listening:
        return _go(MimoState.idle);
    }
    return _maybeInitiative(quiet);
  }

  List<BodyCommand> _maybeInitiative(Duration quiet) {
    if (_state == MimoState.sleepy || _state == MimoState.listening) {
      return const [];
    }
    if (quiet < firstInitiativeAfter) return const [];
    if (!scheduler.canSpeak() || !canAct()) return const [];
    if (_r.nextDouble() >= initiativeChance) return const [];
    final game = scheduler.canPlay() && _r.nextDouble() < 0.45;
    final InitiativeKind kind;
    if (game) {
      const games = [
        InitiativeKind.riddle,
        InitiativeKind.trivia,
        InitiativeKind.reaction,
      ];
      kind = games[_r.nextInt(games.length)];
    } else {
      kind = InitiativeKind.remark;
    }
    scheduler.record(game: game);
    final out = <BodyCommand>[TakeInitiative(kind)];
    if (game) out.insertAll(0, _go(MimoState.playful));
    return out;
  }
}
