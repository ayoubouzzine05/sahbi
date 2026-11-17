import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/app.dart';
import 'package:sahbi/core/backend_client.dart';
import 'package:sahbi/core/connectivity.dart';
import 'package:sahbi/core/providers.dart';
import 'package:sahbi/features/face/robot_face.dart';
import 'package:sahbi/features/memory/memory_store.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/mic_permission.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart' as f;
import '../support/music_fakes.dart';

class FakeMic implements MicPermission {
  @override
  Future<MicStatus> status() async => MicStatus.denied;
  @override
  Future<MicStatus> request() async => MicStatus.denied;
  @override
  Future<bool> openSettings() async => false;
}

Future<void> pumpApp(WidgetTester t, {AppSettings settings = const AppSettings()}) async {
  SharedPreferences.setMockInitialValues({'settings_v1': settings.encode()});
  final prefs = await SharedPreferences.getInstance();
  await t.binding.setSurfaceSize(const Size(412, 915));
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      musicEngineProvider.overrideWithValue(FakeEngine()),
      keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      blobStorageProvider.overrideWithValue(InMemoryBlobStorage()),
      platformBridgeProvider.overrideWithValue(FakeBridge()),
      micPermissionProvider.overrideWithValue(FakeMic()),
      // No connectivity_plus plugin in widget tests: monitor not started.
      connectivityProvider.overrideWith((ref) => ConnectivityMonitor(ref.read(backendClientProvider))),
      deviceSttProvider.overrideWithValue(f.FakeStt('device')),
      cloudSttProvider.overrideWithValue(f.FakeStt('cloud')),
      deviceTtsProvider.overrideWithValue(f.FakeTts('device')),
      cloudTtsProvider.overrideWithValue(f.FakeTts('cloud')),
    ],
    child: const SahbiApp(),
  ));
  await frames(t);
}

/// The face animates forever, so pumpAndSettle never returns.
Future<void> frames(WidgetTester t, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 10)); // flush idle/hold timers
  await t.binding.setSurfaceSize(null);
}

void main() {
  testWidgets('Arabic is the default and the layout is right-to-left', (t) async {
    await pumpApp(t);
    expect(find.byType(RobotFace), findsWidgets);
    expect(Directionality.of(t.element(find.byType(NavigationBar))), TextDirection.rtl);
    expect(find.text('الإعدادات'), findsOneWidget);
    // No backend URL configured → honest banner, not a fake AI.
    expect(find.text('السيرفر ما مضبوطش. زيد العنوان فالإعدادات.'), findsWidgets);
    await unmount(t);
  });

  testWidgets('English UI is left-to-right; tabs navigate', (t) async {
    await pumpApp(t, settings: const AppSettings(uiLocale: 'en'));
    expect(Directionality.of(t.element(find.byType(NavigationBar))), TextDirection.ltr);

    await t.tap(find.text('Chat'));
    await frames(t);
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(find.byKey(const Key('chat_send')), findsOneWidget);

    await t.tap(find.text('Music'));
    await frames(t);
    expect(find.textContaining('Atlas Breeze'), findsWidgets, reason: 'bundled CC0 demo tracks are listed');

    await t.tap(find.text('Settings'));
    await frames(t);
    expect(find.byType(Scrollable), findsWidgets);
    await unmount(t);
  });

  testWidgets('typing in chat without a backend gives a labelled offline reply', (t) async {
    await pumpApp(t, settings: const AppSettings(uiLocale: 'en', cloudVoiceEnabled: false));
    await t.tap(find.text('Chat'));
    await frames(t);
    await t.enterText(find.byKey(const Key('chat_input')), 'chno smitek?');
    await t.tap(find.byKey(const Key('chat_send')));
    await frames(t, 20);
    expect(find.text('chno smitek?'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsWidgets, reason: 'offline replies are labelled');
    await unmount(t);
  });

  testWidgets('French UI loads', (t) async {
    await pumpApp(t, settings: const AppSettings(uiLocale: 'fr'));
    expect(Directionality.of(t.element(find.byType(NavigationBar))), TextDirection.ltr);
    expect(find.byType(RobotFace), findsWidgets);
    await unmount(t);
  });
}
