import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import '../voice/mic_permission.dart';
import '../voice/voice_types.dart';
import '../voice/wake_model_manager.dart';
import 'app_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Created in initState (not lazily): the backend field is usually hidden,
  // and a lazy controller would first be built in dispose(), after `ref` is
  // no longer usable.
  late final TextEditingController _url;
  late final TextEditingController _name;
  late final TextEditingController _robot;
  List<TtsVoice>? _voices;
  int _versionTaps = 0;

  /// The technical part (backend address, service checks, debug) is hidden;
  /// 7 taps on the version show it until the screen is left.
  bool _showTech = false;

  @override
  void initState() {
    super.initState();
    final st = ref.read(settingsProvider);
    _url = TextEditingController(text: st.backendUrl);
    _name = TextEditingController(text: st.userName);
    _robot = TextEditingController(text: st.robotName);
    ref
        .read(deviceTtsProvider)
        .voices()
        .then((v) {
          if (mounted) setState(() => _voices = v);
        })
        .catchError((_) {
          if (mounted) setState(() => _voices = const []);
        });
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _robot.dispose();
    super.dispose();
  }

  void _set(AppSettings Function(AppSettings) f) =>
      ref.read(settingsProvider.notifier).update(f);

  /// Wake-by-name needs the mic permission; ask before switching it on.
  Future<void> _setWakeByName(bool on) async {
    if (!on) {
      _set((x) => x.copyWith(wakeByName: false));
      return;
    }
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final perm = ref.read(micPermissionProvider);
    var st = await perm.status();
    if (st != MicStatus.granted && st != MicStatus.permanentlyDenied) {
      st = await perm.request();
    }
    if (st == MicStatus.granted) {
      _set((x) => x.copyWith(wakeByName: true));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l.wakeByNameNoMic)));
    }
  }

  /// Master microphone toggle (asks for the permission when switched on).
  Future<void> _setMic(bool on) async {
    if (!on) {
      _set((x) => x.copyWith(micEnabled: false));
      return;
    }
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final perm = ref.read(micPermissionProvider);
    var st = await perm.status();
    if (st != MicStatus.granted && st != MicStatus.permanentlyDenied) {
      st = await perm.request();
    }
    if (st == MicStatus.granted) {
      _set((x) => x.copyWith(micEnabled: true));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l.wakeByNameNoMic)));
    }
  }

  String _hour(int h) => '${h.toString().padLeft(2, '0')}:00';

  Widget _hourPicker(int value, ValueChanged<int> onChanged) =>
      DropdownButton<int>(
        value: value,
        items: [
          for (var h = 0; h < 24; h++)
            DropdownMenuItem(value: h, child: Text(_hour(h))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.1,
        color: SahbiColors.turquoise,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _seg<T>(List<(T, String)> opts, T value, void Function(T) onSel) =>
      SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final (v, label) in opts)
            ButtonSegment(
              value: v,
              label: Text(label, style: const TextStyle(fontSize: 12)),
            ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onSel(s.first),
      );

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = ref.watch(settingsProvider);
    final net = ref.watch(connectivityProvider).value;
    final voice = ref.watch(voiceControllerProvider);
    final music = ref.watch(musicControllerProvider);
    final memory = ref.watch(memoryStoreProvider);
    final health = net.health;

    Widget svc(String name, String label) {
      final h = health?.services[name];
      final ok = h?.configured ?? false;
      return ListTile(
        dense: true,
        leading: Icon(
          ok ? Icons.check_circle_rounded : Icons.remove_circle_outline,
          color: ok ? SahbiColors.green : SahbiColors.textSecondary,
          size: 20,
        ),
        title: Text(label),
        trailing: Text(
          health == null
              ? '—'
              : (ok ? '${l.configured} · ${h!.provider}' : l.notConfigured),
          style: const TextStyle(
            fontSize: 12,
            color: SahbiColors.textSecondary,
          ),
        ),
      );
    }

    String modeLabel(String id) => switch (id) {
      'cloud' => l.providerCloud,
      'typed' => l.providerTyped,
      'off' => l.providerOff,
      _ => l.providerDevice,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ZelligeBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            // ---- Language
            _section(l.secLanguage),
            ZelligeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.uiLanguage),
                  const SizedBox(height: 6),
                  _seg(
                    [('ar', 'العربية'), ('fr', 'Français'), ('en', 'English')],
                    s.uiLocale,
                    (v) => _set((x) => x.copyWith(uiLocale: v)),
                  ),
                  const SizedBox(height: 14),
                  Text(l.replyLanguage),
                  const SizedBox(height: 6),
                  _seg(
                    [
                      ('darija', l.langDarija),
                      ('ar', l.langArabic),
                      ('fr', l.langFrench),
                      ('en', l.langEnglish),
                    ],
                    s.replyLanguage,
                    (v) => _set((x) => x.copyWith(replyLanguage: v)),
                  ),
                  const SizedBox(height: 14),
                  Text(l.darijaScript),
                  const SizedBox(height: 6),
                  _seg(
                    [('arabic', l.scriptArabic), ('latin', l.scriptLatin)],
                    s.darijaScript,
                    (v) => _set((x) => x.copyWith(darijaScript: v)),
                  ),
                ],
              ),
            ),

            // ---- Voice
            _section(l.secVoice),
            ZelligeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(l.sttProvider)),
                      Text(
                        '${l.activeNow}: ${modeLabel(voice.activeStt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SahbiColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _seg(
                    [
                      (SttMode.auto, l.modeAuto),
                      (SttMode.cloud, l.modeCloud),
                      (SttMode.device, l.modeDevice),
                      (SttMode.typed, l.modeTyped),
                    ],
                    s.sttMode,
                    (v) {
                      _set((x) => x.copyWith(sttMode: v));
                      voice.resetFallbacks();
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Text(l.ttsProvider)),
                      Text(
                        '${l.activeNow}: ${modeLabel(voice.activeTts)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SahbiColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _seg(
                    [
                      (TtsMode.auto, l.modeAuto),
                      (TtsMode.cloud, l.modeCloud),
                      (TtsMode.device, l.modeDevice),
                      (TtsMode.off, l.modeOff),
                    ],
                    s.ttsMode,
                    (v) {
                      _set((x) => x.copyWith(ttsMode: v));
                      voice.resetFallbacks();
                    },
                  ),
                  if (!net.cloudSttConfigured || !net.cloudTtsConfigured)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${l.serviceStt}: ${net.cloudSttConfigured ? l.configured : l.notConfigured} · '
                        '${l.serviceTts}: ${net.cloudTtsConfigured ? l.configured : l.notConfigured}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SahbiColors.amber,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(l.deviceVoice),
                  DropdownButton<String?>(
                    isExpanded: true,
                    value:
                        (_voices ?? const []).any(
                          (v) => v.name == s.deviceVoiceName,
                        )
                        ? s.deviceVoiceName
                        : null,
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l.defaultVoice),
                      ),
                      for (final v in _voices ?? const <TtsVoice>[])
                        DropdownMenuItem<String?>(
                          value: v.name,
                          child: Text(
                            '${v.locale} · ${v.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => _set(
                      (x) => v == null
                          ? x.copyWith(clearDeviceVoice: true)
                          : x.copyWith(
                              deviceVoiceName: v,
                              deviceVoiceLocale: _voices!
                                  .firstWhere((e) => e.name == v)
                                  .locale,
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(width: 80, child: Text(l.speechRate)),
                      Expanded(
                        child: Slider(
                          value: s.speechRate,
                          min: 0.2,
                          max: 0.9,
                          onChanged: (v) =>
                              _set((x) => x.copyWith(speechRate: v)),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(width: 80, child: Text(l.pitch)),
                      Expanded(
                        child: Slider(
                          value: s.pitch,
                          min: 0.6,
                          max: 1.5,
                          onChanged: (v) => _set((x) => x.copyWith(pitch: v)),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: s.ttsMode == TtsMode.off
                          ? null
                          : () => voice.speak(
                              l.testVoiceText,
                              language: s.uiLocale == 'ar'
                                  ? 'darija'
                                  : s.uiLocale,
                            ),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: Text(l.testVoice),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.tapFaceToTalk),
                    value: s.tapFaceToTalk,
                    onChanged: (v) => _set((x) => x.copyWith(tapFaceToTalk: v)),
                  ),
                  SwitchListTile(
                    key: const Key('wake_by_name'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.wakeByNameTitle),
                    subtitle: Text(
                      l.wakeByNameSubtitle(s.displayRobotName(l.appTitle)),
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: s.wakeByName,
                    onChanged: _setWakeByName,
                  ),
                  SwitchListTile(
                    key: const Key('mic_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.settingsMicTitle),
                    subtitle: Text(
                      l.settingsMicSubtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: s.micEnabled,
                    onChanged: _setMic,
                  ),
                  const WakeModelTile(),
                  const SizedBox(height: 8),
                  Text(l.silenceTitle),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          key: const Key('silence_slider'),
                          value: s.silenceTimeoutSec.toDouble().clamp(5, 60),
                          min: 5,
                          max: 60,
                          divisions: 11,
                          onChanged: (v) => _set(
                            (x) => x.copyWith(silenceTimeoutSec: v.round()),
                          ),
                        ),
                      ),
                      Text(
                        l.silenceValue(s.silenceTimeoutSec),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.keepScreenOn),
                    value: s.keepScreenOn,
                    onChanged: (v) => _set((x) => x.copyWith(keepScreenOn: v)),
                  ),
                  Text(
                    l.darijaQualityNote,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SahbiColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // ---- AI / backend (hidden unless unlocked, see _showTech)
            if (_showTech) _section(l.secAi),
            if (_showTech)
              ZelligeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: l.backendUrl,
                        hintText: 'https://sahbi.example.com',
                      ),
                      onSubmitted: (v) {
                        _set((x) => x.copyWith(backendUrl: v.trim()));
                        ref.read(connectivityProvider).check();
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${l.lastHealthCheck}: ${net.lastCheck == null ? l.never : TimeOfDay.fromDateTime(net.lastCheck!).format(context)}'
                            '${health != null ? ' · v${health.version} · prompt ${health.promptVersion}' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SahbiColors.textSecondary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (_url.text.trim() != s.backendUrl) {
                              _set(
                                (x) => x.copyWith(backendUrl: _url.text.trim()),
                              );
                            }
                            ref.read(connectivityProvider).check();
                          },
                          child: Text(l.checkNow),
                        ),
                      ],
                    ),
                    svc('llm', l.serviceLlm),
                    svc('search', l.serviceSearch),
                    svc('weather', l.serviceWeather),
                    svc('stt', l.serviceStt),
                    svc('tts', l.serviceTts),
                  ],
                ),
              ),

            // ---- Internet
            _section(l.secInternet),
            ZelligeCard(
              child: Row(
                children: [
                  Icon(
                    net.online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: net.online ? SahbiColors.green : SahbiColors.amber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      net.online
                          ? l.online
                          : (net.hasNetwork ? l.networkOnly : l.offline),
                    ),
                  ),
                ],
              ),
            ),

            // ---- Music
            _section(l.secMusic),
            ZelligeCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.bluetooth_audio_rounded,
                      color: music.output.isBluetooth
                          ? SahbiColors.turquoise
                          : SahbiColors.textSecondary,
                    ),
                    title: Text(l.bluetoothStatus),
                    subtitle: Text(
                      music.output.isBluetooth
                          ? '${l.btConnectedOutput} · ${music.output.name}'
                          : l.btNotOutput,
                    ),
                    trailing: IconButton(
                      tooltip: l.openBluetoothSettings,
                      icon: const Icon(Icons.settings_bluetooth_rounded),
                      onPressed: () => music.bridge.openBluetoothSettings(),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.library_music_outlined),
                    title: Text(l.musicTitle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/music'),
                  ),
                ],
              ),
            ),

            // ---- Memory & privacy
            _section(l.secMemory),
            ZelligeCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.psychology_alt_outlined),
                    title: Text(l.memoryTitle),
                    subtitle: Text(
                      memory.anyConsent ? l.memoryOnLabel : l.memoryOffLabel,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/settings/memory'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(l.secPrivacy),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/settings/privacy'),
                  ),
                ],
              ),
            ),

            // ---- Personality
            _section(l.secPersonality),
            ZelligeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('robot_name'),
                    controller: _robot,
                    maxLength: AppSettings.maxRobotNameLength,
                    decoration: InputDecoration(
                      labelText: l.robotNameTitle,
                      hintText: l.robotNameHint,
                      prefixIcon: const Icon(Icons.smart_toy_outlined),
                    ),
                    onChanged: (v) => _set((x) => x.copyWith(robotName: v)),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(labelText: l.userName),
                    onChanged: (v) =>
                        _set((x) => x.copyWith(userName: v.trim())),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(width: 80, child: Text(l.humor)),
                      Expanded(
                        child: Slider(
                          value: s.humor,
                          onChanged: (v) => _set((x) => x.copyWith(humor: v)),
                        ),
                      ),
                    ],
                  ),
                  Text(l.formality),
                  const SizedBox(height: 6),
                  _seg(
                    [('casual', l.casual), ('polite', l.polite)],
                    s.formality,
                    (v) => _set((x) => x.copyWith(formality: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.idleBehavior),
                    value: s.idleEnabled,
                    onChanged: (v) => _set((x) => x.copyWith(idleEnabled: v)),
                  ),
                  SwitchListTile(
                    key: const Key('proactive_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.behaviorTitle),
                    subtitle: Text(
                      l.behaviorSubtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: s.proactiveTalk,
                    onChanged: (v) => _set((x) => x.copyWith(proactiveTalk: v)),
                  ),
                  const SizedBox(height: 4),
                  Text(l.quietHoursTitle),
                  Row(
                    children: [
                      _hourPicker(
                        s.quietStartHour,
                        (h) => _set((x) => x.copyWith(quietStartHour: h)),
                      ),
                      const Text('  →  '),
                      _hourPicker(
                        s.quietEndHour,
                        (h) => _set((x) => x.copyWith(quietEndHour: h)),
                      ),
                    ],
                  ),
                  Text(
                    l.quietHoursValue(
                      _hour(s.quietStartHour),
                      _hour(s.quietEndHour),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SahbiColors.textSecondary,
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('shake_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.shakeTitle),
                    subtitle: Text(
                      l.shakeSubtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: s.shakeReaction,
                    onChanged: (v) => _set((x) => x.copyWith(shakeReaction: v)),
                  ),
                  SwitchListTile(
                    key: const Key('robot_eyes_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.settingsCameraTitle),
                    subtitle: Text(
                      l.eyesSettingSubtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: s.robotEyes,
                    onChanged: (v) => _set(
                      (x) => x.copyWith(robotEyes: v, robotEyesAsked: true),
                    ),
                  ),
                ],
              ),
            ),

            // ---- Robot
            _section(l.secRobot),
            ZelligeCard(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.robotExperimental),
                    value: s.robotExperimental,
                    onChanged: (v) =>
                        _set((x) => x.copyWith(robotExperimental: v)),
                  ),
                  if (s.robotExperimental)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.smart_toy_outlined),
                      title: Text(l.robotTitle),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/settings/robot'),
                    ),
                ],
              ),
            ),

            // ---- About
            _section(l.secAbout),
            ZelligeCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.version),
                    trailing: Text(AppConfig.appVersion),
                    onTap: () {
                      if (_showTech || ++_versionTaps < 7) return;
                      setState(() => _showTech = true);
                      if (!s.debugUnlocked) {
                        _set((x) => x.copyWith(debugUnlocked: true));
                      }
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(l.debugUnlocked)));
                    },
                  ),
                  if (_showTech)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bug_report_outlined),
                      title: Text(l.debugTitle),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/settings/debug'),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.licenses),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'MIMO',
                      applicationVersion: AppConfig.appVersion,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Offline "MIMO" wake model: one-time download with progress, then it
/// works without internet (and while the app is minimised).
class WakeModelTile extends ConsumerWidget {
  const WakeModelTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final m = ref.watch(wakeModelProvider);
    final (String text, Widget? action) = switch (m.status) {
      WakeModelStatus.ready => (l.wakeModelReady, null),
      WakeModelStatus.downloading => (
        l.wakeModelDownloading((m.progress * 100).round()),
        TextButton(onPressed: m.cancel, child: Text(l.cancel)),
      ),
      WakeModelStatus.failed => (
        l.wakeModelFailed,
        FilledButton.tonal(
          key: const Key('wake_model_retry'),
          onPressed: () => unawaited(m.download()),
          child: Text(l.wakeModelRetry),
        ),
      ),
      WakeModelStatus.missing => (
        l.wakeModelMissing,
        FilledButton.tonal(
          key: const Key('wake_model_download'),
          onPressed: () => unawaited(m.download()),
          child: Text(l.wakeModelDownload),
        ),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                m.status == WakeModelStatus.ready
                    ? Icons.offline_bolt_rounded
                    : Icons.download_rounded,
                size: 20,
                color: m.status == WakeModelStatus.ready
                    ? SahbiColors.green
                    : SahbiColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(l.wakeModelTitle)),
              ?action,
            ],
          ),
          if (m.status == WakeModelStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: m.progress),
            ),
          const SizedBox(height: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: SahbiColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
