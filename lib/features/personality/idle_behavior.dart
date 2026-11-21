import 'dart:math' as math;

/// What the idle engine wants the face to do right now.
enum IdleAction { none, lookAround, yawn, fallAsleep, wakeUp, chatter }

/// Pure, clock-injected idle logic so it can be unit tested.
///
/// - after [lookAroundEvery] of no interaction: occasional look-around
/// - at each of [chatterAt] (when [chatterEnabled]): the robot says something
///   by itself (a joke, a question…) so the app feels alive
/// - after [yawnAfter]: a yawn
/// - after [sleepAfter] of being ignored: asleep until called by name,
///   touched or spoken to
///
/// The robot's own talking must not be passed as [tick]'s `busy`, otherwise
/// it would never notice that it is being ignored.
class IdleBehavior {
  IdleBehavior({
    DateTime Function()? clock,
    math.Random? random,
    this.yawnAfter = const Duration(minutes: 9),
    this.sleepAfter = const Duration(minutes: 10),
    this.lookAroundEvery = const Duration(seconds: 8),
    this.chatterAt = defaultChatterAt,
    this.enabled = true,
    this.chatterEnabled = true,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? math.Random() {
    _lastInteraction = _clock();
    _lastLook = _lastInteraction;
  }

  final DateTime Function() _clock;
  final math.Random _random;
  final Duration yawnAfter;
  final Duration sleepAfter;
  final Duration lookAroundEvery;
  final List<Duration> chatterAt;
  bool enabled;
  bool chatterEnabled;

  /// Moments (since the last interaction) when the robot speaks first:
  /// further apart the longer it is ignored.
  static const defaultChatterAt = [
    Duration(seconds: 45),
    Duration(minutes: 2),
    Duration(minutes: 3, seconds: 30),
    Duration(minutes: 5, seconds: 30),
    Duration(minutes: 8),
  ];

  late DateTime _lastInteraction;
  late DateTime _lastLook;
  bool _yawned = false;
  bool _asleep = false;
  int _chatter = 0;

  bool get asleep => _asleep;

  /// Time since the user last did something.
  Duration get idleFor => _clock().difference(_lastInteraction);

  /// Any touch, voice or chat input.
  IdleAction interact() {
    _lastInteraction = _clock();
    _lastLook = _lastInteraction;
    _yawned = false;
    _chatter = 0;
    if (_asleep) {
      _asleep = false;
      return IdleAction.wakeUp;
    }
    return IdleAction.none;
  }

  /// Call periodically (e.g. every second). [busy] = listening/speaking/music.
  IdleAction tick({bool busy = false}) {
    final now = _clock();
    if (busy) {
      _lastInteraction = now;
      _lastLook = now;
      _yawned = false;
      _chatter = 0;
      if (_asleep) {
        _asleep = false;
        return IdleAction.wakeUp;
      }
      return IdleAction.none;
    }
    if (!enabled) return IdleAction.none;
    final idle = now.difference(_lastInteraction);
    if (!_asleep && idle >= sleepAfter) {
      _asleep = true;
      return IdleAction.fallAsleep;
    }
    if (_asleep) return IdleAction.none;
    if (_chatter < chatterAt.length && idle >= chatterAt[_chatter]) {
      // Skip moments that passed while chatter was off or the app was busy.
      while (_chatter < chatterAt.length && idle >= chatterAt[_chatter]) {
        _chatter++;
      }
      if (chatterEnabled && idle < yawnAfter) return IdleAction.chatter;
    }
    if (!_yawned && idle >= yawnAfter) {
      _yawned = true;
      return IdleAction.yawn;
    }
    if (now.difference(_lastLook) >= lookAroundEvery) {
      _lastLook = now;
      // Not every opportunity: keeps it lively but not twitchy.
      if (_random.nextDouble() < 0.6) return IdleAction.lookAround;
    }
    return IdleAction.none;
  }
}
