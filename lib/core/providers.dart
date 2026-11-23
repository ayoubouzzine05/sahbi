import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:material_ui/material_ui.dart'
    show AppLifecycleListener, AppLifecycleState, Locale, WidgetsBinding;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/chat/chat_controller.dart';
import '../features/memory/memory_store.dart';
import '../features/music/music_controller.dart';
import '../features/music/youtube_controller.dart';
import '../features/music/music_models.dart';
import '../features/behavior/behavior_models.dart';
import '../features/behavior/initiative_scheduler.dart';
import '../features/behavior/mimo_behavior_engine.dart';
import '../features/games/game_session.dart';
import '../features/personality/companion_controller.dart';
import '../features/personality/companion_lines.dart';
import '../features/personality/idle_behavior.dart';
import '../features/personality/shake.dart';
import '../features/personality/voice_state.dart';
import '../features/robot_link/robot_link_controller.dart';
import '../features/personality/emotion.dart';
import '../features/settings/app_settings.dart';
import '../features/vision/robot_eyes.dart';
import '../features/vision/vision_controller.dart';
import '../features/voice/mimo_wake.dart';
import '../features/voice/wake_model_manager.dart';
import '../features/voice/wake_word_engine.dart';
import '../l10n/app_localizations.dart';
import '../features/voice/cloud_stt.dart';
import '../features/voice/cloud_tts.dart';
import '../features/voice/conversation_session.dart';
import '../features/voice/device_stt.dart';
import '../features/voice/device_tts.dart';
import '../features/voice/live_voice_tts.dart';
import '../features/voice/mic_permission.dart';
import '../features/voice/voice_controller.dart';
import '../features/voice/voice_types.dart';
import '../features/voice/wake_name.dart';
import 'backend_client.dart';
import 'connectivity.dart';
import 'error_log.dart';
import 'hardware_guard.dart';
import 'platform_bridge.dart';

/// Must be overridden in main() / tests.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPrefsProvider'),
);
final musicEngineProvider = Provider<MusicEngine>(
  (ref) => throw UnimplementedError('override musicEngineProvider'),
);

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => SecureKeyValueStore(),
);
final blobStorageProvider = Provider<BlobStorage>((ref) => FileBlobStorage());
final platformBridgeProvider = Provider<PlatformBridge>(
  (ref) => const PlatformBridge(),
);
final micPermissionProvider = Provider<MicPermission>(
  (ref) => const PluginMicPermission(),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.read(sharedPrefsProvider);
    final s = AppSettings.decode(prefs.getString('settings_v1'));
    if (s.mimoMigrated) return s;
    // SAHBI → MIMO (once): the old default name becomes MIMO; a name the
    // user chose (and all memory / settings) is kept.
    final m = migrateToMimo(s);
    prefs.setString('settings_v1', m.encode());
    return m;
  }

  void update(AppSettings Function(AppSettings) f) {
    state = f(state);
    ref.read(sharedPrefsProvider).setString('settings_v1', state.encode());
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

final errorLogProvider = ChangeNotifierProvider<ErrorLog>((ref) => ErrorLog());

final backendClientProvider = Provider<BackendClient>((ref) {
  return BackendClient(
    baseUrl: () => ref.read(settingsProvider).backendUrl,
    store: ref.read(keyValueStoreProvider),
  );
});

final connectivityProvider = ChangeNotifierProvider<ConnectivityMonitor>((ref) {
  final m = ConnectivityMonitor(ref.read(backendClientProvider));
  m.start();
  return m;
});

final youtubeControllerProvider = ChangeNotifierProvider<YoutubeController>((
  ref,
) {
  final backend = ref.read(backendClientProvider);
  return YoutubeController(search: backend.youtubeSearch);
});

final musicControllerProvider = ChangeNotifierProvider<MusicController>((ref) {
  return MusicController(
    youtube: ref.read(youtubeControllerProvider),
    engine: ref.read(musicEngineProvider),
    bridge: ref.read(platformBridgeProvider),
    prefs: ref.read(sharedPrefsProvider),
  );
});

final memoryStoreProvider = ChangeNotifierProvider<MemoryStore>((ref) {
  final s = MemoryStore(
    keyStore: ref.read(keyValueStoreProvider),
    blob: ref.read(blobStorageProvider),
  );
  s.load();
  return s;
});

final deviceSttProvider = Provider<SttProvider>((ref) => DeviceStt());
final cloudSttProvider = Provider<SttProvider>(
  (ref) => CloudStt(
    ref.read(backendClientProvider),
    isConfigured: () => ref.read(connectivityProvider).value.cloudSttConfigured,
  ),
);

/// SAHBI always speaks with ONE male Casablanca voice (Follow-up 9: never
/// female, never switching). The old gender setting is ignored on purpose.
const sahbiVoiceGender = 'male';

final deviceTtsProvider = Provider<TtsProvider>(
  (ref) => DeviceTts(
    voiceName: () => ref.read(settingsProvider).deviceVoiceName,
    gender: () => sahbiVoiceGender,
    rate: () => ref.read(settingsProvider).speechRate,
    pitch: () => ref.read(settingsProvider).pitch,
  ),
);

/// Backend `/v1/tts` (Gemini TTS, same prebuilt voice): fallback only.
final backendTtsProvider = Provider<TtsProvider>(
  (ref) => CloudTts(
    ref.read(backendClientProvider),
    isConfigured: () => ref.read(connectivityProvider).value.cloudTtsConfigured,
    voice: () => ref.read(settingsProvider).cloudVoice,
    gender: () => sahbiVoiceGender,
    rate: () => ref.read(settingsProvider).speechRate,
    pitch: () => ref.read(settingsProvider).pitch,
  ),
);

/// SAHBI's voice: the Gemini Live voice-actor session (light Casablanca
/// style the user picked), streamed. Unlimited daily use is NOT VERIFIED.
final liveVoiceTtsProvider = Provider<LiveVoiceTts>((ref) {
  final t = LiveVoiceTts(
    isConfigured: () => ref.read(connectivityProvider).value.liveConfigured,
    token: () {
      final s = ref.read(settingsProvider);
      return ref
          .read(backendClientProvider)
          .liveToken(
            gender: sahbiVoiceGender,
            replyLanguage: s.replyLanguage,
            mode: 'voice',
          );
    },
  );
  ref.onDispose(() => unawaited(t.close()));
  return t;
});

/// Live voice first; the backend TTS only for a sentence the live voice
/// could not start (then the live voice is retried after a minute).
final cloudTtsProvider = Provider<TtsProvider>(
  (ref) => FallbackTts(
    ref.read(liveVoiceTtsProvider),
    ref.read(backendTtsProvider),
    onPrimaryFailure: (m) => ref.read(errorLogProvider).add('tts.live', m),
  ),
);

final voiceControllerProvider = ChangeNotifierProvider<VoiceController>((ref) {
  final music = ref.read(musicControllerProvider);
  return VoiceController(
    deviceStt: ref.read(deviceSttProvider),
    cloudStt: ref.read(cloudSttProvider),
    deviceTts: ref.read(deviceTtsProvider),
    cloudTts: ref.read(cloudTtsProvider),
    settings: () => ref.read(settingsProvider),
    cloudSttReady: () =>
        ref.read(connectivityProvider).value.cloudSttConfigured,
    cloudTtsReady: () {
      final n = ref.read(connectivityProvider).value;
      return n.liveConfigured || n.cloudTtsConfigured;
    },
    log: ref.read(errorLogProvider),
    onDuckMusic: music.duck,
  );
});

final ChangeNotifierProvider<CompanionController> companionProvider =
    ChangeNotifierProvider<CompanionController>((ref) {
      final c = CompanionController(
        behavior: MimoBehaviorEngine(
          scheduler: InitiativeScheduler(
            isQuiet: (h) => ref.read(settingsProvider).isQuietHour(h),
          ),
        ),
        // The user is busy with the robot (or music). The robot's own talking
        // (a joke while the user is quiet) and the short listen after it are
        // not: otherwise it would never notice it is being ignored.
        busy: () {
          final v = ref.read(voiceControllerProvider);
          final robotTalking = ref.read(chatControllerProvider).robotTalking;
          final robotListening = ref.read(conversationProvider).robotInitiated;
          return (v.state == VoiceState.listening && !robotListening) ||
              (v.state == VoiceState.speaking && !robotTalking) ||
              ref.read(musicControllerProvider).playing;
        },
      );
      c.idle.enabled = ref.read(settingsProvider).idleEnabled;
      c.idle.chatterEnabled = ref.read(settingsProvider).proactiveTalk;
      ref.listen(settingsProvider, (_, s) {
        c.idle.enabled = s.idleEnabled;
        c.idle.chatterEnabled = s.proactiveTalk;
      });
      c.start();
      return c;
    });

final ChangeNotifierProvider<ChatController> chatControllerProvider =
    ChangeNotifierProvider<ChatController>((ref) {
      final chat = ChatController(
        backend: ref.read(backendClientProvider),
        settings: () => ref.read(settingsProvider),
        net: () => ref.read(connectivityProvider).value,
        voice: ref.read(voiceControllerProvider),
        music: ref.read(musicControllerProvider),
        memory: ref.read(memoryStoreProvider),
        companion: ref.read(companionProvider),
        log: ref.read(errorLogProvider),
        hooks: ChatHooks(
          updateSettings: (f) => ref.read(settingsProvider.notifier).update(f),
          wakeBackend: () => ref.read(connectivityProvider).wake(),
          currentView: () => ref.read(robotEyesProvider).latestFrame(),
          userSpoke: () => ref.read(robotEyesProvider).userSpoke(),
          lookAround: () => ref.read(robotEyesProvider).inspect(),
          game: (t) => ref.read(gameProvider).answer(t),
          startGame: (t) {
            final g = ref.read(gameProvider);
            return g.start(g.kindFor(t));
          },
        ),
      );
      ref.read(voiceControllerProvider).onFinalText = chat.send;
      return chat;
    });

/// The robot's eyes: the front camera on the face screen. Eyes follow
/// movement; when it is shown something new it may react out loud (the AI
/// decides, `/v1/vision/react`). Frames stay in memory.
final ChangeNotifierProvider<RobotEyes> robotEyesProvider =
    ChangeNotifierProvider<RobotEyes>((ref) {
      final recent = <String>[];
      bool busy() {
        final voice = ref.read(voiceControllerProvider);
        final c = ref.read(companionProvider);
        return voice.state != VoiceState.idle ||
            ref.read(musicControllerProvider).playing ||
            ref.read(chatControllerProvider).robotTalking ||
            c.acting ||
            c.dizzy ||
            c.idle.asleep;
      }

      final vision = ref.read(visionProvider);
      final eyes = RobotEyes(
        camera: VisionEyeCamera(vision),
        busy: busy,
        onGaze: (g) => ref.read(companionProvider).glance(g),
        onReact: (jpeg) async {
          final s = ref.read(settingsProvider);
          final net = ref.read(connectivityProvider).value;
          if (!s.sendToAi || !net.hasNetwork) return;
          final c = ref.read(companionProvider);
          final r = await ref
              .read(backendClientProvider)
              .react(
                image: jpeg,
                replyLanguage: s.replyLanguage,
                darijaScript: s.darijaScript,
                robotName: s.robotName.isEmpty ? null : s.robotName,
                userName: s.userName.trim().isEmpty ? null : s.userName.trim(),
                recent: recent,
                mood: c.temper.mood,
              );
          final text = r['display_text'];
          if (r['react'] != true || text is! String || text.isEmpty) return;
          // The user may have started talking meanwhile: their turn first.
          if (busy()) return;
          final subject = r['subject_en'];
          if (subject is String && subject.isNotEmpty) {
            recent.add(subject);
            if (recent.length > 6) recent.removeAt(0);
          }
          final act = reactionAct(r['reaction']);
          if (act != null) {
            c.play(act);
            c.temper.played(act);
          }
          final tts = r['tts_text'];
          final i = r['intensity'];
          await ref
              .read(chatControllerProvider)
              .sayFromEyes(
                text: text,
                tts: tts is String && tts.isNotEmpty ? tts : null,
                emotion: Emotion.values.asNameMap()[r['emotion']],
                intensity: i is num ? i.toDouble().clamp(0, 1) : 0.7,
              );
        },
      );
      // Lifecycle (background = camera closed) comes from HardwareGuard.
      // The camera became free again (live screen closed, toggle on).
      void onVision() {
        if (vision.allowed && !vision.isOpen) eyes.retry();
      }

      vision.addListener(onVision);
      // A hot phone or battery saver rests the camera (checked each minute).
      final heat = Timer.periodic(const Duration(minutes: 1), (_) async {
        final t = await readThermal();
        eyes.setHot(t.cameraShouldRest);
      });
      ref.onDispose(() {
        heat.cancel();
        vision.removeListener(onVision);
      });
      return eyes;
    });

/// Wake-by-name: listens for the robot's name while the app is open.
final ChangeNotifierProvider<WakeNameController> wakeNameProvider =
    ChangeNotifierProvider<WakeNameController>((ref) {
      final voice = ref.read(voiceControllerProvider);
      final stt = ref.read(deviceSttProvider);
      final w = WakeNameController(
        listen: (locale) => stt is DeviceStt
            ? stt.listenForWake(localeId: locale)
            : stt.listen(localeId: locale),
        cancel: stt.cancel,
        settings: () => ref.read(settingsProvider),
        voiceState: () => voice.state,
        micGranted: () async =>
            await ref.read(micPermissionProvider).status() == MicStatus.granted,
        onWake: () async {
          ref.read(companionProvider).interact();
          // Stay in the conversation until "safi sir".
          ref.read(conversationProvider).start();
          await voice.startListening();
        },
        onCommand: (text) {
          ref.read(companionProvider).interact();
          final convo = ref.read(conversationProvider)..start();
          final name = ref.read(settingsProvider).robotName;
          if (convo.handleFinalText(text, robotName: name)) return;
          unawaited(ref.read(chatControllerProvider).send(text));
        },
        musicPlaying: () => ref.read(musicControllerProvider).playing,
        replacedBy: () => ref.read(mimoWakeProvider).available,
        localeFor: (lang) async =>
            pickLocale(await stt.supportedLocales(), lang) ?? 'ar-MA',
        log: ref.read(errorLogProvider),
      );
      // Before the conversation recogniser opens the mic, both wake
      // listeners let go of it.
      voice.beforeListen = () async {
        await w.yieldMic();
        await ref.read(mimoWakeProvider).yieldMic();
      };
      void onVoice() => w.refresh();
      voice.addListener(onVoice);
      // Music on/off changes whether the name is listened for.
      final music = ref.read(musicControllerProvider);
      var wasPlaying = music.playing;
      void onMusic() {
        if (music.playing == wasPlaying) return;
        wasPlaying = music.playing;
        w.refresh();
      }

      music.addListener(onMusic);
      ref.onDispose(() => music.removeListener(onMusic));
      // A YouTube song paused by Android waits until the mic is free.
      ref.read(youtubeControllerProvider).canAutoResume = () =>
          voice.state != VoiceState.listening && !w.active;
      ref.listen(settingsProvider, (a, b) {
        if (a?.wakeByName != b.wakeByName ||
            a?.robotName != b.robotName ||
            a?.micEnabled != b.micEnabled) {
          w.refresh();
        }
      });
      ref.onDispose(() => voice.removeListener(onVoice));
      w.refresh();
      return w;
    });

final robotLinkProvider = ChangeNotifierProvider<RobotLinkController>(
  (ref) => RobotLinkController(companion: ref.read(companionProvider)),
);

/// Conversation after the name: the mic reopens after each answer until the
/// user says "safi sir" (or stays silent, or music starts).
final ChangeNotifierProvider<ConversationSession> conversationProvider =
    ChangeNotifierProvider<ConversationSession>((ref) {
      final voice = ref.read(voiceControllerProvider);
      final chat = ref.read(chatControllerProvider);
      final music = ref.read(musicControllerProvider);
      WakeNameController wake() => ref.read(wakeNameProvider);
      final c = ConversationSession(
        voiceState: () => voice.state,
        voiceChanges: voice,
        listen: () async {
          if (await ref.read(micPermissionProvider).status() !=
              MicStatus.granted) {
            return;
          }
          await voice.startListening();
        },
        chatBusy: () => chat.busy,
        musicPlaying: () => music.playing,
        // Only another screen with its own mic ends it (the app being
        // minimised does not: "MIMO" works in the background too).
        blocked: () => wake().suspendedByScreen,
        silenceTimeout: () =>
            Duration(seconds: ref.read(settingsProvider).silenceTimeoutSec),
        onActiveChanged: (on) => wake().setConversation(on),
        onGoodbye: () => chat.sayLocal(CompanionLines.goodbye),
      );
      // Every spoken sentence passes the goodbye check first.
      voice.onFinalText = (text) {
        if (c.handleFinalText(
          text,
          robotName: ref.read(settingsProvider).robotName,
        )) {
          return;
        }
        unawaited(chat.send(text));
      };
      return c;
    });

/// Offline mini-games: riddles, 3-choice quiz, reaction tap game.
final ChangeNotifierProvider<GameSession> gameProvider =
    ChangeNotifierProvider<GameSession>((ref) => GameSession());

/// The robot's own initiative: it talks when the user is quiet and falls
/// asleep after 10 minutes of being ignored (see [IdleBehavior]).
final proactiveProvider = Provider<void>((ref) {
  final companion = ref.read(companionProvider);
  final chat = ref.read(chatControllerProvider);
  final voice = ref.read(voiceControllerProvider);
  final music = ref.read(musicControllerProvider);
  final convo = ref.read(conversationProvider);
  final wake = ref.read(wakeNameProvider);
  bool calm() =>
      wake.foreground &&
      !wake.externallyBlocked &&
      voice.state == VoiceState.idle &&
      !chat.busy &&
      !music.playing &&
      !convo.active;
  final behavior = companion.behavior;
  // The autonomous loop may only start something when nothing else is
  // going on and the user allows MIMO to talk by itself.
  behavior.canAct = () => calm() && ref.read(settingsProvider).proactiveTalk;

  Future<void> remark() async {
    final spoke = await chat.proactive();
    // Give the user a moment to answer without calling the name.
    if (spoke &&
        ref.read(settingsProvider).wakeByName &&
        voice.state == VoiceState.idle &&
        !music.playing) {
      convo.start(robotInitiated: true, listenNow: true);
    }
  }

  final games = ref.read(gameProvider);

  Future<void> play(GameKind kind) async {
    final line = games.start(kind);
    await chat.sayLocal(line, robotInitiated: true);
    // Riddles / questions: listen for the answer without the name.
    if (kind != GameKind.reaction &&
        games.awaitingAnswer &&
        ref.read(settingsProvider).wakeByName &&
        voice.state == VoiceState.idle &&
        !music.playing) {
      convo.start(robotInitiated: true, listenNow: true);
    }
  }

  companion.onInitiative = (kind) {
    if (!calm() || games.active) return;
    switch (kind) {
      case InitiativeKind.remark:
        unawaited(remark());
      case InitiativeKind.riddle:
        unawaited(play(GameKind.riddle));
      case InitiativeKind.trivia:
        unawaited(play(GameKind.trivia));
      case InitiativeKind.reaction:
        unawaited(play(GameKind.reaction));
    }
  };

  // Reaction game result: said out loud (offline line).
  games.onReactionResult = (line) =>
      unawaited(chat.sayLocal(line, robotInitiated: true));

  var wasGame = games.active;
  void onGame() {
    final a = games.active;
    if (a == wasGame) return;
    wasGame = a;
    companion.behave(a ? BehaviorEvent.gameStart : BehaviorEvent.gameEnd);
  }

  games.addListener(onGame);

  // Conversation / listening drive the "listening" mood.
  var wasConvo = convo.active;
  void onConvo() {
    if (convo.active == wasConvo) return;
    wasConvo = convo.active;
    // The spoken game ends with the conversation ("safi sir", silence).
    if (!convo.active && games.awaitingAnswer) games.stop();
    companion.behave(
      convo.active
          ? BehaviorEvent.conversationStart
          : BehaviorEvent.conversationEnd,
    );
  }

  var wasListening = voice.state == VoiceState.listening;
  void onVoice() {
    final l = voice.state == VoiceState.listening;
    if (l == wasListening) return;
    wasListening = l;
    companion.behave(l ? BehaviorEvent.listenStart : BehaviorEvent.listenEnd);
  }

  convo.addListener(onConvo);
  voice.addListener(onVoice);
  ref.onDispose(() {
    convo.removeListener(onConvo);
    voice.removeListener(onVoice);
    games.removeListener(onGame);
    games.onReactionResult = null;
    companion.onInitiative = null;
    behavior.canAct = () => false;
  });

  companion.onIdleAction = (a) async {
    switch (a) {
      case IdleAction.chatter:
        // Same limits as the autonomous loop (cooldown, quiet hours).
        if (!calm() || !behavior.scheduler.canSpeak()) return;
        behavior.scheduler.record();
        final spoke = await chat.proactive();
        // Give the user a moment to answer without calling the name.
        if (spoke &&
            ref.read(settingsProvider).wakeByName &&
            voice.state == VoiceState.idle &&
            !music.playing) {
          convo.start(robotInitiated: true, listenNow: true);
        }
      case IdleAction.fallAsleep:
        if (!calm()) return;
        await chat.sayLocal(
          CompanionLines.goodnight,
          robotInitiated: true,
          showEmotion: false,
        );
      case IdleAction.none ||
          IdleAction.lookAround ||
          IdleAction.yawn ||
          IdleAction.wakeUp:
        break;
    }
  };
  ref.onDispose(() => companion.onIdleAction = null);
});

/// Shake the phone: the robot gets dizzy, then annoyed (pre-written lines,
/// no AI request). The accelerometer is only read while the app is open.
final shakeProvider = Provider<ShakeWatcher>((ref) {
  final companion = ref.read(companionProvider);
  final chat = ref.read(chatControllerProvider);
  final voice = ref.read(voiceControllerProvider);
  final wake = ref.read(wakeNameProvider);
  final mood = ShakeMood();
  final w = ShakeWatcher(
    events: () =>
        accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
            .map((e) => (e.x, e.y, e.z)),
    // Not in the live camera (moving the phone is normal there).
    enabled: () =>
        ref.read(settingsProvider).shakeReaction && !wake.externallyBlocked,
    onShake: () async {
      final r = mood.onShake(asleep: companion.idle.asleep);
      companion
        ..interact()
        ..makeDizzy(r.dizzyFor);
      final wasSulking = companion.temper.sulking;
      companion.temper.shaken();
      if (!wasSulking && companion.temper.sulking) companion.startSulkFace();
      await voice.interrupt();
      await chat.sayLocal(r.line, robotInitiated: true);
    },
  );
  final life = AppLifecycleListener(
    onStateChange: (s) => w.setActive(s == AppLifecycleState.resumed),
  );
  final now = WidgetsBinding.instance.lifecycleState;
  w.setActive(now == null || now == AppLifecycleState.resumed);
  ref.onDispose(() {
    life.dispose();
    w.stop();
  });
  return w;
});

/// The single owner of the camera (front eyes, back look, live screen).
final ChangeNotifierProvider<VisionController> visionProvider =
    ChangeNotifierProvider<VisionController>((ref) {
      final v = VisionController(
        enabled: () => ref.read(settingsProvider).cameraEnabled,
      );
      ref.listen(settingsProvider, (a, b) {
        if (a?.robotEyes != b.robotEyes) v.refresh();
      });
      return v;
    });

/// Native offline wake-word engine (overridden in tests).
final wakeEngineProvider = Provider<WakeWordEngine>(
  (ref) => NativeWakeEngine(),
);

/// The offline "MIMO" model (downloaded once).
final ChangeNotifierProvider<WakeModelManager> wakeModelProvider =
    ChangeNotifierProvider<WakeModelManager>((ref) => WakeModelManager());

/// "Na3am?" / "Ana hna!" clips in MIMO's voice, cached on the phone.
final ackClipsProvider = Provider<AckClips>((ref) {
  final a = AckClips(
    synthesize: (text) => ref
        .read(backendClientProvider)
        .synthesize(text: text, language: 'ar-MA', gender: sahbiVoiceGender),
  );
  ref.onDispose(() => unawaited(a.stop()));
  return a;
});

L10n _l10nFor(AppSettings s) {
  try {
    return lookupL10n(Locale(s.uiLocale));
  } catch (_) {
    return lookupL10n(const Locale('en'));
  }
}

/// Offline "MIMO" wake word (foreground service while the mic is on).
final ChangeNotifierProvider<MimoWakeController> mimoWakeProvider =
    ChangeNotifierProvider<MimoWakeController>((ref) {
      final voice = ref.read(voiceControllerProvider);
      final own = RegExp(r'mimo|ميمو|mimou', caseSensitive: false);
      final m = MimoWakeController(
        engine: ref.read(wakeEngineProvider),
        models: ref.read(wakeModelProvider),
        settings: () => ref.read(settingsProvider),
        micGranted: () async =>
            await ref.read(micPermissionProvider).status() == MicStatus.granted,
        notice: () {
          final l = _l10nFor(ref.read(settingsProvider));
          return WakeNotice(
            title: l.wakeNoticeTitle,
            text: l.wakeNoticeText,
            stopLabel: l.wakeNoticeStop,
            openLabel: l.wakeNoticeOpen,
            channelName: l.wakeChannelName,
          );
        },
        onWake: () => ref.read(wakeResponderProvider)(),
        onUserStopped: () => ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(micEnabled: false)),
        isOwnSpeech: () =>
            voice.state == VoiceState.speaking &&
            own.hasMatch(voice.speakingText),
        ensureNotifications: () async {
          try {
            if (await Permission.notification.isDenied) {
              await Permission.notification.request();
            }
          } catch (_) {
            // No plugin (tests): the service still shows its notification
            // where Android allows it.
          }
        },
        log: ref.read(errorLogProvider),
      );
      m.init();
      // The conversation recogniser finished: the wake word listens again
      // (also while MIMO talks, so "MIMO" can interrupt it).
      void onVoice() {
        if (voice.state != VoiceState.listening) m.setMicBusy(false);
      }

      voice.addListener(onVoice);
      ref.listen(settingsProvider, (a, b) {
        if (a?.micEnabled != b.micEnabled || a?.wakeByName != b.wakeByName) {
          m.refresh();
        }
      });
      ref.onDispose(() => voice.removeListener(onVoice));
      return m;
    });

/// What happens when "MIMO" is heard: interrupt (barge-in), eyes snap to
/// the user, a short "Na3am?", then the mic opens for the sentence.
final wakeResponderProvider = Provider<Future<void> Function()>((ref) {
  var busy = false;
  return () async {
    if (busy) return;
    final voice = ref.read(voiceControllerProvider);
    if (voice.state == VoiceState.listening) return;
    busy = true;
    try {
      final companion = ref.read(companionProvider);
      if (voice.state == VoiceState.speaking) await voice.interrupt();
      ref.read(robotEyesProvider).noteSomeone();
      companion.heardName();
      final said = await ref.read(ackClipsProvider).play();
      if (said == null) {
        // No clip yet (first run / offline): the eyes answered; make the
        // clips quietly for next time.
        unawaited(ref.read(ackClipsProvider).prepare());
      }
      if (!ref.read(settingsProvider).micEnabled) return;
      ref.read(conversationProvider).start();
      await voice.startListening();
    } finally {
      busy = false;
    }
  };
});

/// Every "release the hardware" path (see [HardwareGuard]).
final hardwareGuardProvider = Provider<HardwareGuard>((ref) {
  final g = HardwareGuard(
    HardwareActions(
      setCameraForeground: (v) {
        ref.read(visionProvider).setForeground(v);
        ref.read(robotEyesProvider).setForeground(v);
      },
      closeCamera: () => ref.read(visionProvider).releaseAll(),
      setMicForeground: (v) {
        ref.read(wakeNameProvider).setForeground(v);
        ref.read(mimoWakeProvider).setForeground(v);
      },
      stopMic: () async {
        ref.read(conversationProvider).end();
        await ref.read(voiceControllerProvider).cancelListening();
        ref.read(wakeNameProvider).refresh();
        await ref.read(mimoWakeProvider).stop();
      },
      stopBackgroundListening: () => ref.read(wakeEngineProvider).stop(),
      micEnabled: () => ref.read(settingsProvider).micEnabled,
      onError: (w, e) => ref.read(errorLogProvider).add('hardware.$w', '$e'),
    ),
  );
  ref.listen(settingsProvider, (a, b) {
    if (a?.micEnabled != b.micEnabled) unawaited(g.onMicToggle(b.micEnabled));
    if (a?.robotEyes != b.robotEyes) unawaited(g.onCameraToggle(b.robotEyes));
  });
  return g;
});
