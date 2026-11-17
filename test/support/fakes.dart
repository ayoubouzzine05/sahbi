import 'dart:async';

import 'package:sahbi/features/voice/voice_types.dart';

/// Scriptable STT engine.
class FakeStt implements SttProvider {
  FakeStt(
    this.id, {
    this.avail = ProviderAvailability.available,
    this.locales = const ['ar-MA', 'fr-FR', 'en-US'],
  });
  @override
  final String id;
  ProviderAvailability avail;
  List<String> locales;
  StreamController<SttEvent>? _ctrl;
  String? lastLocale;
  int stops = 0, cancels = 0;

  @override
  Future<ProviderAvailability> availability() async => avail;
  @override
  Future<List<String>> supportedLocales() async => locales;
  @override
  Stream<SttEvent> listen({required String localeId}) {
    lastLocale = localeId;
    _ctrl = StreamController<SttEvent>();
    return _ctrl!.stream;
  }

  void emit(SttEvent e) => _ctrl!.add(e);
  Future<void> end() async => _ctrl?.close();

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> cancel() async => cancels++;
}

/// TTS engine: `mode` decides what happens on speak.
enum TtsMode { finish, fail, hang }

class FakeTts implements TtsProvider {
  FakeTts(
    this.id, {
    this.avail = ProviderAvailability.available,
    this.mode = TtsMode.finish,
    this.words = 0,
  });
  @override
  final String id;
  ProviderAvailability avail;
  TtsMode mode;
  int words;
  final spoken = <String>[];
  int stops = 0;

  @override
  Future<ProviderAvailability> availability() async => avail;
  @override
  Future<List<TtsVoice>> voices() async => const [];
  @override
  Stream<TtsEvent> speak(String text, {required String language}) async* {
    spoken.add('$language:$text');
    yield const TtsStarted();
    for (var i = 0; i < words; i++) {
      yield TtsWord(i, i + 1, 'w$i');
    }
    switch (mode) {
      case TtsMode.finish:
        yield const TtsDone();
      case TtsMode.fail:
        yield const TtsFailure('synth error');
      case TtsMode.hang:
        await Completer<void>().future; // never finishes until stopped
    }
  }

  @override
  Future<void> stop() async => stops++;
}
