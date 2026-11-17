import 'emotion.dart';

class DetectedEmotion {
  const DetectedEmotion(this.emotion, this.intensity, {this.source = 'rules'});
  final Emotion emotion;
  final double intensity;

  /// 'llm' when taken from the AI reply, 'rules' for the offline detector.
  final String source;

  @override
  String toString() => 'DetectedEmotion($emotion, $intensity, $source)';
}

/// Reads the LLM `emotion` field, with an offline lexicon + rule fallback
/// that understands Darija (Arabic script and Arabizi), French and English.
class EmotionDetector {
  const EmotionDetector();

  DetectedEmotion fromLlm(String? emotion, num? intensity) {
    final e = Emotion.parse(emotion);
    final i = (intensity ?? 0.5).toDouble();
    final safe = Emotion.conversational.contains(e) ? e : Emotion.neutral;
    return DetectedEmotion(safe, i.isNaN ? 0.5 : i.clamp(0, 1), source: 'llm');
  }

  static const Map<Emotion, List<String>> lexicon = {
    Emotion.happy: [
      'hamdoullah',
      'hamdolah',
      'l7amdoulilah',
      '7amdolah',
      'zwin',
      'zwina',
      'mzyan',
      'mezyan',
      'nadi',
      'nady',
      'top',
      'wa3er',
      'wa3era',
      'fr7an',
      'fer7an',
      'far7an',
      '3jbni',
      'kan7bk',
      'kanbghik',
      'merci',
      'chokran',
      'choukran',
      'shukran',
      'haha',
      'hhh',
      'mdr',
      'lol',
      'super',
      'génial',
      'genial',
      'great',
      'awesome',
      'love',
      'happy',
      'content',
      'bravo',
      'الحمد لله',
      'زوين',
      'مزيان',
      'فرحان',
      'شكرا',
      'واعر',
      'نادي',
      'عجبني',
      'كنبغيك',
      'هههه',
      '😂',
      '😄',
      '😍',
      '❤',
      '🥰',
      '👍',
    ],
    Emotion.sad: [
      'm9ale9',
      'mqale9',
      'mqalqa',
      '7azin',
      '7zin',
      'mrid',
      'mrida',
      'te3ban',
      'ta3ban',
      'bkit',
      'kanbki',
      'wa7id',
      'bo7di',
      'mdeyye9',
      'mdi9',
      'triste',
      'déprimé',
      'deprime',
      'seul',
      'sad',
      'lonely',
      'tired',
      'crying',
      'depressed',
      'fatigué',
      'malade',
      'sick',
      'مقلق',
      'حزين',
      'مريض',
      'عيان',
      'تعبان',
      'بكيت',
      'بوحدي',
      'مضيق',
      '😢',
      '😭',
      '💔',
      '😞',
    ],
    Emotion.angry: [
      'tqelle9t',
      'm3assab',
      'mnerv',
      'mnarvi',
      'ghaddeb',
      'tfou',
      'n3el',
      'khayeb',
      'énervé',
      'enerve',
      'fâché',
      'angry',
      'furious',
      'hate',
      'stupid',
      'mkelkh',
      'معصب',
      'منرفز',
      'غضبان',
      'خايب',
      'تفو',
      '😡',
      '🤬',
      '😠',
    ],
    Emotion.surprised: [
      'wa3',
      'wah',
      'wili',
      'wiliii',
      'ya latif',
      'subhanallah',
      'bssa7',
      'b9a9a',
      'sérieux',
      'serieux',
      'quoi',
      'incroyable',
      'wow',
      'omg',
      'really',
      'no way',
      'واو',
      'ويلي',
      'يا لطيف',
      'سبحان الله',
      'بصح',
      '😮',
      '😲',
      '🤯',
    ],
    Emotion.sleepy: [
      'n3ast',
      'n3es',
      'na3ss',
      'fiya nn3as',
      'bghit nn3es',
      'lil',
      'tesb7',
      'tsb7',
      'fatigue',
      'dodo',
      'sommeil',
      'sleepy',
      'sleep',
      'goodnight',
      'good night',
      'bonne nuit',
      'نعاس',
      'نعست',
      'بغيت ننعس',
      'تصبح على خير',
      '😴',
      '🥱',
    ],
    Emotion.curious: [
      'ach',
      'chno',
      'chnou',
      'achnou',
      'kifach',
      'kif',
      '3lach',
      'fin',
      'fayn',
      'imta',
      'mnin',
      'chkoun',
      'ch7al',
      'wach',
      'pourquoi',
      'comment',
      'quoi',
      'why',
      'how',
      'what',
      'when',
      'where',
      'who',
      'شنو',
      'آش',
      'كيفاش',
      'علاش',
      'فين',
      'إمتا',
      'شكون',
      'شحال',
      'واش',
      '🤔',
    ],
  };

  /// Offline, rule-based detection from text (user message or reply text).
  DetectedEmotion detect(String text) {
    final t = ' ${text.toLowerCase()} ';
    if (t.trim().isEmpty) return const DetectedEmotion(Emotion.neutral, 0.3);
    final scores = <Emotion, double>{};
    for (final entry in lexicon.entries) {
      for (final word in entry.value) {
        if (_contains(t, word)) {
          scores[entry.key] = (scores[entry.key] ?? 0) + 1;
        }
      }
    }
    // Punctuation and tone.
    final exclaims = '!'.allMatches(text).length;
    final questions = '?'.allMatches(text).length + '؟'.allMatches(text).length;
    if (questions > 0) {
      scores[Emotion.curious] = (scores[Emotion.curious] ?? 0) + 0.6;
    }
    if (exclaims >= 2 && (scores[Emotion.angry] ?? 0) == 0) {
      scores[Emotion.surprised] = (scores[Emotion.surprised] ?? 0) + 0.5;
    }
    final letters = text.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.length >= 6 && letters == letters.toUpperCase()) {
      scores[Emotion.angry] =
          (scores[Emotion.angry] ?? 0) + 1.5; // shouting dominates
    }
    // Negation flips happy → sad ("ma mzyanch", "machi zwin", "pas bien").
    if (RegExp(r'(machi|mashi|ma\s?\w+ch\b|pas|not|ماشي|ما\s?\S+ش)')
            .hasMatch(t) &&
        (scores[Emotion.happy] ?? 0) > 0) {
      scores[Emotion.sad] = (scores[Emotion.sad] ?? 0) + scores[Emotion.happy]!;
      scores.remove(Emotion.happy);
    }
    if (scores.isEmpty) return const DetectedEmotion(Emotion.neutral, 0.3);
    // Priority on ties: sad > angry > happy > surprised > sleepy > curious.
    const priority = [
      Emotion.sad,
      Emotion.angry,
      Emotion.happy,
      Emotion.surprised,
      Emotion.sleepy,
      Emotion.curious,
    ];
    final best = priority.reduce(
      (a, b) => (scores[b] ?? 0) > (scores[a] ?? 0) ? b : a,
    );
    final s = scores[best]!;
    final intensity = (0.35 + 0.2 * s + 0.05 * exclaims).clamp(0.3, 1.0);
    return DetectedEmotion(best, intensity.toDouble());
  }

  static bool _contains(String haystack, String word) {
    final isAscii = RegExp(r'^[\x00-\x7F]+$').hasMatch(word);
    if (!isAscii) return haystack.contains(word);
    final escaped = RegExp.escape(word);
    return RegExp('(?<![a-z0-9])$escaped(?![a-z0-9])').hasMatch(haystack);
  }
}
