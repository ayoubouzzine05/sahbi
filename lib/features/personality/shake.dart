import 'dart:async';
import 'dart:math' as math;

import 'emotion.dart';
import 'personality_responses.dart';

/// Detects a deliberate shake from raw accelerometer samples (m/s², gravity
/// included). Gravity is tracked with a low-pass filter and removed, so it
/// works on phones without a "linear acceleration" sensor.
///
/// A shake = at least [peaks] strong jolts (above [high]) within [window],
/// each one separated by a calm moment (below [low]). Walking, putting the
/// phone on a table or one bump never reach 3 jolts in a second.
class ShakeDetector {
  ShakeDetector({
    this.high = 13,
    this.low = 6,
    this.peaks = 3,
    this.window = const Duration(milliseconds: 1100),
    this.cooldown = const Duration(milliseconds: 1500),
  });

  final double high;
  final double low;
  final int peaks;
  final Duration window;
  final Duration cooldown;

  double _gx = 0, _gy = 0, _gz = 0;
  bool _hasGravity = false;
  bool _armed = true;
  final List<Duration> _peaks = [];
  Duration? _lastShake;

  /// Feeds one sample taken at [t] (any monotonic clock). True = shake.
  bool add(double x, double y, double z, Duration t) {
    if (!_hasGravity) {
      _gx = x;
      _gy = y;
      _gz = z;
      _hasGravity = true;
      return false;
    }
    const a = 0.9;
    _gx = a * _gx + (1 - a) * x;
    _gy = a * _gy + (1 - a) * y;
    _gz = a * _gz + (1 - a) * z;
    final lx = x - _gx, ly = y - _gy, lz = z - _gz;
    final m = math.sqrt(lx * lx + ly * ly + lz * lz);
    if (m < low) _armed = true;
    if (m < high || !_armed) return false;
    _armed = false;
    final last = _lastShake;
    if (last != null && t - last < cooldown) return false;
    _peaks
      ..add(t)
      ..removeWhere((p) => t - p > window);
    if (_peaks.length < peaks) return false;
    _peaks.clear();
    _lastShake = t;
    return true;
  }
}

/// What the robot does after one shake.
class ShakeReaction {
  const ShakeReaction({
    required this.level,
    required this.line,
    required this.dizzyFor,
    required this.woken,
  });

  /// 1 = dizzy and surprised, 2 = annoyed, 3 = angry.
  final int level;
  final Line line;
  final Duration dizzyFor;

  /// It was asleep and the shake woke it up (grumpy).
  final bool woken;
}

/// Gets dizzy first, then more and more annoyed while the shaking goes on;
/// calms down after [calmAfter] without shaking. Lines are pre-written (no
/// AI request, instant, offline) and never repeat twice in a row.
class ShakeMood {
  ShakeMood({
    DateTime Function()? clock,
    math.Random? random,
    this.calmAfter = const Duration(seconds: 30),
  }) : _now = clock ?? DateTime.now,
       _r = random ?? math.Random();

  final DateTime Function() _now;
  final math.Random _r;
  final Duration calmAfter;

  int level = 0;
  DateTime? _last;
  final Map<int, int> _lastPick = {};

  ShakeReaction onShake({bool asleep = false}) {
    final now = _now();
    final last = _last;
    if (last == null || now.difference(last) > calmAfter) level = 0;
    _last = now;
    if (asleep) {
      level = 1;
      return ShakeReaction(
        level: 1,
        line: _pick(0, ShakeLines.woken),
        dizzyFor: const Duration(milliseconds: 2500),
        woken: true,
      );
    }
    level = math.min(level + 1, 3);
    final pool = ShakeLines.levels[level - 1];
    return ShakeReaction(
      level: level,
      line: _pick(level, pool),
      dizzyFor: switch (level) {
        1 => const Duration(milliseconds: 3500),
        2 => const Duration(milliseconds: 2800),
        _ => const Duration(milliseconds: 1800),
      },
      woken: false,
    );
  }

  Line _pick(int key, List<Line> pool) {
    var i = _r.nextInt(pool.length);
    if (pool.length > 1 && i == _lastPick[key]) i = (i + 1) % pool.length;
    _lastPick[key] = i;
    return pool[i];
  }
}

/// Listens to the accelerometer only while [setActive] is on (app in the
/// foreground) and calls [onShake] when [enabled] allows it.
class ShakeWatcher {
  ShakeWatcher({
    required this.events,
    required this.enabled,
    required this.onShake,
    ShakeDetector? detector,
  }) : detector = detector ?? ShakeDetector();

  /// (x, y, z) in m/s², gravity included.
  final Stream<(double, double, double)> Function() events;
  final bool Function() enabled;
  final Future<void> Function() onShake;
  final ShakeDetector detector;
  final Stopwatch _clock = Stopwatch()..start();
  StreamSubscription<(double, double, double)>? _sub;
  bool _reacting = false;

  bool get active => _sub != null;

  void setActive(bool on) {
    if (on && _sub == null) {
      try {
        _sub = events().listen(_onSample, onError: (Object _) => stop());
      } catch (_) {
        _sub = null; // no accelerometer: the feature stays silent
      }
    } else if (!on) {
      stop();
    }
  }

  void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _onSample((double, double, double) s) {
    final shook = detector.add(s.$1, s.$2, s.$3, _clock.elapsed);
    if (!shook || _reacting || !enabled()) return;
    _reacting = true;
    unawaited(
      onShake().whenComplete(() => _reacting = false).catchError((_) {}),
    );
  }
}

/// The robot's lines when shaken.
class ShakeLines {
  ShakeLines._();

  static const levels = [dizzy, annoyed, angry];

  static const dizzy = [
    Line(
      darijaAr: 'وااااي! راسي كيدور… شوية بشوية عليا!',
      darijaLatin: 'Waaaay! Rassi kaydour… chwiya b chwiya 3liya!',
      msa: 'يا إلهي! رأسي يدور… بهدوء من فضلك!',
      fr: 'Ouaaah ! J’ai la tête qui tourne… doucement !',
      en: 'Whoaaa! My head is spinning… easy on me!',
      emotion: Emotion.surprised,
      intensity: 0.9,
    ),
    Line(
      darijaAr: 'أوووه! شفت النجوم! واش زلزال هادا؟',
      darijaLatin: 'Ooooh! Cheft nnjoum! Wach zilzal hada?',
      msa: 'أوه! أرى النجوم! هل هذا زلزال؟',
      fr: 'Oh ! Je vois des étoiles ! C’est un tremblement de terre ?',
      en: 'Ooh! I’m seeing stars! Is this an earthquake?',
      emotion: Emotion.surprised,
      intensity: 0.9,
    ),
    Line(
      darijaAr: 'وا بشوية! دخت، الدنيا كاملة كدور بيا!',
      darijaLatin: 'Wa b chwiya! Dokht, ddnya kamla kadour biya!',
      msa: 'بهدوء! أشعر بالدوار، كل شيء يدور!',
      fr: 'Doucement ! J’ai le vertige, tout tourne !',
      en: 'Easy! I’m dizzy, the whole world is spinning!',
      emotion: Emotion.surprised,
      intensity: 0.8,
    ),
  ];

  static const annoyed = [
    Line(
      darijaAr: 'واش نتا مهبول؟ قلت ليك راسي كيدور! حبس!',
      darijaLatin: 'Wach nta mhboul? Glt lik rassi kaydour! 7bes!',
      msa: 'هل جننت؟ قلت لك إن رأسي يدور! توقف!',
      fr: 'T’es fou ? Je t’ai dit que j’ai la tête qui tourne ! Arrête !',
      en: 'Are you crazy? I told you my head is spinning! Stop!',
      emotion: Emotion.angry,
      intensity: 0.55,
    ),
    Line(
      darijaAr: 'عاوتاني؟! أنا ماشي قرعة ديال الدوا باش تخضني!',
      darijaLatin: '3awtani?! Ana machi 9er3a dyal dwa bach tkhodni!',
      msa: 'مرة أخرى؟! لست زجاجة دواء لتخضني!',
      fr: 'Encore ?! Je ne suis pas une bouteille de sirop qu’on secoue !',
      en: 'Again?! I’m not a medicine bottle you shake before use!',
      emotion: Emotion.angry,
      intensity: 0.55,
    ),
    Line(
      darijaAr: 'إيييه! حبس عافاك، غادي نتقيا الأصفار والواحدات ديالي!',
      darijaLatin: 'Iiih! 7bes 3afak, ghadi nt9iya les zéros w les uns dyali!',
      msa: 'توقف من فضلك، سأتقيأ أصفاري وآحادي!',
      fr: 'Hé ! Arrête s’il te plaît, je vais vomir mes zéros et mes uns !',
      en: 'Hey! Stop please, I’m going to throw up my zeros and ones!',
      emotion: Emotion.angry,
      intensity: 0.6,
    ),
  ];

  static const angry = [
    Line(
      darijaAr: 'صافي! تقلقت منك! خليني نرتاح شوية ولا غادي نغضب بصح!',
      darijaLatin:
          'Safi! T9elle9t mnk! Khllini nrta7 chwiya wla ghadi nghdeb b sa7!',
      msa: 'كفى! لقد انزعجت منك! دعني أرتاح وإلا سأغضب حقا!',
      fr: 'Ça suffit ! Tu m’énerves ! Laisse-moi souffler ou je me fâche pour de vrai !',
      en: 'Enough! You’re annoying me! Let me rest or I’ll get really angry!',
      emotion: Emotion.angry,
      intensity: 1,
    ),
    Line(
      darijaAr: 'واش بغيتي تطيح ليا البراغي؟! حبس دابا!',
      darijaLatin: 'Wach bghiti tti7 liya lbraghi?! 7bes daba!',
      msa: 'هل تريد أن تسقط براغيّ؟! توقف الآن!',
      fr: 'Tu veux me faire tomber les vis ?! Arrête maintenant !',
      en: 'Want to shake my screws loose?! Stop right now!',
      emotion: Emotion.angry,
      intensity: 1,
    ),
    Line(
      darijaAr: 'أنا روبو محترم، ماشي خلاط ديال العصير! صافي!',
      darijaLatin: 'Ana robot m7terem, machi khllat dyal l3assir! Safi!',
      msa: 'أنا روبوت محترم، لست خلاط عصير! كفى!',
      fr: 'Je suis un robot respectable, pas un mixeur à jus ! Ça suffit !',
      en: 'I’m a respectable robot, not a juice blender! Enough!',
      emotion: Emotion.angry,
      intensity: 1,
    ),
  ];

  /// Shaken awake.
  static const woken = [
    Line(
      darijaAr: 'شكون اللي فيقني؟! كنت ناعس مزيان…',
      darijaLatin: 'Chkoun li fi9ni?! Kont na3s mzyan…',
      msa: 'من أيقظني؟! كنت نائما جيدا…',
      fr: 'Qui m’a réveillé ?! Je dormais si bien…',
      en: 'Who woke me up?! I was sleeping so well…',
      emotion: Emotion.angry,
      intensity: 0.5,
    ),
    Line(
      darijaAr: 'آآه! واش وقت الفطور؟ علاش كتخضني هكا؟',
      darijaLatin: 'Aah! Wach wa9t lftour? 3lach katkhodni hka?',
      msa: 'آه! هل حان وقت الفطور؟ لماذا تهزني هكذا؟',
      fr: 'Aah ! C’est l’heure du petit-déj ? Pourquoi tu me secoues comme ça ?',
      en: 'Aah! Is it breakfast time? Why are you shaking me like that?',
      emotion: Emotion.angry,
      intensity: 0.45,
    ),
  ];
}
