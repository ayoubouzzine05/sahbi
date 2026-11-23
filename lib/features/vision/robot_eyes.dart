import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../face/face_act.dart';
import '../live/scene_watcher.dart';

/// Where movement is in the picture, as a gaze for the face: x and y in
/// -1..1 from the robot's point of view (front camera, not mirrored, so
/// something on the user's right is on the image's left and the robot looks
/// to the screen's right). Null when nothing moved, or when almost
/// everything changed (the phone moved, the light changed).
Offset? motionGaze(
  SceneSignature prev,
  SceneSignature cur, {
  double threshold = 22,
  int minCells = 3,
  double maxShare = 0.6,
}) {
  final n = prev.length < cur.length ? prev.length : cur.length;
  if (n != sceneSigW * sceneSigH) return null;
  var ma = 0, mb = 0;
  for (var i = 0; i < n; i++) {
    ma += prev[i];
    mb += cur[i];
  }
  final shift = (mb - ma) / n;
  var sx = 0.0, sy = 0.0, sw = 0.0;
  var cells = 0;
  for (var i = 0; i < n; i++) {
    final d = (cur[i] - prev[i] - shift).abs();
    if (d < threshold) continue;
    cells++;
    final x = (i % sceneSigW + 0.5) / sceneSigW;
    final y = (i ~/ sceneSigW + 0.5) / sceneSigH;
    sx += x * d;
    sy += y * d;
    sw += d;
  }
  if (cells < minCells || cells > n * maxShare || sw == 0) return null;
  final cx = sx / sw, cy = sy / sw;
  return Offset(
    (1 - 2 * cx).clamp(-1.0, 1.0),
    ((cy - 0.5) * 1.2).clamp(-0.6, 0.6),
  );
}

/// Face skit for a reaction from `/v1/vision/react` (null = just the
/// emotion and the line).
FaceAct? reactionAct(Object? reaction) => switch (reaction) {
  'hello' => FaceAct.handsUp,
  'scared' => FaceAct.scared,
  'love' => FaceAct.love,
  'wow' => FaceAct.sparkle,
  'yummy' => FaceAct.eat,
  'drink' => FaceAct.drink,
  'yuck' => FaceAct.grumpy,
  'surprised' => FaceAct.what,
  _ => null,
};

/// Small camera wrapper (injectable for tests).
abstract class EyeCamera {
  Future<bool> open();
  Future<Uint8List?> grab();
  Future<void> close();
}

/// Front camera, low resolution, JPEG stills (no preview on screen: the
/// face stays the whole screen; Android shows its own camera indicator).
class FrontEyeCamera implements EyeCamera {
  CameraController? _c;

  @override
  Future<bool> open() async {
    if (_c != null) return true;
    final cams = await availableCameras();
    if (cams.isEmpty) return false;
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    final c = CameraController(
      front,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await c.initialize();
      try {
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
    } catch (_) {
      await c.dispose();
      return false;
    }
    _c = c;
    return true;
  }

  @override
  Future<Uint8List?> grab() async {
    final c = _c;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) {
      return null;
    }
    final x = await c.takePicture();
    final bytes = await x.readAsBytes();
    try {
      await File(x.path).delete();
    } catch (_) {}
    return bytes;
  }

  @override
  Future<void> close() async {
    final c = _c;
    _c = null;
    await c?.dispose();
  }
}

/// The robot's eyes on the face screen: looks through the front camera
/// about once a second while [setWanted] is on. The eyes follow movement,
/// and when the view settles on something new (and the robot is free) one
/// small frame goes to [onReact] (the AI decides whether to react).
/// Frames are kept in memory only (the last one, for "chno hada?").
class RobotEyes extends ChangeNotifier {
  RobotEyes({
    required this.busy,
    required this.onGaze,
    required this.onReact,
    EyeCamera? camera,
    SceneWatcher? watcher,
    DateTime Function()? clock,
    this.interval = const Duration(milliseconds: 900),
    this.dailyLimit = 150,
  }) : _camera = camera ?? FrontEyeCamera(),
       _clock = clock ?? DateTime.now,
       watcher =
           watcher ??
           SceneWatcher(
             clock: clock,
             stableFrames: 2,
             changeThreshold: 24,
             minGap: const Duration(seconds: 15),
             userQuietFor: const Duration(seconds: 6),
           );

  /// True while the robot is talking, listening, playing music, asleep…
  final bool Function() busy;
  final void Function(Offset gaze) onGaze;
  final Future<void> Function(Uint8List jpeg) onReact;
  final SceneWatcher watcher;
  final Duration interval;

  /// Reactions asked per day at most (saves the free AI quota).
  final int dailyLimit;

  final EyeCamera _camera;
  final DateTime Function() _clock;
  bool _wanted = false;
  bool _open = false;
  bool _opening = false;
  bool _grabbing = false;
  bool _reacting = false;
  Timer? _timer;
  SceneSignature? _prev;
  Uint8List? _last;
  DateTime? _lastAt;
  int _today = 0;
  String _day = '';

  /// Camera open and looking.
  bool get active => _open;

  /// The camera could not be opened (busy, no camera).
  bool failed = false;

  /// The latest frame if it is fresh (for questions like "chno hada?").
  Uint8List? latestFrame({Duration maxAge = const Duration(seconds: 4)}) {
    final at = _lastAt;
    if (at == null || _clock().difference(at) > maxAge) return null;
    return _last;
  }

  /// The user spoke: their words come first.
  void userSpoke() => watcher.userSpoke();

  bool _face = false;
  bool _foreground = true;

  /// The face screen is visible and the eyes may open (setting on,
  /// permission granted, not asleep, camera not used elsewhere).
  void setFaceWants(bool on) {
    _face = on;
    unawaited(setWanted(_face && _foreground));
  }

  /// The app went to the background / came back.
  void setForeground(bool on) {
    _foreground = on;
    unawaited(setWanted(_face && _foreground));
  }

  /// Turns the eyes on/off.
  Future<void> setWanted(bool on) async {
    if (on == _wanted) return;
    _wanted = on;
    if (on) {
      await _start();
    } else {
      await _stop();
    }
  }

  Future<void> _start() async {
    if (_open || _opening) return;
    _opening = true;
    bool ok;
    try {
      ok = await _camera.open();
    } catch (_) {
      ok = false;
    }
    _opening = false;
    if (!_wanted) {
      if (ok) await _camera.close();
      return;
    }
    failed = !ok;
    _open = ok;
    if (ok) {
      _prev = null;
      watcher.reset();
      _timer = Timer.periodic(interval, (_) => unawaited(tick()));
    }
    notifyListeners();
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    final was = _open;
    _open = false;
    _prev = null;
    _last = null;
    _lastAt = null;
    if (was) await _camera.close();
    notifyListeners();
  }

  /// One look (public for tests).
  @visibleForTesting
  Future<void> tick() async {
    if (!_open || _grabbing) return;
    _grabbing = true;
    try {
      final jpeg = await _camera.grab();
      if (jpeg == null || !_open) return;
      _last = jpeg;
      _lastAt = _clock();
      final sig = await sceneSignature(jpeg);
      if (sig == null) return;
      final prev = _prev;
      final isBusy = busy();
      if (prev != null) {
        final g = motionGaze(prev, sig);
        if (g != null) onGaze(g);
      }
      final look = watcher.onFrame(sig, robotBusy: isBusy || _reacting);
      _prev = sig;
      if (look && _underLimit()) {
        _reacting = true;
        unawaited(
          onReact(jpeg).catchError((_) {}).whenComplete(() {
            _reacting = false;
          }),
        );
      }
    } catch (_) {
      // A missed frame is fine; the next tick tries again.
    } finally {
      _grabbing = false;
    }
  }

  bool _underLimit() {
    final now = _clock();
    final day = '${now.year}-${now.month}-${now.day}';
    if (day != _day) {
      _day = day;
      _today = 0;
    }
    if (_today >= dailyLimit) return false;
    _today++;
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_open) unawaited(_camera.close());
    _open = false;
    super.dispose();
  }
}
