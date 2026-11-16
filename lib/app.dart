import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'core/theme.dart';
import 'features/chat/chat_controller.dart';
import 'features/chat/chat_screen.dart';
import 'features/debug/debug_screen.dart';
import 'features/home/home_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/music/music_screen.dart';
import 'features/robot_link/robot_link_screen.dart';
import 'features/settings/privacy_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/voice/mic_flow.dart';
import 'l10n/app_localizations.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => _Shell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (_, _) => const ChatScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/music', builder: (_, _) => const MusicScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(path: 'memory', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const MemoryScreen()),
                  GoRoute(path: 'privacy', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const PrivacyScreen()),
                  GoRoute(path: 'robot', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const RobotLinkScreen()),
                  GoRoute(path: 'debug', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const DebugScreen()),
                ],
              ),
            ]),
          ],
        ),
      ],
    );

final routerProvider = Provider<GoRouter>((ref) => buildRouter());

class SahbiApp extends ConsumerStatefulWidget {
  const SahbiApp({super.key});

  @override
  ConsumerState<SahbiApp> createState() => _SahbiAppState();
}

class _SahbiAppState extends ConsumerState<SahbiApp> {
  @override
  void initState() {
    super.initState();
    final router = ref.read(routerProvider);
    // Commands like "7el settings" / voice listen requests need navigation
    // and the mic-permission flow, which live in the UI layer.
    ref.read(chatControllerProvider).hooks = ChatHooks(
      updateSettings: ref.read(settingsProvider.notifier).update,
      openSettings: () => router.go('/settings'),
      openMusic: () => router.go('/music'),
      requestListen: () async {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return false;
        return startListeningFlow(ctx, ref);
      },
    );
    // Start background loops.
    ref.read(connectivityProvider);
    ref.read(companionProvider).start();
    ref.read(memoryStoreProvider);
    ref.read(robotLinkProvider);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(settingsProvider.select((s) => s.uiLocale));
    return MaterialApp.router(
      onGenerateTitle: (c) => L10n.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildSahbiTheme(),
      darkTheme: buildSahbiTheme(),
      themeMode: ThemeMode.dark,
      locale: Locale(locale),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _Shell extends ConsumerWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final playing = ref.watch(musicControllerProvider.select((m) => m.playing));
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        backgroundColor: SahbiColors.surface,
        indicatorColor: SahbiColors.turquoise.withValues(alpha: 0.18),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.face_retouching_natural_outlined), selectedIcon: const Icon(Icons.face_retouching_natural), label: l.tabHome),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), selectedIcon: const Icon(Icons.chat_bubble_rounded), label: l.tabChat),
          NavigationDestination(
            icon: Badge(isLabelVisible: playing, smallSize: 8, backgroundColor: SahbiColors.green, child: const Icon(Icons.music_note_outlined)),
            selectedIcon: const Icon(Icons.music_note_rounded),
            label: l.tabMusic,
          ),
          NavigationDestination(icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune_rounded), label: l.tabSettings),
        ],
      ),
    );
  }
}
