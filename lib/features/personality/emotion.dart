/// Every face state SAHBI can show.
enum Emotion {
  neutral,
  happy,
  sad,
  curious,
  surprised,
  sleepy,
  angry,
  listening,
  speaking,
  music;

  /// Emotions an LLM / detector may produce (the rest are app states).
  static const conversational = [
    neutral,
    happy,
    sad,
    curious,
    surprised,
    sleepy,
    angry,
  ];

  static Emotion parse(String? raw, {Emotion fallback = Emotion.neutral}) {
    if (raw == null) return fallback;
    final v = raw.trim().toLowerCase();
    for (final e in Emotion.values) {
      if (e.name == v) return e;
    }
    return fallback;
  }
}
