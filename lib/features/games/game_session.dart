import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../brain/text_normalizer.dart';
import '../personality/emotion.dart';
import '../personality/personality_responses.dart';
import 'game_bank.dart';

enum GameKind { riddle, trivia, reaction }

/// Reaction game phases: wait for green eyes → tap → result.
enum ReactionPhase { off, waiting, now, early, done }

/// What MIMO says after an answer, and whether the game is over.
class GameReply {
  const GameReply(this.line, {required this.over, this.won = false});
  final Line line;
  final bool over;
  final bool won;
}

/// Offline mini-games (riddles, 3-choice trivia, the reaction tap game).
/// No AI request: questions and checking are local, so it works offline and
/// costs no quota.
class GameSession extends ChangeNotifier {
  GameSession({
    math.Random? random,
    DateTime Function()? clock,
    this.answerWindow = const Duration(seconds: 90),
  }) : _r = random ?? math.Random(),
       _clock = clock ?? DateTime.now;

  final math.Random _r;
  final DateTime Function() _clock;

  /// A riddle / question waits this long for an answer.
  final Duration answerWindow;

  GameKind? _kind;
  Riddle? _riddle;
  Trivia? _trivia;
  int _tries = 0;
  DateTime? _askedAt;
  int _lastRiddle = -1;
  int _lastTrivia = -1;

  ReactionPhase reaction = ReactionPhase.off;
  int? reactionMs;
  DateTime? _greenAt;
  Timer? _reactionTimer;

  /// Called when the reaction game ends (result / too early / no tap).
  void Function(Line line)? onReactionResult;

  GameKind? get kind => _kind;

  /// A riddle or question is waiting for the user's answer.
  bool get awaitingAnswer {
    final at = _askedAt;
    if (_kind == null || _kind == GameKind.reaction || at == null) {
      return false;
    }
    if (_clock().difference(at) > answerWindow) {
      _clear();
      return false;
    }
    return true;
  }

  bool get reactionActive =>
      reaction == ReactionPhase.waiting || reaction == ReactionPhase.now;

  bool get active => awaitingAnswer || reactionActive;

  /// Starts a riddle; returns what MIMO says.
  Line startRiddle() {
    stop();
    final list = GameBank.riddles;
    var i = _r.nextInt(list.length);
    if (i == _lastRiddle) i = (i + 1) % list.length;
    _lastRiddle = i;
    _riddle = list[i];
    _kind = GameKind.riddle;
    _askedAt = _clock();
    _tries = 0;
    notifyListeners();
    return _riddle!.question;
  }

  Line startTrivia() {
    stop();
    final list = GameBank.trivia;
    var i = _r.nextInt(list.length);
    if (i == _lastTrivia) i = (i + 1) % list.length;
    _lastTrivia = i;
    _trivia = list[i];
    _kind = GameKind.trivia;
    _askedAt = _clock();
    _tries = 0;
    notifyListeners();
    return _trivia!.question;
  }

  /// Starts the reaction game: the eyes turn green after 1.5–4.5 s.
  Line startReaction() {
    stop();
    _kind = GameKind.reaction;
    reaction = ReactionPhase.waiting;
    reactionMs = null;
    final wait = Duration(milliseconds: 1500 + _r.nextInt(3000));
    // Leaves time for the intro line before the countdown matters.
    _reactionTimer = Timer(wait + const Duration(seconds: 2), _goGreen);
    notifyListeners();
    return _reactionIntro;
  }

  void _goGreen() {
    if (reaction != ReactionPhase.waiting) return;
    reaction = ReactionPhase.now;
    _greenAt = _clock();
    _reactionTimer = Timer(const Duration(seconds: 4), () {
      if (reaction != ReactionPhase.now) return;
      _finishReaction(_tooSlow, ReactionPhase.done);
    });
    notifyListeners();
  }

  /// The user tapped the face during the reaction game.
  void tap() {
    switch (reaction) {
      case ReactionPhase.waiting:
        _finishReaction(_tooEarly, ReactionPhase.early);
      case ReactionPhase.now:
        final ms = _clock().difference(_greenAt!).inMilliseconds;
        reactionMs = ms;
        _finishReaction(_reactionLine(ms), ReactionPhase.done);
      case ReactionPhase.off || ReactionPhase.early || ReactionPhase.done:
        break;
    }
  }

  void _finishReaction(Line line, ReactionPhase phase) {
    _reactionTimer?.cancel();
    reaction = phase;
    _kind = null;
    notifyListeners();
    onReactionResult?.call(line);
    // The result stays on screen for a moment.
    _reactionTimer = Timer(const Duration(seconds: 3), () {
      reaction = ReactionPhase.off;
      notifyListeners();
    });
  }

  /// Checks the user's words against the waiting riddle / question.
  /// Null = no game waiting (the text goes to the normal brain).
  GameReply? answer(String text) {
    if (!awaitingAnswer) return null;
    final t = ' ${normalizeText(text)} ';
    final tokens = t.trim().split(' ').expand(_variants).toSet();
    bool has(String k) {
      final n = normalizeText(k);
      return n.contains(' ') ? t.contains(' $n ') : tokens.contains(n);
    }

    final giveUp = _giveUpRe.hasMatch(t);
    final stop = _stopRe.hasMatch(t);
    switch (_kind) {
      case GameKind.riddle:
        final r = _riddle!;
        if (r.keys.any(has)) {
          _clear();
          return GameReply(_pick(_correct), over: true, won: true);
        }
        _tries++;
        if (giveUp || stop || _tries >= 2) {
          _clear();
          return GameReply(_reveal(r.answer), over: true);
        }
        _askedAt = _clock();
        return GameReply(_pick(_tryAgain), over: false);
      case GameKind.trivia:
        final q = _trivia!;
        var choice = -1;
        for (var i = 0; i < 3 && choice < 0; i++) {
          if (q.keys[i].any(has)) choice = i;
        }
        for (var i = 0; i < 3 && choice < 0; i++) {
          if (GameBank.ordinals[i].any(has)) choice = i;
        }
        if (choice == q.correct) {
          _clear();
          return GameReply(_pick(_correct), over: true, won: true);
        }
        if (choice < 0 && !giveUp && !stop && _tries == 0) {
          _tries++;
          _askedAt = _clock();
          return GameReply(_pick(_pickOne), over: false);
        }
        _clear();
        return GameReply(_reveal(q.answer), over: true);
      case GameKind.reaction || null:
        return null;
    }
  }

  /// Starts [kind] and returns MIMO's first line.
  Line start(GameKind kind) => switch (kind) {
    GameKind.riddle => startRiddle(),
    GameKind.trivia => startTrivia(),
    GameKind.reaction => startReaction(),
  };

  /// Which game the user asked for ("7ajitek" → riddle, "quiz" → trivia,
  /// "sor3a" → reaction), or a random one for "nl3bo".
  GameKind kindFor(String text) {
    final t = normalizeText(text);
    if (RegExp(r'7aji|7jaya|حاجي|حجاي|devinette|riddle').hasMatch(t)) {
      return GameKind.riddle;
    }
    if (RegExp(r'quiz|su2al|so2al|سؤال|question').hasMatch(t)) {
      return GameKind.trivia;
    }
    if (RegExp(r'sor3a|sour3a|سرعه|reaction|reflex|reflexe').hasMatch(t)) {
      return GameKind.reaction;
    }
    return GameKind.values[_r.nextInt(GameKind.values.length)];
  }

  /// Ends any game (conversation over, app in background…).
  void stop() {
    _reactionTimer?.cancel();
    final wasActive = reaction != ReactionPhase.off || _kind != null;
    reaction = ReactionPhase.off;
    _clear();
    if (wasActive) notifyListeners();
  }

  void _clear() {
    _kind = null;
    _riddle = null;
    _trivia = null;
    _askedAt = null;
    _tries = 0;
  }

  @override
  void dispose() {
    _reactionTimer?.cancel();
    super.dispose();
  }

  /// "lfhed" → also "fhed"; "والرباط" → "رباط".
  static Iterable<String> _variants(String w) sync* {
    yield w;
    for (final p in const ['وال', 'ال', 'و', 'ب', 'l', 'f']) {
      if (w.length > p.length + 2 && w.startsWith(p)) {
        yield w.substring(p.length);
      }
    }
  }

  Line _pick(List<Line> l) => l[_r.nextInt(l.length)];

  static final _giveUpRe = RegExp(
    r' (?:ma ?3reft?ch|ma ?3rft?ch|ma n3rf|man3rf|معرفتش|ماعرفتش|ما عرفتش|مانعرف|ما نعرف|golha|goulha|gol li|goul li|قولها|قول ليا|je sais pas|je ne sais pas|sais pas|dis moi|i don t know|dont know|tell me|give up) ',
  );
  static final _stopRe = RegExp(r' (?:safi|baraka|stop|arrete|صافي|بركه) ');

  static Line _reveal(Line a) => Line(
    darijaAr: 'الجواب هو: ${a.darijaAr}. ماشي مشكل، المرة الجاية!',
    darijaLatin: 'Ljawab howa: ${a.darijaLatin}. Machi mochkil, lmerra jaya!',
    msa: 'الجواب هو: ${a.msa}. لا بأس، في المرة القادمة!',
    fr: 'La réponse : ${a.fr}. Pas grave, la prochaine fois !',
    en: 'The answer is: ${a.en}. No worries, next time!',
    emotion: Emotion.happy,
    intensity: 0.5,
  );

  static const _correct = [
    Line(
      darijaAr: 'واااو! صحيح! نتا قافز بزاف!',
      darijaLatin: 'Waaaw! S7i7! Nta 9afez bzaf!',
      msa: 'رائع! صحيح! أنت ذكي جدا!',
      fr: 'Waouh ! Exact ! T’es trop fort !',
      en: 'Wow! Correct! You’re so smart!',
      emotion: Emotion.happy,
      intensity: 1,
    ),
    Line(
      darijaAr: 'هيه! جبتيها! برافو عليك!',
      darijaLatin: 'Hiih! Jbtiha! Bravo 3lik!',
      msa: 'أصبت! أحسنت!',
      fr: 'Ouais ! Trouvé ! Bravo !',
      en: 'Yes! You got it! Well done!',
      emotion: Emotion.happy,
      intensity: 1,
    ),
  ];

  static const _tryAgain = [
    Line(
      darijaAr: 'لا لا، ماشي هي. عاود فكر مزيان!',
      darijaLatin: 'La la, machi hiya. 3awed fker mzyan!',
      msa: 'لا، ليست هي. فكر مرة أخرى!',
      fr: 'Non non, ce n’est pas ça. Réfléchis encore !',
      en: 'Nope, that’s not it. Think again!',
      emotion: Emotion.curious,
      intensity: 0.7,
    ),
    Line(
      darijaAr: 'قريب... ولا لا، ماشي قريب حتى. زيد جرب!',
      darijaLatin: '9rib... wla la, machi 9rib 7ta. Zid jerreb!',
      msa: 'قريب... بل لا، ليس قريبا. حاول مرة أخرى!',
      fr: 'Presque... non, même pas. Essaie encore !',
      en: 'Close... no, not even close. Try again!',
      emotion: Emotion.happy,
      intensity: 0.6,
    ),
  ];

  static const _pickOne = [
    Line(
      darijaAr: 'ختار وحدة من التلاتة: اللولة، التانية، ولا التالتة؟',
      darijaLatin: 'Khtar w7da mn tlata: lwla, tanya, wla talta?',
      msa: 'اختر واحدة من الثلاث: الأولى، الثانية، أم الثالثة؟',
      fr: 'Choisis une des trois : la première, la deuxième ou la troisième ?',
      en: 'Pick one of the three: the first, the second or the third?',
      emotion: Emotion.curious,
      intensity: 0.6,
    ),
  ];

  static const _reactionIntro = Line(
    darijaAr: 'يالله نلعبو! تسنا حتى يخضارو عينيا، وكليكي عليا بالزربة!',
    darijaLatin:
        'Yallah nl3bo! Tsna 7ta ykhdaro 3inya, w kliki 3liya b zzerba!',
    msa: 'لنلعب! انتظر حتى تصبح عيناي خضراوين، ثم المسني بسرعة!',
    fr: 'On joue ! Attends que mes yeux deviennent verts, puis touche-moi vite !',
    en: 'Let’s play! Wait until my eyes turn green, then tap me fast!',
    emotion: Emotion.happy,
    intensity: 0.9,
  );

  static const _tooEarly = Line(
    darijaAr: 'هههه زربتي! مازال ما خضارو عينيا.',
    darijaLatin: 'Hhhh zrbti! Mazal ma khdaro 3inya.',
    msa: 'تسرعت! لم تخضر عيناي بعد.',
    fr: 'Haha trop tôt ! Mes yeux n’étaient pas encore verts.',
    en: 'Haha, too early! My eyes weren’t green yet.',
    emotion: Emotion.happy,
    intensity: 0.8,
  );

  static const _tooSlow = Line(
    darijaAr: 'فين مشيتي؟ عينيا خضارو وما كليكيتيش!',
    darijaLatin: 'Fin mchiti? 3inya khdaro w ma klikitich!',
    msa: 'أين ذهبت؟ اخضرت عيناي ولم تلمسني!',
    fr: 'T’es où ? Mes yeux étaient verts et tu n’as pas touché !',
    en: 'Where did you go? My eyes went green and you didn’t tap!',
    emotion: Emotion.sad,
    intensity: 0.5,
  );

  static Line _reactionLine(int ms) {
    final fast = ms < 350;
    return Line(
      darijaAr: fast
          ? '$ms ميلي ثانية! نتا سريع بحال البرق!'
          : '$ms ميلي ثانية. مزيان، ولكن نقدر نغلبك!',
      darijaLatin: fast
          ? '$ms ms! Nta sri3 b7al lber9!'
          : '$ms ms. Mzyan, walakin n9der nghlbek!',
      msa: fast
          ? '$ms ميلي ثانية! سريع كالبرق!'
          : '$ms ميلي ثانية. جيد، لكن يمكنك أسرع!',
      fr: fast
          ? '$ms ms ! Rapide comme l’éclair !'
          : '$ms ms. Pas mal, mais tu peux faire mieux !',
      en: fast
          ? '$ms ms! Fast as lightning!'
          : '$ms ms. Not bad, but you can do better!',
      emotion: Emotion.happy,
      intensity: fast ? 1 : 0.7,
    );
  }
}
