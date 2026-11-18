import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/backend_client.dart';
import 'voice_types.dart';

/// Backend `/v1/tts` (Gemini TTS male/female voices, or Azure ar-MA
/// Jamal/Mouna). Audio is played from a temp file which is deleted
/// afterwards. No word timings are available here, so the face uses an
/// approximate rhythmic mouth loop.
class CloudTts implements TtsProvider {
  CloudTts(
    this._client, {
    required this.isConfigured,
    required this.voice,
    required this.gender,
    required this.rate,
    required this.pitch,
  });

  final BackendClient _client;
  final bool Function() isConfigured;
  final String Function() voice;

  /// 'male' | 'female' — the backend picks a matching voice (Gemini or Azure).
  final String Function() gender;
  final double Function() rate; // 0..1 flutter_tts scale, 0.5 normal
  final double Function() pitch;
  AudioPlayer? _player;
  StreamController<TtsEvent>? _ctrl;

  @override
  String get id => 'cloud';

  @override
  Future<ProviderAvailability> availability() async => isConfigured()
      ? ProviderAvailability.available
      : ProviderAvailability.notConfigured;

  @override
  Future<List<TtsVoice>> voices() async => const [
    TtsVoice('ar-MA-JamalNeural', 'ar-MA'),
    TtsVoice('ar-MA-MounaNeural', 'ar-MA'),
  ];

  static String _azureLocale(String lang) => switch (lang) {
    'fr' => 'fr-FR',
    'en' => 'en-US',
    'ar' => 'ar-SA',
    _ => 'ar-MA',
  };

  @override
  Stream<TtsEvent> speak(String text, {required String language}) {
    _ctrl?.close();
    final ctrl = StreamController<TtsEvent>();
    _ctrl = ctrl;
    () async {
      File? file;
      try {
        final locale = _azureLocale(language);
        final bytes = await _client.synthesize(
          text: text,
          language: locale,
          // The backend picks a voice for this gender (Gemini prebuilt voice
          // or the Azure ar-MA voice).
          gender: gender(),
          rate: (rate() * 2).clamp(0.5, 2.0),
          pitch: pitch().clamp(0.5, 2.0),
        );
        if (ctrl.isClosed) return;
        final dir = await getTemporaryDirectory();
        // Gemini returns WAV, Azure MP3: name the file after the content.
        final isWav =
            bytes.length > 4 &&
            String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF';
        file = File(
          '${dir.path}/sahbi_tts_${DateTime.now().millisecondsSinceEpoch}'
          '${isWav ? '.wav' : '.mp3'}',
        );
        await file.writeAsBytes(bytes, flush: true);
        final p = _player ??= AudioPlayer();
        await p.setFilePath(file.path);
        if (ctrl.isClosed) return;
        ctrl.add(const TtsStarted());
        await p.play();
        // play() completes when playback stops (end or stop()).
        if (!ctrl.isClosed) {
          ctrl.add(
            TtsDone(
              interrupted: p.processingState != ProcessingState.completed,
            ),
          );
          await ctrl.close();
        }
      } on BackendException catch (e) {
        if (!ctrl.isClosed) {
          ctrl.add(TtsFailure('${e.code.name}: ${e.message}'));
          await ctrl.close();
        }
      } catch (e) {
        if (!ctrl.isClosed) {
          ctrl.add(TtsFailure('$e'));
          await ctrl.close();
        }
      } finally {
        try {
          await file?.delete();
        } catch (_) {}
      }
    }();
    return ctrl.stream;
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    final c = _ctrl;
    if (c != null && !c.isClosed) {
      c.add(const TtsDone(interrupted: true));
      await c.close();
    }
  }
}
