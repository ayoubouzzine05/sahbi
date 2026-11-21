import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../core/backend_client.dart';

/// The object the user tapped or pointed at, as found by the backend
/// (`POST /v1/vision/locate`). [box] is 0..1 on the upright image.
class LocatedObject {
  const LocatedObject({
    required this.box,
    required this.byTap,
    this.label,
    this.nameEn,
  });

  final Rect box;
  final bool byTap;
  final String? label;
  final String? nameEn;

  /// Null when nothing was found or the reply is malformed.
  static LocatedObject? fromJson(Map<String, dynamic> j) {
    if (j['found'] != true) return null;
    final b = j['box'];
    if (b is! Map) return null;
    double? n(Object? v) => v is num ? v.toDouble().clamp(0.0, 1.0) : null;
    final l = n(b['left']), t = n(b['top']), r = n(b['right']);
    final bo = n(b['bottom']);
    if (l == null || t == null || r == null || bo == null) return null;
    if (r - l < 0.01 || bo - t < 0.01) return null;
    String? s(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return LocatedObject(
      box: Rect.fromLTRB(l, t, r, bo),
      byTap: j['by'] == 'tap',
      label: s(j['label']),
      nameEn: s(j['name_en']),
    );
  }

  /// Text shown on the green box.
  String get display => label ?? nameEn ?? '';

  /// Cue for the Gemini Live session (see backend `livePrompt`, POINT).
  String get liveCue {
    final names = {?nameEn, ?label}.join(' / ');
    return names.isEmpty ? 'POINT: the highlighted object' : 'POINT: $names';
  }
}

/// A camera frame decoded by Flutter (EXIF orientation applied, so it is
/// upright exactly as on screen), downscaled and re-encoded as PNG. The
/// object box from the backend is relative to this image.
class UprightFrame {
  const UprightFrame(this.png, this.width, this.height);
  final Uint8List png;
  final int width;
  final int height;
  double get aspect => width / height;
}

Future<UprightFrame?> uprightFrame(Uint8List jpeg, {int maxSide = 512}) async {
  try {
    final codec = await ui.instantiateImageCodec(jpeg);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    codec.dispose();
    final scale = math.min(1.0, maxSide / math.max(src.width, src.height));
    final w = math.max(1, (src.width * scale).round());
    final h = math.max(1, (src.height * scale).round());
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    src.dispose();
    final img = await rec.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) return null;
    return UprightFrame(data.buffer.asUint8List(), w, h);
  } catch (_) {
    return null;
  }
}

/// Where an image of [aspect] (w/h) lands when drawn with `BoxFit.cover`
/// over [screen] (centred, cropped on one axis).
Rect coverRect(Size screen, double aspect) {
  if (screen.isEmpty || aspect <= 0) return Offset.zero & screen;
  final screenAspect = screen.width / screen.height;
  if (aspect > screenAspect) {
    final w = screen.height * aspect;
    return Rect.fromLTWH((screen.width - w) / 2, 0, w, screen.height);
  }
  final h = screen.width / aspect;
  return Rect.fromLTWH(0, (screen.height - h) / 2, screen.width, h);
}

/// Screen point → 0..1 point on the image (null when outside it).
/// [mirror]: the preview is mirrored (front camera) but photos are not.
({double x, double y})? screenToImage(
  Offset p,
  Size screen,
  double aspect, {
  bool mirror = false,
}) {
  final r = coverRect(screen, aspect);
  var x = (p.dx - r.left) / r.width;
  final y = (p.dy - r.top) / r.height;
  if (x < 0 || x > 1 || y < 0 || y > 1) return null;
  if (mirror) x = 1 - x;
  return (x: x, y: y);
}

/// 0..1 image box → screen rectangle.
Rect imageBoxToScreen(Rect box, Size screen, double aspect) {
  final r = coverRect(screen, aspect);
  return Rect.fromLTRB(
    r.left + box.left * r.width,
    r.top + box.top * r.height,
    r.left + box.right * r.width,
    r.top + box.bottom * r.height,
  );
}

final _thisWords = RegExp(
  r'(^|[\s،,.?!؟])(hada|hadi|hadchi|hadik|hadak|had\s+\S+|chno\s+hada|ach\s+hada|'
  r'هادا|هادي|هاذا|هاذي|هادشي|هاديك|هاداك|هاد|هذا|هذه|'
  r'this|that|ça|ceci|cela|celui-ci|celle-ci|c.est\s+quoi)(?=$|[\s،,.?!؟])',
  caseSensitive: false,
  unicode: true,
);

/// True when the user says "this/that" (hada, هادي, ça…) while the camera is
/// on: they are probably pointing at something.
bool mentionsThis(String text) => _thisWords.hasMatch(text.toLowerCase());

/// Language code for `/v1/vision/locate` labels.
String locateLanguage(String replyLanguage) => switch (replyLanguage) {
  'fr' => 'fr',
  'en' => 'en',
  _ => 'ar',
};

/// Calls the backend; null when nothing was found.
Future<LocatedObject?> locateOn(
  BackendClient client,
  UprightFrame frame, {
  ({double x, double y})? tap,
  required String language,
}) async {
  final j = await client.locate(
    image: frame.png,
    mime: 'image/png',
    tap: tap,
    language: language,
  );
  return LocatedObject.fromJson(j);
}

const pointGreen = Color(0xFF3DFF8B);

/// Green highlight: soft dim outside the object, glowing rounded frame with
/// corner brackets, and the object name on a chip. While [busy], only a
/// pulsing ring at [tap] is shown.
class PointHighlightPainter extends CustomPainter {
  PointHighlightPainter({
    required this.aspect,
    this.box,
    this.tap,
    this.label,
    this.busy = false,
    this.pulse = 0,
    this.textDirection = TextDirection.rtl,
  });

  final double aspect;
  final Rect? box;
  final Offset? tap;
  final String? label;
  final bool busy;
  final double pulse;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final b = box;
    if (b != null) {
      final r = imageBoxToScreen(b, size, aspect).inflate(6);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
      // Dim everything else a little so the object stands out.
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRRect(rr),
        ),
        Paint()..color = const Color(0x55000000),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..color = pointGreen.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..color = pointGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      // Corner brackets.
      final c = math.min(26.0, math.min(r.width, r.height) / 3);
      final p = Paint()
        ..color = pointGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      for (final (o, dx, dy) in [
        (r.topLeft, 1.0, 1.0),
        (r.topRight, -1.0, 1.0),
        (r.bottomLeft, 1.0, -1.0),
        (r.bottomRight, -1.0, -1.0),
      ]) {
        canvas.drawLine(o, o + Offset(c * dx, 0), p);
        canvas.drawLine(o, o + Offset(0, c * dy), p);
      }
      final text = label;
      if (text != null && text.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              color: Color(0xFF04130A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: textDirection,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: size.width - 32);
        final w = tp.width + 20, h = tp.height + 10;
        var top = r.top - h - 8;
        if (top < 8) top = r.bottom + 8;
        if (top + h > size.height - 8) top = r.top + 8;
        final left = (r.center.dx - w / 2).clamp(8.0, size.width - w - 8);
        final chip = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, w, h),
          Radius.circular(h / 2),
        );
        canvas.drawRRect(chip, Paint()..color = pointGreen);
        tp.paint(canvas, Offset(left + 10, top + 5));
      }
    }
    final t = tap;
    if (t != null && (busy || b == null)) {
      final rad = 18 + 10 * pulse;
      canvas.drawCircle(
        t,
        rad,
        Paint()
          ..color = pointGreen.withValues(alpha: 1 - pulse * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(t, 5, Paint()..color = pointGreen);
    }
  }

  @override
  bool shouldRepaint(PointHighlightPainter old) =>
      old.box != box ||
      old.tap != tap ||
      old.label != label ||
      old.busy != busy ||
      old.pulse != pulse ||
      old.aspect != aspect;
}
