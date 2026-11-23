import 'dart:math' as math;
import 'dart:typed_data';

/// SAHBI's small-robot voice (the user picked "C"): the same speaking voice,
/// pitched up (smaller, cuter) with a light metallic ring, like a little
/// desktop robot. Streaming, sample by sample, so it works on audio as it
/// arrives (no added delay beyond a few milliseconds).
///
/// Pitch shift: a delay-line shifter with two read heads cross-faded with
/// sin² windows (their gains always sum to 1). Metal: a 1.3 ms comb (ring
/// resonance) and a gentle 55 Hz ring modulation.
class RobotVoiceFx {
  RobotVoiceFx({
    required this.sampleRate,
    this.pitch = robotVoicePitch,
    this.metal = robotVoiceMetal,
    double windowMs = 36,
  }) : _w = (sampleRate * windowMs / 1000).round(),
       _cd = (sampleRate * 0.0013).round();

  final int sampleRate;
  final double pitch;
  final double metal;
  final int _w;
  final int _cd;

  static const _n = 4096; // ring buffer (power of two)
  static const _cn = 256;
  final Float64List _buf = Float64List(_n);
  final Float64List _comb = Float64List(_cn);
  int _wi = 0, _ci = 0, _t = 0;
  double _ph = 0;

  /// Clears the state between sentences.
  void reset() {
    _buf.fillRange(0, _n, 0);
    _comb.fillRange(0, _cn, 0);
    _wi = _ci = _t = 0;
    _ph = 0;
  }

  double _sample(double v) {
    _buf[_wi] = v;
    var y = 0.0;
    for (final k in const [0.0, 0.5]) {
      final ph = (_ph + k) % 1.0;
      final r = _wi - (ph * _w + 1);
      final i0 = r.floor();
      final f = r - i0;
      final a = _buf[i0 & (_n - 1)];
      final b = _buf[(i0 + 1) & (_n - 1)];
      final s = math.sin(math.pi * ph);
      y += s * s * (a + (b - a) * f);
    }
    _ph = (_ph - (pitch - 1) / _w) % 1.0;
    _wi = (_wi + 1) & (_n - 1);
    if (metal > 0) {
      final c = _comb[(_ci - _cd) & (_cn - 1)];
      _comb[_ci] = y;
      _ci = (_ci + 1) & (_cn - 1);
      y = y + metal * 0.55 * c;
      y *=
          1 -
          0.25 * metal +
          0.25 * metal * math.sin(2 * math.pi * 55 * _t / sampleRate);
    }
    _t++;
    // The comb adds up to +33 % level: keep a little headroom.
    return y * (1 / (1 + metal * 0.55));
  }

  /// Processes 16-bit little-endian mono PCM and returns the same length.
  Uint8List process(Uint8List pcm) {
    final n = pcm.length ~/ 2;
    final inp = ByteData.sublistView(pcm, 0, n * 2);
    final out = Uint8List(n * 2);
    final o = ByteData.sublistView(out);
    for (var i = 0; i < n; i++) {
      final v = inp.getInt16(i * 2, Endian.little) / 32768.0;
      final y = (_sample(v) * 32767).round().clamp(-32768, 32767);
      o.setInt16(i * 2, y, Endian.little);
    }
    return out;
  }

  /// Applies the effect to a whole 16-bit PCM WAV file (other formats are
  /// returned unchanged).
  static Uint8List processWav(Uint8List wav) {
    final h = parseWav(wav);
    if (h == null) return wav;
    final fx = RobotVoiceFx(sampleRate: h.sampleRate);
    final body = fx.process(
      Uint8List.sublistView(wav, h.dataOffset, h.dataOffset + h.dataLength),
    );
    final out = Uint8List.fromList(wav);
    out.setRange(h.dataOffset, h.dataOffset + body.length, body);
    return out;
  }
}

/// Picked by the user: pitch ×1.55 and metal 0.6 (played 7 % faster too).
const robotVoicePitch = 1.55;
const robotVoiceMetal = 0.6;

/// Pitch for the phone's own TTS engine (last fallback), close to the robot.
const robotDevicePitch = 1.6;

/// Where the samples are in a mono 16-bit PCM WAV.
({int sampleRate, int dataOffset, int dataLength})? parseWav(Uint8List b) {
  if (b.length < 44) return null;
  final d = ByteData.sublistView(b);
  String tag(int o) => String.fromCharCodes(b.sublist(o, o + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  int? rate, channels, bits;
  var o = 12;
  while (o + 8 <= b.length) {
    final id = tag(o);
    final size = d.getUint32(o + 4, Endian.little);
    final body = o + 8;
    if (id == 'fmt ' && body + 16 <= b.length) {
      final format = d.getUint16(body, Endian.little);
      channels = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
      if (format != 1) return null;
    } else if (id == 'data') {
      if (rate == null || channels != 1 || bits != 16) return null;
      final len = math.min(size, b.length - body) & ~1;
      return (sampleRate: rate, dataOffset: body, dataLength: len);
    }
    o = body + size + (size & 1);
  }
  return null;
}
