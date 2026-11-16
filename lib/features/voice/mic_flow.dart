import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import 'mic_permission.dart';

/// Push-to-talk entry point: rationale screen before the system prompt,
/// handles denied / permanently denied / no recognizer.
/// Returns true if listening started.
Future<bool> startListeningFlow(BuildContext context, WidgetRef ref, {VoidCallback? onTypedFallback}) async {
  final l = L10n.of(context);
  final settings = ref.read(settingsProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (settings.sttMode == SttMode.typed) {
    onTypedFallback?.call();
    return false;
  }
  final perm = ref.read(micPermissionProvider);
  var status = await perm.status();
  if (status != MicStatus.granted) {
    if (status == MicStatus.permanentlyDenied || status == MicStatus.restricted) {
      if (context.mounted) await _showPermanentlyDenied(context, perm);
      return false;
    }
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const MicRationaleDialog(),
    );
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(micRationaleSeen: true));
    if (ok != true) {
      messenger.showSnackBar(SnackBar(content: Text(l.micDenied)));
      onTypedFallback?.call();
      return false;
    }
    status = await perm.request();
    if (status == MicStatus.permanentlyDenied) {
      if (context.mounted) await _showPermanentlyDenied(context, perm);
      return false;
    }
    if (status != MicStatus.granted) {
      messenger.showSnackBar(SnackBar(content: Text(l.micDenied)));
      onTypedFallback?.call();
      return false;
    }
  }
  final which = await ref.read(voiceControllerProvider).startListening();
  if (which == 'typed') {
    messenger.showSnackBar(SnackBar(content: Text(l.noRecognizer)));
    onTypedFallback?.call();
    return false;
  }
  return true;
}

Future<void> _showPermanentlyDenied(BuildContext context, MicPermission perm) async {
  final l = L10n.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.micRationaleTitle),
      content: Text(l.micPermanentlyDenied),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            perm.openSettings();
          },
          child: Text(l.openAppSettings),
        ),
      ],
    ),
  );
}

class MicRationaleDialog extends StatelessWidget {
  const MicRationaleDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Dialog(
      backgroundColor: SahbiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SahbiColors.green.withValues(alpha: 0.12)),
            child: const Icon(Icons.mic_rounded, size: 36, color: SahbiColors.green),
          ),
          const SizedBox(height: 16),
          Text(l.micRationaleTitle, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(l.micRationaleBody, textAlign: TextAlign.center, style: const TextStyle(color: SahbiColors.textSecondary, height: 1.5)),
          const SizedBox(height: 8),
          SizedBox(height: 8, child: CustomPaint(painter: ZelligePainter(opacity: 0.3, cell: 16), size: const Size(160, 8))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.micNotNow))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.micAllow))),
          ]),
        ]),
      ),
    );
  }
}
