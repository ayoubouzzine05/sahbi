import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/chat/chat_controller.dart';
import '../features/memory/memory_store.dart';
import '../features/music/music_controller.dart';
import '../features/music/music_models.dart';
import '../features/personality/companion_controller.dart';
import '../features/personality/voice_state.dart';
import '../features/robot_link/robot_link_controller.dart';
import '../features/settings/app_settings.dart';
import '../features/voice/cloud_stt.dart';
import '../features/voice/cloud_tts.dart';
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

final musicControllerProvider = ChangeNotifierProvider<MusicController>((ref) {
  return MusicController(
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

final companionProvider = ChangeNotifierProvider<CompanionController>((ref) {
  final c = CompanionController(
    busy: () {
      final v = ref.read(voiceControllerProvider);
      return v.state == VoiceState.listening ||
          v.state == VoiceState.speaking ||
          ref.read(musicControllerProvider).playing;
    },
  );
  c.idle.enabled = ref.read(settingsProvider).idleEnabled;
  ref.listen(settingsProvider, (_, s) => c.idle.enabled = s.idleEnabled);
  c.start();
  return c;
});

final chatControllerProvider = ChangeNotifierProvider<ChatController>((ref) {
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
final wakeNameProvider = ChangeNotifierProvider<WakeNameController>((ref) {
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
      await voice.startListening();
    },
    onCommand: (text) => ref.read(chatControllerProvider).send(text),
    localeFor: (lang) async =>
        pickLocale(await stt.supportedLocales(), lang) ?? 'ar-MA',
    log: ref.read(errorLogProvider),
  );
  voice.beforeListen = w.yieldMic;
  void onVoice() => w.refresh();
  voice.addListener(onVoice);
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
