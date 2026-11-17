import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'emotion.dart';
import 'emotion_detector.dart';
import 'idle_behavior.dart';

/// Owns the conversational emotion shown on the face and the idle engine.
class CompanionController extends ChangeNotifier {
  CompanionController({IdleBehavior? idle, this.busy, math.Random? random})
    : idle = idle ?? IdleBehavior(),
      _r = random ?? math.Random();

  final IdleBehavior idle;

  /// Returns true while listening/speaking/music (no idle behaviour then).
  final bool Function()? busy;
  final math.Random _r;

  Emotion emotion = Emotion.neutral;
  double intensity = 0.5;
  String source = 'idle';
  Offset? lookAt;
  Timer? _revert;
  Timer? _ticker;
  Timer? _lookTimer;

  /// Fired when the idle engine yawns / falls asleep / wakes up.
  void Function(IdleAction action)? onIdleAction;

  void start() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final a = idle.tick(busy: busy?.call() ?? false);
    switch (a) {
      case IdleAction.lookAround:
        lookAt = Offset(_r.nextDouble() * 2 - 1, _r.nextDouble() - 0.5);
        _lookTimer?.cancel();
        _lookTimer = Timer(const Duration(milliseconds: 1400), () {
          lookAt = null;
          notifyListeners();
        });
        notifyListeners();
      case IdleAction.yawn:
        show(
          const DetectedEmotion(Emotion.sleepy, 0.6, source: 'idle'),
          hold: const Duration(seconds: 3),
        );
      case IdleAction.fallAsleep:
        _revert?.cancel();
        emotion = Emotion.sleepy;
        intensity = 1;
        source = 'idle';
        notifyListeners();
      case IdleAction.wakeUp:
        show(
          const DetectedEmotion(Emotion.surprised, 0.5, source: 'idle'),
          hold: const Duration(milliseconds: 1200),
        );
      case IdleAction.none:
        break;
    }
    if (a != IdleAction.none) onIdleAction?.call(a);
  }

  /// Touch / voice / chat input.
  void interact() {
    final a = idle.interact();
    if (a == IdleAction.wakeUp) {
      show(
        const DetectedEmotion(Emotion.surprised, 0.5, source: 'idle'),
        hold: const Duration(milliseconds: 1200),
      );
    }
  }

  /// Show an emotion, then ease back to neutral after [hold].
  void show(DetectedEmotion d, {Duration hold = const Duration(seconds: 8)}) {
    emotion = d.emotion;
    intensity = d.intensity;
    source = d.source;
    _revert?.cancel();
    _revert = Timer(hold, () {
      emotion = Emotion.neutral;
      intensity = 0.5;
      source = 'idle';
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _revert?.cancel();
    _ticker?.cancel();
    _lookTimer?.cancel();
    super.dispose();
  }
}
