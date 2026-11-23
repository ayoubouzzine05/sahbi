import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Which side of the phone looks.
enum CameraLens { front, back }

/// Who holds the camera. A higher priority may take it from a lower one
/// (the live screen from the robot's eyes), never the other way round.
enum VisionOwner {
  eyes(0),
  inspect(1),
  live(2);

  const VisionOwner(this.priority);
  final int priority;
}

/// One opened camera.
abstract class VisionCamera {
  /// The plugin controller (preview, pictures); null for test fakes.
  CameraController? get controller;
  CameraLens get lens;

  /// One JPEG picture (null when the camera is not ready).
  Future<Uint8List?> grab();
  Future<void> dispose();
}

typedef VisionCameraFactory = Future<VisionCamera?> Function(
  CameraLens lens,
  ResolutionPreset preset, {
  CameraDescription? description,
});

/// The ONLY place that opens a camera. Every user (robot eyes, rear
/// inspection, live screen) asks here; opening for one owner always closes
/// the previous camera first (awaited), so there is never a second stream
/// (hardware conflicts, heat). Everything is closed at once when the camera
/// toggle goes off or the app leaves the foreground.
class VisionController extends ChangeNotifier {
  VisionController({required this.enabled, VisionCameraFactory? factory})
    : _factory = factory ?? openPluginCamera;

  /// The user's camera toggle.
  final bool Function() enabled;
  final VisionCameraFactory _factory;

  VisionOwner? _owner;
  VisionCamera? _cam;
  VoidCallback? _onRevoked;
  bool _foreground = true;
  bool _disposed = false;
  Future<void> _lock = Future<void>.value();

  /// Peak number of cameras open at the same time (tests: must stay ≤ 1).
  @visibleForTesting
  int maxOpen = 0;
  int _openNow = 0;

  VisionOwner? get owner => _owner;
  CameraLens? get lens => _cam?.lens;
  bool get isOpen => _cam != null;

  /// Toggle on and app visible.
  bool get allowed => !_disposed && enabled() && _foreground;

  Future<T> _serial<T>(Future<T> Function() f) {
    final done = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        done.complete(await f());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  /// Opens [lens] (or exactly [description]) for [who]. Returns null when
  /// the camera is off, the app is in the background, a higher-priority
  /// owner holds it, or the camera fails to open. [onRevoked] is called if
  /// the camera is later taken away (toggle off, background, higher owner).
  Future<VisionCamera?> acquire(
    VisionOwner who, {
    CameraLens lens = CameraLens.front,
    CameraDescription? description,
    ResolutionPreset preset = ResolutionPreset.low,
    VoidCallback? onRevoked,
  }) => _serial(() async {
    if (!allowed) return null;
    final cur = _owner;
    if (cur != null && cur != who && cur.priority > who.priority) {
      return null;
    }
    final want = description == null
        ? lens
        : (description.lensDirection == CameraLensDirection.front
              ? CameraLens.front
              : CameraLens.back);
    if (cur == who &&
        _cam != null &&
        _cam!.lens == want &&
        description == null) {
      _onRevoked = onRevoked ?? _onRevoked;
      return _cam;
    }
    await _closeCurrent(notifyOwner: cur != who);
    VisionCamera? cam;
    try {
      cam = await _factory(want, preset, description: description);
    } catch (_) {
      cam = null;
    }
    if (cam == null) return null;
    if (!allowed) {
      await cam.dispose();
      return null;
    }
    _owner = who;
    _cam = cam;
    _onRevoked = onRevoked;
    _openNow++;
    if (_openNow > maxOpen) maxOpen = _openNow;
    notifyListeners();
    return cam;
  });

  /// [who] is done with the camera (no-op if someone else holds it).
  Future<void> release(VisionOwner who) => _serial(() async {
    if (_owner == who) await _closeCurrent(notifyOwner: false);
  });

  /// Closes whatever is open now (toggle off, background, app closing).
  Future<void> releaseAll() => _serial(() => _closeCurrent(notifyOwner: true));

  Future<void> _closeCurrent({required bool notifyOwner}) async {
    final cam = _cam;
    final revoked = _onRevoked;
    _cam = null;
    _owner = null;
    _onRevoked = null;
    if (cam == null) return;
    try {
      await cam.dispose();
    } catch (_) {
      // Already released by the plugin (e.g. activity destroyed).
    }
    _openNow--;
    if (notifyOwner) revoked?.call();
    if (!_disposed) notifyListeners();
  }

  /// App visible / not. Leaving the foreground closes the camera at once
  /// (Android does not allow it in the background anyway).
  void setForeground(bool v) {
    if (_foreground == v) return;
    _foreground = v;
    if (!v) unawaited(releaseAll());
    notifyListeners();
  }

  /// Re-evaluate after the camera toggle changed.
  void refresh() {
    if (!allowed) unawaited(releaseAll());
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final cam = _cam;
    _cam = null;
    _owner = null;
    if (cam != null) unawaited(cam.dispose().catchError((_) {}));
    super.dispose();
  }
}

/// The real camera (camera plugin / CameraX).
Future<VisionCamera?> openPluginCamera(
  CameraLens lens,
  ResolutionPreset preset, {
  CameraDescription? description,
}) async {
  var d = description;
  if (d == null) {
    final cams = await availableCameras();
    if (cams.isEmpty) return null;
    final dir = lens == CameraLens.front
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    d = cams.firstWhere(
      (c) => c.lensDirection == dir,
      orElse: () => cams.first,
    );
  }
  final c = CameraController(
    d,
    preset,
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
    return null;
  }
  return _PluginCamera(
    c,
    d.lensDirection == CameraLensDirection.front
        ? CameraLens.front
        : CameraLens.back,
  );
}

class _PluginCamera implements VisionCamera {
  _PluginCamera(this._c, this.lens);
  final CameraController _c;
  bool _disposed = false;

  @override
  final CameraLens lens;

  @override
  CameraController? get controller => _disposed ? null : _c;

  @override
  Future<Uint8List?> grab() async {
    if (_disposed || !_c.value.isInitialized || _c.value.isTakingPicture) {
      return null;
    }
    final x = await _c.takePicture();
    final bytes = await x.readAsBytes();
    try {
      await File(x.path).delete();
    } catch (_) {}
    return bytes;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _c.dispose();
  }
}
