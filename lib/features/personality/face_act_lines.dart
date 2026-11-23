import 'dart:math' as math;

import '../face/face_act.dart';
import 'emotion.dart';
import 'personality_responses.dart';

/// Pre-written lines said with a face skit asked by voice ("haz ydik",
/// "kol", "chrob atay"...). Offline and instant: no AI request.
class FaceActLines {
  static const _lines = <FaceAct, List<Line>>{
    FaceAct.eat: [
      Line(
        darijaAr: 'ممم! كعب غزال… بنين بزاف!',
        darijaLatin: 'Mmm! Ka3b ghzal… bnin bzaf!',
        msa: 'ممم! كعب غزال… لذيذ جدا!',
        fr: 'Miam ! Une corne de gazelle… trop bon !',
        en: 'Yum! A gazelle horn cookie… so good!',
        emotion: Emotion.happy,
        intensity: 0.8,
      ),
      Line(
        darijaAr: 'هاني كناكل، ما تبقاش تشوف فيا هكا!',
        darijaLatin: 'Hani kanakoul, ma tb9ach tchouf fiya haka!',
        msa: 'أنا آكل الآن، لا تنظر إلي هكذا!',
        fr: 'Je mange, ne me regarde pas comme ça !',
        en: 'I’m eating, don’t stare at me like that!',
        emotion: Emotion.happy,
        intensity: 0.7,
      ),
      Line(
        darijaAr: 'شوية ديال الطاقة… دابا نقدر نهضر حتى للصباح!',
        darijaLatin: 'Chwiya dyal tta9a… daba n9der nhder 7tta sba7!',
        msa: 'قليل من الطاقة… الآن أستطيع الكلام حتى الصباح!',
        fr: 'Un peu d’énergie… je peux parler jusqu’au matin !',
        en: 'A bit of energy… now I can talk until morning!',
        emotion: Emotion.happy,
        intensity: 0.7,
      ),
    ],
    FaceAct.drink: [
      Line(
        darijaAr: 'آآآه! أتاي بالنعناع، كيرد الروح.',
        darijaLatin: 'Aaah! Atay b na3na3, kayred rou7.',
        msa: 'آه! شاي بالنعناع، يعيد الروح.',
        fr: 'Aaah ! Un thé à la menthe, ça redonne vie.',
        en: 'Aaah! Mint tea, it brings you back to life.',
        emotion: Emotion.happy,
        intensity: 0.7,
      ),
      Line(
        darijaAr: 'كاس ديال أتاي، والدنيا ولات زوينة.',
        darijaLatin: 'Kas dyal atay, w dounya wllat zwina.',
        msa: 'كأس من الشاي، وأصبحت الدنيا جميلة.',
        fr: 'Un verre de thé, et la vie est belle.',
        en: 'One glass of tea, and life is good.',
        emotion: Emotion.happy,
        intensity: 0.6,
      ),
    ],
    FaceAct.handsUp: [
      Line(
        darijaAr: 'ها هوما! يديا لفوق!',
        darijaLatin: 'Ha homa! Yeddiya lfou9!',
        msa: 'ها هما! يداي إلى الأعلى!',
        fr: 'Voilà ! Les mains en l’air !',
        en: 'There you go! Hands up!',
        emotion: Emotion.happy,
        intensity: 0.8,
      ),
      Line(
        darijaAr: 'هاني هازهم، شنو دابا؟ واش غادي نشطحو؟',
        darijaLatin: 'Hani hazzhom, chno daba? Wach ghadi nchet7o?',
        msa: 'ها أنا رفعتهما، والآن؟ هل سنرقص؟',
        fr: 'Je les lève, et maintenant ? On danse ?',
        en: 'Hands up, now what? Are we dancing?',
        emotion: Emotion.happy,
        intensity: 0.8,
      ),
    ],
    FaceAct.peekaboo: [
      Line(
        darijaAr: 'بوووه! شفتيني؟',
        darijaLatin: 'Bouuuh! Chftini?',
        msa: 'بوه! هل رأيتني؟',
        fr: 'Coucou ! Tu m’as vu ?',
        en: 'Peekaboo! Did you see me?',
        emotion: Emotion.happy,
        intensity: 0.8,
      ),
    ],
    FaceAct.love: [
      Line(
        darijaAr: 'حتى أنا كنبغيك أ صاحبي!',
        darijaLatin: '7tta ana kanbghik a sahbi!',
        msa: 'وأنا أيضا أحبك يا صديقي!',
        fr: 'Moi aussi je t’adore, mon pote !',
        en: 'I love you too, buddy!',
        emotion: Emotion.happy,
        intensity: 0.9,
      ),
      Line(
        darijaAr: 'وا قلبي ولا كيضرب بزربة!',
        darijaLatin: 'Wa 9albi wla kaydreb bzerba!',
        msa: 'قلبي صار يدق بسرعة!',
        fr: 'Mon cœur bat la chamade !',
        en: 'My heart is racing!',
        emotion: Emotion.happy,
        intensity: 0.9,
      ),
    ],
    FaceAct.yawn: [
      Line(
        darijaAr: 'آآآه… شوية ديال النعاس، ولكن باقي معاك.',
        darijaLatin: 'Aaah… chwiya dyal n3as, walakin ba9i m3ak.',
        msa: 'آه… أشعر ببعض النعاس، لكنني ما زلت معك.',
        fr: 'Aaah… un peu sommeil, mais je suis là.',
        en: 'Aaah… a little sleepy, but I’m still here.',
        emotion: Emotion.sleepy,
        intensity: 0.6,
      ),
    ],
    FaceAct.dance: [
      Line(
        darijaAr: 'يالاه نشطحو! شوف هاد الحركات!',
        darijaLatin: 'Yallah nchet7o! Chouf had l7arakat!',
        msa: 'هيا نرقص! انظر إلى هذه الحركات!',
        fr: 'Allez, on danse ! Regarde ces pas !',
        en: 'Let’s dance! Check out these moves!',
        emotion: Emotion.happy,
        intensity: 0.9,
      ),
    ],
  };

  static Line? lineFor(FaceAct act, [math.Random? r]) {
    final l = _lines[act];
    if (l == null || l.isEmpty) return null;
    return l[(r ?? math.Random()).nextInt(l.length)];
  }

  /// Acts that can be asked for by voice and say a line.
  static Iterable<FaceAct> get spoken => _lines.keys;
}
