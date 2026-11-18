import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/ui_helpers.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_models.dart';
import '../face/robot_face.dart';
import '../personality/voice_state.dart';
import '../voice/mic_flow.dart';
import 'talk_controls.dart';

/// Dashboard: the whole screen is the robot's face (eyes, brows, mouth).
/// Controls fade out after a few seconds and come back on any touch; they
/// stay tappable while faded, so nothing is ever hidden behind a gesture.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const fadeAfter = Duration(seconds: 6);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _controlsVisible = true;
  Timer? _fade;
  bool _wakelock = false;

  @override
  void initState() {
    super.initState();
    _poke();
  }

  @override
  void dispose() {
    _fade?.cancel();
    _setWakelock(false);
    super.dispose();
  }

  void _setWakelock(bool on) {
    if (on == _wakelock) return;
    _wakelock = on;
    unawaited(
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}),
    );
  }

  /// Show the controls again and restart the fade timer.
  void _poke() {
    _fade?.cancel();
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    _fade = Timer(HomeScreen.fadeAfter, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final companion = ref.watch(companionProvider);
    final music = ref.watch(musicControllerProvider);
    final chat = ref.watch(chatControllerProvider);
    final net = ref.watch(connectivityProvider).value;
    final settings = ref.watch(settingsProvider);
    final wake = ref.watch(wakeNameProvider);
    final backend = ref.read(backendClientProvider);
    final name = settings.displayRobotName(l.appTitle);

    // Keep the face on screen while this tab is visible (setting).
    final visible = TickerMode.valuesOf(context).enabled;
    _setWakelock(settings.keepScreenOn && visible);

    final listening = voice.state == VoiceState.listening;
    final face = RobotFace(
      fullScreen: true,
      inputs: FaceInputs(
        emotion: companion.emotion,
        intensity: companion.intensity,
        speaking: voice.state == VoiceState.speaking,
        listening: listening,
        listenLevel: voice.level,
        music: music.playing,
        lookAt: companion.lookAt,
      ),
      wordPulse: voice.wordPulse,
      semanticLabel: '$name — ${companion.emotion.name}',
      onTap: () {
        _poke();
        companion.interact();
        if (settings.tapFaceToTalk && !listening) {
          startListeningFlow(
            context,
            ref,
            onTypedFallback: () => context.go('/chat'),
          );
        }
      },
    );

    final lastSahbi = chat.messages.reversed
        .where((m) => m.role == ChatRole.sahbi && m.text.isNotEmpty)
        .firstOrNull;

    // Caption: what the user is saying, or the robot's last reply while it
    // talks / thinks. Otherwise the face is alone.
    final String? caption = switch (voice.state) {
      VoiceState.listening =>
        voice.partial.isEmpty ? l.listeningHint : voice.partial,
      VoiceState.thinking => l.stateThinking,
      VoiceState.speaking => lastSahbi?.text,
      VoiceState.error => l.stateError,
      VoiceState.idle =>
        _controlsVisible && wake.active ? l.wakeListening(name) : null,
    };

    final top = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: SahbiColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!net.online)
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: SahbiColors.amber,
              semanticLabel: l.offline,
            ),
          if (wake.active)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Icon(
                Icons.hearing_rounded,
                size: 18,
                color: SahbiColors.green,
                semanticLabel: l.wakeListening(name),
              ),
            ),
          const Spacer(),
          MicIndicator(on: voice.micOpen),
        ],
      ),
    );

    final banner = ConnectivityBanner(
      net: net,
      hasBackendUrl: backend.hasBaseUrl,
      sendToAi: settings.sendToAi,
    );

    Widget navButton(IconData icon, String tip, VoidCallback onTap) =>
        IconButton.filledTonal(
          tooltip: tip,
          iconSize: 24,
          onPressed: () {
            _poke();
            onTap();
          },
          icon: Icon(icon),
        );

    final bottomBar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          navButton(
            Icons.photo_camera_outlined,
            l.openCamera,
            () => context.push('/live'),
          ),
          Expanded(
            child: TalkControls(
              onKeyboard: () => context.go('/chat'),
              compact: true,
            ),
          ),
          navButton(
            Icons.music_note_outlined,
            l.tabMusic,
            () => context.go('/music'),
          ),
          navButton(
            Icons.tune_outlined,
            l.tabSettings,
            () => context.go('/settings'),
          ),
        ],
      ),
    );

    final controlsOpacity = _controlsVisible || listening ? 1.0 : 0.22;

    return Scaffold(
      backgroundColor: SahbiColors.visor,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _poke(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            face,
            SafeArea(
              child: Column(
                children: [
                  AnimatedOpacity(
                    opacity: controlsOpacity,
                    duration: const Duration(milliseconds: 400),
                    child: top,
                  ),
                  banner,
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: caption == null
                        ? const SizedBox(height: 0, key: ValueKey('none'))
                        : Padding(
                            key: ValueKey(caption),
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                            child: GestureDetector(
                              onTap: () => context.go('/chat'),
                              child: Text(
                                caption,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.4,
                                  color: listening
                                      ? SahbiColors.green
                                      : SahbiColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                  ),
                  AnimatedOpacity(
                    opacity: controlsOpacity,
                    duration: const Duration(milliseconds: 400),
                    child: bottomBar,
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
