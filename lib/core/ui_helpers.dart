import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'backend_client.dart';
import 'connectivity.dart';
import 'theme.dart';

String errorText(L10n l, String? code) => switch (code) {
      'noInternet' || 'no_internet' => l.errNoInternet,
      'notConfigured' || 'ai_not_configured' => l.errNotConfigured,
      'timeout' => l.errTimeout,
      'rateLimited' => l.errRateLimited,
      'invalidOutput' => l.errInvalidOutput,
      'unauthorized' => l.errUnauthorized,
      'badRequest' => l.errBadRequest,
      'backend_not_set' => l.backendNotSetBanner,
      'server_unreachable' => l.serverUnreachableBanner,
      'ai_disabled' => l.aiDisabledBanner,
      _ => l.errServer,
    };

/// One banner describing why online features are unavailable (or nothing).
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key, required this.net, required this.hasBackendUrl, required this.sendToAi});

  final NetState net;
  final bool hasBackendUrl;
  final bool sendToAi;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    String? text;
    IconData icon = Icons.cloud_off_rounded;
    if (!hasBackendUrl) {
      text = l.backendNotSetBanner;
      icon = Icons.dns_outlined;
    } else if (!net.hasNetwork) {
      text = l.offlineBanner;
    } else if (net.backendReachable == false) {
      text = net.lastError == BackendErrorCode.noInternet ? l.offlineBanner : l.serverUnreachableBanner;
    } else if (net.backendReachable == true && !net.aiConfigured) {
      text = l.aiNotConfiguredBanner;
      icon = Icons.smart_toy_outlined;
    } else if (!sendToAi) {
      text = l.aiDisabledBanner;
      icon = Icons.privacy_tip_outlined;
    }
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SahbiColors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SahbiColors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: SahbiColors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: SahbiColors.textPrimary))),
        ]),
      ),
    );
  }
}

/// Always-visible red indicator while the microphone is open.
class MicIndicator extends StatelessWidget {
  const MicIndicator({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    if (!on) return const SizedBox.shrink();
    return Semantics(
      label: L10n.of(context).micOn,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: SahbiColors.coral, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mic, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(L10n.of(context).micOn, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.label, this.color = SahbiColors.turquoise});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// Quick phrases in the user's chosen Darija script.
List<(String, String)> quickPhrases(bool latin) => latin
    ? const [
        ('👋', 'Salam Sahbi'),
        ('🎵', 'Ch3el lia chi music'),
        ('📰', 'Qelleb lia 3la akher akhbar lmaghrib'),
        ('🌤️', 'Ch7al kayn f ta9s f Casa?'),
        ('😂', '3awed lia chi nkta'),
        ('🌐', 'Trjem lia "chokran bzaf" l l’anglais'),
      ]
    : const [
        ('👋', 'سلام صاحبي'),
        ('🎵', 'شعل ليا شي موسيقى'),
        ('📰', 'قلب ليا على آخر أخبار المغرب'),
        ('🌤️', 'شحال كاين فالطقس فكازا؟'),
        ('😂', 'عاود ليا شي نكتة'),
        ('🌐', 'ترجم ليا «شكرا بزاف» للإنجليزية'),
      ];
