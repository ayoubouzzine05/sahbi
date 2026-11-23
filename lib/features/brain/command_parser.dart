import 'text_normalizer.dart';

/// Deterministic, offline intents handled without the AI brain.
enum CommandType {
  musicPlay,
  musicPause,
  musicResume,
  musicStop,
  musicNext,
  musicPrevious,
  volumeUp,
  volumeDown,
  volumeSet,

  /// Bare "stop"/"wqef": the app decides (stop speech, else music).
  stopGeneric,
  stopSpeaking,
  listen,
  stopListening,
  setReplyLanguage,
  setDarijaScript,
  openSettings,
  openMusic,

  /// Live camera: "7el camera", "chouf hadi", "شوف هادي".
  openCamera,

  /// Face skit asked by voice: "haz ydik", "kol", "chrob atay", "ghmed
  /// 3inik", "kanbghik", "chte7"... [Command.query] = FaceAct wire name.
  faceAct,
}

/// `youtube` = played inside the app (embedded YouTube player).
enum MusicSource { any, local, spotify, youtubeMusic, youtube }

class Command {
  const Command(
    this.type, {
    this.query,
    this.source = MusicSource.any,
    this.value,
    this.language,
  });

  final CommandType type;

  /// Free text after the verb, e.g. artist or song name.
  final String? query;
  final MusicSource source;

  /// Volume level 0..100 for [CommandType.volumeSet].
  final int? value;

  /// 'darija' | 'ar' | 'fr' | 'en' for language switch; 'arabic' | 'latin' for script.
  final String? language;

  @override
  String toString() =>
      'Command($type, query: $query, source: $source, value: $value, language: $language)';

  @override
  bool operator ==(Object other) =>
      other is Command &&
      other.type == type &&
      other.query == query &&
      other.source == source &&
      other.value == value &&
      other.language == language;

  @override
  int get hashCode => Object.hash(type, query, source, value, language);
}

/// Local command parser. Patterns are written against [normalizeText] output
/// (lower-case, no accents, repeated letters collapsed, ة→ه, ى→ي, أ→ا).
class CommandParser {
  const CommandParser();

  // ---- vocabulary -------------------------------------------------------
  static const _music =
      r'(?:l|el|la |le |the |al)?(?:music|musik|musi[9qk]a|musique|muzik|mzika|mouzika|zika|ghnya|ghenya|ghanya|ghniya|ghinya|ghani|chanson|chansons|song|songs|track|morceau|playlist|موسيقي|موسيقا|موزيكا|ميوزيك|اغنيه|اغاني|غنيه)';
  static const _musicAr =
      r'(?:ال)?(?:موسيقي|موسيقا|موزيكا|ميوزيك|اغنيه|اغاني|غنيه|ميزيكا)';
  static const _lia = r'(?:\s+(?:lia|lya|liya|li|ليا|لي|ليه))?';

  static final _volumeNumber = RegExp(
    r'(?:volume|lvolume|sout|son|الصوت|صوت)\D{0,12}?(\d{1,3})\s*%?',
  );
  static final _volumeUp = RegExp(
    r'(?:\bzid\b|\btl[ae]?3\b|\btale3\b|\b3li\b|\b3eli\b|\bt3li\b|\bmonte|\baugmente|\bplus fort|\bturn up|\blouder|\bup\b|زيد|علي|طلع)'
    r'.{0,14}(?:volume|sout|son|الصوت|صوت)|volume up|louder|plus fort|زيد الصوت|علي الصوت',
  );
  static final _volumeDown = RegExp(
    r'(?:\bn[9qk]e?s\b|\bn[9qk]as\b|\bhbet\b|\bhebet\b|\bteyeh\b|\bbaise|\b\bmoins fort|\bturn down|\bquieter|\bdown\b|نقص|هبط|طيح)'
    r'.{0,14}(?:volume|sout|son|الصوت|صوت)|volume down|quieter|moins fort|نقص الصوت|هبط الصوت',
  );

  static final _langSwitch = RegExp(
    r'(?:hder|hdr|hadr|tkelem|tkalem|tkelm|jaweb|jawb|rd|red|parle|parles|reponds|speak|talk|answer|reply|هضر|تكلم|جاوب|رد|احكي)'
    r'.{0,22}?(darija|derija|dareja|maghribi|marocain|moroccan|3arbiya|3arbia|l3arbia|arabe|arabic|fos7a|fusha|fransawiya|fransawia|fransa|francais|french|fr|nglizia|ngliziya|anglais|englich|دارجه|الدارجه|مغربي|عربيه|العربيه|الفصحي|فرنسيه|الفرنسيه|فرنساويه|بالفرنسيه|انجليزيه|الانجليزيه|نجليزيه|الانكليزيه)(?=\s|$)',
  );

  static final _scriptSwitch = RegExp(
    r'(?:kteb|ktb|ecris|write|كتب|اكتب).{0,20}?(latin|latini|l7rof latin|arabizi|francais|lettres latines|3arbiya|3arbia|arabe|arabic|عربيه|بالعربيه|لاتيني|بالحروف اللاتينيه)',
  );

  static final _listen = RegExp(
    r'^(?:ya sahbi |sahbi )?(?:sme3|sm3|sma3|sme3ni|sma3ni|tsenani nhder|ecoute|ecoute moi|ecoutes|listen|listen to me|سمع|سمعني|اسمع|اسمعني)'
    r'(?:\s+(?:lia|lya|liya|li|ليا|لي|moi|me|mzyan))?$',
  );
  static final _stopListening = RegExp(
    r'(?:stop listening|arete d ecouter|ma tsme3ch|wqef ma tsme3|حبس ما تسمع)',
  );
  static final _stopSpeaking = RegExp(
    r'^(?:skt|sket|sekt|sakt|skot|tais toi|tais|chut|stop talking|be quiet|chut up|arete de parler|baraka mn lhdra|baraka mn lhedra|سكت|اسكت|بركا من الهضره|بركا من الهدره)$',
  );
  static final _stopGeneric = RegExp(
    r'^(?:wqef|wqf|w9ef|w9f|wa9ef|waqef|stop|arete|baraka|7bes|hbes|وقف|حبس|بركا|ستوب)(?:\s+(?:a sahbi|sahbi|daba|db|please|svp|عافاك|3afak))?$',
  );

  static final _stopMusic = RegExp(
    '(?:wqef|wqf|w9ef|w9f|wa9ef|waqef|stop|arete|coupe|baraka mn|7bes|hbes|tfi|وقف|حبس|بركا من|طفي|ستوب)$_lia\\s+(?:$_music|$_musicAr)'
    '|(?:$_music|$_musicAr)\\s+(?:stop|off)'
    '|^(?:stop the music|turn off the music|arete la musique|coupe la musique)\$',
  );

  static final _pause = RegExp(
    r'^(?:pause|dir pause|dir lia pause|met en pause|mets en pause|pause the music|pause music|pause la musique|توقف مؤقت|دير بوز|بوز)$'
    '|(?:pause)\\s+(?:$_music|$_musicAr)',
  );

  static final _resume = RegExp(
    r'^(?:resume|reprends|reprend|continue|kemel|kmel|kamel|kemel lmusic|kemel lmusi9a|كمل|كمل الموسيقي|كمل الموزيكا|زيد كمل)$'
    '|(?:kemel|kmel|kamel|reprends|resume|continue|كمل)\\s+(?:$_music|$_musicAr)',
  );

  static final _next = RegExp(
    r'(?:^next$|next (?:song|track)|skip|suivant|chanson suivante|morceau suivant|li mn b3d|li men ba3d|lmn b3d|douz|dowz|dawez|douwez|zid l(?:track|ghnya|music) li mn b3d|التاليه|اللي من بعد|دوز|اللي موراها)',
  );
  static final _previous = RegExp(
    r'(?:previous|precedent|precedente|chanson precedente|li 9bel|li qbel|li kbel|lqbel|rje3 l9bel|رجع للي قبل|اللي قبل|السابقه)',
  );

  static final _play = RegExp(
    r'(?:ch3el|ch3al|cha3el|che3el|chghel|chghl|chaghel|chegel|dir|dor|7et|7at|hat|jib|play|mets|met|joue|lance|put on|شعل|شغل|دير|حط|جيب|ابدا)'
    '$_lia'
    r'(?:\s+(?:chi|chy|wa7ed|wahed|une|un|de la|du|some|a|شي|واحد))?\s+'
    '(?:$_music|$_musicAr)'
    r'(?<rest>.*)$',
  );
  static final _playDirect = RegExp(
    r'^(?:ch3el|ch3al|chghel|chghl|play|joue|mets|شعل|شغل)'
    '$_lia'
    r'\s+(?<rest>.+)$',
  );

  static final _settings = RegExp(
    r'(?:^|\s)(?:setings|seting|reglages|parametres|parametre|l?parametres|إعدادات|اعدادات|الاعدادات|الإعدادات)(?:\s|$)',
  );
  static final _openSettingsVerb = RegExp(
    r'(?:7el|hel|7al|open|ouvre|ouvrir|حل|افتح|فتح)',
  );

  static final _camera = RegExp(
    r'(?:^|\s)(?:l?camera|l?kamera|kamira|camira|كاميرا|الكاميرا|كاميرة|الكاميره|كاميره)(?:\s|$)',
  );
  static final _cameraVerb = RegExp(
    r'(?:7el|hel|7al|7ell|open|ouvre|ouvrir|allume|cha3el|ch3el|chaal|حل|افتح|فتح|شعل)',
  );

  /// The sentence names the camera itself ("7el camera").
  static bool mentionsCamera(String normalized) => _camera.hasMatch(normalized);

  // "chouf hadi / chno hada / شوف هادي / شنو هادا" — show-and-explain.
  static final _lookAtThis = RegExp(
    r'^(?:(?:a|ya)\s+\S+\s+)?(?:chouf|chof|shouf|regarde|lo+k at|شوف)\s+(?:hadi|hada|hado|had chi|hadchi|this|ca|هادي|هادا|هاد|هادشي|هدا|هدي)(?:\s|$)',
  );

  // ---- face skits ("haz ydik", "kol", "chrob atay"...) --------------------
  static const _who =
      r'^(?:(?:a|ya|wa|يا|ا)\s+\S+\s+)?(?:(?:yallah|yalah|yala|sir|aji|يالاه|سير|اجي)\s+)?';
  static const _please =
      r'(?:\s+(?:3afak|afak|3fak|عافاك|please|stp|svp|s il te plait|daba|دابا|a sahbi|ا صاحبي))?\s*[!?.]*$';
  static final _faceActs = <String, RegExp>{
    'hands_up': RegExp(
      '$_who(?:(?:hez|haz|hz|rfe3|rfa3|rf3|9le3|lev|leve|levez|raise|put|هز|ارفع|رفع|طلع)\\s+(?:(?:lia|liya|ليا)\\s+)?(?:ydik|yedik|idik|yidik|ydek|yedek|ydiyk|lydin|les mains|tes mains|your hands|hands|يديك|يدك|ايديك|ايدك)(?:\\s+up)?|hands up|haut les mains|mains en l ?air)$_please',
    ),
    'eat': RegExp(
      '$_who(?:(?:kol|koul|kul|kuli|mange|manger|eat|كول|كل|كولي)(?:\\s+(?:chi|chwiya|شي|شويه|something|quelque chose|un peu|ka3b ghzal|كعب غزال|chi haja|شي حاجه|ch?i 7aja))?|(?:wach|واش)\\s+(?:(?:nta|nti|انت|نتا)\\s+)?(?:ji3an|jiw3an|jou3an|ji3an|جيعان)|tu as faim|t as faim|tas faim|are you hungry)$_please',
    ),
    'drink': RegExp(
      '$_who(?:(?:chrb|chreb|cherb|chrob|chorb|ochrob|ochreb|ochrb|shrb|shreb|bois|drink|اشرب|شرب|تشرب)(?:\\s+(?:chi|chwiya|شي|شويه|kas|كاس|un|du|some))?(?:\\s+(?:atay|atai|tay|lma|ma|lme|اتاي|الما|ما|the|thé|tea|water|eau|d atay|dyal atay))?|(?:wach|واش)\\s+(?:(?:nta|nti|انت|نتا)\\s+)?(?:3tchan|3atchan|3tchane|عطشان)|tu as soif|t as soif|tas soif|are you thirsty)$_please',
    ),
    'peekaboo': RegExp(
      '$_who(?:(?:ghmed|ghemd|ghmd|ghamed|ghmmed|sed|خبي|غمض|سد)\\s+(?:3inik|3ynik|3inek|عينيك|عينك)|cache[- ]?cache|peek ?a ?boo|peka ?bo|pek a bo|cache tes yeux|cover your eyes|tkhba|تخبا|bouh|بوه)$_please',
    ),
    'love': RegExp(
      '$_who(?:(?:ana\\s+|انا\\s+)?(?:kanbghik|kanbghik bzaf|kanbrik|kan7mek|kan7bek|kan7ebek|n7ebek|n7bek|كنبغيك|كنحبك|نبغيك|je t aime|je taime|je t adore|je tadore|i love you|love you|kanmout 3lik|كنموت عليك)(?:\\s+(?:bzaf|بزاف|a sahbi|ا صاحبي|so much|beaucoup|\\S+))?|(?:3tini\\s+)?(?:bousa|بوسه))$_please',
    ),
    'dance': RegExp(
      '$_who(?:chte7|chta7|chet7|chat7|cht7|ochte7|danse|dance|شطح|اشطح|ترقص|ارقص|r9es|r9s)(?:\\s+(?:chwiya|شويه|m3aya|معايا|avec moi|with me))?$_please',
    ),
    'yawn': RegExp(
      '$_who(?:(?:wach|واش)\\s+(?:(?:nta|nti|انت|نتا)\\s+)?(?:na3s|n3as|ne3san|n3san|3iyan|3yan|ناعس|عيان)|t3ayiti|ta3ayiti|عييتي|tu es fatigue|t es fatigue|tes fatigue|are you tired|are you sleepy)$_please',
    ),
  };

  // ---- API ----------------------------------------------------------------
  Command? parse(String raw) {
    final t = normalizeText(raw);
    if (t.isEmpty) return null;

    final lang = _langSwitch.firstMatch(t);
    if (lang != null) {
      final code = _languageCode(lang.group(1)!);
      if (code != null) {
        return Command(CommandType.setReplyLanguage, language: code);
      }
    }
    final script = _scriptSwitch.firstMatch(t);
    if (script != null) {
      final w = script.group(1)!;
      final latin =
          w.contains('lat') ||
          w.contains('arabizi') ||
          w.contains('francais') ||
          w.contains('لاتيني');
      return Command(
        CommandType.setDarijaScript,
        language: latin ? 'latin' : 'arabic',
      );
    }

    final vol = _volumeNumber.firstMatch(t);
    if (vol != null) {
      final n = int.parse(vol.group(1)!).clamp(0, 100);
      return Command(CommandType.volumeSet, value: n);
    }
    if (_volumeUp.hasMatch(t)) return const Command(CommandType.volumeUp);
    if (_volumeDown.hasMatch(t)) return const Command(CommandType.volumeDown);

    if (_stopListening.hasMatch(t)) {
      return const Command(CommandType.stopListening);
    }
    if (_stopMusic.hasMatch(t)) return const Command(CommandType.musicStop);
    if (_stopSpeaking.hasMatch(t)) {
      return const Command(CommandType.stopSpeaking);
    }
    if (_stopGeneric.hasMatch(t)) return const Command(CommandType.stopGeneric);
    if (_listen.hasMatch(t)) return const Command(CommandType.listen);
    if (_pause.hasMatch(t)) return const Command(CommandType.musicPause);
    if (_resume.hasMatch(t)) return const Command(CommandType.musicResume);
    if (_previous.hasMatch(t)) return const Command(CommandType.musicPrevious);
    if (_next.hasMatch(t)) return const Command(CommandType.musicNext);

    final play = _play.firstMatch(t);
    if (play != null) {
      final rest = _lightTail(raw, t, play.namedGroup('rest') ?? '');
      final (query, source) = _splitQuery(rest);
      return Command(CommandType.musicPlay, query: query, source: source);
    }
    // "ch3el spotify", "play nass el ghiwane f spotify"
    final direct = _playDirect.firstMatch(t);
    if (direct != null) {
      final rest = _lightTail(raw, t, direct.namedGroup('rest')!);
      final (query, source) = _splitQuery(' $rest');
      if (source != MusicSource.any || query != null) {
        return Command(CommandType.musicPlay, query: query, source: source);
      }
    }

    for (final e in _faceActs.entries) {
      if (e.value.hasMatch(t)) {
        return Command(CommandType.faceAct, query: e.key);
      }
    }

    if ((_camera.hasMatch(t) &&
            (_cameraVerb.hasMatch(t) || t.split(' ').length <= 2)) ||
        _lookAtThis.hasMatch(t)) {
      return const Command(CommandType.openCamera);
    }
    if (_settings.hasMatch(t) &&
        (_openSettingsVerb.hasMatch(t) || t.split(' ').length <= 2)) {
      return const Command(CommandType.openSettings);
    }
    if (RegExp('^(?:$_music|$_musicAr)\$').hasMatch(t)) {
      return const Command(CommandType.openMusic);
    }
    return null;
  }

  /// Returns the tail of the *uncollapsed* text with as many words as
  /// [normRest], so queries keep their spelling ("Nass El Ghiwane").
  static String _lightTail(String raw, String norm, String normRest) {
    final restWords = normRest.trim().isEmpty
        ? 0
        : normRest.trim().split(' ').length;
    if (restWords == 0) return '';
    final light = normalizeText(raw, collapse: false).split(' ');
    if (light.length != norm.split(' ').length) return normRest;
    return light.sublist(light.length - restWords).join(' ');
  }

  static String? _languageCode(String w) {
    if (RegExp(r'darija|derija|dareja|maghribi|marocain|moroccan|دارجه|مغربي')
        .hasMatch(w)) {
      return 'darija';
    }
    if (RegExp(r'fran|french|^fr$|فرنس').hasMatch(w)) return 'fr';
    if (RegExp(r'ngliz|anglais|englich|نجليز|انكليز').hasMatch(w)) {
      return 'en';
    }
    if (RegExp(r'3arbi|arab|fos7a|fusha|عربي|فصحي').hasMatch(w)) return 'ar';
    return null;
  }

  static final _sourceSpotify = RegExp(
    r'\s*(?:f|fi|fe|f l|sur|on|in|من|ف|في|على)?\s*(?:spotify|spotifay|سبوتيفاي|سبوتيفي)\s*',
  );
  static final _sourceYt = RegExp(
    r'\s*(?:f|fi|fe|sur|on|in|من|ف|في|على)?\s*(?:youtube music|yt music|youtube|ytb|يوتيوب ميوزيك|يوتيوب)\s*',
  );
  static final _sourceLocal = RegExp(
    r'\s*(?:mn|men|from|de|depuis|من)?\s*(?:telephone|tilifoun|phone|lphone|portable|local|dyali|التلفون|التيليفون|ديالي)\s*',
  );

  static (String?, MusicSource) _splitQuery(String rest) {
    var r = ' $rest ';
    var source = MusicSource.any;
    if (_sourceSpotify.hasMatch(r)) {
      source = MusicSource.spotify;
      r = r.replaceAll(_sourceSpotify, ' ');
    } else if (_sourceYt.hasMatch(r)) {
      source = MusicSource.youtube;
      r = r.replaceAll(_sourceYt, ' ');
    } else if (_sourceLocal.hasMatch(r)) {
      source = MusicSource.local;
      r = r.replaceAll(_sourceLocal, ' ');
    }
    r = r.trim().replaceFirst(
      RegExp(r'^(?:dyal|dial|diyal|d|de|du|des|by|of|from|ديال|د|ل)\s+'),
      '',
    );
    r = r.trim();
    return (r.isEmpty ? null : r, source);
  }
}
