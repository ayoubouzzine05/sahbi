import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme.dart';
import '../../core/zellige.dart';
import 'face_params.dart';

/// Everything that changes per frame on top of [FaceParams].
class FaceFrame {
  const FaceFrame({
    required this.params,
    this.blink = 0,
    this.breath = 0,
    this.time = 0,
    this.listening = false,
    this.listenLevel = 0,
    this.musicNotes = false,
  });

  final FaceParams params;

  /// 0..1 extra eyelid closure from blinking.
  final double blink;

  /// -1..1 breathing phase.
  final double breath;

  /// seconds, for subtle shimmer and music notes.
  final double time;
  final bool listening;
  final double listenLevel;
  final bool musicNotes;
}

/// Draws SAHBI: a white rounded body, a dark glossy visor and glowing eyes.
/// All shapes are procedural; no image assets.
class FacePainter extends CustomPainter {
  FacePainter(this.frame);
  final FaceFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final p = frame.params;
    final s = math.min(size.width, size.height / 1.05);
    final center = Offset(size.width / 2, size.height / 2);
    final breathScale = 1 + 0.012 * frame.breath;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(p.tilt);
    canvas.scale(breathScale, 1 + 0.018 * frame.breath);
    canvas.translate(-center.dx, -center.dy);

    // ---- body ---------------------------------------------------------------
    final bodyRect = Rect.fromCenter(center: center, width: s * 0.92, height: s * 0.84);
    final body = RRect.fromRectAndRadius(bodyRect, Radius.circular(s * 0.3));
    canvas.drawRRect(
      body.shift(Offset(0, s * 0.03)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFFFFFFFF), SahbiColors.body, SahbiColors.bodyShade],
          stops: const [0, 0.55, 1],
        ).createShader(bodyRect),
    );
    // Ear pods with accent LEDs (pulse when listening).
    final podGlow = frame.listening ? 0.5 + 0.5 * frame.listenLevel : 0.25 + 0.1 * p.glow;
    for (final side in [-1.0, 1.0]) {
      final podC = Offset(center.dx + side * bodyRect.width / 2, center.dy);
      final pod = RRect.fromRectAndRadius(
        Rect.fromCenter(center: podC, width: s * 0.07, height: s * 0.2),
        Radius.circular(s * 0.035),
      );
      canvas.drawRRect(pod, Paint()..color = SahbiColors.bodyShade);
      canvas.drawCircle(
        podC,
        s * 0.018,
        Paint()
          ..color = p.accent.withValues(alpha: podGlow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
      );
    }
    // Khatem emblem on the forehead, engraved.
    canvas.drawPath(
      khatemOutline(Offset(center.dx, bodyRect.top + s * 0.075), s * 0.03),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.005
        ..color = SahbiColors.turquoise.withValues(alpha: 0.55),
    );

    // ---- visor ---------------------------------------------------------------
    final visorRect = Rect.fromCenter(
      center: center.translate(0, s * 0.02),
      width: bodyRect.width * 0.8,
      height: bodyRect.height * 0.66,
    );
    final visor = RRect.fromRectAndRadius(visorRect, Radius.circular(s * 0.2));
    canvas.drawRRect(visor, Paint()..color = SahbiColors.visor);
    canvas.drawRRect(
      visor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008
        ..color = p.accent.withValues(alpha: 0.18 + 0.12 * p.glow),
    );
    canvas.save();
    canvas.clipRRect(visor);
    // faint zellige inside the visor
    canvas.save();
    canvas.translate(visorRect.left, visorRect.top);
    ZelligePainter(color: p.accent, opacity: 0.045, cell: s * 0.16).paint(canvas, visorRect.size);
    canvas.restore();

    // ---- eyes -----------------------------------------------------------------
    final eyeW = s * 0.15 * p.eyeScale;
    final eyeH = s * 0.2 * p.eyeScale;
    final eyeY = visorRect.center.dy - s * 0.035;
    final gaze = Offset(p.gazeX * s * 0.05, p.gazeY * s * 0.035);
    final open = (p.eyeOpen * (1 - frame.blink)).clamp(0.0, 1.0);
    for (final side in [-1.0, 1.0]) {
      final c = Offset(visorRect.center.dx + side * s * 0.15, eyeY) + gaze;
      _eye(canvas, c, eyeW, eyeH, open, p, side, s);
    }

    // ---- brows ----------------------------------------------------------------
    final browPaint = Paint()
      ..color = p.accent.withValues(alpha: 0.85)
      ..strokeWidth = s * 0.02
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      final bc = Offset(
        visorRect.center.dx + side * s * 0.15 + gaze.dx * 0.6,
        eyeY - eyeH / 2 - s * (0.035 + 0.04 * p.browLift),
      );
      final angle = p.browAngle * 0.35 * side; // inner end down when angry
      final dx = math.cos(angle) * s * 0.06;
      final dy = math.sin(angle) * s * 0.06;
      canvas.drawLine(bc - Offset(dx, dy), bc + Offset(dx, dy), browPaint);
    }

    // ---- cheeks ---------------------------------------------------------------
    if (p.blush > 0.01) {
      for (final side in [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(visorRect.center.dx + side * s * 0.25, eyeY + eyeH * 0.6),
            width: s * 0.09,
            height: s * 0.045,
          ),
          Paint()
            ..color = const Color(0xFFFF8FA3).withValues(alpha: 0.35 * p.blush)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.015),
        );
      }
    }

    // ---- mouth ----------------------------------------------------------------
    _mouth(canvas, Offset(visorRect.center.dx + gaze.dx * 0.3, visorRect.center.dy + s * 0.15), p, s);

    // ---- listening ring / music notes -------------------------------------------
    if (frame.musicNotes) _notes(canvas, visorRect, p, s);
    // glossy reflection
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(visorRect.left + s * 0.04, visorRect.top + s * 0.03, visorRect.width * 0.5, s * 0.05),
        Radius.circular(s * 0.03),
      ),
      Paint()..color = const Color(0x12FFFFFF),
    );
    canvas.restore(); // visor clip

    if (frame.listening) {
      final r = visor.inflate(s * (0.012 + 0.02 * frame.listenLevel));
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.01
          ..color = SahbiColors.green.withValues(alpha: 0.35 + 0.5 * frame.listenLevel),
      );
    }
    canvas.restore();
  }

  void _eye(Canvas canvas, Offset c, double w, double h, double open, FaceParams p, double side, double s) {
    final rect = Rect.fromCenter(center: c, width: w, height: h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.45));
    canvas.save();
    // Upper lid: clip from the top according to openness.
    final visibleTop = rect.top + h * (1 - open) * 0.98;
    // Lower lid curve for smiles ("^ ^").
    final smileLift = h * 0.55 * p.eyeSmile;
    final clip = Path()
      ..moveTo(rect.left - 2, visibleTop)
      ..lineTo(rect.right + 2, visibleTop)
      ..lineTo(rect.right + 2, rect.bottom + 2)
      ..quadraticBezierTo(c.dx, rect.bottom + 2 - smileLift * 2.2, rect.left - 2, rect.bottom + 2)
      ..close();
    canvas.clipPath(clip);
    // glow
    canvas.drawRRect(
      rr.inflate(s * 0.012),
      Paint()
        ..color = p.accent.withValues(alpha: 0.35 * p.glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.9,
          colors: [Color.lerp(p.accent, const Color(0xFFFFFFFF), 0.45)!, p.accent],
        ).createShader(rect),
    );
    // pupil (darker iris) + highlight
    final pr = w * (0.18 + 0.16 * p.pupilSize);
    final pc = c + Offset(p.gazeX * w * 0.12, p.gazeY * h * 0.1);
    canvas.drawCircle(pc, pr, Paint()..color = SahbiColors.visor.withValues(alpha: 0.55));
    canvas.drawCircle(pc + Offset(-pr * 0.35, -pr * 0.4), pr * 0.32, Paint()..color = const Color(0xE6FFFFFF));
    canvas.restore();
    // When nearly closed, draw a lash line so the eye never "disappears".
    if (open < 0.12) {
      final y = rect.top + h * (1 - open) * 0.98;
      canvas.drawLine(
        Offset(rect.left + w * 0.1, y.clamp(rect.top, rect.bottom)),
        Offset(rect.right - w * 0.1, y.clamp(rect.top, rect.bottom)),
        Paint()
          ..color = p.accent.withValues(alpha: 0.8)
          ..strokeWidth = s * 0.012
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _mouth(Canvas canvas, Offset c, FaceParams p, double s) {
    final w = s * 0.12 * p.mouthWidth;
    final curve = p.mouthCurve * s * 0.045;
    final openH = p.mouthOpen * s * 0.07;
    final paint = Paint()
      ..color = p.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.016
      ..strokeCap = StrokeCap.round;
    if (openH < s * 0.006) {
      final path = Path()
        ..moveTo(c.dx - w / 2, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + curve * 2, c.dx + w / 2, c.dy);
      canvas.drawPath(path, paint);
      return;
    }
    final path = Path()
      ..moveTo(c.dx - w / 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy + curve * 1.4 - openH * 0.3, c.dx + w / 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy + curve * 1.4 + openH * 1.6, c.dx - w / 2, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = p.accent.withValues(alpha: 0.9));
    // tongue hint
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(
      Offset(c.dx, c.dy + curve * 1.4 + openH * 1.1),
      w * 0.28,
      Paint()..color = const Color(0xFFFF8FA3).withValues(alpha: 0.6),
    );
    canvas.restore();
  }

  void _notes(Canvas canvas, Rect visor, FaceParams p, double s) {
    final paint = Paint()..color = p.accent.withValues(alpha: 0.7);
    for (var i = 0; i < 3; i++) {
      final t = (frame.time * 0.4 + i / 3) % 1.0;
      final x = visor.left + visor.width * (0.15 + 0.35 * i) + math.sin(t * math.pi * 2) * s * 0.02;
      final y = visor.bottom - visor.height * t;
      final a = math.sin(t * math.pi);
      paint.color = p.accent.withValues(alpha: 0.6 * a);
      canvas.drawCircle(Offset(x, y), s * 0.012, paint);
      canvas.drawLine(
        Offset(x + s * 0.011, y),
        Offset(x + s * 0.011, y - s * 0.04),
        Paint()
          ..color = paint.color
          ..strokeWidth = s * 0.005,
      );
    }
  }

  @override
  bool shouldRepaint(FacePainter old) => true;
}
