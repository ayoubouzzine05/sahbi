import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme.dart';
import 'face_params.dart';

/// Short one-shot face "skits" played on top of the current emotion
/// (inspired by how desktop robot pets act out little scenes; every shape
/// here is original and procedural: a Moroccan tea glass, a ka3b ghzal
/// cookie, round robot mitten hands, hearts and stars).
enum FaceAct {
  /// Nibbles a ka3b ghzal cookie (3 bites, chewing, happy eyes).
  eat,

  /// Sips a glass of mint tea (eyes closed, "aaah").
  drink,

  /// Raises both hands and waves.
  handsUp,

  /// Hides the eyes behind both hands, then "bouh!".
  peekaboo,

  /// Heart eyes, floating hearts, blush.
  love,

  /// Big yawn with a hand over the mouth.
  yawn,

  /// Hands up, alternating, head bobbing, music notes.
  dance,

  /// Starry, excited eyes.
  sparkle,

  /// Narrow eyes sliding left and right ("hmm…").
  suspicious,

  /// One big eye, one small eye ("what?!").
  what,

  /// Eyes squashed by a finger poke.
  squish,

  /// Woken up by a touch: sleepy-angry orange eyes.
  grumpy,

  /// Frightened by something it sees: small trembling eyes, worried brows,
  /// a sweat drop.
  scared,
}

extension FaceActInfo on FaceAct {
  Duration get duration => switch (this) {
    FaceAct.eat => const Duration(milliseconds: 3600),
    FaceAct.drink => const Duration(milliseconds: 3800),
    FaceAct.handsUp => const Duration(milliseconds: 3000),
    FaceAct.peekaboo => const Duration(milliseconds: 3400),
    FaceAct.love => const Duration(milliseconds: 3000),
    FaceAct.yawn => const Duration(milliseconds: 3200),
    FaceAct.dance => const Duration(milliseconds: 4200),
    FaceAct.sparkle => const Duration(milliseconds: 2600),
    FaceAct.suspicious => const Duration(milliseconds: 3200),
    FaceAct.what => const Duration(milliseconds: 2400),
    FaceAct.squish => const Duration(milliseconds: 700),
    FaceAct.grumpy => const Duration(milliseconds: 3600),
    FaceAct.scared => const Duration(milliseconds: 3000),
  };

  /// Name used by the brain action `face.play {animation}`.
  String get wire => switch (this) {
    FaceAct.handsUp => 'hands_up',
    _ => name,
  };

  static FaceAct? fromWire(Object? s) {
    if (s is! String) return null;
    for (final a in FaceAct.values) {
      if (a.wire == s || a.name == s) return a;
    }
    return null;
  }
}

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

double _smooth(double x) => x * x * (3 - 2 * x);

/// 0 → 1 between [a] and [b], holds, 1 → 0 between [c] and [d].
double _bump(double t, double a, double b, double c, double d) =>
    _smooth(_seg(t, a, b)) * (1 - _smooth(_seg(t, c, d)));

/// Overall strength of the act at progress [t] (blends in and out).
double actEnvelope(FaceAct act, double t) => switch (act) {
  FaceAct.squish => _bump(t, 0, 0.2, 0.55, 1),
  _ => _bump(t, 0, 0.12, 0.85, 1),
};

const _pink = Color(0xFFFF6FA0);
const _orange = Color(0xFFFF8A3D);
const _red = Color(0xFFFF4A3D);

/// Face parameters while [act] plays (blended with [p] by the envelope).
FaceParams applyAct(FaceAct act, double t, double time, FaceParams p) {
  final env = actEnvelope(act, t);
  if (env <= 0) return p;
  final FaceParams target;
  switch (act) {
    case FaceAct.eat:
      final chew = t > 0.25 && t < 0.85
          ? (math.sin(time * 12).abs() * 0.5)
          : 0.0;
      target = p.copyWith(
        eyeOpen: 0.7,
        eyeSmile: 0.8,
        mouthOpen: chew,
        mouthCurve: 0.6,
        blush: 0.6 * _seg(t, 0.6, 0.9),
        gazeY: 0.2,
      );
    case FaceAct.drink:
      final sip = _bump(t, 0.28, 0.36, 0.74, 0.8);
      final aah = _bump(t, 0.8, 0.85, 0.95, 1);
      target = p.copyWith(
        eyeOpen: 1 - 0.88 * sip,
        eyeSmile: 0.5 * sip + 0.7 * aah,
        mouthOpen: 0.5 * aah,
        mouthCurve: 0.5,
        blush: 0.5 * aah,
      );
    case FaceAct.handsUp:
      target = p.copyWith(
        eyeScale: 1.08,
        eyeSmile: 0.45,
        mouthOpen: 0.35,
        mouthCurve: 0.8,
      );
    case FaceAct.dance:
      target = p.copyWith(
        eyeSmile: 0.8,
        mouthCurve: 0.9,
        mouthOpen: 0.2,
        tilt: math.sin(time * 6) * 0.12,
      );
    case FaceAct.peekaboo:
      final bouh = _bump(t, 0.58, 0.64, 0.82, 0.92);
      target = p.copyWith(
        eyeScale: 1 + 0.22 * bouh,
        pupilSize: 0.3,
        mouthOpen: 0.65 * bouh,
        mouthWidth: 0.7,
        browLift: 0.8 * bouh,
      );
    case FaceAct.love:
      target = p.copyWith(
        accent: Color.lerp(p.accent, _pink, 0.8),
        blush: 1,
        mouthCurve: 1,
        eyeSmile: 0.2,
      );
    case FaceAct.yawn:
      final shut = _seg(t, 0.1, 0.45);
      final mouth = _bump(t, 0.15, 0.45, 0.72, 0.85);
      target = p.copyWith(
        eyeOpen: 1 - 0.92 * shut * (1 - _seg(t, 0.8, 0.95) * 0.5),
        mouthOpen: mouth,
        mouthWidth: 0.8,
        mouthCurve: 0,
        browLift: 0.4 * mouth,
      );
    case FaceAct.sparkle:
      target = p.copyWith(
        eyeScale: 1.15,
        pupilSize: 0.9,
        eyeSmile: 0.3,
        mouthCurve: 0.9,
        mouthOpen: 0.25,
        glow: 1,
      );
    case FaceAct.suspicious:
      final gx = t < 0.4
          ? -0.85 * _smooth(_seg(t, 0.1, 0.3))
          : t < 0.75
          ? -0.85 + 1.7 * _smooth(_seg(t, 0.42, 0.62))
          : 0.85 * (1 - _smooth(_seg(t, 0.75, 0.9)));
      target = p.copyWith(
        eyeOpen: 0.32,
        browAngle: 0.5,
        browLift: -0.3,
        mouthCurve: -0.1,
        mouthWidth: 0.6,
        mouthOpen: 0,
        gazeX: gx,
        tilt: -0.06,
      );
    case FaceAct.what:
      target = p.copyWith(
        mouthOpen: 0.35,
        mouthWidth: 0.4,
        browLift: 0.8,
        tilt: 0.08,
        pupilSize: 0.2,
      );
    case FaceAct.squish:
      target = p.copyWith(mouthOpen: 0.3, mouthWidth: 0.4);
    case FaceAct.grumpy:
      final mad = _bump(t, 0.4, 0.5, 0.75, 0.85);
      target = p.copyWith(
        accent: Color.lerp(_orange, _red, mad),
        eyeOpen: 0.35 + 0.15 * mad,
        eyeSmile: 0,
        browAngle: 0.4 + 0.6 * mad,
        browLift: -0.2,
        mouthCurve: -0.5,
        mouthOpen: 0,
      );
    case FaceAct.scared:
      // A jump back at first, then shivering.
      final jump = _bump(t, 0, 0.06, 0.18, 0.3);
      final shiver = math.sin(time * 42) * 0.07 * (1 - jump);
      target = p.copyWith(
        eyeOpen: 1,
        eyeSmile: 0,
        pupilSize: 0.15,
        browLift: 0.9,
        browAngle: -0.5,
        mouthCurve: -0.7,
        mouthOpen: 0.25 + 0.25 * jump,
        mouthWidth: 0.5,
        gazeX: shiver,
        tilt: shiver * 0.6,
      );
  }
  return FaceParams.lerp(p, target, env);
}

/// Per-eye geometry tweaks while an act plays.
class ActEyes {
  const ActEyes({
    this.leftScale = 1,
    this.rightScale = 1,
    this.squashY = 1,
    this.heart = 0,
  });
  final double leftScale;
  final double rightScale;

  /// < 1 = squashed flat (and a little wider).
  final double squashY;

  /// 0..1: the eyes turn into hearts.
  final double heart;

  static const none = ActEyes();
}

ActEyes actEyes(FaceAct? act, double t) {
  if (act == null) return ActEyes.none;
  final env = actEnvelope(act, t);
  return switch (act) {
    FaceAct.what => ActEyes(
      leftScale: 1 + 0.32 * env,
      rightScale: 1 - 0.3 * env,
    ),
    FaceAct.squish => ActEyes(squashY: 1 - 0.5 * env),
    FaceAct.love => ActEyes(heart: env),
    FaceAct.scared => ActEyes(
      leftScale: 1 - 0.2 * env,
      rightScale: 1 - 0.2 * env,
      squashY: 1 + 0.12 * env,
    ),
    _ => ActEyes.none,
  };
}

/// Geometry of the face, so props line up with the eyes and the mouth.
class FaceLayout {
  const FaceLayout({
    required this.centerX,
    required this.eyeY,
    required this.mouthY,
    required this.eyeDx,
    required this.s,
    this.halfWidth = double.infinity,
  });
  final double centerX;
  final double eyeY;
  final double mouthY;

  /// Horizontal distance of each eye from the centre.
  final double eyeDx;
  final double s;

  /// Half the drawable width (props stay inside it).
  final double halfWidth;

  /// x of a hand of size [u] beside the eyes on [side], kept on screen.
  double handX(double side, double u, [double far = 2.0]) =>
      centerX + side * math.min(eyeDx * far, halfWidth - u * 0.75);
}

/// Draws the props of [act] (hands, cookie, tea glass, hearts, stars...).
void paintActProps(
  Canvas canvas,
  FaceAct act,
  double t,
  double time,
  FaceLayout g,
  Color accent,
) {
  final s = g.s;
  final env = actEnvelope(act, t);
  switch (act) {
    case FaceAct.eat:
      _paintEat(canvas, t, g);
    case FaceAct.drink:
      _paintDrink(canvas, t, time, g);
    case FaceAct.handsUp:
      final up = _bump(t, 0, 0.25, 0.8, 1);
      final wave = math.sin(time * 9) * 0.35;
      for (final side in [-1.0, 1.0]) {
        final u = s * 0.11;
        final pos = Offset(
          g.handX(side, u),
          _lerp(g.mouthY + s * 0.55, g.eyeY - s * 0.08, up),
        );
        _hand(canvas, pos, u, side * wave, side, up);
      }
    case FaceAct.dance:
      final up = _bump(t, 0, 0.15, 0.85, 1);
      for (final side in [-1.0, 1.0]) {
        final phase = math.sin(time * 6 + (side > 0 ? math.pi : 0));
        final u = s * 0.1;
        final pos = Offset(
          g.handX(side, u),
          _lerp(g.mouthY + s * 0.55, g.eyeY + s * 0.04 - phase * s * 0.08, up),
        );
        _hand(canvas, pos, u, side * phase * 0.3, side, up);
      }
      _notes(canvas, time, g, accent, env);
    case FaceAct.peekaboo:
      final cover = _smooth(_seg(t, 0, 0.22));
      final open = _smooth(_seg(t, 0.55, 0.65));
      final down = _smooth(_seg(t, 0.75, 0.95));
      for (final side in [-1.0, 1.0]) {
        final eye = Offset(g.centerX + side * g.eyeDx, g.eyeY);
        final start = Offset(eye.dx, g.mouthY + s * 0.6);
        final aside = Offset(g.handX(side, s * 0.14, 2.1), g.eyeY);
        var pos = Offset.lerp(start, eye, cover)!;
        pos = Offset.lerp(pos, aside, open)!;
        pos = Offset.lerp(pos, Offset(aside.dx, g.mouthY + s * 0.6), down)!;
        _hand(canvas, pos, s * 0.14, side * -0.15, side, 1 - down);
      }
    case FaceAct.love:
      for (var i = 0; i < 4; i++) {
        final k = (time * 0.45 + i / 4) % 1.0;
        final x =
            g.centerX +
            (i.isEven ? -1 : 1) * g.eyeDx * (1.6 + 0.4 * i / 4) +
            math.sin(k * math.pi * 2) * s * 0.02;
        final y = g.mouthY + s * 0.1 - k * s * 0.5;
        _heart(
          canvas,
          Offset(x, y),
          s * 0.035,
          _pink.withValues(alpha: 0.7 * math.sin(k * math.pi) * env),
        );
      }
    case FaceAct.yawn:
      final cover = _bump(t, 0.35, 0.45, 0.68, 0.8);
      if (cover > 0) {
        _hand(
          canvas,
          Offset(
            g.centerX + s * 0.04,
            _lerp(g.mouthY + s * 0.5, g.mouthY + s * 0.03, cover),
          ),
          s * 0.11,
          -0.25,
          1,
          cover,
        );
      }
    case FaceAct.sparkle:
      const spots = [
        Offset(-2.3, -0.9),
        Offset(2.2, -1.1),
        Offset(-2.6, 0.6),
        Offset(2.5, 0.5),
        Offset(0, -1.6),
      ];
      for (var i = 0; i < spots.length; i++) {
        final tw = (math.sin(time * 7 + i * 1.7) + 1) / 2;
        _star(
          canvas,
          Offset(
            g.centerX + spots[i].dx * g.eyeDx,
            g.eyeY + spots[i].dy * s * 0.12,
          ),
          s * (0.02 + 0.025 * tw),
          accent.withValues(alpha: (0.4 + 0.6 * tw) * env),
        );
      }
      for (final side in [-1.0, 1.0]) {
        _star(
          canvas,
          Offset(g.centerX + side * g.eyeDx - s * 0.02, g.eyeY - s * 0.03),
          s * 0.03,
          const Color(0xFFFFFFFF).withValues(alpha: 0.95 * env),
        );
      }
    case FaceAct.scared:
      // A sweat drop sliding down next to one eye.
      final slide = _seg(t, 0.15, 0.95);
      final c = Offset(
        g.centerX + g.eyeDx * 1.75,
        g.eyeY - s * 0.06 + s * 0.08 * slide,
      );
      final r = s * 0.028;
      final drop = Path()
        ..moveTo(c.dx, c.dy - r * 2.2)
        ..quadraticBezierTo(c.dx + r * 1.1, c.dy - r * 0.2, c.dx, c.dy + r)
        ..quadraticBezierTo(
          c.dx - r * 1.1,
          c.dy - r * 0.2,
          c.dx,
          c.dy - r * 2.2,
        )
        ..close();
      canvas.drawPath(
        drop,
        Paint()..color = const Color(0xFF8FD8FF).withValues(alpha: 0.9 * env),
      );
      // Little shiver lines on both sides.
      final shake = Paint()
        ..color = accent.withValues(alpha: 0.55 * env)
        ..strokeWidth = s * 0.008
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final side in [-1.0, 1.0]) {
        for (var i = 0; i < 3; i++) {
          final x = g.centerX + side * (g.eyeDx * 2.3 + i * s * 0.022);
          final w = math.sin(time * 40 + i) * s * 0.006;
          canvas.drawLine(
            Offset(x + w, g.eyeY - s * 0.04),
            Offset(x - w, g.eyeY + s * 0.04),
            shake,
          );
        }
      }
    case FaceAct.what:
    case FaceAct.squish:
    case FaceAct.suspicious:
    case FaceAct.grumpy:
      break;
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Cartoon robot hand (palm towards the viewer): a rounded palm, four
/// short rounded fingers and a thumb on the inner side.
void _hand(
  Canvas canvas,
  Offset c,
  double u,
  double rotation,
  double side,
  double alpha,
) {
  if (alpha <= 0) return;
  final a = alpha.clamp(0.0, 1.0);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(rotation);
  var shape = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, u * 0.15), width: u * 1.1, height: u),
        Radius.circular(u * 0.38),
      ),
    );
  Path capsule(Offset at, double w, double h, double angle) {
    final m = Matrix4.identity()
      ..translateByDouble(at.dx, at.dy, 0, 1)
      ..rotateZ(angle);
    return (Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(0, -h / 2), width: w, height: h),
            Radius.circular(w / 2),
          ),
        ))
        .transform(m.storage);
  }

  const fingers = [-0.39, -0.13, 0.13, 0.39];
  const lengths = [0.5, 0.62, 0.6, 0.48];
  for (var i = 0; i < 4; i++) {
    shape = Path.combine(
      PathOperation.union,
      shape,
      capsule(
        Offset(fingers[i] * u, -u * 0.2),
        u * 0.24,
        u * lengths[i] + u * 0.2,
        fingers[i] * 0.35,
      ),
    );
  }
  // Thumb on the side facing the face.
  shape = Path.combine(
    PathOperation.union,
    shape,
    capsule(Offset(-side * u * 0.45, u * 0.35), u * 0.26, u * 0.6, -side * 1.0),
  );
  canvas.drawPath(
    shape,
    Paint()..color = SahbiColors.body.withValues(alpha: a),
  );
  canvas.drawPath(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.05
      ..color = SahbiColors.bodyShade.withValues(alpha: a),
  );
  // Palm line.
  canvas.drawArc(
    Rect.fromCenter(
      center: Offset(0, u * 0.25),
      width: u * 0.5,
      height: u * 0.3,
    ),
    0.2,
    math.pi - 0.4,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.04
      ..strokeCap = StrokeCap.round
      ..color = SahbiColors.bodyShade.withValues(alpha: 0.7 * a),
  );
  canvas.restore();
}

/// Ka3b ghzal (crescent almond cookie) that loses three bites.
void _paintEat(Canvas canvas, double t, FaceLayout g) {
  final s = g.s;
  final arrive = _smooth(_seg(t, 0, 0.2));
  final fade = 1 - _seg(t, 0.78, 0.86);
  if (fade <= 0) return;
  final start = Offset(g.centerX + s * 0.5, g.mouthY + s * 0.4);
  final at = Offset(g.centerX + s * 0.14, g.mouthY + s * 0.01);
  final c = Offset.lerp(start, at, arrive)!;
  final r = s * 0.075;
  var cookie = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: c, radius: r)),
    Path()..addOval(
      Rect.fromCircle(
        center: c.translate(r * 0.45, -r * 0.35),
        radius: r * 0.85,
      ),
    ),
  );
  final bites = [0.32, 0.5, 0.68].where((b) => t >= b).length;
  for (var i = 0; i < bites; i++) {
    cookie = Path.combine(
      PathOperation.difference,
      cookie,
      Path()..addOval(
        Rect.fromCircle(
          center: c.translate(-r * (0.9 - i * 0.45), -r * (0.2 - i * 0.55)),
          radius: r * 0.42,
        ),
      ),
    );
  }
  canvas.drawPath(
    cookie,
    Paint()..color = const Color(0xFFF2D49B).withValues(alpha: fade),
  );
  canvas.drawPath(
    cookie,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.006
      ..color = const Color(0xFFC9A062).withValues(alpha: fade),
  );
  // Crumbs falling after each bite.
  for (final b in [0.32, 0.5, 0.68]) {
    final k = _seg(t, b, b + 0.12);
    if (k <= 0 || k >= 1) continue;
    for (var j = 0; j < 3; j++) {
      canvas.drawCircle(
        at.translate(-r * 0.6 + j * r * 0.35, r * 0.4 + k * s * 0.18),
        s * 0.006,
        Paint()..color = const Color(0xFFF2D49B).withValues(alpha: 1 - k),
      );
    }
  }
}

/// A Moroccan mint-tea glass: amber tea, golden band, a mint leaf, steam.
void _paintDrink(Canvas canvas, double t, double time, FaceLayout g) {
  final s = g.s;
  final arrive = _smooth(_seg(t, 0, 0.2));
  final leave = _smooth(_seg(t, 0.82, 0.95));
  if (leave >= 1) return;
  final tiltAmt = _bump(t, 0.25, 0.35, 0.75, 0.82);
  final level = 0.8 - 0.65 * _seg(t, 0.35, 0.75);
  final home = Offset(g.centerX + s * 0.17, g.mouthY + s * 0.02);
  final low = Offset(g.centerX + s * 0.45, g.mouthY + s * 0.5);
  final c = Offset.lerp(Offset.lerp(low, home, arrive)!, low, leave)!;
  final h = s * 0.16;
  final wt = s * 0.11;
  final wb = s * 0.08;
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(-0.7 * tiltAmt);
  final glass = Path()
    ..moveTo(-wt / 2, -h / 2)
    ..lineTo(wt / 2, -h / 2)
    ..lineTo(wb / 2, h / 2)
    ..lineTo(-wb / 2, h / 2)
    ..close();
  canvas.drawPath(glass, Paint()..color = const Color(0x26FFFFFF));
  canvas.save();
  canvas.clipPath(glass);
  final top = h / 2 - h * level;
  canvas.drawRect(
    Rect.fromLTRB(-wt, top, wt, h / 2),
    Paint()..color = const Color(0xFFC77A22).withValues(alpha: 0.9),
  );
  // Golden band.
  canvas.drawRect(
    Rect.fromLTRB(-wt, -h * 0.32, wt, -h * 0.2),
    Paint()..color = const Color(0xFFE6B84A).withValues(alpha: 0.85),
  );
  canvas.restore();
  canvas.drawPath(
    glass,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.006
      ..color = const Color(0xCCFFFFFF),
  );
  // Mint leaf.
  canvas.save();
  canvas.translate(-wt * 0.15, -h / 2 - s * 0.012);
  canvas.rotate(-0.6);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: s * 0.025, height: s * 0.05),
    Paint()..color = const Color(0xFF3DBE6A),
  );
  canvas.restore();
  canvas.restore();
  // Steam before the first sip.
  final steam = 1 - _seg(t, 0.3, 0.4);
  if (steam > 0 && leave == 0) {
    for (var i = 0; i < 2; i++) {
      final path = Path();
      for (var k = 0; k <= 12; k++) {
        final f = k / 12;
        final x =
            c.dx +
            (i - 0.5) * s * 0.03 +
            math.sin(f * 6 + time * 4 + i) * s * 0.01;
        final y = c.dy - h / 2 - s * 0.02 - f * s * 0.08;
        k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.006
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35 * steam),
      );
    }
  }
}

Path heartPath(Offset c, double r) {
  return Path()
    ..moveTo(c.dx, c.dy + r * 0.95)
    ..cubicTo(
      c.dx - r * 1.9,
      c.dy - r * 0.2,
      c.dx - r * 0.9,
      c.dy - r * 1.35,
      c.dx,
      c.dy - r * 0.45,
    )
    ..cubicTo(
      c.dx + r * 0.9,
      c.dy - r * 1.35,
      c.dx + r * 1.9,
      c.dy - r * 0.2,
      c.dx,
      c.dy + r * 0.95,
    )
    ..close();
}

void _heart(Canvas canvas, Offset c, double r, Color color) {
  canvas.drawPath(heartPath(c, r), Paint()..color = color);
}

void _star(Canvas canvas, Offset c, double r, Color color) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4 - math.pi / 2;
    final rr = i.isEven ? r : r * 0.32;
    final pt = c + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  p.close();
  canvas.drawPath(p, Paint()..color = color);
}

void _notes(
  Canvas canvas,
  double time,
  FaceLayout g,
  Color accent,
  double env,
) {
  final s = g.s;
  for (var i = 0; i < 3; i++) {
    final k = (time * 0.5 + i / 3) % 1.0;
    final x = g.centerX + (i - 1) * g.eyeDx * 1.6 + math.sin(k * 6) * s * 0.02;
    final y = g.eyeY - s * 0.12 - k * s * 0.25;
    final a = math.sin(k * math.pi) * env;
    final paint = Paint()..color = accent.withValues(alpha: 0.7 * a);
    canvas.drawCircle(Offset(x, y), s * 0.014, paint);
    canvas.drawLine(
      Offset(x + s * 0.013, y),
      Offset(x + s * 0.013, y - s * 0.045),
      Paint()
        ..color = paint.color
        ..strokeWidth = s * 0.006,
    );
  }
}
