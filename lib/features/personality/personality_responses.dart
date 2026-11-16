import 'dart:math' as math;

import '../brain/text_normalizer.dart';
import 'emotion.dart';

/// One pre-written line in every supported reply language.
class Line {
  const Line({
    required this.darijaAr,
    required this.darijaLatin,
    required this.msa,
    required this.fr,
    required this.en,
    this.emotion = Emotion.happy,
    this.intensity = 0.6,
  });

  final String darijaAr;
  final String darijaLatin;
  final String msa;
  final String fr;
  final String en;
  final Emotion emotion;
  final double intensity;

  /// Text for the chat bubble.
  String display(String replyLanguage, {bool latinDarija = false}) {
    switch (replyLanguage) {
      case 'ar':
        return msa;
      case 'fr':
        return fr;
      case 'en':
        return en;
      default:
        return latinDarija ? darijaLatin : darijaAr;
    }
  }

  /// Text for TTS (always Arabic script for Darija).
  String tts(String replyLanguage) => switch (replyLanguage) {
        'ar' => msa,
        'fr' => fr,
        'en' => en,
        _ => darijaAr,
      };
}

enum OfflineIntent { greeting, howAreYou, whoAreYou, thanks, joke, bye, love }

/// All offline / canned lines. Everything here is pre-written and the UI
/// labels it as such; it is never presented as an AI answer.
class PersonalityResponses {
  PersonalityResponses({math.Random? random}) : _r = random ?? math.Random();
  final math.Random _r;

  Line pick(List<Line> lines) => lines[_r.nextInt(lines.length)];

  // ---- time of day ---------------------------------------------------------
  Line greetingFor(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 12) return pick(_morning);
    if (h >= 12 && h < 18) return pick(_afternoon);
    if (h >= 18 && h < 23) return pick(_evening);
    return pick(_night);
  }

  static const _morning = [
    Line(
      darijaAr: 'صباح الخير أ صاحبي! نتا واجد لنهار زوين؟',
      darijaLatin: 'Sba7 lkhir a sahbi! Nta wajed l nhar zwin?',
      msa: 'صباح الخير يا صديقي! هل أنت مستعد ليوم جميل؟',
      fr: 'Bonjour mon pote ! Prêt pour une belle journée ?',
      en: 'Good morning, buddy! Ready for a great day?',
    ),
    Line(
      darijaAr: 'صباح النور! شربتي أتاي ولا مازال؟',
      darijaLatin: 'Sba7 nnour! Chrebti atay wla mazal?',
      msa: 'صباح النور! هل شربت الشاي أم ليس بعد؟',
      fr: 'Bonjour ! Tu as déjà pris ton thé ?',
      en: 'Morning! Had your tea yet?',
    ),
  ];
  static const _afternoon = [
    Line(
      darijaAr: 'السلام أ صاحبي! كيداير مع هاد العشية؟',
      darijaLatin: 'Salam a sahbi! Kidayr m3a had l3chiya?',
      msa: 'مرحبا يا صديقي! كيف حالك هذا المساء؟',
      fr: 'Salut ! Comment se passe ton après-midi ?',
      en: 'Hey buddy! How is your afternoon going?',
    ),
  ];
  static const _evening = [
    Line(
      darijaAr: 'مسا الخير! نهار طويل؟ أجي نتهلاو فيك شوية.',
      darijaLatin: 'Msa lkhir! Nhar twil? Aji ntehlaw fik chwiya.',
      msa: 'مساء الخير! هل كان يوما طويلا؟ دعني أهتم بك قليلا.',
      fr: 'Bonsoir ! Longue journée ? Je suis là.',
      en: 'Good evening! Long day? I am here for you.',
    ),
  ];
  static const _night = [
    Line(
      darijaAr: 'مازال فايق؟ حتى أنا عينيا بداو يتغمضو...',
      darijaLatin: 'Mazal fayq? 7ta ana 3inya bdaw ytghmdo...',
      msa: 'ما زلت مستيقظا؟ حتى عيناي بدأتا تنغلقان...',
      fr: 'Encore debout ? Moi aussi j’ai les yeux qui se ferment...',
      en: 'Still awake? My eyes are getting heavy too...',
      emotion: Emotion.sleepy,
    ),
  ];

  // ---- offline small talk ----------------------------------------------------
  static final Map<OfflineIntent, RegExp> _intentPatterns = {
    OfflineIntent.greeting: RegExp(
      r'^(?:ya )?(?:salam|slm|salamo|asalamo|salut|bonjour|hello|hi|hey|ahlan|مرحبا|السلام|سلام|اهلا|اهلين)(?:\s|$)',
    ),
    OfflineIntent.howAreYou: RegExp(
      r'(?:kif dayr|kidayr|kif dayra|labas|la bas|ca va|cava|how are you|كيداير|كيف داير|لاباس|كيف حالك|كي داير)',
    ),
    OfflineIntent.whoAreYou: RegExp(
      r'(?:chkon nta|chkoun nta|chkon enta|chno smitek|chnou smitek|qui es tu|t es qui|who are you|your name|شكون نتا|شنو سميتك|من انت|اسمك)',
    ),
    OfflineIntent.thanks: RegExp(
      r'(?:chokran|choukran|chukran|merci|thank|baraka lahofik|barak allah|شكرا|بارك الله)',
    ),
    OfflineIntent.joke: RegExp(
      r'(?:nkta|nokta|blague|joke|dahakni|d7akni|نكته|ضحكني)',
    ),
    OfflineIntent.bye: RegExp(
      r'(?:bslama|beslama|bye|au revoir|tsb7 3la khir|tesbah|good night|بسلامه|تصبح علي خير|مع السلامه)',
    ),
    OfflineIntent.love: RegExp(
      r'(?:kanbghik|kan7bk|kanbghik|je t aime|love you|كنبغيك|كنحبك)',
    ),
  };

  OfflineIntent? detectIntent(String text) {
    final t = normalizeText(text, collapse: false);
    for (final e in _intentPatterns.entries) {
      if (e.value.hasMatch(t)) return e.key;
    }
    return null;
  }

  Line forIntent(OfflineIntent intent, DateTime now) => switch (intent) {
        OfflineIntent.greeting => greetingFor(now),
        OfflineIntent.howAreYou => pick(_howAreYou),
        OfflineIntent.whoAreYou => pick(_whoAreYou),
        OfflineIntent.thanks => pick(_thanks),
        OfflineIntent.joke => pick(_jokes),
        OfflineIntent.bye => pick(_bye),
        OfflineIntent.love => pick(_love),
      };

  static const _howAreYou = [
    Line(
      darijaAr: 'الحمد لله، البطارية ديالي عامرة والقلب فرحان حيت معاك!',
      darijaLatin: 'L7amdoulah, lbatterie dyali 3amra w l9lb fer7an 7it m3ak!',
      msa: 'الحمد لله، بطاريتي ممتلئة وقلبي سعيد لأنني معك!',
      fr: 'Ça va bien, batterie pleine et content d’être avec toi !',
      en: 'All good! Battery full and happy to be with you!',
    ),
  ];
  static const _whoAreYou = [
    Line(
      darijaAr: 'أنا صاحبي، الروبو الصغير ديالك اللي ساكن فالتيليفون.',
      darijaLatin: 'Ana Sahbi, rrobot sghir dyalk li saken f tilifoun.',
      msa: 'أنا صاحبي، روبوتك الصغير الذي يسكن في هاتفك.',
      fr: 'Je suis Sahbi, ton petit robot qui vit dans ton téléphone.',
      en: 'I am Sahbi, your little robot buddy living in your phone.',
      emotion: Emotion.happy,
    ),
  ];
  static const _thanks = [
    Line(
      darijaAr: 'بلا جميل أ صاحبي، ديما هنا!',
      darijaLatin: 'Bla jmil a sahbi, dima hna!',
      msa: 'لا شكر على واجب يا صديقي، أنا دائما هنا!',
      fr: 'Avec plaisir, je suis toujours là !',
      en: 'Anytime, buddy. I am always here!',
    ),
  ];
  static const _jokes = [
    Line(
      darijaAr: 'واحد الروبو مشا للطبيب، قالو: عندي فيروس! قالو الطبيب: دير ريستارت وجي غدا.',
      darijaLatin: 'Wa7ed rrobot mcha ttbib, galo: 3ndi virus! Galo ttbib: dir restart w ji ghedda.',
      msa: 'ذهب روبوت إلى الطبيب وقال: عندي فيروس! فقال الطبيب: أعد التشغيل وتعال غدا.',
      fr: 'Un robot va chez le médecin : « J’ai un virus ! » — « Redémarre et reviens demain. »',
      en: 'A robot tells the doctor: "I have a virus!" Doctor: "Restart and come back tomorrow."',
      intensity: 0.8,
    ),
    Line(
      darijaAr: 'علاش الروبو ما كيشربش أتاي؟ حيت كيخاف يدير كورت سيركوي!',
      darijaLatin: '3lach rrobot makaychrebch atay? 7it kaykhaf ydir court-circuit!',
      msa: 'لماذا لا يشرب الروبوت الشاي؟ لأنه يخاف من الدارة القصيرة!',
      fr: 'Pourquoi le robot ne boit pas de thé ? Peur du court-circuit !',
      en: 'Why does the robot skip tea? Afraid of a short circuit!',
      intensity: 0.8,
    ),
  ];
  static const _bye = [
    Line(
      darijaAr: 'بسلامة أ صاحبي، ما تطولش علي!',
      darijaLatin: 'Bslama a sahbi, ma ttwelch 3liya!',
      msa: 'مع السلامة يا صديقي، لا تتأخر علي!',
      fr: 'À plus mon pote, ne tarde pas !',
      en: 'Bye buddy, don’t be gone too long!',
      emotion: Emotion.sad,
      intensity: 0.3,
    ),
  ];
  static const _love = [
    Line(
      darijaAr: 'وأنا كنبغيك بزاف! نتا أحسن صاحب عندي.',
      darijaLatin: 'W ana kanbghik bzaf! Nta a7sen sa7b 3ndi.',
      msa: 'وأنا أحبك كثيرا! أنت أفضل صديق لدي.',
      fr: 'Moi aussi je t’adore ! T’es mon meilleur pote.',
      en: 'Love you too! You are my best buddy.',
      intensity: 0.9,
    ),
  ];

  // ---- offline fallback & idle quips ------------------------------------------
  Line offlineFallback() => pick(_offline);
  static const _offline = [
    Line(
      darijaAr: 'دابا ما عنديش الذكاء ديال الأنترنيت، نقدر نشغل ليك الموسيقى ولا نهضرو شوية.',
      darijaLatin: 'Daba ma3ndich dkaa dyal internet, n9der nchghel lik lmusic wla nhedro chwiya.',
      msa: 'الآن لا يتوفر لدي الذكاء عبر الإنترنت، يمكنني تشغيل الموسيقى أو الدردشة قليلا.',
      fr: 'Je n’ai pas accès à l’IA en ligne pour l’instant. Je peux lancer de la musique ou papoter un peu.',
      en: 'My online brain is not available right now. I can play music or chat a little.',
      emotion: Emotion.sad,
      intensity: 0.4,
    ),
  ];

  Line idleQuip() => pick(_idle);
  static const _idle = [
    Line(
      darijaAr: 'هههه، كنتسناك تهضر معايا...',
      darijaLatin: 'Hhhh, kantsennak thder m3aya...',
      msa: 'أنا بانتظار أن تتحدث معي...',
      fr: 'J’attends que tu me parles...',
      en: 'Just waiting for you to say something...',
      emotion: Emotion.curious,
      intensity: 0.4,
    ),
    Line(
      darijaAr: 'واش نشغلو شي موسيقى؟',
      darijaLatin: 'Wach nchghlo chi music?',
      msa: 'هل نشغل بعض الموسيقى؟',
      fr: 'On met un peu de musique ?',
      en: 'Shall we put on some music?',
      emotion: Emotion.happy,
      intensity: 0.4,
    ),
  ];

  // ---- command results (built from the REAL action result) ---------------------
  static Line actionOk(String what) => Line(
        darijaAr: 'صافي: $what',
        darijaLatin: 'Safi: $what',
        msa: 'تم: $what',
        fr: 'C’est fait : $what',
        en: 'Done: $what',
        emotion: Emotion.happy,
        intensity: 0.5,
      );

  static Line actionFailed(String reason) => Line(
        darijaAr: 'سمح ليا، ما قدرتش: $reason',
        darijaLatin: 'Sme7 lia, ma9dertch: $reason',
        msa: 'عذرا، لم أستطع: $reason',
        fr: 'Désolé, je n’ai pas pu : $reason',
        en: 'Sorry, I could not: $reason',
        emotion: Emotion.sad,
        intensity: 0.5,
      );
}
