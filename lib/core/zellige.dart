import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Procedural khatem (8-point star, two overlapping squares) path centred on [c].
Path khatemPath(Offset c, double r) {
  final path = Path();
  for (var k = 0; k < 2; k++) {
    final rot = k * math.pi / 4;
    for (var i = 0; i < 4; i++) {
      final a = rot + i * math.pi / 2 + math.pi / 4;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
  }
  return path;
}

/// Outline-only 16-vertex star (the union outline of the khatem).
Path khatemOutline(Offset c, double r) {
  final path = Path();
  final inner = r * math.cos(math.pi / 4) / math.cos(math.pi / 8);
  for (var i = 0; i < 16; i++) {
    final a = i * math.pi / 8 + math.pi / 8;
    final rr = i.isEven ? r : inner;
    final p = c + Offset(math.cos(a), math.sin(a)) * rr;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// Subtle zellige tiling: khatem stars on a square lattice joined by
/// small crosses, drawn as thin strokes so it stays elegant, not heavy.
class ZelligePainter extends CustomPainter {
  ZelligePainter({
    this.color = SahbiColors.turquoise,
    this.opacity = 0.06,
    this.cell = 72,
    this.phase = 0,
  });

  final Color color;
  final double opacity;
  final double cell;

  /// 0..1, used by loaders to rotate/pulse the pattern.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: opacity);
    final fill = Paint()..color = color.withValues(alpha: opacity * 0.5);
    final r = cell * 0.36;
    for (var y = -cell; y < size.height + cell; y += cell) {
      final row = (y / cell).round();
      for (var x = -cell; x < size.width + cell; x += cell) {
        final c = Offset(x + (row.isOdd ? cell / 2 : 0), y);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(phase * math.pi / 4);
        canvas.translate(-c.dx, -c.dy);
        canvas.drawPath(khatemOutline(c, r), stroke);
        canvas.drawPath(khatemOutline(c, r * 0.45), stroke);
        canvas.restore();
        canvas.drawCircle(c + Offset(cell / 2, 0), 1.6, fill);
      }
    }
  }

  @override
  bool shouldRepaint(ZelligePainter old) =>
      old.color != color ||
      old.opacity != opacity ||
      old.cell != cell ||
      old.phase != phase;
}

/// Full-screen background: dark gradient + faint zellige.
class ZelligeBackground extends StatelessWidget {
  const ZelligeBackground({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.5),
          radius: 1.3,
          colors: [Color(0xFF0E1A2C), SahbiColors.background],
        ),
      ),
      child: CustomPaint(
        painter: ZelligePainter(color: accent ?? SahbiColors.turquoise),
        child: child,
      ),
    );
  }
}

/// Loading indicator: a slowly rotating khatem star.
class ZelligeLoader extends StatefulWidget {
  const ZelligeLoader({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  State<ZelligeLoader> createState() => _ZelligeLoaderState();
}

class _ZelligeLoaderState extends State<ZelligeLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'loading',
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _StarPainter(
              _c.value,
              widget.color ?? SahbiColors.turquoise,
            ),
          ),
        ),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * math.pi / 2);
    canvas.translate(-c.dx, -c.dy);
    final pulse = 0.75 + 0.25 * math.sin(t * math.pi * 2);
    canvas.drawPath(
      khatemOutline(c, size.width / 2 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    canvas.drawCircle(c, size.width * 0.08, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.t != t || old.color != color;
}

/// A rounded card with a fine zellige border strip on top.
class ZelligeCard extends StatelessWidget {
  const ZelligeCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SahbiColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SahbiColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 6,
            child: CustomPaint(
              painter: ZelligePainter(opacity: 0.35, cell: 14),
            ),
          ),
          // Transparent Material so ListTile/InkWell ripples paint above the
          // card's coloured decoration instead of being hidden by it.
          Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
