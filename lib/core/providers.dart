import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:material_ui/material_ui.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/chat/chat_controller.dart';
import '../features/memory/memory_store.dart';
import '../features/music/music_controller.dart';
import '../features/music/youtube_controller.dart';
import '../features/music/music_models.dart';
import '../features/personality/companion_controller.dart';
import '../features/personality/companion_lines.dart';
import '../features/personality/idle_behavior.dart';
import '../features/personality/shake.dart';
import '../features/personality/voice_state.dart';
import '../features/robot_link/robot_link_controller.dart';
import '../features/settings/app_settings.dart';
import '../features/voice/cloud_stt.dart';
import '../features/voice/cloud_tts.dart';
import '../features/voice/conversation_session.dart';
import '../features/voice/device_stt.dart';
import '../features/voice/device_tts.dart';
import '../features/voice/mic_permission.dart';
import '../features/voice/voice_controller.dart';
import '../features/voice/voice_types.dart';
import '../features/voice/wake_name.dart';
import 'backend_client.dart';
import 'connectivity.dart';
import 'error_log.dart';
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
  AppSettings build() => AppSettings.decode(
    ref.read(sharedPrefsProvider).getString('settings_v1'),
  );

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
final deviceTtsProvider = Provider<TtsProvider>(
  (ref) => DeviceTts(
    voiceName: () => ref.read(settingsProvider).deviceVoiceName,
    gender: () => ref.read(settingsProvider).voiceGender,
    rate: () => ref.read(settingsProvider).speechRate,
    pitch: () => ref.read(settingsProvider).pitch,
  ),
);
final cloudTtsProvider = Provider<TtsProvider>(
  (ref) => CloudTts(
    ref.read(backendClientProvider),
    isConfigured: () => ref.read(connectivityProvider).value.cloudTtsConfigured,
    voice: () => ref.read(settingsProvider).cloudVoice,
    gender: () => ref.read(settingsProvider).voiceGender,
    rate: () => ref.read(settingsProvider).speechRate,
    pitch: () => ref.read(settingsProvider).pitch,
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
    cloudTtsReady: () =>
        ref.read(connectivityProvider).value.cloudTtsConfigured,
    log: ref.read(errorLogProvider),
    onDuckMusic: music.duck,
  );
});

final ChangeNotifierProvider<CompanionController> companionProvider =
    ChangeNotifierProvider<CompanionController>((ref) {
      final c = CompanionController(
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
        ),
      );
      ref.read(voiceControllerProvider).onFinalText = chat.send;
      return chat;
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
        localeFor: (lang) async =>
            pickLocale(await stt.supportedLocales(), lang) ?? 'ar-MA',
        log: ref.read(errorLogProvider),
      );
      voice.beforeListen = w.yieldMic;
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
        if (a?.wakeByName != b.wakeByName || a?.robotName != b.robotName) {
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
        blocked: () => wake().externallyBlocked,
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
  companion.onIdleAction = (a) async {
    switch (a) {
      case IdleAction.chatter:
        if (!calm()) return;
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
