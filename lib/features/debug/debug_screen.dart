import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import '../personality/emotion.dart';
import '../personality/emotion_detector.dart';

/// Hidden debug screen (7 taps on version): provider health, error log,
/// and an emotion preview for checking the face.
class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final log = ref.watch(errorLogProvider);
    final net = ref.watch(connectivityProvider).value;
    final voice = ref.watch(voiceControllerProvider);
    final companion = ref.read(companionProvider);
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 12);
    return Scaffold(
      appBar: AppBar(title: Text(l.debugTitle)),
      body: ZelligeBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l.providerHealth,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            ZelligeCard(
              child: Text(
                'version ${AppConfig.appVersion}\n'
                'network=${net.hasNetwork} backend=${net.backendReachable} lastError=${net.lastError?.name}\n'
                'health=${net.health == null ? 'none' : net.health!.services.entries.map((e) => '${e.key}:${e.value.configured ? e.value.provider : 'off'}').join(' ')}\n'
                'stt=${voice.activeStt} tts=${voice.activeTts} wordTimings=${voice.hasWordTimings}\n'
                'voiceState=${voice.state.name} lastVoiceError=${voice.lastError}',
                style: mono,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Emotion preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in Emotion.values)
                  ActionChip(
                    label: Text(e.name),
                    onPressed: () => companion.show(
                      DetectedEmotion(e, 0.9, source: 'debug'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.lastErrors,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: log.items.isEmpty ? null : log.clear,
                  child: Text(l.clear),
                ),
              ],
            ),
            if (log.items.isEmpty)
              Text(
                l.noErrors,
                style: const TextStyle(color: SahbiColors.textSecondary),
              ),
            for (final e in log.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${e.time.toIso8601String().substring(11, 19)} [${e.area}] ${e.message}',
                  style: mono,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
