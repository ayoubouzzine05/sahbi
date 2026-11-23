import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

/// What [HardwareGuard] can switch off. Every action must be safe to call
/// when nothing is running.
class HardwareActions {
  const HardwareActions({
    required this.setCameraForeground,
    required this.closeCamera,
    required this.setMicForeground,
    required this.stopMic,
    required this.stopBackgroundListening,
    required this.micEnabled,
    this.onError,
  });

  /// The app became visible / invisible (camera may only run when visible).
  final void Function(bool foreground) setCameraForeground;

  /// Closes every camera (eyes, rear look, live screen).
  final Future<void> Function() closeCamera;

  /// Tells the listening parts whether the app is visible.
  final void Function(bool foreground) setMicForeground;

  /// Stops listening, recording, the live voice socket and the wake word.
  final Future<void> Function() stopMic;

  /// Stops the Android foreground service (notification goes away).
  final Future<void> Function() stopBackgroundListening;

  /// The user's microphone toggle.
  final bool Function() micEnabled;
  final void Function(String where, Object error)? onError;
}

/// The single owner of every "release the hardware" path:
///
/// | trigger                 | camera | mic + wake word | foreground service |
/// |-------------------------|--------|-----------------|--------------------|
/// | camera toggle off       | closed | —               | —                  |
/// | mic toggle off          | —      | stopped         | stopped            |
/// | app hidden / paused     | closed | kept if mic ON  | kept if mic ON     |
/// | app detached / swiped   | closed | stopped         | stopped            |
///
/// (Android also stops the service itself when the task is removed:
/// `stopWithTask` + `onTaskRemoved` in MimoWakeService.)
class HardwareGuard {
  HardwareGuard(this.actions);

  final HardwareActions actions;
  AppLifecycleState? lastState;
  bool _released = false;

  /// True after [releaseAll] (until the app is resumed again).
  bool get released => _released;

  Future<void> _safe(String where, FutureOr<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      actions.onError?.call(where, e);
    }
  }

  Future<void> onLifecycle(AppLifecycleState s) async {
    lastState = s;
    switch (s) {
      case AppLifecycleState.resumed:
        _released = false;
        await _safe('camera.fg', () => actions.setCameraForeground(true));
        await _safe('mic.fg', () => actions.setMicForeground(true));
      case AppLifecycleState.inactive:
        // Notification shade, a call overlay: still visible, nothing to do.
        break;
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        // Never keep a camera in the background.
        await _safe('camera.bg', () => actions.setCameraForeground(false));
        await _safe('camera.close', actions.closeCamera);
        await _safe('mic.bg', () => actions.setMicForeground(false));
        if (!actions.micEnabled()) {
          await _safe('mic.stop', actions.stopMic);
          await _safe('service.stop', actions.stopBackgroundListening);
        }
      case AppLifecycleState.detached:
        await releaseAll();
    }
  }

  /// The app is closing: release everything, keep nothing running.
  Future<void> releaseAll() async {
    _released = true;
    await _safe('camera.bg', () => actions.setCameraForeground(false));
    await _safe('camera.close', actions.closeCamera);
    await _safe('mic.stop', actions.stopMic);
    await _safe('service.stop', actions.stopBackgroundListening);
  }

  Future<void> onMicToggle(bool on) async {
    if (on) return;
    await _safe('mic.stop', actions.stopMic);
    await _safe('service.stop', actions.stopBackgroundListening);
  }

  Future<void> onCameraToggle(bool on) async {
    if (on) return;
    await _safe('camera.close', actions.closeCamera);
  }
}
