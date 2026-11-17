import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/features/brain/brain_models.dart';
import 'package:sahbi/features/search/search_sources.dart';
import 'package:sahbi/l10n/app_localizations.dart';

Widget host(Widget w) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: L10n.supportedLocales,
  localizationsDelegates: const [
    L10n.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(body: w),
);

const web1 = SourceRef(
  id: 1,
  title: 'Hespress',
  url: 'https://www.hespress.com/a',
  date: '2026-11-15',
);
const web2 = SourceRef(id: 2, title: 'Le360', url: 'https://fr.le360.ma/b');
const data = SourceRef(
  id: 3,
  title: 'Open-Meteo',
  url: 'https://open-meteo.com',
  kind: 'data',
);

void main() {
  testWidgets('numbered chips with domain and date; confirmed badge', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const SearchSources(
          sources: [web1, web2],
          verification: Verification.confirmed,
        ),
      ),
    );
    expect(find.byType(SourceChip), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('2026-11-15'), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
  });

  testWidgets('unconfirmed answers say so', (t) async {
    await t.pumpWidget(
      host(
        const SearchSources(
          sources: [web1],
          verification: Verification.unconfirmed,
        ),
      ),
    );
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
  });

  testWidgets('data sources (weather) have no verification badge', (t) async {
    await t.pumpWidget(
      host(
        const SearchSources(sources: [data], verification: Verification.data),
      ),
    );
    expect(find.byType(SourceChip), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    expect(find.byIcon(Icons.help_outline), findsNothing);
  });

  testWidgets('search unavailable is stated, not hidden', (t) async {
    await t.pumpWidget(
      host(
        const SearchSources(
          sources: [],
          verification: Verification.none,
          searchUnavailable: true,
        ),
      ),
    );
    final l = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l.searchUnavailable), findsOneWidget);
  });

  testWidgets('non-http source URLs are not launchable', (t) async {
    await t.pumpWidget(
      host(
        const SourceChip(
          s: SourceRef(id: 9, title: 'x', url: 'javascript:alert(1)'),
        ),
      ),
    );
    expect(t.widget<ActionChip>(find.byType(ActionChip)).onPressed, isNull);
  });
}
