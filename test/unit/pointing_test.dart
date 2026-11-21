import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sahbi/core/backend_client.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/features/live/pointing.dart';

void main() {
  test('locateOn posts the PNG + tap and parses the box', () async {
    late Map<String, dynamic> sent;
    final client = BackendClient(
      baseUrl: () => 'https://sahbi.example',
      store: MemoryKeyValueStore(),
      client: MockClient((req) async {
        if (req.url.path == '/v1/auth/anonymous') {
          return http.Response(
            jsonEncode({'token': 't', 'expires_in': 9}),
            200,
          );
        }
        expect(req.url.path, '/v1/vision/locate');
        expect(req.headers['authorization'], 'Bearer t');
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'found': true,
            'by': 'tap',
            'label': 'سوري',
            'name_en': 'mouse',
            'box': {'left': 0.7, 'top': 0.6, 'right': 0.8, 'bottom': 0.75},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final frame = UprightFrame(Uint8List.fromList([1, 2, 3]), 3, 4);
    final o = await locateOn(
      client,
      frame,
      tap: (x: 0.73, y: 0.69),
      language: 'ar',
    );
    expect(sent['mime'], 'image/png');
    expect(sent['image'], base64Encode([1, 2, 3]));
    expect(sent['tap'], {'x': 0.73, 'y': 0.69});
    expect(sent['language'], 'ar');
    expect(o!.label, 'سوري');
    expect(o.box.left, 0.7);
  });

  group('LocatedObject.fromJson', () {
    test('parses a found object', () {
      final o = LocatedObject.fromJson({
        'found': true,
        'by': 'tap',
        'label': 'كاس',
        'name_en': 'cup',
        'box': {'left': 0.2, 'top': 0.1, 'right': 0.6, 'bottom': 0.5},
      })!;
      expect(o.box, const Rect.fromLTRB(0.2, 0.1, 0.6, 0.5));
      expect(o.byTap, isTrue);
      expect(o.display, 'كاس');
      expect(o.liveCue, 'POINT: cup / كاس');
    });

    test('null when not found or malformed', () {
      expect(LocatedObject.fromJson({'found': false}), isNull);
      expect(LocatedObject.fromJson({'found': true}), isNull);
      expect(
        LocatedObject.fromJson({
          'found': true,
          'box': {'left': 0.5, 'top': 0.5, 'right': 0.5, 'bottom': 0.9},
        }),
        isNull,
      );
    });

    test('cue without names still says POINT', () {
      final o = LocatedObject.fromJson({
        'found': true,
        'box': {'left': 0, 'top': 0, 'right': 0.5, 'bottom': 0.5},
      })!;
      expect(o.liveCue, startsWith('POINT:'));
      expect(o.display, '');
    });
  });

  group('cover mapping (camera picture drawn with BoxFit.cover)', () {
    const screen = Size(400, 800);

    test('portrait 3:4 image on a tall screen is cropped left and right', () {
      final r = coverRect(screen, 3 / 4);
      expect(r.height, 800);
      expect(r.width, closeTo(600, 1e-9));
      expect(r.left, closeTo(-100, 1e-9));
    });

    test('screen centre is image centre; taps outside the image are null', () {
      final p = screenToImage(const Offset(200, 400), screen, 3 / 4)!;
      expect(p.x, closeTo(0.5, 1e-9));
      expect(p.y, closeTo(0.5, 1e-9));
      expect(screenToImage(const Offset(200, 900), screen, 3 / 4), isNull);
    });

    test('front camera preview is mirrored', () {
      final p = screenToImage(const Offset(50, 400), screen, 3 / 4)!;
      final m = screenToImage(
        const Offset(50, 400),
        screen,
        3 / 4,
        mirror: true,
      )!;
      expect(m.x, closeTo(1 - p.x, 1e-9));
    });

    test('box → screen → point round-trips', () {
      const box = Rect.fromLTRB(0.25, 0.3, 0.75, 0.6);
      final r = imageBoxToScreen(box, screen, 9 / 16);
      final tl = screenToImage(r.topLeft, screen, 9 / 16)!;
      expect(tl.x, closeTo(0.25, 1e-9));
      expect(tl.y, closeTo(0.3, 1e-9));
    });
  });

  test('mentionsThis: Darija, Arabizi, French, English', () {
    for (final s in [
      'chno hada?',
      'hadi chnou hiya',
      'شنو هادي؟',
      'وا هادشي زوين',
      "c'est quoi ça",
      'what is this',
    ]) {
      expect(mentionsThis(s), isTrue, reason: s);
    }
    for (final s in ['salam', 'kidayr', 'شنو سميتك', 'bonjour']) {
      expect(mentionsThis(s), isFalse, reason: s);
    }
  });

  test('locateLanguage maps reply languages', () {
    expect(locateLanguage('darija'), 'ar');
    expect(locateLanguage('ar'), 'ar');
    expect(locateLanguage('fr'), 'fr');
    expect(locateLanguage('en'), 'en');
  });

  testWidgets('uprightFrame downsizes and re-encodes as PNG', (tester) async {
    final frame = await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 600, 800),
        Paint()..color = const Color(0xFF3366FF),
      );
      final img = await rec.endRecording().toImage(600, 800);
      final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
      return uprightFrame(png.buffer.asUint8List(), maxSide: 400);
    });
    expect(frame, isNotNull);
    expect(frame!.height, 400);
    expect(frame.width, 300);
    expect(frame.png.sublist(1, 4), 'PNG'.codeUnits);
  });

  testWidgets('highlight painter draws a box and a tap ring', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: CustomPaint(
          size: const Size(400, 800),
          painter: PointHighlightPainter(
            aspect: 3 / 4,
            box: const Rect.fromLTRB(0.2, 0.2, 0.6, 0.5),
            label: 'كاس',
            tap: const Offset(150, 300),
            busy: true,
            pulse: 0.5,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
