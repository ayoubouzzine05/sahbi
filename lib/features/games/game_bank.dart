import '../personality/emotion.dart';
import '../personality/personality_responses.dart';

/// "7ajitek majitek": a riddle, its answer and the words that count as right
/// (normalised: lower-case, no accents, Arabic letters unified).
class Riddle {
  const Riddle(this.question, this.answer, this.keys);
  final Line question;
  final Line answer;
  final List<String> keys;
}

/// A 3-choice question; [keys] holds the words that pick each choice.
class Trivia {
  const Trivia(this.question, this.answer, this.correct, this.keys);
  final Line question;

  /// The correct answer, said when revealing it.
  final Line answer;

  /// Index (0..2) of the right choice.
  final int correct;
  final List<List<String>> keys;
}

Line _l(String ar, String latin, String msa, String fr, String en) => Line(
  darijaAr: ar,
  darijaLatin: latin,
  msa: msa,
  fr: fr,
  en: en,
  emotion: Emotion.curious,
  intensity: 0.7,
);

/// Our own small offline bank (no AI request, works without internet).
class GameBank {
  GameBank._();

  static final riddles = <Riddle>[
    Riddle(
      _l(
        'حاجيتك ماجيتك: شي حاجة كاتمشي بلا رجلين، وكاتبكي بلا عينين. شنو هي؟',
        '7ajitek majitek: chi 7aja katmchi bla rjlin, w katbki bla 3inin. Chno hiya?',
        'لغز: شيء يمشي بلا أرجل ويبكي بلا عيون. ما هو؟',
        'Devinette : elle marche sans pieds et pleure sans yeux. Qui est-ce ?',
        'Riddle: it walks with no feet and cries with no eyes. What is it?',
      ),
      _l('السحاب', 'S-s7ab', 'السحاب', 'Le nuage', 'A cloud'),
      ['سحاب', 'سحابه', 'شحاب', 's7ab', 'sehab', 'sa7ab', 'nuage', 'cloud'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: كلما خديتي منها، كاتكبر. شنو هي؟',
        '7ajitek majitek: kolma khditi mnha, katkber. Chno hiya?',
        'لغز: كلما أخذت منها كبرت. ما هي؟',
        'Devinette : plus on lui enlève, plus elle grandit. Qu’est-ce que c’est ?',
        'Riddle: the more you take from it, the bigger it gets. What is it?',
      ),
      _l('الحفرة', 'L-7ofra', 'الحفرة', 'Un trou', 'A hole'),
      ['حفره', 'حفرة', '7ofra', '7fra', 'hofra', 'trou', 'hole'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: عندو سنان بزاف، وعمرو ما عض حتى واحد. شنو هو؟',
        '7ajitek majitek: 3ando snan bzaf, w 3omro ma 3ed 7ta wa7ed. Chno howa?',
        'لغز: له أسنان كثيرة ولا يعض أحدا. ما هو؟',
        'Devinette : il a plein de dents mais ne mord jamais. Qui est-ce ?',
        'Riddle: it has lots of teeth but never bites. What is it?',
      ),
      _l('المشط', 'L-mcht', 'المشط', 'Le peigne', 'A comb'),
      ['مشط', 'mcht', 'mecht', 'mocht', 'mosht', 'peigne', 'comb'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: كاتسمعو وما كاتشوفوش، وإلا هضرتي كيعاود موراك. شنو هو؟',
        '7ajitek majitek: katsm3o w ma katchoufouch, w ila hdrti ki3awed morak. Chno howa?',
        'لغز: تسمعه ولا تراه، وإذا تكلمت أعاد كلامك. ما هو؟',
        'Devinette : on l’entend sans le voir, et il répète ce que tu dis. Qui est-ce ?',
        'Riddle: you hear it but never see it, and it repeats what you say. What is it?',
      ),
      _l('الصدى', 'S-sada', 'الصدى', 'L’écho', 'An echo'),
      ['صدى', 'صدي', 'sada', 'sda', 'sadda', 'echo'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: ديالك نتا، ولكن الناس كيخدمو بيه كثر منك. شنو هو؟',
        '7ajitek majitek: dyalek nta, walakin nas kikhdmo bih ktar mnek. Chno howa?',
        'لغز: هو لك، لكن الناس يستعملونه أكثر منك. ما هو؟',
        'Devinette : il est à toi, mais les autres l’utilisent plus que toi. Qu’est-ce que c’est ?',
        'Riddle: it’s yours, but other people use it more than you. What is it?',
      ),
      _l('سميتك', 'Smiytek', 'اسمك', 'Ton prénom', 'Your name'),
      [
        'سميتك',
        'سميه',
        'اسم',
        'smiya',
        'smitek',
        'smiytek',
        'prenom',
        'nom',
        'name',
      ],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: كيطلع ديما، وعمرو ما كيهبط. شنو هو؟',
        '7ajitek majitek: kitla3 dima, w 3omro ma kihbet. Chno howa?',
        'لغز: يصعد دائما ولا ينزل أبدا. ما هو؟',
        'Devinette : il monte toujours et ne descend jamais. Qu’est-ce que c’est ?',
        'Riddle: it always goes up and never comes down. What is it?',
      ),
      _l('العمر', 'L-3omr', 'العمر', 'L’âge', 'Your age'),
      ['عمر', 'سن', '3omr', '3mr', 'omr', 'sen', 'age'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: كلما نشفات، كاتفزڭ كثر. شنو هي؟',
        '7ajitek majitek: kolma nchfat, katfzeg ktar. Chno hiya?',
        'لغز: كلما جففت ابتلت أكثر. ما هي؟',
        'Devinette : plus elle sèche, plus elle est mouillée. Qu’est-ce que c’est ?',
        'Riddle: the more it dries, the wetter it gets. What is it?',
      ),
      _l('الفوطة', 'L-fouta', 'المنشفة', 'La serviette', 'A towel'),
      ['فوطه', 'فوطة', 'منشفه', 'fouta', 'fota', 'serviette', 'towel'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: عندها عين وحدة، وما كاتشوفش بيها. شنو هي؟',
        '7ajitek majitek: 3andha 3in w7da, w ma katchoufch biha. Chno hiya?',
        'لغز: لها عين واحدة ولا ترى بها. ما هي؟',
        'Devinette : elle a un œil mais ne voit rien. Qu’est-ce que c’est ?',
        'Riddle: it has one eye but can’t see. What is it?',
      ),
      _l('الإبرة', 'L-ibra', 'الإبرة', 'L’aiguille', 'A needle'),
      ['ابره', 'ابرة', 'ibra', 'lbra', 'ebra', 'aiguille', 'needle'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: كيجري بلا رجلين، وعمرو ما عيا. شنو هو؟',
        '7ajitek majitek: kijri bla rjlin, w 3omro ma 3ya. Chno howa?',
        'لغز: يجري بلا أرجل ولا يتعب أبدا. ما هو؟',
        'Devinette : il court sans jambes et n’est jamais fatigué. Qui est-ce ?',
        'Riddle: it runs with no legs and never gets tired. What is it?',
      ),
      _l('الواد', 'L-wad', 'النهر', 'La rivière', 'A river'),
      ['واد', 'نهر', 'wad', 'oued', 'riviere', 'fleuve', 'river'],
    ),
    Riddle(
      _l(
        'حاجيتك ماجيتك: صينية ديال النقرة، ما كاتبانش غير فالليل. شنو هي؟',
        '7ajitek majitek: siniya dyal n-nogra, ma katbanch ghir f lil. Chno hiya?',
        'لغز: صينية من فضة لا تظهر إلا في الليل. ما هي؟',
        'Devinette : un plateau d’argent qu’on ne voit que la nuit. Qu’est-ce que c’est ?',
        'Riddle: a silver tray you only see at night. What is it?',
      ),
      _l('القمر', 'L-gamra', 'القمر', 'La lune', 'The moon'),
      ['قمر', 'قمره', 'كمره', 'gamra', 'qamar', '9mar', 'lune', 'moon'],
    ),
  ];

  static const _first = [
    '1',
    'lwla',
    'lowla',
    'lewla',
    'lwl',
    'اللوله',
    'الاولى',
    'الاولي',
    'الاول',
    'premiere',
    'premier',
    'first',
    'one',
  ];
  static const _second = [
    '2',
    'tanya',
    'tania',
    'tania',
    'التانيه',
    'الثانيه',
    'الثاني',
    'deuxieme',
    'second',
    'two',
  ];
  static const _third = [
    '3',
    'talta',
    'talata',
    'التالته',
    'الثالثه',
    'الثالث',
    'troisieme',
    'third',
    'three',
  ];

  /// Words that pick choice 1, 2 or 3 when the answer itself isn't said.
  static const ordinals = [_first, _second, _third];

  static final trivia = <Trivia>[
    Trivia(
      _l(
        'سؤال: شنو هي العاصمة ديال المغرب؟ الرباط، كازا، ولا فاس؟',
        'Su2al: chno hiya l3asima dyal lmghrib? Rbat, Kaza, wla Fes?',
        'سؤال: ما عاصمة المغرب؟ الرباط، الدار البيضاء، أم فاس؟',
        'Question : quelle est la capitale du Maroc ? Rabat, Casablanca ou Fès ?',
        'Question: what is Morocco’s capital? Rabat, Casablanca or Fez?',
      ),
      _l('الرباط', 'Rbat', 'الرباط', 'Rabat', 'Rabat'),
      0,
      [
        ['رباط', 'الرباط', 'rbat', 'rabat'],
        ['كازا', 'البيضاء', 'kaza', 'casa', 'casablanca'],
        ['فاس', 'fes', 'fas', 'fez'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شحال من رجل عند الرتيلة؟ ستة، تمنية، ولا عشرة؟',
        'Su2al: ch7al mn rjel 3and rtila? Stta, tmnya, wla 3achra?',
        'سؤال: كم رجلا للعنكبوت؟ ستة، ثمانية، أم عشرة؟',
        'Question : combien de pattes a une araignée ? Six, huit ou dix ?',
        'Question: how many legs does a spider have? Six, eight or ten?',
      ),
      _l('تمنية', 'Tmnya', 'ثمانية', 'Huit', 'Eight'),
      1,
      [
        ['6', 'سته', 'ستة', 'stta', 'sta', 'six'],
        ['8', 'تمنيه', 'ثمانيه', 'tmnya', 'tmenya', 'tmanya', 'huit', 'eight'],
        ['10', 'عشره', 'عشرة', '3achra', '3echra', 'dix', 'ten'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شنو هو أعلى جبل فالمغرب؟ توبقال، العياشي، ولا بويبلان؟',
        'Su2al: chno howa a3la jbel f lmghrib? Toubkal, l3ayachi, wla Bouiblane?',
        'سؤال: ما أعلى جبل في المغرب؟ توبقال، العياشي، أم بويبلان؟',
        'Question : quelle est la plus haute montagne du Maroc ? Toubkal, Ayachi ou Bouiblane ?',
        'Question: what is the highest mountain in Morocco? Toubkal, Ayachi or Bouiblane?',
      ),
      _l('توبقال', 'Toubkal', 'توبقال', 'Le Toubkal', 'Toubkal'),
      0,
      [
        ['توبقال', 'toubkal', 'tobkal', 'toubqal'],
        ['عياشي', 'العياشي', 'ayachi', '3ayachi'],
        ['بويبلان', 'bouiblane', 'bouiblan', 'bwiblan'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شنو هو أكبر كوكب؟ المريخ، المشتري، ولا الزهرة؟',
        'Su2al: chno howa akbar kawkab? Lmerrikh, lmouchtari, wla zzohra?',
        'سؤال: ما أكبر كوكب؟ المريخ، المشتري، أم الزهرة؟',
        'Question : quelle est la plus grande planète ? Mars, Jupiter ou Vénus ?',
        'Question: which is the biggest planet? Mars, Jupiter or Venus?',
      ),
      _l('المشتري', 'Lmouchtari', 'المشتري', 'Jupiter', 'Jupiter'),
      1,
      [
        ['مريخ', 'المريخ', 'merrikh', 'mrikh', 'mars'],
        ['مشتري', 'المشتري', 'mouchtari', 'mochtari', 'jupiter'],
        ['زهره', 'الزهره', 'zohra', 'zzohra', 'venus'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: إلا خلطتي الزرق مع الصفر، شنو كيعطيك؟ لخضر، البنفسجي، ولا ليموني؟',
        'Su2al: ila khlti zreq m3a sfer, chno ki3tik? Lkhder, lbanafsaji, wla limouni?',
        'سؤال: إذا خلطت الأزرق مع الأصفر، ماذا تحصل؟ الأخضر، البنفسجي، أم البرتقالي؟',
        'Question : bleu + jaune, ça donne quoi ? Vert, violet ou orange ?',
        'Question: blue mixed with yellow makes what? Green, purple or orange?',
      ),
      _l('لخضر', 'Lkhder', 'الأخضر', 'Vert', 'Green'),
      0,
      [
        ['خضر', 'لخضر', 'اخضر', 'khder', 'lkhder', 'vert', 'green'],
        ['بنفسجي', 'mouv', 'banafsaji', 'violet', 'purple'],
        ['ليموني', 'برتقالي', 'limouni', 'orange'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شنو هو أكبر محيط فالعالم؟ الأطلسي، الهندي، ولا الهادي؟',
        'Su2al: chno howa akbar mo7it f l3alam? Latlassi, lhindi, wla lhadi?',
        'سؤال: ما أكبر محيط في العالم؟ الأطلسي، الهندي، أم الهادئ؟',
        'Question : quel est le plus grand océan ? Atlantique, Indien ou Pacifique ?',
        'Question: which is the largest ocean? Atlantic, Indian or Pacific?',
      ),
      _l('الهادي', 'Lhadi', 'المحيط الهادئ', 'Le Pacifique', 'The Pacific'),
      2,
      [
        ['اطلسي', 'الاطلسي', 'atlassi', 'atlantique', 'atlantic'],
        ['هندي', 'الهندي', 'hindi', 'indien', 'indian'],
        ['هادي', 'الهادي', 'الهادئ', 'hadi', 'pacifique', 'pacific'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شكون أسرع حيوان فالبر؟ السبع، الفهد، ولا العود؟',
        'Su2al: chkoun asra3 7ayawan f lberr? Sb3, lfhed, wla l3awd?',
        'سؤال: ما أسرع حيوان على اليابسة؟ الأسد، الفهد، أم الحصان؟',
        'Question : quel est l’animal terrestre le plus rapide ? Le lion, le guépard ou le cheval ?',
        'Question: what is the fastest land animal? Lion, cheetah or horse?',
      ),
      _l('الفهد', 'Lfhed', 'الفهد', 'Le guépard', 'The cheetah'),
      1,
      [
        ['سبع', 'السبع', 'اسد', 'sb3', 'sbe3', 'lion'],
        ['فهد', 'الفهد', 'fhed', 'fahd', 'guepard', 'cheetah'],
        ['عود', 'العود', 'حصان', '3awd', '3aoud', 'cheval', 'horse'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شحال من نهار فالعام الكبيس؟ تلت مية وخمسة وستين، ستة وستين، ولا ربعة وستين؟',
        'Su2al: ch7al mn nhar f l3am lkbis? 365, 366, wla 364?',
        'سؤال: كم يوما في السنة الكبيسة؟ ٣٦٥، ٣٦٦، أم ٣٦٤؟',
        'Question : combien de jours dans une année bissextile ? 365, 366 ou 364 ?',
        'Question: how many days are in a leap year? 365, 366 or 364?',
      ),
      _l('تلت مية وستة وستين', '366', 'ثلاثمائة وستة وستون', '366', '366'),
      1,
      [
        ['365', 'خمسه وستين', 'khamsa w sttin'],
        ['366', 'سته وستين', 'stta w sttin', 'six'],
        ['364', 'ربعه وستين', 'reb3a w sttin'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شمن كوكب كيسميوه الكوكب الحمر؟ المريخ، زحل، ولا عطارد؟',
        'Su2al: chmen kawkab kisamiwh lkawkab l7mer? Lmerrikh, Zo7al, wla 3otarid?',
        'سؤال: أي كوكب يسمى الكوكب الأحمر؟ المريخ، زحل، أم عطارد؟',
        'Question : quelle planète appelle-t-on la planète rouge ? Mars, Saturne ou Mercure ?',
        'Question: which planet is called the red planet? Mars, Saturn or Mercury?',
      ),
      _l('المريخ', 'Lmerrikh', 'المريخ', 'Mars', 'Mars'),
      0,
      [
        ['مريخ', 'المريخ', 'merrikh', 'mrikh', 'mars'],
        ['زحل', 'zo7al', 'zohal', 'saturne', 'saturn'],
        ['عطارد', '3otarid', 'otarid', 'mercure', 'mercury'],
      ],
    ),
    Trivia(
      _l(
        'سؤال: شحال من دقيقة فالساعة؟ ستين، مية، ولا تلاتين؟',
        'Su2al: ch7al mn d9i9a f sa3a? Sttin, mya, wla tlatin?',
        'سؤال: كم دقيقة في الساعة؟ ستون، مئة، أم ثلاثون؟',
        'Question : combien de minutes dans une heure ? 60, 100 ou 30 ?',
        'Question: how many minutes are in an hour? 60, 100 or 30?',
      ),
      _l('ستين', 'Sttin', 'ستون', 'Soixante', 'Sixty'),
      0,
      [
        ['60', 'ستين', 'sttin', 'stin', 'soixante', 'sixty'],
        ['100', 'ميه', 'mya', 'mia', 'cent', 'hundred'],
        ['30', 'تلاتين', 'tlatin', 'trente', 'thirty'],
      ],
    ),
  ];
}
