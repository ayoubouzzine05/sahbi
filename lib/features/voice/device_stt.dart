import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice_types.dart';

/// Android SpeechRecognizer via speech_to_text. Locales are queried at
/// runtime; Darija (ar-MA) is only used if the device actually offers it.
class DeviceStt implements SttProvider {
  DeviceStt([SpeechToText? stt]) : _stt = stt ?? SpeechToText();
  final SpeechToText _stt;
  StreamController<SttEvent>? _ctrl;
  bool _initialised = false;
  bool _available = false;
  String? _lastPartial;

  @override
  String get id => 'device';

  Future<bool> _init() async {
    if (_initialised) return _available;
    _available = await _stt.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    _initialised = true;
    return _available;
  }

  @override
  Future<ProviderAvailability> availability() async {
    try {
      final ok = await _init();
      return ok ? ProviderAvailability.available : ProviderAvailability.notInstalled;
    } catch (_) {
      return ProviderAvailability.notInstalled;
    }
  }

  @override
  Future<List<String>> supportedLocales() async {
    if (!await _init()) return const [];
    final l = await _stt.locales();
    return [for (final x in l) x.localeId];
  }

  @override
  Stream<SttEvent> listen({required String localeId}) {
    _ctrl?.close();
    final ctrl = StreamController<SttEvent>();
    _ctrl = ctrl;
    _lastPartial = null;
    () async {
      if (!await _init()) {
        ctrl.add(const SttFailure('not_available', 'No speech recognizer on this device'));
        await ctrl.close();
        return;
      }
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) {
          if (ctrl.isClosed) return;
          if (r.finalResult) {
            ctrl.add(SttFinal(r.recognizedWords));
            ctrl.close();
          } else {
            _lastPartial = r.recognizedWords;
            ctrl.add(SttPartial(r.recognizedWords));
          }
        },
        onSoundLevelChange: (level) {
          // Android reports roughly -2..10 dB.
          if (!ctrl.isClosed) {
            ctrl.add(SttLevel(((level + 2) / 12).clamp(0.0, 1.0)));
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          listenMode: ListenMode.dictation,
        ),
      );
    }();
    return ctrl.stream;
  }

  void _onError(SpeechRecognitionError e) {
    final c = _ctrl;
    if (c == null || c.isClosed) return;
    final code = switch (e.errorMsg) {
      'error_no_match' || 'error_speech_timeout' => 'no_match',
      'error_permission' || 'error_insufficient_permissions' => 'no_permission',
      'error_network' || 'error_network_timeout' || 'error_server' => 'network',
      'error_busy' => 'busy',
      _ => 'unknown',
    };
    c.add(SttFailure(code, e.errorMsg));
    c.close();
  }

  void _onStatus(String status) {
    final c = _ctrl;
    if (c == null || c.isClosed) return;
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      // Some engines end without a final result: use the last partial.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!c.isClosed) {
          final p = _lastPartial;
          if (p != null && p.isNotEmpty) c.add(SttFinal(p));
          c.close();
        }
      });
    }
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() async {
    await _stt.cancel();
    await _ctrl?.close();
  }
}
