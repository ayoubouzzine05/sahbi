import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../personality/emotion.dart';
import '../personality/emotion_animation_mapper.dart';
import 'face_painter.dart';
import 'face_params.dart';

/// Inputs that drive the animated face.
class FaceInputs {
  const FaceInputs({
    this.emotion = Emotion.neutral,
    this.intensity = 0.5,
    this.speaking = false,
    this.listening = false,
    this.listenLevel = 0,
    this.music = false,
    this.lookAt,
  });

  final Emotion emotion;
  final double intensity;
  final bool speaking;
  final bool listening;
  final double listenLevel;
  final bool music;

  /// Gaze target from the idle engine / robot (-1..1), null = automatic.
  final Offset? lookAt;
}

/// The animated face: blinking at random intervals, gaze (automatic or
/// following touch), breathing, smooth emotion transitions and a speaking
/// mouth driven by TTS word callbacks when available, otherwise a rhythmic
/// loop (approximate, NOT true lip-sync).
class RobotFace extends StatefulWidget {
  const RobotFace({
    super.key,
    required this.inputs,
    this.wordPulse,
    this.onTap,
    this.onLongPress,
    this.animate = true,
    this.fullScreen = false,
    this.semanticLabel,
  });

  final FaceInputs inputs;
  final ValueListenable<int>? wordPulse;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// false = static frame (golden tests).
  final bool animate;

  /// Dashboard mode: draw only eyes/brows/mouth over the whole area.
  final bool fullScreen;
  final String? semanticLabel;

  @override
  State<RobotFace> createState() => _RobotFaceState();
}

class _RobotFaceState extends State<RobotFace>
    with SingleTickerProviderStateMixin {
  static const _mapper = EmotionAnimationMapper();
  final _rand = math.Random();
  late final Ticker _ticker;
  late FaceParams _current;
  Duration _last = Duration.zero;
  double _t = 0;

  // blink
  double _nextBlink = 2.5;
  double _blinkStart = -1;

  // gaze
  Offset _gazeTarget = Offset.zero;
  Offset _gaze = Offset.zero;
  double _nextGaze = 1.5;
  Offset? _touch;

  // mouth
  double _mouthEnv = 0;
  double _lastPulseT = -10;
  int _lastPulse = 0;

  final ValueNotifier<int> _repaint = ValueNotifier(0);

  FaceSpec get _spec {
    final i = widget.inputs;
    final e = i.listening
        ? Emotion.listening
        : i.music && !i.speaking
        ? Emotion.music
        : i.speaking && i.emotion == Emotion.neutral
        ? Emotion.speaking
        : i.emotion;
    return _mapper.map(e, i.intensity);
  }

  @override
  void initState() {
    super.initState();
    _current = _spec.params;
    _ticker = createTicker(_tick);
    if (widget.animate) _ticker.start();
    widget.wordPulse?.addListener(_onPulse);
  }

  @override
  void didUpdateWidget(RobotFace old) {
    super.didUpdateWidget(old);
    if (old.wordPulse != widget.wordPulse) {
      old.wordPulse?.removeListener(_onPulse);
      widget.wordPulse?.addListener(_onPulse);
    }
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  void _onPulse() {
    final v = widget.wordPulse!.value;
    if (v != _lastPulse) {
      _lastPulse = v;
      _lastPulseT = _t;
      _mouthEnv = 1;
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _t += dt;
    final spec = _spec;
    final target = spec.params;

    // Smooth emotion transition (exponential approach; never snaps).
    final k = 1 - math.exp(-dt * 7);
    _current = FaceParams.lerp(_current, target, k);

    // Blink at randomised intervals (not while sleeping/closed eyes).
    if (_blinkStart < 0 && _t >= _nextBlink && target.eyeOpen > 0.3) {
      _blinkStart = _t;
    }
    if (_blinkStart >= 0 && _t - _blinkStart > 0.16) {
      _blinkStart = -1;
      // Occasional double blink.
      _nextBlink =
          _t + (_rand.nextDouble() < 0.15 ? 0.25 : 2 + _rand.nextDouble() * 4);
    }

    // Gaze.
    final i = widget.inputs;
    if (_touch != null) {
      _gazeTarget = _touch!;
    } else if (i.lookAt != null) {
      _gazeTarget = i.lookAt!;
    } else if (_t >= _nextGaze) {
      _gazeTarget = switch (spec.gaze) {
        GazeBehavior.wander => Offset(
          _rand.nextDouble() * 1.6 - 0.8,
          _rand.nextDouble() * 0.8 - 0.4,
        ),
        GazeBehavior.focus => Offset(
          _rand.nextDouble() * 0.3 - 0.15,
          _rand.nextDouble() * 0.2 - 0.1,
        ),
        GazeBehavior.dart => Offset(
          _rand.nextDouble() * 2 - 1,
          _rand.nextDouble() - 0.5,
        ),
        GazeBehavior.down => Offset(_rand.nextDouble() * 0.4 - 0.2, 0.7),
        GazeBehavior.up => Offset(_rand.nextDouble() * 0.8 - 0.4, -0.7),
        GazeBehavior.rest => Offset.zero,
      };
      _nextGaze =
          _t +
          switch (spec.gaze) {
            GazeBehavior.dart => 0.4 + _rand.nextDouble() * 0.6,
            GazeBehavior.focus => 1.2 + _rand.nextDouble() * 1.5,
            _ => 1.5 + _rand.nextDouble() * 2.5,
          };
    }
    final gk = 1 - math.exp(-dt * (_touch != null ? 14 : 6));
    _gaze = Offset.lerp(_gaze, _gazeTarget, gk)!;

    // Mouth while speaking.
    var mouth = _current.mouthOpen;
    if (i.speaking) {
      final recentPulse = _t - _lastPulseT < 0.45;
      if (recentPulse) {
        _mouthEnv = math.max(0, _mouthEnv - dt * 5);
        mouth = math.max(mouth, 0.15 + 0.6 * _mouthEnv);
      } else {
        // Approximate syllable rhythm (~4.5 Hz with variation).
        final syll =
            (math.sin(_t * 2 * math.pi * 4.5) +
                math.sin(_t * 2 * math.pi * 2.3) * 0.5 +
                1.5) /
            3;
        mouth = math.max(mouth, 0.1 + 0.55 * syll.clamp(0, 1));
      }
    }
    // Music bob.
    var tilt = _current.tilt;
    if (i.music && !i.speaking) tilt += math.sin(_t * 2 * math.pi * 1.0) * 0.06;

    _current = _current.copyWith(
      gazeX: _gaze.dx.clamp(-1, 1),
      gazeY: _gaze.dy.clamp(-1, 1),
    );
    // Music: the eye colour slowly cycles through the rainbow.
    final accent = i.music && !i.speaking
        ? Color.lerp(
            _current.accent,
            HSVColor.fromAHSV(1, (_t * 45) % 360, 0.6, 1).toColor(),
            0.75,
          )!
        : _current.accent;
    _frameParams = _current.copyWith(
      mouthOpen: mouth,
      tilt: tilt,
      accent: accent,
    );
    _repaint.value++;
  }

  FaceParams? _frameParams;

  double get _blinkAmount {
    if (_blinkStart < 0) return 0;
    final x = ((_t - _blinkStart) / 0.16).clamp(0.0, 1.0);
    return math.sin(x * math.pi);
  }

  void _updateTouch(Offset local, Size size) {
    setState(() {
      _touch = Offset(
        ((local.dx / size.width) * 2 - 1).clamp(-1, 1),
        ((local.dy / size.height) * 2 - 1).clamp(-1, 1),
      );
    });
  }

  @override
  void dispose() {
    widget.wordPulse?.removeListener(_onPulse);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(
          c.maxWidth,
          c.maxHeight.isFinite ? c.maxHeight : c.maxWidth,
        );
        return Semantics(
          label: widget.semanticLabel ?? 'Sahbi',
          button: widget.onTap != null,
          // Expose only meaningful actions to TalkBack; the drag-to-look pan
          // would otherwise show up as four bogus "scroll" actions.
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onPanStart: (d) => _updateTouch(d.localPosition, size),
            onPanUpdate: (d) => _updateTouch(d.localPosition, size),
            onPanEnd: (_) => setState(() => _touch = null),
            onPanCancel: () => setState(() => _touch = null),
            child: RepaintBoundary(
              child: ValueListenableBuilder<int>(
                valueListenable: _repaint,
                builder: (context, _, _) => CustomPaint(
                  size: size,
                  painter: FacePainter(
                    FaceFrame(
                      params: widget.animate
                          ? (_frameParams ?? _current)
                          : _spec.params,
                      blink: widget.animate ? _blinkAmount : 0,
                      breath: widget.animate
                          ? math.sin(_t * 2 * math.pi / 4)
                          : 0,
                      time: _t,
                      listening: widget.inputs.listening,
                      listenLevel: widget.inputs.listenLevel,
                      musicNotes:
                          widget.inputs.music && !widget.inputs.speaking,
                      fullScreen: widget.fullScreen,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
