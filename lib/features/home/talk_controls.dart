import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../personality/voice_state.dart';
import '../voice/mic_flow.dart';

/// Push-to-talk (tap to start/stop, or hold and release), plus
/// stop-listening and interrupt-speech buttons that are only enabled when
/// they can do something.
class TalkControls extends ConsumerWidget {
  const TalkControls({super.key, this.onKeyboard, this.compact = false});

  final VoidCallback? onKeyboard;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final listening = voice.state == VoiceState.listening;
    final speaking = voice.state == VoiceState.speaking;
    final thinking = voice.state == VoiceState.thinking;

    Future<void> toggle() async {
      if (listening) {
        await voice.stopListening();
      } else {
        await startListeningFlow(context, ref, onTypedFallback: onKeyboard);
      }
    }

    final big = compact ? 64.0 : 84.0;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      spacing: compact ? 4 : 0,
      children: [
        _RoundButton(
          icon: Icons.keyboard_alt_outlined,
          tooltip: l.typeMessage,
          onPressed: onKeyboard,
        ),
        Semantics(
          button: true,
          label: listening ? l.stopListening : l.tapToTalk,
          child: GestureDetector(
            onLongPressStart: (_) {
              if (!listening) {
                startListeningFlow(context, ref, onTypedFallback: onKeyboard);
              }
            },
            onLongPressEnd: (_) => voice.stopListening(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: big,
              height: big,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: listening
                      ? [SahbiColors.coral, const Color(0xFFFF9472)]
                      : [SahbiColors.turquoise, SahbiColors.green],
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (listening ? SahbiColors.coral : SahbiColors.turquoise)
                            .withValues(alpha: 0.35 + 0.4 * voice.level),
                    blurRadius: 18 + 24 * voice.level,
                    spreadRadius: 1 + 6 * voice.level,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('ptt'),
                  customBorder: const CircleBorder(),
                  onTap: toggle,
                  child: Icon(
                    listening
                        ? Icons.stop_rounded
                        : (thinking
                              ? Icons.more_horiz_rounded
                              : Icons.mic_rounded),
                    size: big * 0.45,
                    color: SahbiColors.background,
                  ),
                ),
              ),
            ),
          ),
        ),
        _RoundButton(
          key: const Key('interrupt'),
          icon: listening ? Icons.mic_off_rounded : Icons.volume_off_rounded,
          tooltip: listening ? l.stopListening : l.interruptSpeech,
          onPressed: listening
              ? voice.cancelListening
              : (speaking || thinking)
              ? voice.interrupt
              : null,
        ),
      ],
    );
    // On narrow phones the compact bar shares its row with other buttons:
    // scale the three controls down instead of overflowing.
    return compact ? FittedBox(fit: BoxFit.scaleDown, child: row) : row;
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        iconSize: 26,
        style: IconButton.styleFrom(
          backgroundColor: SahbiColors.surfaceHigh,
          foregroundColor: SahbiColors.textPrimary,
          disabledBackgroundColor: SahbiColors.surface,
          fixedSize: const Size(54, 54),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
