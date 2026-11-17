import '../personality/emotion.dart';

class SourceRef {
  const SourceRef({
    required this.id,
    required this.title,
    required this.url,
    this.date,
    this.kind = 'web',
  });
  final int id;
  final String title;
  final String url;
  final String? date;
  final String kind; // web | data

  static SourceRef fromJson(Map<String, dynamic> j) => SourceRef(
    id: (j['id'] as num?)?.toInt() ?? 0,
    title: (j['title'] as String?) ?? '',
    url: (j['url'] as String?) ?? '',
    date: j['date'] as String?,
    kind: (j['kind'] as String?) ?? 'web',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'date': date,
    'kind': kind,
  };

  String get domain {
    final u = Uri.tryParse(url);
    return (u?.host ?? url).replaceFirst(RegExp(r'^www\.'), '');
  }
}

/// none | data | confirmed | unconfirmed
enum Verification { none, data, confirmed, unconfirmed }

/// A typed action proposed by the brain. The app executes it and reports
/// the real result; nothing is assumed to have succeeded.
class BrainAction {
  const BrainAction(this.type, this.args);
  final String type;
  final Map<String, dynamic> args;

  static BrainAction fromJson(Map<String, dynamic> j) =>
      BrainAction(j['type'] as String? ?? '', Map.of(j)..remove('type'));
}

class BrainReply {
  const BrainReply({
    required this.displayText,
    required this.ttsText,
    required this.language,
    required this.emotion,
    required this.intensity,
    this.actions = const [],
    this.sources = const [],
    this.verification = Verification.none,
    this.usedTools = const [],
    this.searchUnavailable = false,
  });

  final String displayText;
  final String ttsText;
  final String language;
  final Emotion emotion;
  final double intensity;
  final List<BrainAction> actions;
  final List<SourceRef> sources;
  final Verification verification;
  final List<String> usedTools;
  final bool searchUnavailable;

  /// Validates the backend payload. Throws [FormatException] on bad data.
  static BrainReply fromJson(Map<String, dynamic> j) {
    final display = j['display_text'];
    final tts = j['tts_text'];
    if (display is! String || display.trim().isEmpty) {
      throw const FormatException('display_text missing');
    }
    if (tts is! String || tts.trim().isEmpty) {
      throw const FormatException('tts_text missing');
    }
    final lang = j['language'];
    if (lang is! String || !['darija', 'ar', 'fr', 'en'].contains(lang)) {
      throw const FormatException('language invalid');
    }
    final intensity = j['intensity'];
    if (intensity is! num || intensity < 0 || intensity > 1) {
      throw const FormatException('intensity invalid');
    }
    return BrainReply(
      displayText: display,
      ttsText: tts,
      language: lang,
      emotion: Emotion.parse(j['emotion'] as String?),
      intensity: intensity.toDouble(),
      actions: [
        for (final a in (j['actions'] as List? ?? const []))
          if (a is Map<String, dynamic>) BrainAction.fromJson(a),
      ],
      sources: [
        for (final s in (j['sources'] as List? ?? const []))
          if (s is Map<String, dynamic>) SourceRef.fromJson(s),
      ],
      verification: Verification.values.firstWhere(
        (v) => v.name == j['verification'],
        orElse: () => Verification.none,
      ),
      usedTools: [
        for (final t in (j['used_tools'] as List? ?? const []))
          if (t is String) t,
      ],
      searchUnavailable: j['search_unavailable'] == true,
    );
  }
}

sealed class BrainEvent {
  const BrainEvent();
}

class BrainStatus extends BrainEvent {
  const BrainStatus(this.phase);
  final String phase; // thinking | searching | weather | retrying
}

class BrainDelta extends BrainEvent {
  const BrainDelta(this.text);
  final String text;
}

class BrainFinal extends BrainEvent {
  const BrainFinal(this.reply);
  final BrainReply reply;
}
