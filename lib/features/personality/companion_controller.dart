import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../behavior/behavior_models.dart';
import '../behavior/initiative_scheduler.dart';
import '../behavior/mimo_behavior_engine.dart';
import '../face/face_act.dart';
import 'emotion.dart';
import 'emotion_detector.dart';
import 'idle_behavior.dart';
import 'temper.dart';

/// Owns the conversational emotion shown on the face and the idle engine.
class CompanionController extends ChangeNotifier {
  CompanionController({
    IdleBehavior? idle,
    this.busy,
    math.Random? random,
    Temper? temper,
    MimoBehaviorEngine? behavior,
  }) : idle = idle ?? IdleBehavior(),
       _r = random ?? math.Random(),
       temper = temper ?? Temper(random: random),
       behavior =
           behavior ??
           MimoBehaviorEngine(
             scheduler: InitiativeScheduler(isQuiet: _defaultQuiet),
             random: random,
           );

  static bool _defaultQuiet(int h) => h >= 23 || h < 8;

  final IdleBehavior idle;

  /// MIMO's autonomous moods (idle, curious, playful, bored, sleepy,
  /// listening) and initiatives. Hardware-neutral: the phone face applies
  /// its commands here; a robot body can apply the same ones.
  final MimoBehaviorEngine behavior;

  /// Current autonomous mood and how the eyes behave in it.
  MimoState get mood => behavior.state;
  EyeStyle get eyes => behavior.eyes;

  /// MIMO decided to say / play something by itself.
  void Function(InitiativeKind kind)? onInitiative;

  /// The mood changed (robot link mirrors it).
  void Function(MimoState state)? onMood;

  /// Feeds an event to the behaviour engine and performs its commands.
  void behave(BehaviorEvent e) => _perform(behavior.on(e));

  void _perform(List<BodyCommand> cmds) {
    for (final c in cmds) {
      switch (c) {
        case SetMood(:final state):
          onMood?.call(state);
          notifyListeners();
        case LookAt(:final x, :final y, :final holdMs):
          glance(Offset(x, y), hold: Duration(milliseconds: holdMs));
        case PlaySkit(:final name):
          final a = FaceActInfo.fromWire(name);
          if (a != null && !acting && !dizzy && !temper.sulking) play(a);
        case TakeInitiative(:final kind):
          onInitiative?.call(kind);
      }
    }
  }

  /// Strong character: annoyed, sulking, making up (see [Temper]).
  final Temper temper;
  bool _wasSulking = false;
  double _sulkSide = 1;

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
  Timer? _dizzyTimer;

  /// Spiral eyes after the phone was shaken.
  bool dizzy = false;

  /// Current face skit (eat, drink, hands up...); restarts when [actSeq]
  /// changes. The face ends it by itself after its duration.
  FaceAct? act;
  int actSeq = 0;
  DateTime? _actUntil;

  /// Seconds of calm before the robot acts out a little scene by itself.
  int _skitIn = 60;

  bool get acting {
    final u = _actUntil;
    return u != null && DateTime.now().isBefore(u);
  }

  /// Plays a skit now (replaces the one playing).
  void play(FaceAct a) {
    act = a;
    actSeq++;
    _actUntil = DateTime.now().add(a.duration);
    notifyListeners();
  }

  /// Stroked on the face: heart eyes and a happy face. While sulking it
  /// takes about two strokes; returns 'madeUp', 'stillSulking' or 'happy'.
  String pet() {
    idle.interact();
    behave(BehaviorEvent.touched);
    _resetSkit();
    final wasSulking = temper.sulking;
    if (!temper.pet()) {
      show(
        const DetectedEmotion(Emotion.sad, 0.4, source: 'touch'),
        hold: const Duration(seconds: 3),
      );
      return 'stillSulking';
    }
    _endSulkFace();
    play(FaceAct.love);
    show(
      const DetectedEmotion(Emotion.happy, 0.9, source: 'touch'),
      hold: const Duration(seconds: 4),
    );
    return wasSulking ? 'madeUp' : 'happy';
  }

  /// A finger poke on the face (not asleep): squish, grumble or sulk.
  PokeReaction poke() {
    idle.interact();
    behave(BehaviorEvent.touched);
    _resetSkit();
    final r = temper.poke();
    switch (r) {
      case PokeReaction.squish:
        play(FaceAct.squish);
      case PokeReaction.annoyed:
        play(FaceAct.squish);
        show(
          const DetectedEmotion(Emotion.angry, 0.45, source: 'touch'),
          hold: const Duration(seconds: 4),
        );
      case PokeReaction.sulk:
        startSulkFace();
      case PokeReaction.ignore:
        // Sulking: a small "hmph", stays turned away.
        play(FaceAct.suspicious);
    }
    return r;
  }

  /// Looks at [g] for a moment (the eyes follow movement it sees). Not
  /// while sulking (it stays turned away) or asleep.
  void glance(Offset g, {Duration hold = const Duration(milliseconds: 1500)}) {
    if (temper.sulking || idle.asleep || dizzy) return;
    if (hold <= const Duration(milliseconds: 1500)) {
      // A short glance = something moved in front of the eyes.
      final cmds = behavior.on(BehaviorEvent.motion);
      if (cmds.isNotEmpty) _perform(cmds);
    }
    lookAt = g;
    _lookTimer?.cancel();
    _lookTimer = Timer(hold, () {
      lookAt = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Turned away with a pout until the sulk ends.
  void startSulkFace() {
    final until = temper.sulkUntil;
    if (until == null) return;
    _wasSulking = true;
    _sulkSide = _r.nextBool() ? 1 : -1;
    lookAt = Offset(0.95 * _sulkSide, 0.15);
    _lookTimer?.cancel();
    show(
      const DetectedEmotion(Emotion.angry, 0.35, source: 'temper'),
      hold: until.difference(DateTime.now()),
    );
  }

  void _endSulkFace() {
    if (!_wasSulking) return;
    _wasSulking = false;
    lookAt = null;
    notifyListeners();
  }

  /// Called by name ("MIMO"): the eyes snap wide and look straight at the
  /// user (woken up first if asleep).
  void heardName() {
    interact();
    behave(BehaviorEvent.wake);
    if (temper.sulking) {
      // Still sulking: a quick side glance, then turned away again.
      glance(Offset.zero, hold: const Duration(milliseconds: 700));
      return;
    }
    play(FaceAct.what);
    glance(Offset.zero, hold: const Duration(milliseconds: 2500));
  }

  /// Apology / sweet word: forgiven, heart eyes.
  void madeUp() {
    _endSulkFace();
    play(FaceAct.love);
    show(
      const DetectedEmotion(Emotion.happy, 0.85, source: 'temper'),
      hold: const Duration(seconds: 4),
    );
  }

  void _resetSkit() => _skitIn = 45 + _r.nextInt(60);

  /// Idle scenes, chosen at random, silent and offline.
  FaceAct _randomSkit() {
    final long = idle.idleFor >= const Duration(minutes: 5);
    final pool = [
      FaceAct.eat,
      FaceAct.drink,
      FaceAct.sparkle,
      FaceAct.suspicious,
      FaceAct.dance,
      if (long) FaceAct.yawn,
    ];
    return pool[_r.nextInt(pool.length)];
  }

  void makeDizzy(Duration d) {
    dizzy = true;
    _dizzyTimer?.cancel();
    _dizzyTimer = Timer(d, () {
      dizzy = false;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Fired when the idle engine yawns / falls asleep / wakes up.
  void Function(IdleAction action)? onIdleAction;

  void start() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final isBusy = busy?.call() ?? false;
    final a = idle.tick(busy: isBusy);
    _perform(behavior.tick());
    if (a == IdleAction.fallAsleep) behave(BehaviorEvent.fellAsleep);
    if (a == IdleAction.wakeUp) behave(BehaviorEvent.wokeUp);
    final sulking = temper.sulking;
    if (_wasSulking && !sulking) _endSulkFace();
    if (sulking && _wasSulking) {
      // Keeps the head turned away (the idle "look around" is skipped).
      final want = Offset(0.95 * _sulkSide, 0.15);
      if (lookAt != want) {
        lookAt = want;
        notifyListeners();
      }
    }
    if (isBusy || idle.asleep || !idle.enabled || dizzy || sulking) {
      _resetSkit();
    } else if (a == IdleAction.none && !acting && --_skitIn <= 0) {
      _resetSkit();
      play(_randomSkit());
    }
    switch (a) {
      case IdleAction.lookAround:
        if (sulking) break;
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
      case IdleAction.chatter: // handled by onIdleAction (the AI talks)
      case IdleAction.none:
        break;
    }
    if (a != IdleAction.none) onIdleAction?.call(a);
  }

  /// Touch / voice / chat input. Woken up by a [touch] while asleep, the
  /// robot is grumpy for a moment (orange, then a short angry flash).
  void interact({bool touch = false}) {
    final a = idle.interact();
    _resetSkit();
    behave(touch ? BehaviorEvent.touched : BehaviorEvent.userSpoke);
    if (a == IdleAction.wakeUp) behave(BehaviorEvent.wokeUp);
    if (a == IdleAction.wakeUp) {
      if (touch) {
        play(FaceAct.grumpy);
        show(
          const DetectedEmotion(Emotion.angry, 0.4, source: 'touch'),
          hold: FaceAct.grumpy.duration,
        );
        return;
      }
      show(
        const DetectedEmotion(Emotion.surprised, 0.5, source: 'idle'),
        hold: const Duration(milliseconds: 1200),
      );
    }
  }

  /// Show an emotion, then ease back to neutral after [hold].
  void show(DetectedEmotion d, {Duration hold = const Duration(seconds: 8)}) {
    // A real surprise (not waking up) gets the "what?!" eyes.
    if (d.emotion == Emotion.surprised &&
        d.source != 'idle' &&
        d.intensity >= 0.5 &&
        !dizzy &&
        !acting) {
      play(FaceAct.what);
    }
    emotion = d.emotion;
    intensity = d.intensity;
    source = d.source;
    _revert?.cancel();
    _revert = Timer(hold, () {
      // Asleep: go back to the sleeping face, not to neutral.
      emotion = idle.asleep ? Emotion.sleepy : Emotion.neutral;
      intensity = idle.asleep ? 1 : 0.5;
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
    _dizzyTimer?.cancel();
    super.dispose();
  }
}
