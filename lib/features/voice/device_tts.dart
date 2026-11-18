import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'voice_types.dart';

/// Android TextToSpeech via flutter_tts. Uses installed voices only.
/// Word-boundary progress callbacks are forwarded when the engine sends them.
class DeviceTts implements TtsProvider {
  DeviceTts({
    FlutterTts? tts,
    required this.voiceName,
    this.gender,
    required this.rate,
    required this.pitch,
  }) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  final String? Function() voiceName;

  /// 'male' | 'female'. Android does not report voice gender, so with no
  /// explicit voice chosen we look for a voice whose name says "male" and,
  /// failing that, lower the pitch a little for "male".
  final String Function()? gender;
  final double Function() rate;
  final double Function() pitch;
  StreamController<TtsEvent>? _ctrl;
  List<String>? _languages;
  bool _handlersSet = false;

  @override
  String get id => 'device';

  void _setHandlers() {
    if (_handlersSet) return;
    _handlersSet = true;
    _tts.setStartHandler(() => _emit(const TtsStarted()));
    _tts.setProgressHandler(
      (text, start, end, word) => _emit(TtsWord(start, end, word)),
    );
    _tts.setCompletionHandler(() => _finish(const TtsDone()));
    _tts.setCancelHandler(() => _finish(const TtsDone(interrupted: true)));
    _tts.setErrorHandler((msg) => _finish(TtsFailure('$msg')));
  }

  void _emit(TtsEvent e) {
    final c = _ctrl;
    if (c != null && !c.isClosed) c.add(e);
  }

  void _finish(TtsEvent e) {
    final c = _ctrl;
    if (c != null && !c.isClosed) {
      c.add(e);
      c.close();
    }
  }

  Future<List<String>> _langs() async {
    if (_languages != null) return _languages!;
    try {
      final l = await _tts.getLanguages;
      _languages = [for (final x in (l as List? ?? const [])) '$x'];
    } catch (_) {
      _languages = const [];
    }
    return _languages!;
  }

  @override
  Future<ProviderAvailability> availability() async {
    final l = await _langs();
    return l.isEmpty
        ? ProviderAvailability.notInstalled
        : ProviderAvailability.available;
  }

  @override
  Future<List<TtsVoice>> voices() async {
    try {
      final v = await _tts.getVoices;
      return [
        for (final x in (v as List? ?? const []))
          if (x is Map) TtsVoice('${x['name']}', '${x['locale']}'),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Stream<TtsEvent> speak(String text, {required String language}) {
    _setHandlers();
    _ctrl?.close();
    final ctrl = StreamController<TtsEvent>();
    _ctrl = ctrl;
    () async {
      try {
        final locale = pickLocale(await _langs(), language);
        if (locale == null) {
          _finish(TtsFailure('No installed TTS voice for $language'));
          return;
        }
        await _tts.setLanguage(locale);
        final vn = voiceName();
        var pitchFactor = 1.0;
        if (vn != null) {
          final all = await voices();
          final match = all.where((v) => v.name == vn).toList();
          if (match.isNotEmpty) {
            await _tts.setVoice({
              'name': match.first.name,
              'locale': match.first.locale,
            });
          }
        } else if (gender != null) {
          final g = gender!();
          final pick = pickGenderVoice(await voices(), locale, g);
          if (pick != null) {
            await _tts.setVoice({'name': pick.name, 'locale': pick.locale});
          } else if (g == 'male') {
            pitchFactor = maleFallbackPitch;
          }
        }
        await _tts.setSpeechRate(rate());
        await _tts.setPitch((pitch() * pitchFactor).clamp(0.5, 2.0));
        await _tts.awaitSpeakCompletion(false);
        final r = await _tts.speak(text);
        if (r != 1 && r != null) {
          _finish(const TtsFailure('Engine refused to speak'));
        }
      } catch (e) {
        _finish(TtsFailure('$e'));
      }
    }();
    return ctrl.stream;
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _finish(const TtsDone(interrupted: true));
  }
}

/// Pitch multiplier used for "male" when no voice says it is male.
const maleFallbackPitch = 0.8;

/// A voice for [locale] whose name explicitly says [gender] (some engines,
/// e.g. Samsung, name voices "...-male-..."). Null when none does.
TtsVoice? pickGenderVoice(List<TtsVoice> voices, String locale, String gender) {
  final lang = locale.toLowerCase().split(RegExp('[-_]')).first;
  final want = RegExp(gender == 'male' ? r'(^|[^a-z])male' : 'female');
  for (final v in voices) {
    final n = v.name.toLowerCase();
    final l = v.locale.toLowerCase();
    if (!l.startsWith(lang)) continue;
    if (want.hasMatch(n) && !(gender == 'male' && n.contains('female'))) {
      return v;
    }
  }
  return null;
}
