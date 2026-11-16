import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget item(IconData i, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 20, color: SahbiColors.turquoise),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: const TextStyle(height: 1.45))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(l.privacyTitle)),
      body: ZelligeBackground(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ZelligeCard(
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.sendToAi),
                value: s.sendToAi,
                onChanged: (v) => n.update((x) => x.copyWith(sendToAi: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.cloudVoiceToggle),
                value: s.cloudVoiceEnabled,
                onChanged: (v) {
                  n.update((x) => x.copyWith(cloudVoiceEnabled: v));
                  ref.read(voiceControllerProvider).resetFallbacks();
                },
              ),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.mic_rounded, color: SahbiColors.coral), title: Text(l.micIndicator)),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.analytics_outlined), title: Text(l.analyticsOff)),
            ]),
          ),
          const SizedBox(height: 16),
          Text(l.whatLeaves, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ZelligeCard(
            child: Column(children: [
              item(Icons.chat_bubble_outline, l.privChat),
              item(Icons.travel_explore_rounded, l.privSearch),
              item(Icons.record_voice_over_outlined, l.privVoice),
              item(Icons.lock_outline_rounded, l.privMemory),
              item(Icons.music_note_outlined, l.privMusic),
            ]),
          ),
        ]),
      ),
    );
  }
}
