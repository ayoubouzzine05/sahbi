import 'dart:ui' show Color, lerpDouble;

/// Continuous face parameters. Everything the painter needs, nothing else.
/// Transitions interpolate these values; they never snap.
class FaceParams {
  const FaceParams({
    this.eyeOpen = 1,
    this.eyeSmile = 0,
    this.eyeScale = 1,
    this.pupilSize = 0.5,
    this.browAngle = 0,
    this.browLift = 0.3,
    this.mouthCurve = 0.25,
    this.mouthOpen = 0,
    this.mouthWidth = 1,
    this.gazeX = 0,
    this.gazeY = 0,
    this.tilt = 0,
    this.glow = 0.6,
    this.blush = 0,
    this.accent = const Color(0xFF2ED3C6),
  });

  /// 0 = closed, 1 = fully open (upper lid).
  final double eyeOpen;

  /// 0..1 lower-lid curve (happy squint "^ ^").
  final double eyeSmile;

  /// Overall eye size multiplier (surprised > 1).
  final double eyeScale;

  /// 0..1 pupil/iris highlight size.
  final double pupilSize;

  /// -1..1. Positive = angry (inner ends down), negative = sad/worried.
  final double browAngle;

  /// 0..1 how high the brows sit.
  final double browLift;

  /// -1 frown .. 1 big smile.
  final double mouthCurve;

  /// 0..1 mouth opening.
  final double mouthOpen;

  /// 0.5..1.5 mouth width multiplier.
  final double mouthWidth;

  /// -1..1 gaze offsets.
  final double gazeX;
  final double gazeY;

  /// Head tilt in radians.
  final double tilt;

  /// 0..1 eye glow strength.
  final double glow;

  /// 0..1 cheek blush.
  final double blush;

  final Color accent;

  FaceParams copyWith({
    double? eyeOpen,
    double? eyeSmile,
    double? eyeScale,
    double? pupilSize,
    double? browAngle,
    double? browLift,
    double? mouthCurve,
    double? mouthOpen,
    double? mouthWidth,
    double? gazeX,
    double? gazeY,
    double? tilt,
    double? glow,
    double? blush,
    Color? accent,
  }) {
    return FaceParams(
      eyeOpen: eyeOpen ?? this.eyeOpen,
      eyeSmile: eyeSmile ?? this.eyeSmile,
      eyeScale: eyeScale ?? this.eyeScale,
      pupilSize: pupilSize ?? this.pupilSize,
      browAngle: browAngle ?? this.browAngle,
      browLift: browLift ?? this.browLift,
      mouthCurve: mouthCurve ?? this.mouthCurve,
      mouthOpen: mouthOpen ?? this.mouthOpen,
      mouthWidth: mouthWidth ?? this.mouthWidth,
      gazeX: gazeX ?? this.gazeX,
      gazeY: gazeY ?? this.gazeY,
      tilt: tilt ?? this.tilt,
      glow: glow ?? this.glow,
      blush: blush ?? this.blush,
      accent: accent ?? this.accent,
    );
  }

  static FaceParams lerp(FaceParams a, FaceParams b, double t) {
    double l(double x, double y) => lerpDouble(x, y, t)!;
    return FaceParams(
      eyeOpen: l(a.eyeOpen, b.eyeOpen),
      eyeSmile: l(a.eyeSmile, b.eyeSmile),
      eyeScale: l(a.eyeScale, b.eyeScale),
      pupilSize: l(a.pupilSize, b.pupilSize),
      browAngle: l(a.browAngle, b.browAngle),
      browLift: l(a.browLift, b.browLift),
      mouthCurve: l(a.mouthCurve, b.mouthCurve),
      mouthOpen: l(a.mouthOpen, b.mouthOpen),
      mouthWidth: l(a.mouthWidth, b.mouthWidth),
      gazeX: l(a.gazeX, b.gazeX),
      gazeY: l(a.gazeY, b.gazeY),
      tilt: l(a.tilt, b.tilt),
      glow: l(a.glow, b.glow),
      blush: l(a.blush, b.blush),
      accent: Color.lerp(a.accent, b.accent, t)!,
    );
  }

  /// Largest absolute difference across numeric fields (used by tests and
  /// to stop animating once settled).
  double distanceTo(FaceParams o) {
    final d = [
      eyeOpen - o.eyeOpen,
      eyeSmile - o.eyeSmile,
      eyeScale - o.eyeScale,
      pupilSize - o.pupilSize,
      browAngle - o.browAngle,
      browLift - o.browLift,
      mouthCurve - o.mouthCurve,
      mouthOpen - o.mouthOpen,
      mouthWidth - o.mouthWidth,
      gazeX - o.gazeX,
      gazeY - o.gazeY,
      tilt - o.tilt,
      glow - o.glow,
      blush - o.blush,
    ];
    return d.map((e) => e.abs()).reduce((a, b) => a > b ? a : b);
  }

  @override
  String toString() =>
      'FaceParams(open=$eyeOpen smile=$eyeSmile scale=$eyeScale brow=$browAngle '
      'mouth=$mouthCurve/$mouthOpen gaze=($gazeX,$gazeY))';
}
