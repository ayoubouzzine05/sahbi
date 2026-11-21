import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import '../../core/backend_client.dart';
import '../live/live_player.dart';
import '../live/live_session.dart';
import 'voice_types.dart';

/// Gemini Live output: 24 kHz mono 16-bit PCM.
const liveVoiceSampleRate = 24000;

/// The voice the user picked ("C"): the Live voice played 7 % faster, which
/// makes it a little lighter and quicker (pitch and tempo together).
const liveVoicePlaybackRate = 1.07;

int get liveVoiceOutputRate =>
    (liveVoiceSampleRate * liveVoicePlaybackRate).round();

/// Speaker for raw PCM (injectable for tests).
abstract class PcmSpeaker {
  Future<void> open(int sampleRate);
  Future<void> feed(Uint8List pcm);
  Future<void> close();
}

class FlutterPcmSpeaker implements PcmSpeaker {
  bool _open = false;

  @override
  Future<void> open(int sampleRate) async {
    if (_open) return;
    await FlutterPcmSound.setLogLevel(LogLevel.none);
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    await FlutterPcmSound.setFeedThreshold(sampleRate ~/ 10);
    _open = true;
  }

  @override
  Future<void> feed(Uint8List pcm) => FlutterPcmSound.feed(
    PcmArrayInt16(bytes: ByteData.view(Uint8List.fromList(pcm).buffer)),
  );

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
  }
}

/// SAHBI's speaking voice: a Gemini Live session minted by the backend in
/// "voice" mode (a voice-actor prompt that reads each line word for word in
/// a light Casablanca street style). Audio streams in, so the first syllable
/// plays about half a second after the text is sent. The session stays open
/// between sentences and closes after [idleClose] of silence.
class LiveVoiceTts implements TtsProvider {
  LiveVoiceTts({
    required this.token,
    required this.isConfigured,
    PcmSpeaker? speaker,
    LiveConnector? connector,
    this.firstAudioTimeout = const Duration(seconds: 6),
    this.turnTimeout = const Duration(seconds: 40),
    this.readyTimeout = const Duration(seconds: 8),
    this.idleClose = const Duration(seconds: 90),
    this.tail = const Duration(milliseconds: 150),
  }) : _speaker = speaker ?? FlutterPcmSpeaker(),
       _connector = connector;

  /// Mints a voice-mode token (`POST /v1/live/token` with mode "voice").
  final Future<LiveTokenInfo> Function() token;
  final bool Function() isConfigured;
  final Duration firstAudioTimeout;
  final Duration turnTimeout;
  final Duration readyTimeout;
  final Duration idleClose;
  final Duration tail;
  final PcmSpeaker _speaker;
  final LiveConnector? _connector;

  LiveSession? _session;
  Future<LiveSession>? _opening;
  Timer? _idle;
  StreamController<TtsEvent>? _ctrl;
  StreamSubscription<LiveEvent>? _turnSub;
  LivePlayer? _player;
  int _gen = 0;

  @override
  String get id => 'live';

  @override
  Future<ProviderAvailability> availability() async => isConfigured()
      ? ProviderAvailability.available
      : ProviderAvailability.notConfigured;

  @override
  Future<List<TtsVoice>> voices() async => const [];

  Future<LiveSession> _ensureSession() {
    final s = _session;
    if (s != null && s.ready) return Future.value(s);
    return _opening ??= () async {
      try {
        final t = await token();
        final session = LiveSession(
          wsUrl: t.wsUrl,
          token: t.token,
          model: t.model,
          connector: _connector,
        );
        final ready = session.events
            .firstWhere((e) => e is LiveReady || e is LiveClosed)
            .timeout(readyTimeout);
        await session.start();
        final first = await ready;
        if (first is! LiveReady) {
          await session.close();
          throw StateError('live voice closed before ready');
        }
        session.events.listen((e) {
          if (e is LiveClosed && identical(_session, session)) _session = null;
        });
        _session = session;
        return session;
      } finally {
        _opening = null;
      }
    }();
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(idleClose, () => unawaited(close()));
  }

  @override
  Stream<TtsEvent> speak(String text, {required String language}) {
    _finishTurn(interrupted: true);
    final ctrl = StreamController<TtsEvent>();
    _ctrl = ctrl;
    final gen = ++_gen;
    _idle?.cancel();
    () async {
      try {
        final s = await _ensureSession();
        if (gen != _gen) return;
        await _speaker.open(liveVoiceOutputRate);
        final player = LivePlayer(
          feed: _speaker.feed,
          sampleRate: liveVoiceOutputRate,
        );
        _player = player;
        final firstAudio = Completer<void>();
        final turnDone = Completer<void>();
        _turnSub = s.events.listen((e) {
          if (gen != _gen) return;
          switch (e) {
            case LiveAudio(:final pcm):
              if (!firstAudio.isCompleted) {
                firstAudio.complete();
                if (!ctrl.isClosed) ctrl.add(const TtsStarted());
              }
              player.add(pcm);
            case LiveTurnComplete():
              player.turnComplete();
              if (!turnDone.isCompleted) turnDone.complete();
            case LiveClosed():
              if (!firstAudio.isCompleted) {
                firstAudio.completeError(StateError('live voice closed'));
              }
              if (!turnDone.isCompleted) turnDone.complete();
            default:
              break;
          }
        });
        s.sendText(text);
        await firstAudio.future.timeout(firstAudioTimeout);
        await turnDone.future.timeout(turnTimeout, onTimeout: () {});
        // Let the queued audio finish playing.
        while (gen == _gen && player.playing) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (gen != _gen) return;
        await Future<void>.delayed(tail);
        if (gen != _gen) return;
        await _endTurn(gen);
        if (!ctrl.isClosed) {
          ctrl.add(const TtsDone());
          await ctrl.close();
        }
      } catch (e) {
        if (gen != _gen) return;
        await _endTurn(gen);
        // A broken session is not reused.
        final s = _session;
        _session = null;
        unawaited(s?.close());
        if (!ctrl.isClosed) {
          ctrl.add(TtsFailure('live voice: $e'));
          await ctrl.close();
        }
      }
    }();
    return ctrl.stream;
  }

  Future<void> _endTurn(int gen) async {
    await _turnSub?.cancel();
    _turnSub = null;
    _player?.clear();
    _player = null;
    await _speaker.close();
    if (gen == _gen) _armIdle();
  }

  void _finishTurn({required bool interrupted}) {
    final c = _ctrl;
    _ctrl = null;
    if (c != null && !c.isClosed) {
      c.add(TtsDone(interrupted: interrupted));
      unawaited(c.close());
    }
  }

  @override
  Future<void> stop() async {
    final gen = ++_gen; // late audio of the cut sentence is ignored
    _finishTurn(interrupted: true);
    await _endTurn(gen);
  }

  /// Closes the session (idle, app in background, live camera opening).
  Future<void> close() async {
    _idle?.cancel();
    _gen++;
    _finishTurn(interrupted: true);
    await _turnSub?.cancel();
    _turnSub = null;
    _player?.clear();
    _player = null;
    await _speaker.close();
    final s = _session;
    _session = null;
    await s?.close();
  }
}

/// Tries [primary] (the live voice) and, for that one sentence, [secondary]
/// (the backend TTS with the same prebuilt voice) when the primary fails
/// before making any sound. After a primary failure it is skipped for
/// [cooldown], then tried again.
class FallbackTts implements TtsProvider {
  FallbackTts(
    this.primary,
    this.secondary, {
    this.cooldown = const Duration(seconds: 60),
    DateTime Function()? clock,
    this.onPrimaryFailure,
  }) : _now = clock ?? DateTime.now;

  final TtsProvider primary;
  final TtsProvider secondary;
  final Duration cooldown;
  final DateTime Function() _now;
  final void Function(String message)? onPrimaryFailure;
  DateTime? _primaryDownUntil;
  TtsProvider? _active;

  @override
  String get id => 'cloud';

  bool get primaryCooling {
    final u = _primaryDownUntil;
    return u != null && _now().isBefore(u);
  }

  @override
  Future<ProviderAvailability> availability() async {
    final a = await primary.availability();
    if (a == ProviderAvailability.available) return a;
    return secondary.availability();
  }

  @override
  Future<List<TtsVoice>> voices() => secondary.voices();

  @override
  Stream<TtsEvent> speak(String text, {required String language}) async* {
    if (!primaryCooling &&
        await primary.availability() == ProviderAvailability.available) {
      _active = primary;
      var started = false;
      String? failure;
      await for (final e in primary.speak(text, language: language)) {
        if (e is TtsFailure && !started) {
          failure = e.message;
          break;
        }
        if (e is TtsStarted) started = true;
        yield e;
      }
      if (failure == null) return;
      _primaryDownUntil = _now().add(cooldown);
      onPrimaryFailure?.call(failure);
    }
    _active = secondary;
    yield* secondary.speak(text, language: language);
  }

  @override
  Future<void> stop() async {
    final a = _active;
    if (a != null) await a.stop();
  }
}
