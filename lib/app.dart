import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'core/theme.dart';
import 'features/chat/chat_controller.dart';
import 'features/chat/chat_screen.dart';
import 'features/debug/debug_screen.dart';
import 'features/home/home_screen.dart';
import 'features/live/live_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/music/music_screen.dart';
import 'features/music/youtube_panel.dart';
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
    // Full-screen live camera, above the tab shell.
    GoRoute(
      path: '/live',
      parentNavigatorKey: rootNavigatorKey,
      builder: (_, _) => const LiveScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _Shell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/music', builder: (_, _) => const MusicScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'memory',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, _) => const MemoryScreen(),
                ),
                GoRoute(
                  path: 'privacy',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, _) => const PrivacyScreen(),
                ),
                GoRoute(
                  path: 'robot',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, _) => const RobotLinkScreen(),
                ),
                GoRoute(
                  path: 'debug',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, _) => const DebugScreen(),
                ),
              ],
            ),
          ],
        ),
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

class _SahbiAppState extends ConsumerState<SahbiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final router = ref.read(routerProvider);
    // Commands like "7el settings" / voice listen requests need navigation
    // and the mic-permission flow, which live in the UI layer.
    ref.read(chatControllerProvider).hooks = ChatHooks(
      updateSettings: ref.read(settingsProvider.notifier).update,
      openSettings: () => router.go('/settings'),
      openMusic: () => router.go('/music'),
      openCamera: () => router.push('/live'),
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
    // Wake-by-name only runs while the app is in the foreground.
    ref.read(wakeNameProvider);
    // Conversation after the name, and the robot talking on its own.
    ref.read(conversationProvider);
    ref.read(proactiveProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(wakeNameProvider)
        .setForeground(state == AppLifecycleState.resumed);
    // Opening the app again counts as the user being here (no goodnight
    // line the moment they come back after a long time).
    if (state == AppLifecycleState.resumed) {
      ref.read(companionProvider).interact();
    }
    if (state == AppLifecycleState.paused) {
      ref.read(conversationProvider).end();
    }
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
      // NOT L10n.localizationsDelegates: those bundle flutter_localizations'
      // delegates, which serve the legacy package:flutter/material
      // MaterialLocalizations type. material_ui widgets look up their own type,
      // so ar/fr crashed (no MaterialLocalizations). Use material_ui's delegates
      // (as its README prescribes) plus the app strings.
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
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
    // The home tab is the full-screen face: no tab bar there (its own
    // buttons navigate); every other tab shows the bar to come back.
    return Scaffold(
      body: Stack(
        children: [
          shell,
          // Songs from YouTube play here, inside the app.
          const Align(alignment: Alignment.topCenter, child: YoutubePanel()),
        ],
      ),
      bottomNavigationBar: shell.currentIndex == 0
          ? null
          : NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
              backgroundColor: SahbiColors.surface,
              indicatorColor: SahbiColors.turquoise.withValues(alpha: 0.18),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.face_retouching_natural_outlined),
                  selectedIcon: const Icon(Icons.face_retouching_natural),
                  label: l.tabHome,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  selectedIcon: const Icon(Icons.chat_bubble_rounded),
                  label: l.tabChat,
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: playing,
                    smallSize: 8,
                    backgroundColor: SahbiColors.green,
                    child: const Icon(Icons.music_note_outlined),
                  ),
                  selectedIcon: const Icon(Icons.music_note_rounded),
                  label: l.tabMusic,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.tune_outlined),
                  selectedIcon: const Icon(Icons.tune_rounded),
                  label: l.tabSettings,
                ),
              ],
            ),
    );
  }
}
