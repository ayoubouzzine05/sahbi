import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';
import 'features/music/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Media session + mediaPlayback foreground service (notification controls).
  final handler = await AudioService.init(
    builder: () => SahbiAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'ma.sahbi.audio',
      androidNotificationChannelName: 'SAHBI music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        musicEngineProvider.overrideWithValue(handler),
      ],
      child: const SahbiApp(),
    ),
  );
}
