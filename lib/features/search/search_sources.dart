import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../brain/brain_models.dart';

/// Search & tool provenance shown under an AI answer.
///
/// Web search itself runs on the backend (Brave with a key, else free
/// Wikipedia + GDELT news), so no key
/// ships in the app. Here we only render what the server *verified*:
/// numbered source chips (web = turquoise, data such as weather = green),
/// a confirmed/unconfirmed badge, or an honest "search unavailable" note.
class SearchSources extends StatelessWidget {
  const SearchSources({
    super.key,
    required this.sources,
    required this.verification,
    this.searchUnavailable = false,
  });

  final List<SourceRef> sources;
  final Verification verification;
  final bool searchUnavailable;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final confirmed = verification == Verification.confirmed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (searchUnavailable)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l.searchUnavailable,
              style: const TextStyle(fontSize: 12, color: SahbiColors.amber),
            ),
          ),
        if (sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (confirmed || verification == Verification.unconfirmed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          confirmed
                              ? Icons.verified_outlined
                              : Icons.help_outline,
                          size: 14,
                          color: confirmed
                              ? SahbiColors.green
                              : SahbiColors.amber,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            confirmed
                                ? l.sourcesConfirmed
                                : l.sourcesUnconfirmed,
                            style: const TextStyle(
                              fontSize: 11,
                              color: SahbiColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final s in sources) SourceChip(s: s)],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One numbered source; opens the page in the browser.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.s});
  final SourceRef s;

  @override
  Widget build(BuildContext context) {
    final data = s.kind == 'data';
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(
        radius: 9,
        backgroundColor: data ? SahbiColors.green : SahbiColors.turquoise,
        child: Text(
          '${s.id}',
          style: const TextStyle(fontSize: 10, color: SahbiColors.background),
        ),
      ),
      label: Text(
        '${s.domain}${s.date != null ? ' · ${s.date}' : ''}',
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: s.title.isEmpty ? s.url : s.title,
      // Non-http URLs are never launched (no dead button: chip is disabled).
      onPressed: s.url.startsWith('http')
          ? () => launchUrl(
              Uri.parse(s.url),
              mode: LaunchMode.externalApplication,
            )
          : null,
    );
  }
}
