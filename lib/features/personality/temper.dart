import 'dart:math' as math;

import '../brain/text_normalizer.dart';
import '../face/face_act.dart';

/// What the robot does after a poke on the face.
enum PokeReaction {
  /// A normal poke: eyes squash.
  squish,

  /// Poked again and again: "wa baraka!" (says a line once per burst).
  annoyed,

  /// Too much: starts sulking (turns away, refuses skits).
  sulk,

  /// Already sulking: "hmph", looks away, no squish.
  ignore,
}

/// Answer to a skit asked by voice ("haz ydik", "kol"...).
enum SkitDecision {
  /// Does it.
  play,

  /// Sulking: "la, ma bghitch".
  refuseSulking,

  /// Annoyed: not in the mood right now.
  refuseMood,

  /// Wants "3afak" first; does it if the next thing said is "3afak".
  askPlease,

  /// Just ate.
  full,

  /// Just drank.
  quenched,
}

/// The robot's temper: a strong, EMO-like character that gets annoyed,
/// sulks and makes up. Purely local and deterministic for a given random
/// source. It only affects playful things (skits, face, tone): real help
/// (questions, music, search, camera) is never refused.
///
/// [level] goes 0 (calm) … 1 (fed up) and halves every [halfLife].
class Temper {
  Temper({
    DateTime Function()? clock,
    math.Random? random,
    this.halfLife = const Duration(seconds: 60),
  }) : _now = clock ?? DateTime.now,
       _r = random ?? math.Random();

  final DateTime Function() _now;
  final math.Random _r;
  final Duration halfLife;

  double _level = 0;
  DateTime? _at;
  DateTime? _sulkUntil;
  String? _sulkReason;
  DateTime? _ate, _drank, _annoyedSaid;
  final List<DateTime> _pokes = [];

  /// Skit waiting for "3afak" (with its deadline).
  FaceAct? _pending;
  DateTime? _pendingUntil;

  double get level {
    _decay();
    return _level;
  }

  bool get sulking {
    final u = _sulkUntil;
    if (u == null) return false;
    if (_now().isAfter(u)) {
      _sulkUntil = null;
      _sulkReason = null;
      return false;
    }
    return true;
  }

  /// When the current sulk ends (null = not sulking).
  DateTime? get sulkUntil => sulking ? _sulkUntil : null;

  /// For the AI: 'ok', 'annoyed' or 'sulking'.
  String get mood => sulking
      ? 'sulking'
      : level >= 0.45
      ? 'annoyed'
      : 'ok';

  /// One line for the AI prompt (app state), or null when calm.
  String? get moodForBrain {
    if (sulking) {
      return 'mood: SULKING because the user ${_sulkReason ?? 'annoyed you'}. '
          'Still answer real requests, but pouty and short, until they '
          'apologise or say something sweet; then forgive warmly.';
    }
    if (level >= 0.45) {
      return 'mood: a bit annoyed (poked or shaken a lot). Grumble a little, '
          'then be yourself again.';
    }
    return null;
  }

  void _decay() {
    final now = _now();
    final at = _at;
    _at = now;
    if (at == null || _level == 0) return;
    final dt = now.difference(at).inMilliseconds / halfLife.inMilliseconds;
    if (dt > 0) _level *= math.pow(0.5, dt).toDouble();
    if (_level < 0.01) _level = 0;
  }

  void _add(double v) {
    _decay();
    _level = (_level + v).clamp(0.0, 1.0);
  }

  void _startSulk(String reason, Duration d) {
    _sulkUntil = _now().add(d);
    _sulkReason = reason;
    _level = math.max(_level, 0.85);
    _pending = null;
  }

  /// Ends the sulk and calms down.
  void _forgive() {
    _sulkUntil = null;
    _sulkReason = null;
    _decay();
    _level = math.min(_level, 0.1);
  }

  /// A finger on the face. Rapid pokes add up.
  PokeReaction poke() {
    final now = _now();
    _pokes
      ..add(now)
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 5));
    if (sulking) return PokeReaction.ignore;
    final n = _pokes.length;
    _add(n >= 3 ? 0.12 + 0.05 * (n - 3) : 0.03);
    if (_level >= 0.8) {
      _startSulk('kept poking your face', const Duration(seconds: 30));
      return PokeReaction.sulk;
    }
    if (n >= 4) {
      final said = _annoyedSaid;
      if (said == null || now.difference(said) > const Duration(seconds: 6)) {
        _annoyedSaid = now;
        return PokeReaction.annoyed;
      }
    }
    return PokeReaction.squish;
  }

  /// True while the user is clearly poking (3+ taps within a few seconds):
  /// those taps are not "tap to talk".
  bool get poking {
    final now = _now();
    return _pokes
            .where((t) => now.difference(t) <= const Duration(seconds: 3))
            .length >=
        3;
  }

  /// The phone was shaken.
  void shaken() {
    _add(0.3);
    if (_level >= 0.9 && !sulking) {
      _startSulk('shook you hard', const Duration(seconds: 25));
    }
  }

  /// Stroked on the face. Returns true when it makes up (or was fine).
  /// While sulking it takes about two strokes.
  bool pet() {
    _decay();
    _level = math.max(0, _level - 0.35);
    if (!sulking) return true;
    if (_level < 0.5) {
      _forgive();
      return true;
    }
    return false;
  }

  /// Checks what the user said: an insult makes it sulk, an apology or a
  /// sweet word ends a sulk. Returns the change.
  TemperChange heard(String text) {
    final t = normalizeText(text);
    if (_sweet.hasMatch(t)) {
      final was = sulking || level >= 0.3;
      _forgive();
      return was ? TemperChange.madeUp : TemperChange.none;
    }
    if (_insult.hasMatch(t)) {
      _add(0.6);
      _startSulk('insulted you', const Duration(seconds: 45));
      return TemperChange.insulted;
    }
    return TemperChange.none;
  }

  /// "3afak" said alone right after a skit was asked: returns that skit.
  FaceAct? pleaseFollowUp(String text) {
    final p = _pending, u = _pendingUntil;
    if (p == null || u == null || _now().isAfter(u)) return null;
    if (!_pleaseOnly.hasMatch(normalizeText(text))) return null;
    _pending = null;
    return p;
  }

  /// Should it play the skit asked by voice? [said] is the user's sentence
  /// (to see if it says "3afak").
  SkitDecision decide(FaceAct a, String said) {
    final now = _now();
    final polite = _please.hasMatch(normalizeText(said));
    if (sulking) return SkitDecision.refuseSulking;
    if (a == FaceAct.eat &&
        _ate != null &&
        now.difference(_ate!) < const Duration(minutes: 3)) {
      return SkitDecision.full;
    }
    if (a == FaceAct.drink &&
        _drank != null &&
        now.difference(_drank!) < const Duration(minutes: 3)) {
      return SkitDecision.quenched;
    }
    // Love is never refused when it is not sulking.
    if (a == FaceAct.love) return SkitDecision.play;
    final lv = level;
    if (lv >= 0.45 && !polite && _r.nextDouble() < 0.6) {
      return SkitDecision.refuseMood;
    }
    if (!polite && _r.nextDouble() < 0.2) {
      _pending = a;
      _pendingUntil = now.add(const Duration(seconds: 30));
      return SkitDecision.askPlease;
    }
    return SkitDecision.play;
  }

  /// A skit really played (eating/drinking makes it happy and full).
  void played(FaceAct a) {
    if (a == FaceAct.eat) _ate = _now();
    if (a == FaceAct.drink) _drank = _now();
    if (a == FaceAct.eat || a == FaceAct.drink) {
      _decay();
      _level = math.max(0, _level - 0.25);
    }
  }

  static final _please = RegExp(
    r'\b(?:3afak|afak|3fak|3afek|please|pls|stp|svp|s il te plait|s il vous plait)\b|عافاك|من فضلك',
  );
  static final _pleaseOnly = RegExp(
    r'^(?:(?:wa|ya|a)\s+)?(?:3afak|afak|3fak|3afek|please|pls|stp|svp|s il te plait|عافاك|من فضلك)(?:\s+(?:a|ya)\s+\S+)?\s*[!.]*$',
  );
  static final _sweet = RegExp(
    r'\b(?:sme7 ?li|smeh ?li|sma7 ?li|sm7 ?li|smh ?li|sme7li|sma7li|smhli|sm7li|sme7 lia|sma7 lia|smh lia|sm7 lia|pardon|desole|sorry|kanbghik|kanbghik bzaf|kanmout 3lik|nta zwin|nta l3ziz|nta 3ziz|habibi|je t aime|je taime|i love you|love you)\b|سمح ?لي|سمحلي|كنبغيك|سماح|سامحني|نتا زوين|حبيبي',
  );
  static const _w =
      r'(?:7mar|hmar|7mara|bhim|bhima|kelb|klb|ghbi|ghabi|mkelkh|mklkh|m3a9|mse6ti|msetti|khayb|khayeb|stupid|idiot|dumb|nul|bete|con|debile|imbecile|حمار|بهيم|كلب|غبي|مكلخ|خايب|مسطي)';
  // Aimed at the robot: "nta 7mar", "ya bhim", "7mar!" alone, "you are dumb".
  static final _insult = RegExp(
    '^(?:(?:a|ya|wa|يا|ا)\\s+\\S+\\s+)?(?:(?:wa|ya|a|nta|enta|anta|nti|you|you re|youre|you are|are|tu es|t es|tes|t as|tu|t|وا|يا|ا|نتا|انتا)\\s+)*$_w(?:\\s+(?:nta|bzaf|wa|a|ya|\\S+))?\\s*[!.?]*\$|\\b(?:tfou 3lik|sir t9awed|sir tqawed|shut up|ta gueule|ferme la)\\b|سير تقود|تفو عليك',
  );
}

enum TemperChange { none, insulted, madeUp }
