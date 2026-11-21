import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/error_log.dart';
import '../personality/voice_state.dart';
import '../settings/app_settings.dart';
import 'voice_types.dart';

/// Result of spotting the robot's name in a transcript.
class WakeHit {
  const WakeHit(this.rest);

  /// What the user said after the name ('' when they only called it).
  final String rest;
}

/// Phonetic skeleton shared by Arabic script and Latin/Arabizi spellings, so
/// "Zizou", "zizo" and "زيزو" all give "zz"; "Sahbi", "sa7bi" and "صاحبي"
/// give "shb". Vowels and ع/ء are dropped, doubled consonants collapsed.
String phoneticKey(String word) {
  final w = word.toLowerCase().trim();
  const ar = {
    'ب': 'b',
    'پ': 'b',
    'ت': 't',
    'ث': 't',
    'ط': 't',
    'ج': 'j',
    'ح': 'h',
    'ه': 'h',
    'خ': 'k',
    'ق': 'k',
    'ك': 'k',
    'ڭ': 'g',
    'گ': 'g',
    'غ': 'g',
    'د': 'd',
    'ذ': 'd',
    'ض': 'd',
    'ظ': 'd',
    'ر': 'r',
    'ز': 'z',
    'س': 's',
    'ص': 's',
    'ش': 'c',
    'ف': 'f',
    'ڤ': 'f',
    'ل': 'l',
    'م': 'm',
    'ن': 'n',
  };
  final b = StringBuffer();
  var prev = '';
  var i = 0;
  while (i < w.length) {
    final ch = w[i];
    final two = i + 1 < w.length ? w.substring(i, i + 2) : '';
    String? out;
    var step = 1;
    if (two == 'ph') {
      out = 'f';
      step = 2;
    } else if (two == 'ch' || two == 'sh') {
      out = 'c';
      step = 2;
    } else if (two == 'kh') {
      out = 'k';
      step = 2;
    } else if (two == 'gh') {
      out = 'g';
      step = 2;
    } else if (ar.containsKey(ch)) {
      out = ar[ch];
    } else {
      out = switch (ch) {
        '7' => 'h',
        '9' || '5' || 'q' || 'c' => 'k',
        'x' => 'ks',
        'v' => 'f',
        'p' => 'b',
        'b' || 'd' || 'f' || 'g' || 'h' || 'j' || 'k' || 'l' || 'm' => ch,
        'n' || 'r' || 's' || 't' || 'z' => ch,
        _ => null, // vowels, w/y, 3, 2, ع, ء, ا, و, ي, ة, ى, punctuation
      };
    }
    if (out != null) {
      // Collapse only directly doubled consonants ("Sahhbi"), not repeats
      // separated by a vowel ("Zizou" keeps both z).
      for (final o in out.split('')) {
        if (o != prev) b.write(o);
        prev = o;
      }
    } else {
      prev = '';
    }
    i += step;
  }
  return b.toString();
}

int _lev(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

String _plain(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '') // harakat, tatweel
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي');

/// Finds [name] (1–3 words, any script) in [transcript]. Matches the exact
/// normalised words, or the phonetic skeleton (edit distance ≤ 1 when the
/// skeleton has ≥ 4 consonants). A leading "ya / يا / a / أ" is allowed.
WakeHit? matchWakeName(String transcript, String name) {
  final words = _plain(transcript)
      .split(RegExp(r'[\s,.!?؟،:;]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final nameWords = _plain(name)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty || nameWords.isEmpty) return null;
  final n = nameWords.length;
  final nameJoined = nameWords.join(' ');
  final nameKey = phoneticKey(nameWords.join());
  for (var i = 0; i + n <= words.length; i++) {
    var cand = words.sublist(i, i + n).join(' ');
    // "يا صاحبي" written as one word, or Arabizi "yasahbi".
    for (final p in const ['يا', 'ya']) {
      if (cand.startsWith(p) &&
          !nameJoined.startsWith(p) &&
          cand.length > p.length + 1) {
        final stripped = cand.substring(p.length);
        if (stripped == nameJoined ||
            phoneticKey(stripped.replaceAll(' ', '')) == nameKey) {
          cand = stripped;
        }
      }
    }
    final candKey = phoneticKey(cand.replaceAll(' ', ''));
    final exact = cand == nameJoined;
    final phon =
        nameKey.length >= 2 &&
        (candKey == nameKey ||
            (nameKey.length >= 4 && _lev(candKey, nameKey) <= 1));
    if (exact || phon) {
      return WakeHit(words.sublist(i + n).join(' ').trim());
    }
  }
  return null;
}

/// Names to listen for: the user's chosen name, or صاحبي / Sahbi by default
/// ("sahbi" is an everyday word, so it is not used once a name is chosen).
List<String> wakeNamesFor(AppSettings s) => s.robotName.trim().isEmpty
    ? const ['صاحبي', 'sahbi']
    : [s.robotName.trim()];

/// While the app is open and idle, keeps the on-device recogniser running in
/// short sessions and reacts when the robot's name is heard: with words after
/// the name they are sent straight away ("Zizou, chno ljaw?"), otherwise it
/// opens the mic as if the user had tapped it. Nothing is recorded or sent
/// anywhere while waiting for the name: the platform recogniser does it.
class WakeNameController extends ChangeNotifier {
  WakeNameController({
    required this.listen,
    required this.cancel,
    required this.settings,
    required this.voiceState,
    required this.micGranted,
    required this.onWake,
    required this.onCommand,
    required this.log,
    this.localeFor,
    Duration? restartDelay,
  }) : restartDelay = restartDelay ?? const Duration(milliseconds: 400);

  final Stream<SttEvent> Function(String localeId) listen;
  final Future<void> Function() cancel;
  final AppSettings Function() settings;
  final VoiceState Function() voiceState;
  final Future<bool> Function() micGranted;
  final Future<void> Function() onWake;
  final void Function(String text) onCommand;
  final Future<String> Function(String replyLanguage)? localeFor;
  final ErrorLog log;
  final Duration restartDelay;

  bool _foreground = true;
  int _suspended = 0;
  bool _running = false;
  int _gen = 0;
  int _failures = 0;
  StreamSubscription<SttEvent>? _sub;
  Timer? _restart;

  /// True while the recogniser is waiting for the name.
  bool get active => _running;
  String? lastError;

  bool get _shouldRun =>
      settings().wakeByName &&
      _foreground &&
      _suspended == 0 &&
      voiceState() == VoiceState.idle;

  /// App lifecycle: only listen while the app is in the foreground.
  void setForeground(bool v) {
    _foreground = v;
    refresh();
  }

  /// Screens with their own mic (live camera) suspend wake listening.
  void suspend() {
    _suspended++;
    refresh();
  }

  void resume() {
    if (_suspended > 0) _suspended--;
    refresh();
  }

  /// Re-evaluate after settings / voice-state changes.
  void refresh() {
    if (_shouldRun) {
      if (!_running && _restart == null) _schedule(restartDelay);
    } else {
      _stop();
    }
  }

  void _schedule(Duration d) {
    _restart?.cancel();
    _restart = Timer(d, () {
      _restart = null;
      _start();
    });
  }

  Future<void> _start() async {
    if (_running || !_shouldRun) return;
    if (!await micGranted()) {
      lastError = 'no_permission';
      notifyListeners();
      return;
    }
    if (!_shouldRun) return;
    final gen = ++_gen;
    _running = true;
    lastError = null;
    notifyListeners();
    final locale =
        await (localeFor?.call(settings().replyLanguage) ??
            Future.value('ar-MA'));
    if (gen != _gen || !_shouldRun) {
      _running = false;
      notifyListeners();
      return;
    }
    var handled = false;
    _sub = listen(locale).listen(
      (e) {
        if (gen != _gen || handled) return;
        final (text, alts) = switch (e) {
          SttPartial(:final text, :final alternates) => (text, alternates),
          SttFinal(:final text, :final alternates) => (text, alternates),
          _ => (null, const <String>[]),
        };
        if (e case SttFailure(:final code, :final message)) {
          if (code != 'no_match') {
            _failures++;
            log.add('wake', '$code: $message');
            if (code == 'not_available' || code == 'no_permission') {
              lastError = code;
            }
          }
          return;
        }
        if (text == null || text.isEmpty) return;
        // The name is often only in the recogniser's 2nd/3rd guess.
        WakeHit? hit;
        for (final t in [text, ...alts]) {
          hit = _match(t);
          if (hit != null) break;
        }
        if (hit == null) return;
        // In a partial, wait for the final result when words follow the name.
        if (e is SttPartial && hit.rest.isNotEmpty) return;
        handled = true;
        _failures = 0;
        _fire(gen, hit);
      },
      onDone: () {
        if (gen != _gen) return;
        _running = false;
        notifyListeners();
        if (handled) return;
        if (lastError == 'not_available' || lastError == 'no_permission') {
          return; // do not spin on a missing recogniser
        }
        // Back off on repeated errors (busy engine, no network…).
        final backoff = _failures == 0
            ? restartDelay
            : Duration(milliseconds: (500 * _failures).clamp(500, 8000));
        if (_shouldRun) _schedule(backoff);
      },
    );
  }

  WakeHit? _match(String text) {
    for (final n in wakeNamesFor(settings())) {
      final hit = matchWakeName(text, n);
      if (hit != null) return hit;
    }
    return null;
  }

  Future<void> _fire(int gen, WakeHit hit) async {
    await _sub?.cancel();
    _sub = null;
    await cancel();
    _running = false;
    notifyListeners();
    log.add('wake', hit.rest.isEmpty ? 'name heard' : 'name + command');
    if (hit.rest.isEmpty) {
      await onWake();
    } else {
      onCommand(hit.rest);
    }
  }

  /// Stops wake listening and waits until the recogniser is released, so the
  /// push-to-talk session that follows gets the microphone.
  Future<void> yieldMic() async {
    _restart?.cancel();
    _restart = null;
    if (!_running) return;
    _gen++;
    _running = false;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    await cancel();
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  void _stop() {
    _restart?.cancel();
    _restart = null;
    if (!_running) return;
    _gen++;
    _running = false;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    unawaited(cancel());
    notifyListeners();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
