import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/error_log.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/mimo_wake.dart';
import 'package:sahbi/features/voice/wake_model_manager.dart';
import 'package:sahbi/features/voice/wake_word_engine.dart';

class FakeEngine implements WakeWordEngine {
  final ctrl = StreamController<WakeEvent>.broadcast();
  final calls = <String>[];
  bool allowStart = true;
  @override
  Stream<WakeEvent> get events => ctrl.stream;
  @override
  Future<bool> start({
    required String modelPath,
    required WakeNotice notice,
    bool paused = false,
  }) async {
    calls.add(paused ? 'start(paused)' : 'start');
    return allowStart;
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<bool> isRunning() async => false;
}

void main() {
  late Directory tmp;
  late FakeEngine engine;
  late WakeModelManager models;
  late AppSettings settings;
  late int wakes;
  late int userStops;
  late bool ownSpeech;
  late MimoWakeController c;

  const notice = WakeNotice(
    title: 't',
    text: 'x',
    stopLabel: 's',
    openLabel: 'o',
    channelName: 'c',
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wake');
    final model = Directory('${tmp.path}/wake/${WakeModelSource.name}/am');
    await model.create(recursive: true);
    await File('${model.parent.path}/.complete').writeAsString('ok');
    engine = FakeEngine();
    models = WakeModelManager(baseDir: () async => tmp);
    settings = const AppSettings();
    wakes = 0;
    userStops = 0;
    ownSpeech = false;
    c = MimoWakeController(
      engine: engine,
      models: models,
      settings: () => settings,
      micGranted: () async => true,
      notice: () => notice,
      onWake: () async => wakes++,
      // Like the app: "Stop MIMO" turns the mic toggle off.
      onUserStopped: () {
        userStops++;
        settings = settings.copyWith(micEnabled: false);
        c.refresh();
      },
      isOwnSpeech: () => ownSpeech,
      log: ErrorLog(),
    );
    await models.check();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> settle() async {
    await c.settled;
    await Future<void>.delayed(Duration.zero);
  }

  test('starts when mic + wake word + model are ready', () async {
    c.refresh();
    await settle();
    expect(engine.calls, ['start']);
    expect(c.active, isTrue);
  });

  test('does not START from the background (Android 14 rule)', () async {
    c.setForeground(false);
    await settle();
    expect(engine.calls, isEmpty);
    c.setForeground(true);
    await settle();
    expect(engine.calls, ['start']);
  });

  test('minimising keeps it running', () async {
    c.refresh();
    await settle();
    c.setForeground(false);
    await settle();
    expect(engine.calls, ['start']);
    expect(c.running, isTrue);
  });

  test('mic toggle off stops it', () async {
    c.refresh();
    await settle();
    settings = settings.copyWith(micEnabled: false);
    c.refresh();
    await settle();
    expect(engine.calls.last, 'stop');
    expect(c.running, isFalse);
  });

  test('no model: nothing starts', () async {
    await Directory('${tmp.path}/wake').delete(recursive: true);
    await models.check();
    c.refresh();
    await settle();
    expect(engine.calls, isEmpty);
    expect(c.available, isFalse);
  });

  test('pauses for the conversation recogniser / live screen', () async {
    c.refresh();
    await settle();
    await c.yieldMic();
    expect(engine.calls.last, 'pause');
    c.setMicBusy(false);
    await settle();
    expect(engine.calls.last, 'resume');
    c.suspend();
    await settle();
    expect(engine.calls.last, 'pause');
    c.resume();
    await settle();
    expect(engine.calls.last, 'resume');
  });

  test(
    '"MIMO" heard → onWake; ignored while paused or echoing itself',
    () async {
      c.init();
      c.refresh();
      await settle();
      engine.ctrl.add(const WakeHeard('mimo'));
      await settle();
      expect(wakes, 1);
      ownSpeech = true;
      engine.ctrl.add(const WakeHeard('mimo'));
      await settle();
      expect(wakes, 1, reason: 'its own voice');
      ownSpeech = false;
      c.setMicBusy(true);
      await settle();
      engine.ctrl.add(const WakeHeard('mimo'));
      await settle();
      expect(wakes, 1, reason: 'paused');
    },
  );

  test('"Stop MIMO" in the notification → onUserStopped', () async {
    c.init();
    c.refresh();
    await settle();
    engine.ctrl.add(const WakeStopped(byUser: true));
    await settle();
    expect(userStops, 1);
    expect(c.running, isFalse);
  });

  test('Android refused the start: error kept, not running', () async {
    engine.allowStart = false;
    c.refresh();
    await settle();
    expect(c.running, isFalse);
    expect(c.lastError, 'start_failed');
  });
}
