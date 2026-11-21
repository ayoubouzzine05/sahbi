import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/backend_client.dart';
import 'voice_types.dart';

/// Records 16 kHz mono WAV locally, sends it to the backend `/v1/stt`
/// (which proxies Azure Speech or OpenAI), then deletes the file.
/// Raw audio is never kept.
class CloudStt implements SttProvider {
  CloudStt(this._client, {required this.isConfigured, AudioRecorder? recorder})
    : _rec = recorder ?? AudioRecorder();

  final BackendClient _client;
  final bool Function() isConfigured;
  final AudioRecorder _rec;
  StreamController<SttEvent>? _ctrl;
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;
  String _locale = 'ar-MA';
  bool _cancelled = false;

  @override
  String get id => 'cloud';

  @override
  Future<ProviderAvailability> availability() async {
    if (!isConfigured()) return ProviderAvailability.notConfigured;
    return ProviderAvailability.available;
  }

  @override
  Future<List<String>> supportedLocales() async => const [
    'ar-MA',
    'ar-SA',
    'fr-FR',
    'en-US',
  ];

  @override
  Stream<SttEvent> listen({required String localeId}) {
    _ctrl?.close();
    final ctrl = StreamController<SttEvent>();
    _ctrl = ctrl;
    _cancelled = false;
    _locale = localeId.replaceAll('_', '-');
    () async {
      try {
        if (!await _rec.hasPermission(request: false)) {
          ctrl.add(
            const SttFailure('no_permission', 'Microphone permission missing'),
          );
          await ctrl.close();
          return;
        }
        final dir = await getTemporaryDirectory();
        _path =
            '${dir.path}/sahbi_utt_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _rec.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            noiseSuppress: true,
            echoCancel: true,
          ),
          path: _path!,
        );
        final vad = EndOfSpeech();
        _ampSub = _rec
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen((a) {
              final level = ((a.current + 50) / 50).clamp(0.0, 1.0);
              if (!ctrl.isClosed) ctrl.add(SttLevel(level));
              if (vad.add(a.current)) {
                // Nobody spoke: do not upload seconds of silence.
                vad.heardSpeech ? stop() : _noSpeech(ctrl);
              }
            });
      } catch (e) {
        if (!ctrl.isClosed) {
          ctrl.add(SttFailure('not_available', 'Recorder failed: $e'));
          await ctrl.close();
        }
      }
    }();
    return ctrl.stream;
  }

  @override
  Future<void> stop() async {
    final ctrl = _ctrl;
    await _ampSub?.cancel();
    _ampSub = null;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    path ??= _path;
    if (ctrl == null || ctrl.isClosed) return;
    if (_cancelled || path == null) {
      await _delete(path);
      await ctrl.close();
      return;
    }
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      await _delete(path);
      if (bytes.length < 16000) {
        ctrl.add(const SttFailure('no_match', 'Too short'));
      } else {
        ctrl.add(const SttPartial('…'));
        final text = await _client.transcribe(bytes, _locale);
        if (text.trim().isEmpty) {
          ctrl.add(const SttFailure('no_match', 'Nothing recognised'));
        } else {
          ctrl.add(SttFinal(text));
        }
      }
    } on BackendException catch (e) {
      ctrl.add(
        SttFailure(
          e.code == BackendErrorCode.noInternet ? 'network' : 'server',
          e.message,
        ),
      );
    } catch (e) {
      ctrl.add(SttFailure('unknown', '$e'));
    } finally {
      await ctrl.close();
    }
  }

  Future<void> _noSpeech(StreamController<SttEvent> ctrl) async {
    if (!ctrl.isClosed) {
      ctrl.add(const SttFailure('no_match', 'No speech heard'));
    }
    _cancelled = true;
    await stop(); // closes the stream without uploading anything
  }

  Future<void> _delete(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await stop();
  }
}

/// Decides when the user has finished talking from 100 ms loudness readings
/// (dBFS). The threshold follows the room's noise floor, so a TV or a fan
/// does not keep the recording open until the time limit, and a quiet voice
/// in a silent room is still caught.
class EndOfSpeech {
  EndOfSpeech({
    this.stepMs = 100,
    this.silenceMs = 900,
    this.maxMs = 15000,
    this.noSpeechMs = 7000,
  });

  final int stepMs;

  /// Silence after speech that ends the utterance.
  final int silenceMs;

  /// Hard limit for one utterance.
  final int maxMs;

  /// Give up when nobody spoke at all.
  final int noSpeechMs;

  double? _floor;
  bool heardSpeech = false;
  int _silent = 0;
  int _total = 0;
  int _loud = 0;

  /// Returns true when recording should stop.
  bool add(double db) {
    _total += stepMs;
    final d = db.isFinite ? db.clamp(-90.0, 0.0) : -90.0;
    // Noise floor: the quietest reading of the first 0.5 s, then quick to go
    // down and slow to go up (speech must not raise it). Capped at -40 dBFS so
    // a user who starts talking at once is never mistaken for background.
    final f = _floor;
    _floor = f == null
        ? d
        : _total <= 500
        ? (d < f ? d : f)
        : (d < f ? f + (d - f) * 0.5 : f + (d - f) * 0.02);
    final speechAt = (_floor! + 12).clamp(-48.0, -28.0);
    if (d >= speechAt) {
      _loud += stepMs;
      // 200 ms of loud audio = speech (a click or a cough does not count).
      if (_loud >= 200) heardSpeech = true;
      _silent = 0;
    } else {
      _loud = 0;
      _silent += stepMs;
    }
    if (heardSpeech && _silent >= silenceMs) return true;
    if (!heardSpeech && _total >= noSpeechMs) return true;
    return _total >= maxMs;
  }
}
