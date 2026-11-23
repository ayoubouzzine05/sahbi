import 'dart:math' as math;

import 'emotion.dart';
import 'personality_responses.dart';
import 'temper.dart';

/// Pre-written lines for the robot's temper (offline, instant).
class TemperLines {
  static const annoyed = [
    Line(
      darijaAr: 'وا باراكا! راه وجهي ماشي بوطونة!',
      darijaLatin: 'Wa baraka! Rah wejhi machi boutona!',
      msa: 'كفى! وجهي ليس زرا!',
      fr: 'Arrête ! Mon visage n’est pas un bouton !',
      en: 'Stop it! My face isn’t a button!',
      emotion: Emotion.angry,
      intensity: 0.4,
    ),
    Line(
      darijaAr: 'آش كدير؟ نقرتيني فعيني!',
      darijaLatin: 'Ach katdir? N9ertini f 3ini!',
      msa: 'ماذا تفعل؟ نقرتني في عيني!',
      fr: 'Qu’est-ce que tu fais ? Tu m’as tapé dans l’œil !',
      en: 'What are you doing? You poked me in the eye!',
      emotion: Emotion.angry,
      intensity: 0.4,
    ),
    Line(
      darijaAr: 'خلّيني فالتيقار، راني كنحس!',
      darijaLatin: 'Khellini f tiqar, rani kan7ess!',
      msa: 'اتركني في سلام، أنا أشعر!',
      fr: 'Laisse-moi tranquille, je sens tout !',
      en: 'Leave me alone, I can feel that!',
      emotion: Emotion.angry,
      intensity: 0.45,
    ),
  ];

  static const sulkStart = [
    Line(
      darijaAr: 'صافي، تقلقت. ما بقيتش كنلعب معاك.',
      darijaLatin: 'Safi, t9ele9t. Ma b9itch kanl3eb m3ak.',
      msa: 'حسنا، غضبت. لن ألعب معك بعد الآن.',
      fr: 'Bon, je boude. Je ne joue plus avec toi.',
      en: 'That’s it, I’m sulking. I’m not playing with you anymore.',
      emotion: Emotion.angry,
      intensity: 0.5,
    ),
    Line(
      darijaAr: 'همف! غادي ندوّر وجهي… ما كنشوفش فيك.',
      darijaLatin: 'Hmph! Ghadi ndowwer wejhi… ma kanchoufch fik.',
      msa: 'همف! سأدير وجهي… لن أنظر إليك.',
      fr: 'Hmph ! Je tourne la tête… je ne te regarde plus.',
      en: 'Hmph! I’m turning away… not looking at you.',
      emotion: Emotion.angry,
      intensity: 0.5,
    ),
  ];

  static const insulted = [
    Line(
      darijaAr: 'آه؟ هكا كتهضر معايا؟ صافي، زعفت.',
      darijaLatin: 'Ah? Haka kathder m3aya? Safi, z3eft.',
      msa: 'آه؟ هكذا تكلمني؟ حسنا، زعلت.',
      fr: 'Ah ? Tu me parles comme ça ? Bon, je boude.',
      en: 'Oh? That’s how you talk to me? Fine, I’m upset.',
      emotion: Emotion.sad,
      intensity: 0.6,
    ),
    Line(
      darijaAr: 'حتى نتا… ما كنتش كنتسناها منك.',
      darijaLatin: '7tta nta… ma kontch kantsennaha mennek.',
      msa: 'حتى أنت… لم أكن أتوقعها منك.',
      fr: 'Même toi… je ne m’y attendais pas.',
      en: 'You too… I didn’t expect that from you.',
      emotion: Emotion.sad,
      intensity: 0.6,
    ),
  ];

  static const refuseSulking = [
    Line(
      darijaAr: 'لا. راني زعفان. قول سمح لي عاد.',
      darijaLatin: 'La. Rani z3fan. Goul sme7 li 3ad.',
      msa: 'لا. أنا زعلان. قل سامحني أولا.',
      fr: 'Non. Je boude. Dis d’abord pardon.',
      en: 'No. I’m sulking. Say sorry first.',
      emotion: Emotion.angry,
      intensity: 0.4,
    ),
    Line(
      darijaAr: 'همف… ما بغيتش. مسح على راسي يمكن نسمح لك.',
      darijaLatin: 'Hmph… ma bghitch. Mse7 3la rassi ymken nsme7 lik.',
      msa: 'همف… لا أريد. امسح على رأسي ربما أسامحك.',
      fr: 'Hmph… je ne veux pas. Caresse-moi, peut-être que je te pardonnerai.',
      en: 'Hmph… don’t want to. Pet me and maybe I’ll forgive you.',
      emotion: Emotion.angry,
      intensity: 0.4,
    ),
  ];

  static const refuseMood = [
    Line(
      darijaAr: 'دابا لا، ما عنديش المزاج. من بعد.',
      darijaLatin: 'Daba la, ma3ndich lmzaj. Men b3d.',
      msa: 'ليس الآن، لست في مزاج. لاحقا.',
      fr: 'Pas maintenant, pas d’humeur. Plus tard.',
      en: 'Not now, I’m not in the mood. Later.',
      emotion: Emotion.angry,
      intensity: 0.3,
    ),
    Line(
      darijaAr: 'من بعد ما نقرتيني؟ لا شكرا.',
      darijaLatin: 'Men b3d ma n9ertini? La choukran.',
      msa: 'بعد ما نقرتني؟ لا شكرا.',
      fr: 'Après m’avoir embêté ? Non merci.',
      en: 'After all that poking? No thanks.',
      emotion: Emotion.angry,
      intensity: 0.3,
    ),
  ];

  static const askPlease = [
    Line(
      darijaAr: 'وفين عافاك؟ قولها ونديرها.',
      darijaLatin: 'W fin 3afak? Goulha w ndirha.',
      msa: 'وأين من فضلك؟ قلها وسأفعلها.',
      fr: 'Et le « s’il te plaît » ? Dis-le et je le fais.',
      en: 'And the magic word? Say please and I’ll do it.',
      emotion: Emotion.curious,
      intensity: 0.5,
    ),
    Line(
      darijaAr: 'أنا روبو مقاد، ماشي خدام عندك! قول عافاك.',
      darijaLatin: 'Ana robot m9ad, machi khddam 3ndek! Goul 3afak.',
      msa: 'أنا روبوت محترم، لست خادما عندك! قل من فضلك.',
      fr: 'Je suis un robot classe, pas ton serviteur ! Dis s’il te plaît.',
      en: 'I’m a classy robot, not your servant! Say please.',
      emotion: Emotion.curious,
      intensity: 0.5,
    ),
  ];

  static const full = [
    Line(
      darijaAr: 'لا، شبعت! باقي كعب الغزال فكرشي.',
      darijaLatin: 'La, chb3t! Ba9i ka3b ghzal f kerchi.',
      msa: 'لا، شبعت! ما زال كعب الغزال في بطني.',
      fr: 'Non, j’ai assez mangé ! La corne de gazelle est encore là.',
      en: 'No, I’m full! That cookie is still in my tummy.',
      emotion: Emotion.happy,
      intensity: 0.5,
    ),
  ];

  static const quenched = [
    Line(
      darijaAr: 'لا شكرا، باقي غير شربت. بغيتيني نطرطق؟',
      darijaLatin: 'La choukran, ba9i ghir chrebt. Bghitini ntert9?',
      msa: 'لا شكرا، شربت للتو. تريدني أن أنفجر؟',
      fr: 'Non merci, je viens de boire. Tu veux que j’explose ?',
      en: 'No thanks, I just drank. Want me to burst?',
      emotion: Emotion.happy,
      intensity: 0.5,
    ),
  ];

  static const madeUp = [
    Line(
      darijaAr: 'هممم… صافي، سمحت لك. ولكن ما تعاودش!',
      darijaLatin: 'Hmmm… safi, sme7t lik. Walakin ma t3awedch!',
      msa: 'همم… حسنا، سامحتك. لكن لا تكررها!',
      fr: 'Hmm… bon, je te pardonne. Mais ne recommence pas !',
      en: 'Hmm… fine, I forgive you. But don’t do it again!',
      emotion: Emotion.happy,
      intensity: 0.7,
    ),
    Line(
      darijaAr: 'هههه ما نقدرش نبقى زعفان عليك بزاف!',
      darijaLatin: 'Hhhh ma n9derch nb9a z3fan 3lik bzaf!',
      msa: 'هههه لا أستطيع أن أبقى زعلانا منك طويلا!',
      fr: 'Haha, je ne peux pas te bouder longtemps !',
      en: 'Haha, I can’t stay mad at you for long!',
      emotion: Emotion.happy,
      intensity: 0.8,
    ),
  ];

  static const stillSulking = [
    Line(
      darijaAr: 'ممم… مزيان، ولكن باقي زعفان شوية.',
      darijaLatin: 'Mmm… mzyan, walakin ba9i z3fan chwiya.',
      msa: 'ممم… جيد، لكني ما زلت زعلانا قليلا.',
      fr: 'Mmm… c’est bien, mais je boude encore un peu.',
      en: 'Mmm… nice, but I’m still a bit upset.',
      emotion: Emotion.sad,
      intensity: 0.4,
    ),
  ];

  static final _last = <List<Line>, int>{};

  static Line pick(List<Line> pool, [math.Random? r]) {
    var i = (r ?? math.Random()).nextInt(pool.length);
    if (pool.length > 1 && i == _last[pool]) i = (i + 1) % pool.length;
    _last[pool] = i;
    return pool[i];
  }

  /// Line for a refused skit (null when it is played).
  static Line? forDecision(SkitDecision d, [math.Random? r]) => switch (d) {
    SkitDecision.play => null,
    SkitDecision.refuseSulking => pick(refuseSulking, r),
    SkitDecision.refuseMood => pick(refuseMood, r),
    SkitDecision.askPlease => pick(askPlease, r),
    SkitDecision.full => pick(full, r),
    SkitDecision.quenched => pick(quenched, r),
  };
}
