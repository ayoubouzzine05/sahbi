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
        var heardSpeech = false;
        var silentMs = 0;
        var totalMs = 0;
        _ampSub = _rec
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen((a) {
              totalMs += 100;
              final level = ((a.current + 50) / 50).clamp(0.0, 1.0);
              if (!ctrl.isClosed) ctrl.add(SttLevel(level));
              if (a.current > -35) {
                heardSpeech = true;
                silentMs = 0;
              } else {
                silentMs += 100;
              }
              // Auto-stop on 1.5 s of silence after speech, or 20 s max.
              if ((heardSpeech && silentMs >= 1500) || totalMs >= 20000) stop();
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
