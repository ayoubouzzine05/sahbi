import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/backend_client.dart';
import '../../core/connectivity.dart';
import '../../core/error_log.dart';
import '../brain/brain_models.dart';
import '../brain/command_parser.dart';
import '../brain/text_normalizer.dart';
import '../memory/memory_store.dart';
import '../music/music_controller.dart';
import '../music/music_models.dart';
import '../personality/companion_controller.dart';
import '../personality/conversation_context.dart';
import '../personality/emotion.dart';
import '../personality/emotion_detector.dart';
import '../personality/personality_responses.dart';
import '../personality/voice_state.dart';
import '../settings/app_settings.dart';
import '../voice/voice_controller.dart';
import 'chat_models.dart';
import 'result_lines.dart';

/// Hooks into the rest of the app (navigation, settings, listening).
class ChatHooks {
  const ChatHooks({
    required this.updateSettings,
    this.openSettings,
    this.openMusic,
    this.openCamera,
    this.requestListen,
    this.wakeBackend,
  });
  final void Function(AppSettings Function(AppSettings) update) updateSettings;
  final VoidCallback? openSettings;
  final VoidCallback? openMusic;

  /// Opens the live camera screen ("7el camera", "chouf hadi").
  final VoidCallback? openCamera;

  /// Starts the mic flow (permission rationale etc.). Returns true if listening.
  final Future<bool> Function()? requestListen;

  /// Re-checks a sleeping backend with a long timeout (free hosting wakes in
  /// about a minute). When null, an unreachable server means offline at once.
  final Future<void> Function()? wakeBackend;
}

/// The single pipeline for typed AND spoken input:
/// (1) local command parser → (2) AI brain → offline presets when needed.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.backend,
    required this.settings,
    required this.net,
    required this.voice,
    required this.music,
    required this.memory,
    required this.companion,
    required this.log,
    required this.hooks,
    this.parser = const CommandParser(),
    this.detector = const EmotionDetector(),
    PersonalityResponses? responses,
    ConversationContext? context,
    DateTime Function()? clock,
  }) : responses = responses ?? PersonalityResponses(),
       context = context ?? ConversationContext(),
       _clock = clock ?? DateTime.now;

  final BackendClient backend;
  final AppSettings Function() settings;
  final NetState Function() net;
  final VoiceController voice;
  final MusicController music;
  final MemoryStore memory;
  final CompanionController companion;
  final ErrorLog log;
  ChatHooks hooks;
  final CommandParser parser;
  final EmotionDetector detector;
  final PersonalityResponses responses;
  final ConversationContext context;
  final DateTime Function() _clock;

  final List<ChatMessage> messages = [];
  bool busy = false;
  int _id = 0;
  bool _wasSpeaking = false;
  StreamSubscription<BrainEvent>? _brainSub;
  Completer<void>? _brainDone;
  ChatMessage? _brainMsg;
  int _brainGen = 0;

  /// Drops the in-flight AI request (new input, stop button, dispose).
  ///
  /// Cancelling a subscription does not fire onDone, so the waiting send()
  /// is released explicitly; the cancel itself is not awaited because the
  /// backend stream is an async* generator that may be blocked on the
  /// network. An empty "thinking" bubble is removed; streamed partial text
  /// is kept as-is (never completed or invented).
  void _abandonBrain() {
    _brainGen++;
    final sub = _brainSub;
    _brainSub = null;
    if (sub != null) unawaited(sub.cancel());
    final m = _brainMsg;
    _brainMsg = null;
    if (m != null && m.streaming) {
      if (m.text.isEmpty) {
        messages.remove(m);
      } else {
        m
          ..streaming = false
          ..phase = null;
      }
    }
    final d = _brainDone;
    _brainDone = null;
    if (d != null && !d.isCompleted) d.complete();
    if (busy) {
      busy = false;
      voice.setThinking(false);
    }
  }

  /// Stop button: cancels a pending AI request and any speech.
  Future<void> stop() async {
    _abandonBrain();
    notifyListeners();
    await voice.interrupt();
  }

  String _nextId() => '${++_id}';

  static final _rememberRe = RegExp(
    r'^(?:3[q9]el|aq[l]|3a9el|tfeker|tfkker|remember|retiens|souviens toi|n3qel|عقل|تفكر|تذكر)\s+(?:3la|3ela|bli|that|que|على|بلي|ان)?\s*(.+)$',
  );

  ChatMessage _sahbi(
    Line line,
    ChatKind kind, {
    List<ActionResult> results = const [],
  }) {
    final s = settings();
    return ChatMessage(
      id: _nextId(),
      role: ChatRole.sahbi,
      text: line.display(s.replyLanguage, latinDarija: s.latinDarija),
      ttsText: line.tts(s.replyLanguage),
      language: s.replyLanguage,
      kind: kind,
      results: results,
    );
  }

  Future<void> _say(
    ChatMessage m, {
    Emotion? emotion,
    double intensity = 0.6,
  }) async {
    messages.add(m);
    notifyListeners();
    if (emotion != null) companion.show(DetectedEmotion(emotion, intensity));
    await voice.speak(m.ttsText ?? m.text, language: m.language);
  }

  /// Typed or spoken input.
  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    companion.interact();
    _wasSpeaking = voice.state == VoiceState.speaking;
    await voice.interrupt(); // new input interrupts speech
    _abandonBrain();
    messages.add(
      ChatMessage(
        id: _nextId(),
        role: ChatRole.user,
        text: text,
        language: isArabicScript(text) ? 'ar' : 'latin',
        kind: ChatKind.ai,
      ),
    );
    notifyListeners();
    // Immediate reaction to the user's tone (rules, offline).
    final userTone = detector.detect(text);
    if (userTone.emotion != Emotion.neutral) {
      companion.show(userTone, hold: const Duration(seconds: 4));
    }

    // Memory: "3qel 3la ..." / "remember that ..."
    final rem = _rememberRe.firstMatch(normalizeText(text, collapse: false));
    if (rem != null) {
      final ok = await memory.addFact(rem.group(1)!);
      final r = ok
          ? const ActionResult.ok('Remembered')
          : const ActionResult.fail('memory_off');
      final line = resultLine(r);
      voice.setThinking(false);
      await _say(
        _sahbi(line, ChatKind.command, results: [r]),
        emotion: line.emotion,
      );
      return;
    }

    // (1) Local deterministic commands.
    final cmd = parser.parse(text);
    if (cmd != null) {
      final r = await execute(cmd);
      final line = resultLine(r);
      voice.setThinking(false);
      final m = _sahbi(line, ChatKind.command, results: [r]);
      // Don't talk over music we just started, or after "stop talking".
      final quiet =
          cmd.type == CommandType.stopSpeaking ||
          cmd.type == CommandType.listen ||
          (cmd.type == CommandType.stopGeneric &&
              r.message == 'Stopped talking') ||
          (cmd.type == CommandType.musicPlay &&
              r.ok &&
              r.message.startsWith('Playing'));
      if (quiet) {
        messages.add(m);
        notifyListeners();
        companion.show(DetectedEmotion(line.emotion, line.intensity));
      } else {
        await _say(m, emotion: line.emotion, intensity: line.intensity);
      }
      return;
    }

    // (2) AI brain or honest offline fallback.
    await _askBrain(text);
  }

  /// Speak an earlier Sahbi message again.
  Future<void> replay(ChatMessage m) async {
    if (m.role != ChatRole.sahbi || m.text.isEmpty) return;
    await voice.interrupt();
    await voice.speak(m.ttsText ?? m.text, language: m.language);
  }

  Future<void> retry(ChatMessage failed) async {
    final t = failed.retryText;
    if (t == null) return;
    messages.remove(failed);
    notifyListeners();
    await _askBrain(t);
  }

  String? _offlineReason() {
    final s = settings();
    final n = net();
    if (!s.sendToAi) return 'ai_disabled';
    if (!backend.hasBaseUrl) return 'backend_not_set';
    if (!n.hasNetwork) return 'no_internet';
    if (n.backendReachable != true) return 'server_unreachable';
    if (!n.aiConfigured) return 'ai_not_configured';
    return null;
  }

  Future<void> _offline(String text, String reason) async {
    final intent = responses.detectIntent(text);
    final line = intent != null
        ? responses.forIntent(intent, _clock(), robotName: settings().robotName)
        : responses.offlineFallback();
    final m = _sahbi(line, ChatKind.offline)..errorCode = reason;
    voice.setThinking(false);
    await _say(m, emotion: line.emotion, intensity: line.intensity);
  }

  /// Shows "waking the server…" while [ChatHooks.wakeBackend] runs.
  /// Returns the new offline reason ('' = online now), or null if the user
  /// sent something else or pressed stop meanwhile.
  Future<String?> _wakeBackend() async {
    busy = true;
    voice.setThinking(true);
    final m = ChatMessage(
      id: _nextId(),
      role: ChatRole.sahbi,
      text: '',
      language: settings().replyLanguage,
      kind: ChatKind.ai,
      streaming: true,
      phase: 'waking',
    );
    messages.add(m);
    notifyListeners();
    final released = Completer<void>();
    final gen = _brainGen;
    _brainDone = released;
    _brainMsg = m;
    await Future.any([hooks.wakeBackend!(), released.future]);
    if (gen != _brainGen) return null;
    _brainDone = null;
    _brainMsg = null;
    messages.remove(m);
    busy = false;
    notifyListeners();
    return _offlineReason() ?? '';
  }

  Map<String, dynamic> _request(String text) {
    final s = settings();
    final now = _clock();
    return {
      'message': text,
      'history': [for (final t in context.turns) t.toJson()],
      'summary': ?context.summary,
      'settings': {
        'reply_language': s.replyLanguage,
        'darija_script': s.darijaScript,
        'humor': s.humor,
        'formality': s.formality,
        if (s.userName.trim().isNotEmpty) 'user_name': s.userName.trim(),
        if (s.robotName.isNotEmpty) 'robot_name': s.robotName,
      },
      if (memory.consentFacts && memory.facts.isNotEmpty)
        'memory': {'facts': memory.factsForBrain()},
      'client': {
        'local_time': now.toIso8601String(),
        'app_state': music.playing
            ? 'music playing: ${music.snapshot.current?.title ?? ''}'
            : 'idle',
      },
    };
  }

  Future<void> _askBrain(String text) async {
    var reason = _offlineReason();
    if (reason == 'server_unreachable' && hooks.wakeBackend != null) {
      final woke = await _wakeBackend();
      if (woke == null) return; // superseded or stopped while waking
      reason = woke.isEmpty ? null : woke;
    }
    if (reason != null) {
      await _offline(text, reason);
      return;
    }
    busy = true;
    voice.setThinking(true);
    companion.show(
      const DetectedEmotion(Emotion.curious, 0.4),
      hold: const Duration(seconds: 30),
    );
    final m = ChatMessage(
      id: _nextId(),
      role: ChatRole.sahbi,
      text: '',
      language: settings().replyLanguage,
      kind: ChatKind.ai,
      streaming: true,
      phase: 'thinking',
    );
    messages.add(m);
    notifyListeners();
    final done = Completer<void>();
    final gen = _brainGen;
    _brainDone = done;
    _brainMsg = m;
    BrainReply? reply;
    _brainSub = backend
        .chat(_request(text))
        .listen(
          (e) {
            switch (e) {
              case BrainStatus(:final phase):
                m.phase = phase;
              case BrainDelta(text: final t):
                m.text += t;
              case BrainFinal(reply: final r):
                reply = r;
            }
            notifyListeners();
          },
          onError: (Object err) {
            final code = err is BackendException
                ? err.code
                : BackendErrorCode.server;
            log.add(
              'brain',
              err is BackendException
                  ? '${err.code.name}: ${err.message}'
                  : '$err',
            );
            m
              ..streaming = false
              ..kind = ChatKind.error
              ..errorCode = code.name
              ..retryText = text
              ..text = '';
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    await done.future;
    if (gen != _brainGen) return; // superseded or stopped
    _brainSub = null;
    _brainDone = null;
    _brainMsg = null;
    busy = false;
    final r = reply;
    if (r == null) {
      if (m.kind != ChatKind.error) {
        // Stream ended without a final reply: treat as server error.
        m
          ..streaming = false
          ..kind = ChatKind.error
          ..errorCode = BackendErrorCode.server.name
          ..retryText = text
          ..text = '';
      }
      voice.setError(m.errorCode ?? 'server');
      companion.show(const DetectedEmotion(Emotion.sad, 0.3));
      notifyListeners();
      return;
    }
    m
      ..text = r.displayText
      ..ttsText = r.ttsText
      ..language = r.language
      ..streaming = false
      ..phase = null
      ..sources = r.sources
      ..verification = r.verification
      ..searchUnavailable = r.searchUnavailable;
    final emo = detector.fromLlm(r.emotion.name, r.intensity);
    companion.show(emo);
    context
      ..add('user', text)
      ..add('assistant', r.displayText);
    unawaited(memory.addChat('user', text));
    unawaited(memory.addChat('assistant', r.displayText));
    notifyListeners();

    // Execute proposed actions and record their REAL results.
    final results = <ActionResult>[];
    for (final a in r.actions) {
      if (a.type == 'translate') {
        m.translation = (
          source: '${a.args['source_text'] ?? ''}',
          target: '${a.args['target_language'] ?? ''}',
          translation: '${a.args['translation'] ?? ''}',
        );
        continue;
      }
      final cmd = actionToCommand(a);
      if (cmd != null) results.add(await execute(cmd));
    }
    m.results = results;
    notifyListeners();
    final quietForMusic = results.any(
      (x) => x.ok && x.message.startsWith('Playing'),
    );
    if (!quietForMusic) {
      await voice.speak(r.ttsText, language: r.language);
    } else {
      voice.setThinking(false);
    }
    unawaited(_maybeSummarize());
  }

  Future<void> _maybeSummarize() async {
    if (!context.needsSummary) return;
    try {
      final s = await backend.summarize(context.summary, [
        for (final t in context.pendingForSummary) t.toJson(),
      ]);
      context.applySummary(s);
    } catch (e) {
      log.add('summary', '$e');
      context.dropPending();
    }
  }

  /// Maps a typed brain action to a local command (null = unsupported).
  static Command? actionToCommand(BrainAction a) {
    switch (a.type) {
      case 'music.play':
        final src = switch (a.args['source']) {
          'spotify' => MusicSource.spotify,
          'youtube_music' => MusicSource.youtubeMusic,
          'local' => MusicSource.local,
          _ => MusicSource.any,
        };
        final q = a.args['query'];
        return Command(
          CommandType.musicPlay,
          query: q is String && q.trim().isNotEmpty ? q.trim() : null,
          source: src,
        );
      case 'music.pause':
        return const Command(CommandType.musicPause);
      case 'music.resume':
        return const Command(CommandType.musicResume);
      case 'music.stop':
        return const Command(CommandType.musicStop);
      case 'music.next':
        return const Command(CommandType.musicNext);
      case 'music.previous':
        return const Command(CommandType.musicPrevious);
      case 'set_volume':
        final level = a.args['level'];
        final delta = a.args['delta'];
        if (level is num) {
          return Command(
            CommandType.volumeSet,
            value: (level * 100).round().clamp(0, 100),
          );
        }
        if (delta is num) {
          return Command(
            delta >= 0 ? CommandType.volumeUp : CommandType.volumeDown,
          );
        }
        return null;
      case 'set_reply_language':
        final l = a.args['language'];
        return l is String
            ? Command(CommandType.setReplyLanguage, language: l)
            : null;
    }
    return null;
  }

  /// Executes a command and returns what REALLY happened.
  Future<ActionResult> execute(Command c) async {
    try {
      switch (c.type) {
        case CommandType.musicPlay:
          switch (c.source) {
            case MusicSource.spotify:
              return await music.links.openSpotify(c.query);
            case MusicSource.youtubeMusic:
              return await music.links.openYouTubeMusic(c.query);
            case MusicSource.local || MusicSource.any:
              return await music.playQuery(c.query);
          }
        case CommandType.musicPause:
          return await music.pause();
        case CommandType.musicResume:
          return await music.resume();
        case CommandType.musicStop:
          return await music.stop();
        case CommandType.musicNext:
          return await music.next();
        case CommandType.musicPrevious:
          return await music.previous();
        case CommandType.volumeUp:
          return await music.volumeStep(1);
        case CommandType.volumeDown:
          return await music.volumeStep(-1);
        case CommandType.volumeSet:
          return await music.setVolume((c.value ?? 50) / 100);
        case CommandType.stopGeneric:
          if (_wasSpeaking) return const ActionResult.ok('Stopped talking');
          if (music.playing) return await music.stop();
          return const ActionResult.fail('nothing_to_stop');
        case CommandType.stopSpeaking:
          await voice.interrupt();
          return const ActionResult.ok('Stopped talking');
        case CommandType.listen:
          final ok = await (hooks.requestListen?.call() ?? Future.value(false));
          return ok
              ? const ActionResult.ok('Listening')
              : const ActionResult.fail('mic_unavailable');
        case CommandType.stopListening:
          await voice.stopListening();
          return const ActionResult.ok('Stopped listening');
        case CommandType.setReplyLanguage:
          final l = c.language ?? 'darija';
          hooks.updateSettings((s) => s.copyWith(replyLanguage: l));
          return const ActionResult.ok('Language changed');
        case CommandType.setDarijaScript:
          hooks.updateSettings(
            (s) => s.copyWith(
              darijaScript: c.language ?? 'arabic',
              replyLanguage: 'darija',
            ),
          );
          return const ActionResult.ok('Script changed');
        case CommandType.openSettings:
          hooks.openSettings?.call();
          return const ActionResult.ok('Opened settings');
        case CommandType.openMusic:
          hooks.openMusic?.call();
          return const ActionResult.ok('Opened music');
        case CommandType.openCamera:
          if (hooks.openCamera == null) {
            return const ActionResult.fail('camera unavailable');
          }
          hooks.openCamera!.call();
          return const ActionResult.ok('Opened camera');
      }
    } catch (e) {
      log.add('action', '${c.type.name}: $e');
      return ActionResult.fail('error: $e');
    }
  }

  /// "Wqef" while Sahbi talks: handled here before the parser so speech stops instantly.
  Future<void> interruptSpeech() => voice.interrupt();

  void clear() {
    messages.clear();
    context.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _brainGen++;
    unawaited(_brainSub?.cancel());
    final d = _brainDone;
    if (d != null && !d.isCompleted) d.complete();
    super.dispose();
  }
}
