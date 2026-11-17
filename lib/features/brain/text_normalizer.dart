/// Normalisation shared by the command parser and memory search.
///
/// Arabic: strips diacritics/tatweel, unifies alef/ya/ta-marbuta/hamza seats.
/// Latin: lower-case, strips accents, unifies "sh"→"ch", "5"→"kh".
/// Both: collapses repeated letters ("wqeeef" → "wqef", "سمععع" → "سمع"),
/// removes punctuation, collapses whitespace.
String normalizeText(String input, {bool collapse = true}) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp('[\u064B-\u0652\u0670\u0640]'), '');
  s = s
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('ڤ', 'ف')
      .replaceAll('گ', 'ك')
      .replaceAll('ک', 'ك')
      .replaceAll('ی', 'ي');
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'œ': 'oe',
    'ÿ': 'y',
  };
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(accents[ch] ?? ch);
  }
  s = b.toString();
  // Arabizi spelling variants.
  s = s.replaceAll('sh', 'ch').replaceAll(RegExp(r'(?<=[a-z]|^|\s)5'), 'kh');
  // Apostrophes join articles: l'music → lmusic, ' → nothing.
  s = s.replaceAll(RegExp("[’'`]"), '');
  // Punctuation → space (keep letters, digits, Arabic letters).
  s = s.replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A\s]'), ' ');
  // Collapse repeated letters, and repeated Arabizi digits after a letter.
  if (collapse) {
    s = s.replaceAllMapped(
      RegExp(r'([a-z\u0621-\u064A])\1+'),
      (m) => m.group(1)!,
    );
    s = s.replaceAllMapped(
      RegExp(r'(?<=[a-z])([2379])\1+'),
      (m) => m.group(1)!,
    );
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// True if [text] is mostly Arabic script.
bool isArabicScript(String text) {
  final arabic = RegExp('[\u0600-\u06FF]').allMatches(text).length;
  final latin = RegExp('[A-Za-z]').allMatches(text).length;
  return arabic > 0 && arabic >= latin;
}
