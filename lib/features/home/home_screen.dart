import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/ui_helpers.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_models.dart';
import '../face/robot_face.dart';
import '../personality/emotion.dart';
import '../personality/emotion_animation_mapper.dart';
import '../personality/voice_state.dart';
import '../voice/mic_flow.dart';
import 'talk_controls.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final companion = ref.watch(companionProvider);
    final music = ref.watch(musicControllerProvider);
    final chat = ref.watch(chatControllerProvider);
    final net = ref.watch(connectivityProvider).value;
    final settings = ref.watch(settingsProvider);
    final backend = ref.read(backendClientProvider);

    final inputs = FaceInputs(
      emotion: companion.emotion,
      intensity: companion.intensity,
      speaking: voice.state == VoiceState.speaking,
      listening: voice.state == VoiceState.listening,
      listenLevel: voice.level,
      music: music.playing,
      lookAt: companion.lookAt,
    );

    final face = RobotFace(
      inputs: inputs,
      wordPulse: voice.wordPulse,
      semanticLabel: '${l.appTitle} — ${companion.emotion.name}',
      onTap: () {
        companion.interact();
        if (settings.tapFaceToTalk && voice.state != VoiceState.listening) {
          startListeningFlow(
            context,
            ref,
            onTypedFallback: () => context.go('/chat'),
          );
        }
      },
    );

    String stateText() => switch (voice.state) {
      VoiceState.listening =>
        voice.partial.isEmpty ? l.listeningHint : voice.partial,
      VoiceState.thinking => l.stateThinking,
      VoiceState.speaking => l.stateSpeaking,
      VoiceState.error => l.stateError,
      VoiceState.idle => l.stateIdle,
    };

    final lastSahbi = chat.messages.reversed
        .where((m) => m.role == ChatRole.sahbi && m.text.isNotEmpty)
        .firstOrNull;

    final providerLabel = switch (voice.activeStt) {
      'cloud' => l.providerCloud,
      'typed' => l.providerTyped,
      _ => l.providerDevice,
    };

    final status = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          StatusPill(
            icon: net.online
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
            label: net.online ? l.online : l.offline,
            color: net.online ? SahbiColors.green : SahbiColors.amber,
          ),
          const SizedBox(width: 8),
          StatusPill(
            icon: Icons.record_voice_over_outlined,
            label: providerLabel,
          ),
          const Spacer(),
          MicIndicator(on: voice.micOpen),
        ],
      ),
    );

    final caption = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              stateText(),
              key: ValueKey(stateText()),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: voice.state == VoiceState.listening
                    ? SahbiColors.green
                    : SahbiColors.textSecondary,
                fontSize: 15,
              ),
            ),
          ),
          if (lastSahbi != null && voice.state != VoiceState.listening) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => context.go('/chat'),
              child: Text(
                lastSahbi.text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.4,
                  color: SahbiColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final chips = SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (emoji, phrase) in quickPhrases(settings.latinDarija))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                label: Text('$emoji  $phrase'),
                onPressed: () => chat.send(phrase),
              ),
            ),
        ],
      ),
    );

    final controls = TalkControls(onKeyboard: () => context.go('/chat'));
    final banner = ConnectivityBanner(
      net: net,
      hasBackendUrl: backend.hasBaseUrl,
      sendToAi: settings.sendToAi,
    );

    return Scaffold(
      body: ZelligeBackground(
        // Background tint follows the face's emotion accent (neutral = brand turquoise).
        accent: companion.emotion == Emotion.neutral
            ? null
            : const EmotionAnimationMapper()
                  .map(companion.emotion, 1)
                  .params
                  .accent,
        child: SafeArea(
          child: OrientationBuilder(
            builder: (context, o) {
              if (o == Orientation.landscape) {
                // Desk mode: big face, controls on the side.
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: face,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          status,
                          banner,
                          const SizedBox(height: 8),
                          caption,
                          const SizedBox(height: 16),
                          TalkControls(
                            onKeyboard: () => context.go('/chat'),
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  status,
                  banner,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 8,
                      ),
                      child: Center(
                        child: AspectRatio(aspectRatio: 1 / 1.02, child: face),
                      ),
                    ),
                  ),
                  caption,
                  const SizedBox(height: 14),
                  chips,
                  const SizedBox(height: 14),
                  controls,
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
