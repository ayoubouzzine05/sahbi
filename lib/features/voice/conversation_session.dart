import 'dart:async';

import 'package:flutter/foundation.dart';

import '../brain/text_normalizer.dart';
import '../personality/voice_state.dart';

/// "Safi sir", "safi barak", "bslama", "صافي سير", "c'est bon, merci", "bye"…
/// The whole utterance must be a goodbye (an optional name or "a sahbi"
/// around it is fine), so "safi, chno ljaw?" keeps the conversation going.
bool isStopPhrase(String text, {String robotName = ''}) {
  var t = _clean(text);
  if (t.isEmpty) return false;
  final names = <String>{
    'a sahbi',
    'ya sahbi',
    'sahbi',
    'يا صاحبي',
    'صاحبي',
    'خويا',
    'khoya',
    'a khoya',
  };
  final n = _clean(robotName);
  if (n.isNotEmpty) names.addAll({n, 'a $n', 'ya $n', 'يا $n'});
  final cleanNames = names.map(_clean).toList()
    // Longest first so "ya sahbi" goes before "sahbi".
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final w in cleanNames) {
    if (t.startsWith('$w ')) t = t.substring(w.length + 1).trim();
    if (t.endsWith(' $w')) t = t.substring(0, t.length - w.length - 1).trim();
  }
  return _stopPhrases.contains(t);
}

String _clean(String s) =>
    normalizeText(s.replaceAll(RegExp(r"['’`]"), ' '))
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// Goodbyes, normalised like the transcripts (doubled letters collapsed…).
final Set<String> _stopPhrases = () {
  const safiTails = [
    '',
    'sir',
    'sir t3ess',
    'sir n3ess',
    'barak',
    'baraka',
    'baraka 3lik',
    'hadchi',
    'salina',
    'safi',
    'chokran',
    'choukran',
    'shukran',
    'merci',
    'bslama',
    'beslama',
    'tsbe7 3la khir',
    'tsbah 3la khir',
    'lah y3tik sse7a',
  ];
  const safiTailsAr = [
    '',
    'سير',
    'سير تعس',
    'سير نعس',
    'باراكا',
    'بركا',
    'بركة',
    'هادشي',
    'سالينا',
    'شكرا',
    'ميرسي',
    'بسلامة',
    'بالسلامة',
    'تصبح على خير',
  ];
  const others = [
    'sir',
    'sir t3ess',
    'sir n3ess',
    'sir t3es',
    'sir nn3ess',
    'baraka',
    'baraka 3lik',
    'baraka daba',
    'baraka 3lik daba',
    'bslama',
    'beslama',
    'b slama',
    'bsslama',
    'm3a salama',
    'ma3a salama',
    'tsbe7 3la khir',
    'tsbah 3la khir',
    'سير',
    'سير تعس',
    'سير نعس',
    'بركا',
    'بركا عليك',
    'باراكا',
    'باراكا عليك',
    'بسلامة',
    'بالسلامة',
    'مع السلامة',
    'تصبح على خير',
    'c est bon',
    'c est bon merci',
    'cest bon',
    'ça suffit',
    'au revoir',
    'bonne nuit',
    'à plus',
    "that's all",
    "that's it",
    'goodbye',
    'good bye',
    'bye',
    'bye bye',
    'good night',
    'see you',
  ];
  return {
    for (final t in safiTails) _clean('safi $t'),
    for (final t in safiTailsAr) _clean('صافي $t'),
    for (final o in others) _clean(o),
  };
}();

/// Keeps a spoken conversation going after the robot was called by name:
/// once the robot has answered, the mic opens again by itself for the next
/// sentence, so the user does not repeat the name. It ends when the user says
/// a goodbye ("safi sir"), stays silent for [maxSilentTurns] listens in a
/// row, music starts, or another screen takes the mic (live camera).
class ConversationSession extends ChangeNotifier {
  ConversationSession({
    required this.voiceState,
    required this.voiceChanges,
    required this.listen,
    required this.chatBusy,
    required this.musicPlaying,
    required this.blocked,
    this.onActiveChanged,
    this.onGoodbye,
    this.maxSilentTurns = 2,
    this.followUpDelay = const Duration(milliseconds: 450),
    this.silenceTimeout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    voiceChanges.addListener(_onVoice);
    _prev = voiceState();
  }

  final VoiceState Function() voiceState;
  final Listenable voiceChanges;

  /// Opens the mic for the next sentence (same path as the mic button).
  final Future<void> Function() listen;
  final bool Function() chatBusy;
  final bool Function() musicPlaying;

  /// True while another screen owns the mic or the app is in the background.
  final bool Function() blocked;
  final void Function(bool active)? onActiveChanged;

  /// Says a short goodbye after a stop phrase.
  final Future<void> Function()? onGoodbye;

  /// Used only when [silenceTimeout] is null: silent listens in a row.
  final int maxSilentTurns;
  final Duration followUpDelay;

  /// The conversation ends when the user has said nothing for this long
  /// (or says "safi sir"). Null = count silent listens ([maxSilentTurns]).
  final Duration Function()? silenceTimeout;
  final DateTime Function() _clock;
  DateTime _lastHeard = DateTime.fromMillisecondsSinceEpoch(0);

  bool _active = false;
  bool _robotInitiated = false;
  int _silent = 0;
  bool _listenEndedEmpty = false;
  late VoiceState _prev;
  Timer? _next;

  /// True while the robot keeps listening between turns.
  bool get active => _active;

  /// The robot started this exchange itself (a joke while the user was
  /// quiet): one silent listen ends it, and it does not count as the user
  /// being active.
  bool get robotInitiated => _active && _robotInitiated;

  /// Called by name (or the robot spoke first when [robotInitiated]).
  /// With [listenNow] the mic opens shortly (nobody else opens it).
  void start({bool robotInitiated = false, bool listenNow = false}) {
    if (_active) {
      if (!robotInitiated) _robotInitiated = false;
    } else {
      _active = true;
      _robotInitiated = robotInitiated;
      _silent = 0;
      _listenEndedEmpty = false;
      _lastHeard = _clock();
      onActiveChanged?.call(true);
      notifyListeners();
    }
    if (listenNow) _schedule(followUpDelay);
  }

  void end() {
    _next?.cancel();
    _next = null;
    if (!_active) return;
    _active = false;
    _robotInitiated = false;
    onActiveChanged?.call(false);
    notifyListeners();
  }

  /// Every final transcript passes here first. Returns true when it was a
  /// goodbye that ended the conversation (it is then not sent to the AI).
  bool handleFinalText(String text, {String robotName = ''}) {
    if (!_active) return false;
    _lastHeard = _clock();
    if (!isStopPhrase(text, robotName: robotName)) {
      // The user answered: a robot-started moment becomes a conversation.
      _robotInitiated = false;
      return false;
    }
    end();
    unawaited(onGoodbye?.call());
    return true;
  }

  void _onVoice() {
    final s = voiceState();
    final prev = _prev;
    _prev = s;
    if (s == prev || !_active) return;
    if (prev == VoiceState.listening) {
      if (s == VoiceState.thinking) {
        _silent = 0;
      } else {
        _listenEndedEmpty = true; // idle / error without words
      }
    }
    if (s != VoiceState.idle) {
      _next?.cancel();
      _next = null;
      return;
    }
    if (_listenEndedEmpty) {
      _listenEndedEmpty = false;
      _silent++;
      final timeout = silenceTimeout?.call();
      final over = _robotInitiated
          ? _silent >= 1
          : timeout != null
          ? _clock().difference(_lastHeard) >= timeout
          : _silent >= maxSilentTurns;
      if (over) {
        end();
        return;
      }
    }
    _schedule(followUpDelay);
  }

  void _schedule(Duration d) {
    _next?.cancel();
    _next = Timer(d, _followUp);
  }

  Future<void> _followUp() async {
    _next = null;
    if (!_active) return;
    if (musicPlaying() || blocked()) {
      end();
      return;
    }
    if (voiceState() != VoiceState.idle || chatBusy()) {
      // Still answering (or another flow took over): check again soon.
      _schedule(const Duration(milliseconds: 500));
      return;
    }
    await listen();
  }

  @override
  void dispose() {
    _next?.cancel();
    voiceChanges.removeListener(_onVoice);
    super.dispose();
  }
}
