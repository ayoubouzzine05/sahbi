import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/error_log.dart';
import '../settings/app_settings.dart';
import 'robot_voice_fx.dart';
import 'wake_model_manager.dart';
import 'wake_word_engine.dart';

/// Decides when the offline "MIMO" wake word listens:
///
/// - mic toggle ON + wake word ON + model on the phone + permission;
/// - it is STARTED only while the app is visible (Android 14+ rule) and
///   then keeps running when the app is minimised (foreground service with
///   a notification);
/// - it PAUSES (mic fully released) while the conversation recogniser or
///   the live camera needs the microphone, and resumes right after;
/// - mic toggle OFF, "Stop MIMO" in the notification or the app closing
///   stop it (see HardwareGuard).
class MimoWakeController extends ChangeNotifier {
  MimoWakeController({
    required this.engine,
    required this.models,
    required this.settings,
    required this.micGranted,
    required this.notice,
    required this.onWake,
    required this.onUserStopped,
    required this.log,
    this.isOwnSpeech,
    this.ensureNotifications,
  });

  final WakeWordEngine engine;
  final WakeModelManager models;
  final AppSettings Function() settings;
  final Future<bool> Function() micGranted;
  final WakeNotice Function() notice;

  /// "MIMO" was heard (the caller handles barge-in, the eyes, the reply).
  final Future<void> Function() onWake;

  /// The user pressed "Stop MIMO" in the notification.
  final VoidCallback onUserStopped;

  /// True while MIMO itself is saying its name (ignore the echo).
  final bool Function()? isOwnSpeech;

  /// Asks for the notification permission (Android 13+) before the first
  /// start, so the "Stop MIMO" notification is visible.
  final Future<void> Function()? ensureNotifications;
  final ErrorLog log;

  StreamSubscription<WakeEvent>? _sub;
  bool _foreground = true;
  int _suspended = 0;
  bool _micBusy = false;
  bool _running = false;
  bool _paused = false;
  bool _starting = false;
  bool _disposed = false;
  Future<void> _lock = Future<void>.value();
  String? lastError;

  /// Service running (notification visible).
  bool get running => _running;

  /// Listening for "MIMO" right now.
  bool get active => _running && !_paused;

  /// The offline wake word is configured and usable (the old recogniser
  /// must then stay off).
  bool get available =>
      models.modelPath != null &&
      settings().micEnabled &&
      settings().wakeByName;

  bool get foreground => _foreground;

  void init() {
    _sub = engine.events.listen(_onEvent);
    models.addListener(refresh);
    unawaited(models.check().then((_) => refresh()));
  }

  void _onEvent(WakeEvent e) {
    switch (e) {
      case WakeHeard():
        if (!_running || _paused) return;
        if (isOwnSpeech?.call() ?? false) return;
        unawaited(
          onWake().catchError((Object err) {
            log.add('wake', '$err');
          }),
        );
      case WakeState(:final running, :final paused):
        _running = running;
        _paused = paused;
        notifyListeners();
      case WakeStopped(:final byUser):
        _running = false;
        _paused = false;
        notifyListeners();
        if (byUser) onUserStopped();
      case WakeError(:final code, :final message):
        lastError = code;
        log.add('wake.$code', message);
        if (code == 'permission' || code == 'model' || code == 'engine') {
          _running = false;
        }
        notifyListeners();
    }
  }

  /// App visible or not. Starting needs the app visible; minimising keeps
  /// a running service.
  void setForeground(bool v) {
    _foreground = v;
    refresh();
  }

  /// Another screen records (live camera): release the microphone.
  void suspend() {
    _suspended++;
    refresh();
  }

  void resume() {
    if (_suspended > 0) _suspended--;
    refresh();
  }

  /// The conversation recogniser is (not) using the microphone.
  void setMicBusy(bool busy) {
    if (_micBusy == busy) return;
    _micBusy = busy;
    refresh();
  }

  /// Re-evaluate (settings, permission, model, lifecycle changed).
  void refresh() {
    if (_disposed) return;
    _lock = _lock.then((_) => _apply()).catchError((Object e) {
      log.add('wake', '$e');
    });
  }

  /// Completes when the pending start / pause / resume is applied.
  Future<void> get settled => _lock;

  /// Before another recorder opens the mic: pause and wait until the
  /// microphone is really free.
  Future<void> yieldMic() async {
    setMicBusy(true);
    await settled;
    if (_running) {
      // The engine thread closes AudioRecord within ~100 ms.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _apply() async {
    if (_disposed) return;
    final s = settings();
    final want = s.micEnabled && s.wakeByName && models.modelPath != null;
    if (!want) {
      if (_running || _starting) await stop();
      return;
    }
    final shouldPause = _suspended > 0 || _micBusy;
    if (!_running) {
      if (!_foreground) return; // Android: start only while visible.
      if (!await micGranted()) {
        lastError = 'no_permission';
        notifyListeners();
        return;
      }
      await ensureNotifications?.call();
      _starting = true;
      final ok = await engine.start(
        modelPath: models.modelPath!,
        notice: notice(),
        paused: shouldPause,
      );
      _starting = false;
      if (!ok) {
        lastError = 'start_failed';
        notifyListeners();
        return;
      }
      lastError = null;
      _running = true;
      _paused = shouldPause;
      notifyListeners();
      return;
    }
    if (shouldPause != _paused) {
      _paused = shouldPause;
      notifyListeners();
      if (shouldPause) {
        await engine.pause();
      } else {
        await engine.resume();
      }
    }
  }

  /// Stops listening and the notification; frees the microphone.
  Future<void> stop() async {
    _running = false;
    _paused = false;
    _starting = false;
    await engine.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    models.removeListener(refresh);
    unawaited(engine.stop());
    super.dispose();
  }
}

/// Short answers when called ("Na3am?", "Ana hna!"), pre-made once in
/// MIMO's own voice and kept on the phone, so the reply is instant and
/// works offline. Missing clips are simply skipped (the eyes react anyway).
class AckClips {
  AckClips({
    required this.synthesize,
    math.Random? random,
    Future<Directory> Function()? dir,
  }) : _r = random ?? math.Random(),
       _dir = dir ?? getApplicationSupportDirectory;

  /// Text → WAV bytes in MIMO's voice (backend TTS).
  final Future<Uint8List> Function(String text) synthesize;
  final math.Random _r;
  final Future<Directory> Function() _dir;
  AudioPlayer? _player;
  bool _preparing = false;

  /// Spoken (Arabic script for the voice) and shown (Latin) forms.
  static const lines = [
    ('نعم؟', 'Na3am?'),
    ('أنا هنا!', 'Ana hna!'),
    ('قول أ صاحبي', 'Goul a sahbi'),
    ('واش بغيتي؟', 'Wach bghiti?'),
    ('آه؟ شنو كاين؟', 'Ah? Chno kayn?'),
  ];

  Future<File> _file(int i) async =>
      File('${(await _dir()).path}/ack/ack_v1_$i.wav');

  /// Makes the missing clips (slowly: the free voice quota is small).
  Future<void> prepare() async {
    if (_preparing) return;
    _preparing = true;
    try {
      for (var i = 0; i < lines.length; i++) {
        final f = await _file(i);
        if (await f.exists()) continue;
        try {
          var wav = await synthesize(lines[i].$1);
          if (wav.length > 4 &&
              String.fromCharCodes(wav.sublist(0, 4)) == 'RIFF') {
            wav = RobotVoiceFx.processWav(wav);
            await f.parent.create(recursive: true);
            await f.writeAsBytes(wav, flush: true);
          }
        } catch (_) {
          return; // offline / quota: try again another time
        }
        await Future<void>.delayed(const Duration(seconds: 7));
      }
    } finally {
      _preparing = false;
    }
  }

  /// Plays one ready clip; returns its Latin text, or null if none is ready.
  Future<String?> play() async {
    final ready = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (await (await _file(i)).exists()) ready.add(i);
    }
    if (ready.isEmpty) return null;
    final i = ready[_r.nextInt(ready.length)];
    try {
      final p = _player ??= AudioPlayer();
      await p.setFilePath((await _file(i)).path);
      await p.play().timeout(const Duration(seconds: 3));
      return lines[i].$2;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
