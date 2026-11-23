import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// What the native wake-word service reports.
sealed class WakeEvent {
  const WakeEvent();
}

/// "MIMO" was heard.
class WakeHeard extends WakeEvent {
  const WakeHeard(this.text);
  final String text;
}

/// The service is (not) running / paused.
class WakeState extends WakeEvent {
  const WakeState({required this.running, required this.paused});
  final bool running;
  final bool paused;
}

/// The user pressed "Stop MIMO" in the notification (or Android stopped it).
class WakeStopped extends WakeEvent {
  const WakeStopped({required this.byUser});
  final bool byUser;
}

class WakeError extends WakeEvent {
  const WakeError(this.code, this.message);
  final String code;
  final String message;
}

/// Labels for the persistent notification (localised by the app).
class WakeNotice {
  const WakeNotice({
    required this.title,
    required this.text,
    required this.stopLabel,
    required this.openLabel,
    required this.channelName,
  });
  final String title;
  final String text;
  final String stopLabel;
  final String openLabel;
  final String channelName;
}

/// The offline wake-word engine (tests use a fake).
abstract class WakeWordEngine {
  Stream<WakeEvent> get events;

  /// Starts listening (foreground service + notification). Must be called
  /// while the app is visible (Android 14+). Returns false when Android
  /// refused or the engine is unavailable.
  Future<bool> start({
    required String modelPath,
    required WakeNotice notice,
    bool paused = false,
  });

  /// Stops the service and frees the microphone. Safe when not running.
  Future<void> stop();

  /// Frees the microphone for another recorder (the model stays loaded).
  Future<void> pause();
  Future<void> resume();
  Future<bool> isRunning();
}

/// The wake words and look-alike decoys. Decoys absorb similar words
/// ("momo", "mama", "mimi", "nemo") so they do not wake MIMO. Tested with
/// the Vosk small French model (see docs/STATUS.md).
const mimoWakeWords = ['mimo'];
const mimoGrammar = ['mimo', 'momo', 'mama', 'mimi', 'nemo', '[unk]'];

/// Native Vosk engine in `MimoWakeService` (Android).
class NativeWakeEngine implements WakeWordEngine {
  NativeWakeEngine({MethodChannel? method, EventChannel? eventChannel})
    : _m = method ?? const MethodChannel('ma.sahbi/mimo'),
      _e = eventChannel ?? const EventChannel('ma.sahbi/mimo_events');

  final MethodChannel _m;
  final EventChannel _e;
  Stream<WakeEvent>? _events;

  @override
  Stream<WakeEvent> get events => _events ??= _e
      .receiveBroadcastStream()
      .map(_parse)
      .where((e) => e != null)
      .cast<WakeEvent>()
      .handleError((Object _) {})
      .asBroadcastStream();

  static WakeEvent? _parse(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['type']) {
      'wake' => WakeHeard('${raw['text'] ?? ''}'),
      'state' => WakeState(
        running: raw['running'] == true,
        paused: raw['paused'] == true,
      ),
      'stopped' => WakeStopped(byUser: raw['byUser'] == true),
      'error' => WakeError('${raw['code']}', '${raw['message'] ?? ''}'),
      _ => null,
    };
  }

  @override
  Future<bool> start({
    required String modelPath,
    required WakeNotice notice,
    bool paused = false,
  }) async {
    try {
      final ok = await _m.invokeMethod<bool>('start', {
        'model': modelPath,
        'grammar': jsonEncode(mimoGrammar),
        'words': mimoWakeWords,
        'paused': paused,
        'title': notice.title,
        'text': notice.text,
        'stopLabel': notice.stopLabel,
        'openLabel': notice.openLabel,
        'channelName': notice.channelName,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _call(String m) async {
    try {
      await _m.invokeMethod<Object?>(m);
    } on PlatformException {
      // Nothing running: fine.
    } on MissingPluginException {
      // Tests / other platforms.
    }
  }

  @override
  Future<void> stop() => _call('stop');
  @override
  Future<void> pause() => _call('pause');
  @override
  Future<void> resume() => _call('resume');

  @override
  Future<bool> isRunning() async {
    try {
      return await _m.invokeMethod<bool>('isRunning') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Battery temperature and battery saver (to rest the camera).
class ThermalInfo {
  const ThermalInfo({this.batteryC, this.powerSave = false});
  final double? batteryC;
  final bool powerSave;

  /// The camera should rest (hot phone or battery saver).
  bool get cameraShouldRest =>
      powerSave || (batteryC != null && batteryC! >= 42);
}

Future<ThermalInfo> readThermal({MethodChannel? channel}) async {
  final m = channel ?? const MethodChannel('ma.sahbi/mimo');
  try {
    final r = await m.invokeMapMethod<String, Object?>('thermal');
    if (r == null) return const ThermalInfo();
    final t = r['batteryC'];
    return ThermalInfo(
      batteryC: t is num ? t.toDouble() : null,
      powerSave: r['powerSave'] == true,
    );
  } on PlatformException {
    return const ThermalInfo();
  } on MissingPluginException {
    return const ThermalInfo();
  }
}
