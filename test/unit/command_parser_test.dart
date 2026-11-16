import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/brain/command_parser.dart';

typedef C = CommandType;

/// (phrase, expected type or null, optional checks)
class Case {
  const Case(this.phrase, this.type, {this.query, this.source, this.value, this.language});
  final String phrase;
  final CommandType? type;
  final String? query;
  final MusicSource? source;
  final int? value;
  final String? language;
}

const cases = <Case>[
  // ---- play: Arabizi
  Case('Ch3el lia chi music', C.musicPlay, source: MusicSource.any),
  Case('ch3el lmusic', C.musicPlay),
  Case('Sh3el lia chi musique', C.musicPlay),
  Case('dir lia chi ghnya dyal Hoba Hoba Spirit', C.musicPlay, query: 'hoba hoba spirit'),
  Case('ch3el lia nass el ghiwane f spotify', C.musicPlay, query: 'nass el ghiwane', source: MusicSource.spotify),
  Case('ch3el spotify', C.musicPlay, source: MusicSource.spotify),
  Case('Ch3el lia chi music!!', C.musicPlay),
  // ---- play: Arabic script
  Case('شعل ليا شي موسيقى', C.musicPlay),
  Case('شغل الموسيقى', C.musicPlay),
  // ---- play: French / English
  Case('mets de la musique', C.musicPlay),
  Case('play some music', C.musicPlay),
  Case('play Saad Lamjarred on youtube music', C.musicPlay, query: 'saad lamjarred', source: MusicSource.youtubeMusic),
  // ---- stop / pause / resume / next / previous
  Case('Wqef lmusic', C.musicStop),
  Case('Wqeeef lmusic!!', C.musicStop),
  Case('وقف الموسيقى', C.musicStop),
  Case('arrête la musique', C.musicStop),
  Case('arrete la musique', C.musicStop),
  Case('stop the music', C.musicStop),
  Case('pause', C.musicPause),
  Case('kemmel lmusic', C.musicResume),
  Case('next', C.musicNext),
  Case('douz', C.musicNext),
  Case('li 9bel', C.musicPrevious),
  // ---- generic stop / stop speaking
  Case('wqef', C.stopGeneric),
  Case('stop', C.stopGeneric),
  Case('baraka', C.stopGeneric),
  Case('skt', C.stopSpeaking),
  // ---- volume
  Case('Zid lvolume', C.volumeUp),
  Case('zid sout', C.volumeUp),
  Case('زيد الصوت', C.volumeUp),
  Case('monte le son', C.volumeUp),
  Case('louder', C.volumeUp),
  Case('volume up', C.volumeUp),
  Case('N9es lvolume', C.volumeDown),
  Case('نقص الصوت', C.volumeDown),
  Case('baisse le son', C.volumeDown),
  Case('volume down', C.volumeDown),
  Case('volume 40', C.volumeSet, value: 40),
  Case('volume 150', C.volumeSet, value: 100),
  // ---- listen
  Case('Sme3 lia', C.listen),
  Case('Sme33 liaaa', C.listen),
  Case('سمع ليا', C.listen),
  // ---- reply language
  Case('hder m3aya b lfransawiya', C.setReplyLanguage, language: 'fr'),
  Case('speak english', C.setReplyLanguage, language: 'en'),
  Case('tkellem bdarija', C.setReplyLanguage, language: 'darija'),
  Case('تكلم معايا بالعربية', C.setReplyLanguage, language: 'ar'),
  // Regression: the French preposition "en" must not be read as English.
  Case('parle en français', C.setReplyLanguage, language: 'fr'),
  Case('réponds en anglais', C.setReplyLanguage, language: 'en'),
  Case('reply in english', C.setReplyLanguage, language: 'en'),
  // ---- script
  Case('kteb b latin', C.setDarijaScript, language: 'latin'),
  // ---- navigation
  Case('7el settings', C.openSettings),
  // ---- must fall through to the AI (null)
  Case('Salam Sahbi', null),
  Case('Kif dayr?', null),
  Case('Qelleb lia 3la akher akhbar lmaghrib', null),
  Case('Ch7al kayn f ta9s f Tanger?', null),
  Case('Trjem lia had lkalma', null),
  Case('Ya Sahbi', null),
  Case('ach katdir', null),
  Case('3awed lia chi nkta', null),
  Case('chno hiya l3asima dyal lmaghrib?', null),
  Case('السلام عليكم', null),
  Case('bonjour, ça va ?', null),
  Case('what is the weather in Rabat', null),
  Case('ana fer7an lyoum', null),
  Case('', null),
];

void main() {
  const p = CommandParser();

  test('has at least 60 phrases', () => expect(cases.length, greaterThanOrEqualTo(60)));

  for (final c in cases) {
    test('"${c.phrase}" → ${c.type?.name ?? 'null'}', () {
      final r = p.parse(c.phrase);
      if (c.type == null) {
        expect(r, isNull, reason: 'should fall through to the AI, got $r');
        return;
      }
      expect(r, isNotNull);
      expect(r!.type, c.type);
      if (c.query != null) expect(r.query, c.query);
      if (c.source != null) expect(r.source, c.source);
      if (c.value != null) expect(r.value, c.value);
      if (c.language != null) expect(r.language, c.language);
    });
  }
}
