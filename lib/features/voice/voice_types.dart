/// Shared voice types and provider interfaces.
enum ProviderAvailability {
  available,
  notConfigured,
  notInstalled,
  noPermission,
  offline,
  disabledByUser,
}

sealed class SttEvent {
  const SttEvent();
}

class SttPartial extends SttEvent {
  const SttPartial(this.text);
  final String text;
}

class SttFinal extends SttEvent {
  const SttFinal(this.text);
  final String text;
}

class SttLevel extends SttEvent {
  const SttLevel(this.level);

  /// 0..1
  final double level;
}

class SttFailure extends SttEvent {
  const SttFailure(this.code, this.message);

  /// no_match | no_permission | network | not_available | busy | server | unknown
  final String code;
  final String message;
}

abstract class SttProvider {
  String get id; // device | cloud
  Future<ProviderAvailability> availability();

  /// Locale ids the engine supports (empty if unknown).
  Future<List<String>> supportedLocales();

  /// Starts listening. Emits partial/final results, levels and failures.
  /// The stream closes when recognition ends.
  Stream<SttEvent> listen({required String localeId});

  /// Stop and finalise what was heard.
  Future<void> stop();

  /// Abort without a result.
  Future<void> cancel();
}

sealed class TtsEvent {
  const TtsEvent();
}

class TtsStarted extends TtsEvent {
  const TtsStarted();
}

/// Word-boundary callback (only from engines that provide it).
class TtsWord extends TtsEvent {
  const TtsWord(this.start, this.end, this.word);
  final int start;
  final int end;
  final String word;
}

class TtsDone extends TtsEvent {
  const TtsDone({this.interrupted = false});
  final bool interrupted;
}

class TtsFailure extends TtsEvent {
  const TtsFailure(this.message);
  final String message;
}

class TtsVoice {
  const TtsVoice(this.name, this.locale);
  final String name;
  final String locale;
}

abstract class TtsProvider {
  String get id; // device | cloud
  Future<ProviderAvailability> availability();
  Future<List<TtsVoice>> voices();

  /// Speaks and completes when finished or interrupted.
  /// [language] is the reply language code: darija | ar | fr | en.
  Stream<TtsEvent> speak(String text, {required String language});
  Future<void> stop();
}

/// Maps reply language → preferred BCP-47 locales, best first.
List<String> preferredLocales(String replyLanguage) => switch (replyLanguage) {
  'fr' => ['fr-FR', 'fr-MA', 'fr-CA', 'fr'],
  'en' => ['en-US', 'en-GB', 'en'],
  'ar' => ['ar-SA', 'ar-MA', 'ar-EG', 'ar-AE', 'ar'],
  _ => ['ar-MA', 'ar-DZ', 'ar-TN', 'ar-SA', 'ar-EG', 'ar'],
};

/// Picks the best supported locale. Accepts ids like "ar_MA" or "ar-MA".
String? pickLocale(List<String> supported, String replyLanguage) {
  String n(String s) => s.replaceAll('_', '-').toLowerCase();
  final sup = {for (final s in supported) n(s): s};
  for (final want in preferredLocales(replyLanguage)) {
    final w = n(want);
    if (sup.containsKey(w)) return sup[w];
    if (!w.contains('-')) {
      for (final e in sup.entries) {
        if (e.key.startsWith('$w-')) return e.value;
      }
    }
  }
  return null;
}
