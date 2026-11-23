import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/ui_helpers.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_models.dart';
import '../face/face_act.dart';
import '../face/robot_face.dart';
import '../vision/robot_eyes.dart';
import '../personality/personality_responses.dart';
import '../personality/temper.dart';
import '../personality/temper_lines.dart';
import '../personality/voice_state.dart';
import '../voice/mic_flow.dart';
import '../chat/photo_strip.dart';
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

  /// Camera permission for the robot's eyes (null = unknown / unavailable).
  bool? _camGranted;
  bool _eyesWanted = false;
  // Read in initState (not lazily): it is used in dispose().
  late final RobotEyes _eyes;

  @override
  void initState() {
    super.initState();
    _eyes = ref.read(robotEyesProvider);
    _poke();
    unawaited(_checkCamera());
  }

  @override
  void dispose() {
    _fade?.cancel();
    _setWakelock(false);
    _eyes.setFaceWants(false);
    super.dispose();
  }

  Future<void> _checkCamera() async {
    PermissionStatus st;
    try {
      st = await Permission.camera.status;
    } catch (_) {
      return; // no permission plugin (tests): eyes stay closed
    }
    if (!mounted) return;
    setState(() => _camGranted = st.isGranted);
    final s = ref.read(settingsProvider);
    if (!st.isGranted && s.robotEyes && !s.robotEyesAsked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_askEyes());
      });
    }
  }

  /// First time: explains the robot's eyes, then asks for the camera.
  Future<void> _askEyes() async {
    final l = L10n.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.eyesRationaleTitle),
        content: Text(l.eyesRationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.micNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.micAllow),
          ),
        ],
      ),
    );
    notifier.update((x) => x.copyWith(robotEyesAsked: true));
    if (ok != true) {
      notifier.update((x) => x.copyWith(robotEyes: false));
      return;
    }
    await _requestCamera();
  }

  Future<bool> _requestCamera() async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notifier = ref.read(settingsProvider.notifier);
    PermissionStatus st;
    try {
      st = await Permission.camera.request();
    } catch (_) {
      return false;
    }
    if (!mounted) return false;
    setState(() => _camGranted = st.isGranted);
    if (!st.isGranted) {
      notifier.update((x) => x.copyWith(robotEyes: false));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(l.eyesDenied),
          action: st.isPermanentlyDenied
              ? SnackBarAction(
                  label: l.tabSettings,
                  onPressed: () => unawaited(openAppSettings()),
                )
              : null,
        ),
      );
      return false;
    }
    return true;
  }

  /// The eye button: close / open the robot's eyes.
  Future<void> _toggleEyes() async {
    final notifier = ref.read(settingsProvider.notifier);
    if (ref.read(settingsProvider).robotEyes && _camGranted == true) {
      notifier.update((x) => x.copyWith(robotEyes: false));
      return;
    }
    if (_camGranted != true && !await _requestCamera()) return;
    notifier.update((x) => x.copyWith(robotEyes: true, robotEyesAsked: true));
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

  /// Says a short temper line right away (offline).
  void _react(Line line) {
    final voice = ref.read(voiceControllerProvider);
    final chat = ref.read(chatControllerProvider);
    unawaited(() async {
      await voice.interrupt();
      await chat.sayLocal(line, robotInitiated: true, showEmotion: false);
    }());
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
    final convo = ref.watch(conversationProvider);
    final backend = ref.read(backendClientProvider);
    final name = settings.displayRobotName(l.appTitle);

    // Keep the face on screen while this tab is visible (setting).
    final visible = TickerMode.valuesOf(context).enabled;
    _setWakelock(settings.keepScreenOn && visible);

    final listening = voice.state == VoiceState.listening;

    // The robot's eyes (front camera) are open while its face is on screen.
    final eyesOn = settings.robotEyes && _camGranted == true;
    final eyesWanted =
        eyesOn && visible && !companion.idle.asleep && !wake.externallyBlocked;
    if (eyesWanted != _eyesWanted) {
      _eyesWanted = eyesWanted;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _eyes.setFaceWants(eyesWanted),
      );
    }

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
        dizzy: companion.dizzy,
        act: companion.act,
        actSeq: companion.actSeq,
      ),
      wordPulse: voice.wordPulse,
      semanticLabel: '$name — ${companion.emotion.name}',
      onPet: () {
        _poke();
        switch (companion.pet()) {
          case 'madeUp':
            _react(TemperLines.pick(TemperLines.madeUp));
          case 'stillSulking':
            _react(TemperLines.pick(TemperLines.stillSulking));
        }
      },
      onTap: () {
        _poke();
        if (companion.idle.asleep) {
          // Woken up by a finger: grumpy.
          companion.play(FaceAct.squish);
          companion.interact(touch: true);
        } else {
          // A poke squashes the eyes; poking again and again annoys him,
          // too much and he sulks (turns away).
          switch (companion.poke()) {
            case PokeReaction.annoyed:
              _react(TemperLines.pick(TemperLines.annoyed));
            case PokeReaction.sulk:
              _react(TemperLines.pick(TemperLines.sulkStart));
            case PokeReaction.squish:
            case PokeReaction.ignore:
              break;
          }
        }
        // Rapid taps are pokes, not "tap to talk".
        final poking = companion.temper.poking;
        if (poking && listening) {
          unawaited(ref.read(voiceControllerProvider).cancelListening());
        }
        if (settings.tapFaceToTalk && !listening && !poking) {
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
        convo.active
            ? l.conversationOn
            : _controlsVisible && wake.active
            ? l.wakeListening(name)
            : null,
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
          if (convo.active)
            TextButton.icon(
              key: const Key('end_conversation'),
              onPressed: convo.end,
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: Text(l.conversationEnd),
            ),
          IconButton(
            key: const Key('eyes_toggle'),
            tooltip: eyesOn ? l.eyesClose : l.eyesOpen,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              _poke();
              unawaited(_toggleEyes());
            },
            icon: Icon(
              eyesOn ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 20,
              color: eyesOn ? SahbiColors.green : SahbiColors.textSecondary,
            ),
          ),
          MicIndicator(on: voice.micOpen),
        ],
      ),
    );

    // The face screen stays clean: only "no internet" is shown here; backend
    // problems are explained by the robot when it cannot answer.
    final banner = ConnectivityBanner(
      onlyOffline: true,
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
            // Asleep after 10 minutes without an answer: dimmed face, still
            // listening for the name (taps go through to wake it too).
            if (companion.idle.asleep)
              IgnorePointer(
                child: Container(
                  key: const Key('sleep_dim'),
                  color: Colors.black.withValues(alpha: 0.6),
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Text(
                    settings.wakeByName
                        ? l.sleepingHint(name)
                        : l.sleepingHintTap,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: SahbiColors.textSecondary,
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  AnimatedOpacity(
                    opacity: controlsOpacity,
                    duration: const Duration(milliseconds: 400),
                    child: top,
                  ),
                  banner,
                  if (chat.shownImages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: PhotoOverlayCard(
                        images: chat.shownImages,
                        query: chat.shownImagesQuery ?? '',
                        onClose: chat.clearShownImages,
                      ),
                    ),
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
