import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/voice/robot_voice_fx.dart';

Uint8List sine(double hz, int n, {int sr = 24000, double amp = 0.5}) {
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    b.setInt16(
      i * 2,
      (amp * 32767 * math.sin(2 * math.pi * hz * i / sr)).round(),
      Endian.little,
    );
  }
  return b.buffer.asUint8List();
}

List<int> samples(Uint8List pcm) {
  final d = ByteData.sublistView(pcm);
  return [
    for (var i = 0; i < pcm.length ~/ 2; i++) d.getInt16(i * 2, Endian.little),
  ];
}

/// Zero crossings per second ≈ 2 × frequency.
double freq(List<int> s, int sr) {
  var z = 0;
  for (var i = 1; i < s.length; i++) {
    if ((s[i - 1] < 0) != (s[i] < 0)) z++;
  }
  return z / 2 / (s.length / sr);
}

Uint8List wav(Uint8List pcm, int sr) {
  final h = ByteData(44);
  void tag(int o, String t) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, sr, Endian.little);
  h.setUint32(28, sr * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...pcm]);
}

void main() {
  test('raises the pitch by the chosen factor, same length', () {
    final inp = sine(200, 24000);
    final fx = RobotVoiceFx(sampleRate: 24000, metal: 0);
    final out = fx.process(inp);
    expect(out.length, inp.length);
    final f = freq(samples(out).sublist(2400), 24000);
    expect(f, closeTo(200 * robotVoicePitch, 200 * robotVoicePitch * 0.08));
  });

  test('streaming in chunks equals one block (no clicks between chunks)', () {
    final inp = sine(180, 12000);
    final a = RobotVoiceFx(sampleRate: 24000).process(inp);
    final fx = RobotVoiceFx(sampleRate: 24000);
    final parts = <int>[];
    for (var o = 0; o < inp.length; o += 1234) {
      parts.addAll(
        fx.process(
          Uint8List.sublistView(inp, o, math.min(o + 1234, inp.length)),
        ),
      );
    }
    expect(parts, a);
  });

  test('no clipping on a loud voice; silence stays silent', () {
    final loud = samples(
      RobotVoiceFx(sampleRate: 24000).process(sine(150, 24000, amp: 0.95)),
    );
    expect(
      loud.where((v) => v.abs() >= 32767).length,
      lessThan(loud.length ~/ 100),
    );
    final quiet = samples(
      RobotVoiceFx(sampleRate: 24000).process(Uint8List(4800)),
    );
    expect(quiet.every((v) => v == 0), isTrue);
  });

  test(
    'WAV from the backup voice gets the same effect; other files untouched',
    () {
      final w = wav(sine(200, 4800), 24000);
      final out = RobotVoiceFx.processWav(w);
      expect(out.length, w.length);
      expect(out.sublist(0, 44), w.sublist(0, 44));
      expect(out.sublist(44), isNot(w.sublist(44)));
      final mp3 = Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(60, 1)]);
      expect(RobotVoiceFx.processWav(mp3), mp3);
      expect(parseWav(w)!.sampleRate, 24000);
    },
  );

  test('chosen settings: C (small robot)', () {
    expect(robotVoicePitch, 1.55);
    expect(robotVoiceMetal, 0.6);
    expect(robotDevicePitch, greaterThan(1));
  });
}
