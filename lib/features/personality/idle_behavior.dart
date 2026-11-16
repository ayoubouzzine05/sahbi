import 'dart:math' as math;

/// What the idle engine wants the face to do right now.
enum IdleAction { none, lookAround, yawn, fallAsleep, wakeUp }

/// Pure, clock-injected idle logic so it can be unit tested.
///
/// - after [lookAroundEvery] of no interaction: occasional look-around
/// - after [yawnAfter]: a yawn
/// - after [sleepAfter]: sleepy face until touched / spoken to
class IdleBehavior {
  IdleBehavior({
    DateTime Function()? clock,
    math.Random? random,
    this.yawnAfter = const Duration(seconds: 60),
    this.sleepAfter = const Duration(seconds: 120),
    this.lookAroundEvery = const Duration(seconds: 8),
    this.enabled = true,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? math.Random() {
    _lastInteraction = _clock();
    _lastLook = _lastInteraction;
  }

  final DateTime Function() _clock;
  final math.Random _random;
  final Duration yawnAfter;
  final Duration sleepAfter;
  final Duration lookAroundEvery;
  bool enabled;

  late DateTime _lastInteraction;
  late DateTime _lastLook;
  bool _yawned = false;
  bool _asleep = false;

  bool get asleep => _asleep;

  /// Any touch, voice or chat input.
  IdleAction interact() {
    _lastInteraction = _clock();
    _lastLook = _lastInteraction;
    _yawned = false;
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
