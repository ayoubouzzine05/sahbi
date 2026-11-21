import 'dart:typed_data';
import 'dart:ui' as ui;

/// Tiny grey-scale picture of a camera frame (16×12 = 192 values, 0..255).
typedef SceneSignature = Uint8List;

const sceneSigW = 16;
const sceneSigH = 12;

/// Decodes a JPEG straight to 16×12 pixels (cheap) and keeps the luminance.
Future<SceneSignature?> sceneSignature(Uint8List jpeg) async {
  try {
    final codec = await ui.instantiateImageCodec(
      jpeg,
      targetWidth: sceneSigW,
      targetHeight: sceneSigH,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    final rgba = data.buffer.asUint8List();
    final out = Uint8List(sceneSigW * sceneSigH);
    for (var i = 0; i < out.length && i * 4 + 2 < rgba.length; i++) {
      final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
      out[i] = (r * 77 + g * 150 + b * 29) >> 8;
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// Mean absolute difference between two signatures, 0..255. The overall
/// brightness change is removed first, so auto-exposure is not "motion".
double sceneDistance(SceneSignature a, SceneSignature b) {
  final n = a.length < b.length ? a.length : b.length;
  if (n == 0) return 255;
  var ma = 0, mb = 0;
  for (var i = 0; i < n; i++) {
    ma += a[i];
    mb += b[i];
  }
  final shift = (ma - mb) / n;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    sum += (a[i] - b[i] - shift).abs();
  }
  return sum / n;
}

/// Decides when the live robot should explain what the camera points at,
/// without being asked: when the camera has been held still for
/// [stableFrames] frames on something clearly different from what it last
/// explained, the robot and the user are both quiet, and at least [minGap]
/// passed since the last explanation.
class SceneWatcher {
  SceneWatcher({
    DateTime Function()? clock,
    this.stableFrames = 2,
    this.motionThreshold = 9,
    this.changeThreshold = 22,
    this.minGap = const Duration(seconds: 7),
    this.userQuietFor = const Duration(milliseconds: 2500),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final int stableFrames;

  /// Below this, two consecutive frames count as "held still".
  final double motionThreshold;

  /// Above this, the steady view is a new thing to explain.
  final double changeThreshold;
  final Duration minGap;
  final Duration userQuietFor;

  SceneSignature? _prev;
  SceneSignature? _described;
  int _stable = 0;
  DateTime? _lastLook;
  DateTime? _lastUserSpeech;

  /// The user said something (their words come first).
  void userSpoke() => _lastUserSpeech = _clock();

  /// The user asked about the current view themselves: do not repeat it.
  void markDescribed() {
    _described = _prev;
    _lastLook = _clock();
  }

  void reset() {
    _prev = null;
    _described = null;
    _stable = 0;
    _lastLook = null;
  }

  /// Feed every frame. Returns true when the robot should explain now.
  bool onFrame(SceneSignature sig, {required bool robotBusy}) {
    final now = _clock();
    final prev = _prev;
    _prev = sig;
    if (prev == null) {
      _stable = 0;
      return false;
    }
    if (sceneDistance(sig, prev) <= motionThreshold) {
      _stable++;
    } else {
      _stable = 0;
    }
    if (_stable < stableFrames || robotBusy) return false;
    final userTalked = _lastUserSpeech;
    if (userTalked != null && now.difference(userTalked) < userQuietFor) {
      return false;
    }
    final last = _lastLook;
    if (last != null && now.difference(last) < minGap) return false;
    final described = _described;
    if (described != null && sceneDistance(sig, described) < changeThreshold) {
      return false;
    }
    _described = sig;
    _lastLook = now;
    return true;
  }
}

/// Sent to the live model when the camera settles on something new (the
/// backend prompt explains it). Plain text, no user words.
const liveLookCue = 'LOOK';
