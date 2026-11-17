import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/platform_bridge.dart';
import 'package:sahbi/features/music/music_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/music_fakes.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEngine engine;
  late FakeBridge bridge;
  late MusicController c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    engine = FakeEngine();
    bridge = FakeBridge();
    c = MusicController(
      engine: engine,
      bridge: bridge,
      prefs: await SharedPreferences.getInstance(),
    );
  });

  test(
    'demo tracks are bundled CC0 assets that exist in assets/audio',
    () async {
      expect(demoTracks, isNotEmpty);
      for (final t in demoTracks) {
        expect(t.uri, startsWith('asset:///assets/audio/'));
        final data = await rootBundle.load(t.uri.replaceFirst('asset:///', ''));
        expect(
          data.lengthInBytes,
          greaterThan(44),
          reason: t.uri,
        ); // more than a WAV header
      }
    },
  );

  test(
    'play with no query plays everything; pause/resume/stop report honestly',
    () async {
      expect((await c.pause()).ok, isFalse); // nothing playing yet
      final r = await c.playQuery(null);
      await pump();
      expect(r.ok, isTrue);
      expect(c.playing, isTrue);
      expect((await c.pause()).ok, isTrue);
      await pump();
      expect(c.playing, isFalse);
      expect((await c.playQuery(null)).message, 'Resumed');
      expect((await c.stop()).ok, isTrue);
    },
  );

  test(
    'query matches title/artist; no match is a failure, not a fake success',
    () async {
      final r = await c.playQuery('medina');
      expect(r.ok, isTrue);
      expect(engine.calls, contains('setQueue:1@0'));
      final miss = await c.playQuery('nass el ghiwane');
      expect(miss.ok, isFalse);
      expect(miss.message, startsWith('no_local_match'));
    },
  );

  test('next at the end of the queue fails', () async {
    await c.playTracks([demoTracks.first]);
    await pump();
    expect((await c.next()).message, 'end_of_queue');
    await c.playTracks(demoTracks);
    await pump();
    expect((await c.next()).ok, isTrue);
  });

  test('engine errors surface as failures', () async {
    engine.failPlay = true;
    final r = await c.playTracks(demoTracks);
    expect(r.ok, isFalse);
    expect(r.message, startsWith('could_not_play'));
  });

  test('imports via SAF are de-duplicated and persisted', () async {
    bridge.picked = const [
      PickedAudio(uri: 'content://a/1', name: 'one.mp3', title: 'One'),
      PickedAudio(uri: 'content://a/2', name: 'two.mp3'),
    ];
    expect((await c.importFiles()).ok, isTrue);
    expect((await c.importFiles()).message, '0 track(s) added');
    expect(c.library.length, 2);
    final again = MusicController(
      engine: engine,
      bridge: bridge,
      prefs: await SharedPreferences.getInstance(),
    );
    expect(again.library.length, 2);
    expect(c.allTracks.length, 2 + demoTracks.length);
  });

  test('cancelled picker and picker errors are reported', () async {
    expect((await c.importFiles()).message, 'nothing_selected');
    bridge.pickerError = PlatformException(code: 'x');
    expect((await c.importFiles()).message, startsWith('picker_failed'));
  });

  test(
    'system volume: success reports the real level, unavailable fails',
    () async {
      expect((await c.volumeStep(1)).message, 'Volume 60%');
      expect((await c.setVolume(1.7)).message, 'Volume 100%'); // clamped
      bridge.volumeResult = null;
      expect((await c.volumeStep(-1)).message, 'volume_unavailable');
    },
  );

  test('refreshOutput shows the active route', () async {
    await c.refreshOutput();
    expect(c.output.isBluetooth, isTrue);
    expect(c.output.name, 'JBL Go');
    expect(c.systemVolume, 0.4);
  });

  test(
    'ducking lowers Sahbi\'s player while speaking and restores it',
    () async {
      await c.playTracks(demoTracks);
      await pump();
      await c.duck(true);
      expect(engine.calls.last, 'volume:0.25');
      await c.duck(true); // idempotent
      await c.duck(false);
      expect(engine.calls.last, 'volume:1.00');
    },
  );
}
