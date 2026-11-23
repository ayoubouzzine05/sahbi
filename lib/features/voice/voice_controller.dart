import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/error_log.dart';
import '../personality/voice_state.dart';
import '../settings/app_settings.dart';
import 'voice_types.dart';

/// Orchestrates STT/TTS providers with automatic fallback
/// (cloud → on-device → typed input) and drives the voice state machine.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.deviceStt,
    required this.cloudStt,
    required this.deviceTts,
    required this.cloudTts,
    required this.settings,
    required this.cloudSttReady,
    required this.cloudTtsReady,
    required this.log,
    this.onFinalText,
    this.onDuckMusic,
    DateTime Function()? clock,
    this.cloudRetryDelays = const [
      Duration(milliseconds: 1500),
      Duration(milliseconds: 3500),
    ],
    this.cloudFailCooldown = const Duration(minutes: 2),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Waits before trying the cloud voice again when it is rate limited
  /// (Gemini's free TTS allows only a few sentences per minute). Retrying
  /// keeps the same voice instead of switching to the phone's voice.
  final List<Duration> cloudRetryDelays;

  /// After a real cloud failure (network, server) the phone voice is used
  /// for this long, then the cloud voice is tried again.
  final Duration cloudFailCooldown;

  final SttProvider deviceStt;
  final SttProvider cloudStt;
  final TtsProvider deviceTts;
  final TtsProvider cloudTts;
  final AppSettings Function() settings;
  final bool Function() cloudSttReady;
  final bool Function() cloudTtsReady;
  final ErrorLog log;

  /// Called with the recognised text (same pipeline as typed input).
  void Function(String text)? onFinalText;

  /// Awaited before the mic opens (wake-by-name releases the recogniser).
  Future<void> Function()? beforeListen;

  /// Called with true while Sahbi speaks so music can be ducked.
  void Function(bool duck)? onDuckMusic;

  final VoiceStateMachine _sm = VoiceStateMachine();
  VoiceState get state => _sm.state;

  String partial = '';

  /// What the robot is saying right now ('' when quiet): lets the wake
  /// word ignore MIMO saying its own name.
  String speakingText = '';
  double level = 0;
  bool micOpen = false;
  String? lastError;

  /// 'cloud' | 'device' | 'typed' — what the next/current listen uses.
  String activeStt = 'device';

  /// 'cloud' | 'device' | 'off'
  String activeTts = 'device';

  /// Incremented on every TTS word-boundary callback.
  final ValueNotifier<int> wordPulse = ValueNotifier(0);

  /// True while the current TTS engine sends word boundaries.
  bool hasWordTimings = false;

  bool _cloudSttFailed = false;
  DateTime? _cloudTtsFailedUntil;
  String? _lastTtsFailure;

  bool get _cloudTtsFailed {
    final u = _cloudTtsFailedUntil;
    return u != null && _clock().isBefore(u);
  }

  StreamSubscription<SttEvent>? _sttSub;
  StreamSubscription<TtsEvent>? _ttsSub;
  SttProvider? _currentStt;
  TtsProvider? _currentTts;

  /// Completer of the utterance in progress; completed with false when it is
  /// stopped so `speak()` never hangs.
  Completer<bool>? _speaking;

  /// Bumped on every stop/interrupt: an interrupted cloud utterance must not
  /// "fall back" to the device engine and start talking again.
  int _ttsGeneration = 0;

  /// Reset sticky cloud failures (e.g. after a successful health check).
  void resetFallbacks() {
    _cloudSttFailed = false;
    _cloudTtsFailedUntil = null;
  }

  bool _go(VoiceState to, {String? error}) {
    final ok = _sm.tryTransition(to, error: error);
    if (!ok) {
      log.add('voice', 'ignored transition ${_sm.state.name} → ${to.name}');
    }
    notifyListeners();
    return ok;
  }

  Future<String> resolveStt() async {
    final s = settings();
    if (s.sttMode == SttMode.typed) return activeStt = 'typed';
    final cloudAllowed =
        s.cloudVoiceEnabled && cloudSttReady() && !_cloudSttFailed;
    if (s.sttMode != SttMode.device && cloudAllowed) {
      if (await cloudStt.availability() == ProviderAvailability.available) {
        return activeStt = 'cloud';
      }
    }
    if (s.sttMode != SttMode.cloud || !cloudAllowed) {
      if (await deviceStt.availability() == ProviderAvailability.available) {
        return activeStt = 'device';
      }
    }
    return activeStt = 'typed';
  }

  Future<String> resolveTts() async {
    final s = settings();
    if (s.ttsMode == TtsMode.off) return activeTts = 'off';
    final cloudAllowed =
        s.cloudVoiceEnabled && cloudTtsReady() && !_cloudTtsFailed;
    if (s.ttsMode != TtsMode.device && cloudAllowed) return activeTts = 'cloud';
    if (await deviceTts.availability() == ProviderAvailability.available) {
      return activeTts = 'device';
    }
    return activeTts = 'off';
  }

  /// Start listening. Returns the provider id used, or 'typed' when no
  /// recogniser is available (the UI then focuses the text field).
  /// The caller must have obtained RECORD_AUDIO permission first.
  Future<String> startListening() async {
    // Microphone toggle off: nothing may record.
    if (!settings().micEnabled) {
      lastError = 'mic_off';
      notifyListeners();
      return 'mic_off';
    }
    if (state == VoiceState.speaking) await interrupt();
    if (state == VoiceState.listening) return activeStt;
    await beforeListen?.call();
    final which = await resolveStt();
    if (which == 'typed') {
      lastError = 'no_recognizer';
      notifyListeners();
      return which;
    }
    final provider = which == 'cloud' ? cloudStt : deviceStt;
    _currentStt = provider;
    final s = settings();
    var locale = 'ar-MA';
    final supported = await provider.supportedLocales();
    locale =
        pickLocale(supported, s.replyLanguage) ??
        (supported.isNotEmpty ? supported.first : locale);
    partial = '';
    lastError = null;
    micOpen = true;
    _go(VoiceState.listening);
    await _sttSub?.cancel();
    _sttSub = provider
        .listen(localeId: locale)
        .listen(
          (e) {
            switch (e) {
              case SttPartial(:final text):
                partial = text;
                notifyListeners();
              case SttLevel(level: final l):
                level = l;
                notifyListeners();
              case SttFinal(:final text):
                _closeMic();
                partial = text;
                if (text.trim().isEmpty) {
                  _go(VoiceState.idle);
                } else {
                  _go(VoiceState.thinking);
                  onFinalText?.call(text.trim());
                }
              case SttFailure(:final code, :final message):
                _closeMic();
                lastError = code;
                if (provider.id == 'cloud' &&
                    (code == 'network' || code == 'server')) {
                  _cloudSttFailed = true;
                }
                log.add('stt.${provider.id}', '$code: $message');
                if (code == 'no_match') {
                  _go(VoiceState.idle);
                } else {
                  _go(VoiceState.error, error: code);
                  _go(VoiceState.idle);
                }
            }
          },
          onDone: () {
            _closeMic();
            if (state == VoiceState.listening) _go(VoiceState.idle);
          },
        );
    return which;
  }

  void _closeMic() {
    micOpen = false;
    level = 0;
    notifyListeners();
  }

  Future<void> stopListening() async {
    if (state != VoiceState.listening) return;
    await _currentStt?.stop();
  }

  Future<void> cancelListening() async {
    if (state != VoiceState.listening) return;
    await _currentStt?.cancel();
    await _sttSub?.cancel();
    _closeMic();
    _go(VoiceState.idle);
  }

  void setThinking(bool thinking) {
    if (thinking) {
      _go(VoiceState.thinking);
    } else if (state == VoiceState.thinking) {
      _go(VoiceState.idle);
    }
  }

  void setError(String code) {
    lastError = code;
    _go(VoiceState.error, error: code);
    _go(VoiceState.idle);
  }

  /// Speak [text] in [language] (darija | ar | fr | en).
  /// Falls back from cloud to device TTS on failure. Completes when done.
  Future<bool> speak(String text, {required String language}) async {
    if (text.trim().isEmpty) {
      setThinking(false);
      return false;
    }
    await _stopTts();
    final gen = _ttsGeneration;
    speakingText = text;
    final which = await resolveTts();
    if (which == 'off' || gen != _ttsGeneration) {
      setThinking(false);
      return false;
    }
    if (which == 'device') return _speakWith(deviceTts, text, language);
    // Cloud voice: on a rate limit wait and retry with the SAME voice; only
    // fall back to the phone's voice for this sentence if it keeps failing.
    for (var attempt = 0; ; attempt++) {
      final ok = await _speakWith(cloudTts, text, language, idleAfter: false);
      if (gen != _ttsGeneration) return false; // interrupted: stay quiet
      if (ok) {
        _settleIdle();
        return true;
      }
      if (state == VoiceState.listening) return false;
      final limited = _lastTtsFailure?.startsWith('rateLimited') ?? false;
      if (limited && attempt < cloudRetryDelays.length) {
        log.add('tts.cloud', 'rate limited, retry ${attempt + 1}');
        _go(VoiceState.thinking); // nobody opens the mic meanwhile
        await Future<void>.delayed(cloudRetryDelays[attempt]);
        if (gen != _ttsGeneration || state == VoiceState.listening) {
          return false;
        }
        continue;
      }
      if (!limited) _cloudTtsFailedUntil = _clock().add(cloudFailCooldown);
      break;
    }
    activeTts = 'device';
    if (await deviceTts.availability() == ProviderAvailability.available &&
        gen == _ttsGeneration) {
      return _speakWith(deviceTts, text, language);
    }
    _settleIdle();
    return false;
  }

  void _settleIdle() {
    speakingText = '';
    if (state == VoiceState.speaking || state == VoiceState.thinking) {
      _go(VoiceState.idle);
    }
  }

  Future<bool> _speakWith(
    TtsProvider p,
    String text,
    String language, {
    bool idleAfter = true,
  }) async {
    _currentTts = p;
    _lastTtsFailure = null;
    activeTts = p.id;
    hasWordTimings = false;
    final done = _speaking = Completer<bool>();
    _go(VoiceState.speaking);
    onDuckMusic?.call(true);
    _ttsSub = p
        .speak(text, language: language)
        .listen(
          (e) {
            switch (e) {
              case TtsStarted():
                break;
              case TtsWord():
                hasWordTimings = true;
                wordPulse.value++;
              case TtsDone():
                if (!done.isCompleted) done.complete(true);
              case TtsFailure(:final message):
                log.add('tts.${p.id}', message);
                _lastTtsFailure = message;
                lastError = 'tts_failed';
                if (!done.isCompleted) done.complete(false);
            }
          },
          onDone: () {
            if (!done.isCompleted) done.complete(false);
          },
        );
    final ok = await done.future;
    onDuckMusic?.call(false);
    if (idleAfter && state == VoiceState.speaking) _go(VoiceState.idle);
    return ok;
  }

  Future<void> _stopTts() async {
    _ttsGeneration++;
    final pending = _speaking;
    _speaking = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    // Never await the engine here: cancelling an async* stream waits for the
    // producer to reach its next yield, which a busy engine may never do.
    final sub = _ttsSub;
    _ttsSub = null;
    unawaited(sub?.cancel());
    await _currentTts?.stop();
  }

  /// Interrupt speech immediately (button, new input, barge-in).
  Future<void> interrupt() async {
    await _stopTts();
    onDuckMusic?.call(false);
    if (state == VoiceState.speaking || state == VoiceState.thinking) {
      _go(VoiceState.idle);
    }
  }

  @override
  void dispose() {
    _sttSub?.cancel();
    _ttsSub?.cancel();
    wordPulse.dispose();
    super.dispose();
  }
}
