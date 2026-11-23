import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/hardware_guard.dart';

class Hw {
  bool camFg = true, camOpen = true, micFg = true, mic = true, service = true;
  bool micToggle = true;
  final errors = <String>[];

  HardwareActions get actions => HardwareActions(
    setCameraForeground: (v) => camFg = v,
    closeCamera: () async => camOpen = false,
    setMicForeground: (v) => micFg = v,
    stopMic: () async => mic = false,
    stopBackgroundListening: () async => service = false,
    micEnabled: () => micToggle,
    onError: (w, e) => errors.add(w),
  );
}

void main() {
  test('camera toggle off: camera closed, mic untouched', () async {
    final h = Hw();
    await HardwareGuard(h.actions).onCameraToggle(false);
    expect(h.camOpen, isFalse);
    expect(h.mic, isTrue);
    expect(h.service, isTrue);
  });

  test('mic toggle off: mic, wake word and service stopped', () async {
    final h = Hw()..micToggle = false;
    await HardwareGuard(h.actions).onMicToggle(false);
    expect(h.mic, isFalse);
    expect(h.service, isFalse);
    expect(h.camOpen, isTrue);
  });

  for (final st in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    test(
      'minimised ($st) with mic ON: camera closed, wake word kept',
      () async {
        final h = Hw();
        await HardwareGuard(h.actions).onLifecycle(st);
        expect(h.camOpen, isFalse);
        expect(h.camFg, isFalse);
        expect(h.micFg, isFalse);
        expect(h.mic, isTrue);
        expect(h.service, isTrue);
      },
    );

    test('minimised ($st) with mic OFF: everything stopped', () async {
      final h = Hw()..micToggle = false;
      await HardwareGuard(h.actions).onLifecycle(st);
      expect(h.camOpen, isFalse);
      expect(h.mic, isFalse);
      expect(h.service, isFalse);
    });
  }

  test('closed / swiped (detached): everything released', () async {
    final h = Hw();
    final g = HardwareGuard(h.actions);
    await g.onLifecycle(AppLifecycleState.detached);
    expect(h.camOpen, isFalse);
    expect(h.mic, isFalse);
    expect(h.service, isFalse);
    expect(g.released, isTrue);
  });

  test('inactive (notification shade) changes nothing', () async {
    final h = Hw();
    await HardwareGuard(h.actions).onLifecycle(AppLifecycleState.inactive);
    expect(h.camOpen && h.mic && h.service && h.camFg, isTrue);
  });

  test('resumed: camera and mic may run again', () async {
    final h = Hw()
      ..camFg = false
      ..micFg = false;
    await HardwareGuard(h.actions).onLifecycle(AppLifecycleState.resumed);
    expect(h.camFg, isTrue);
    expect(h.micFg, isTrue);
  });

  test('one failing release never blocks the others', () async {
    var service = true;
    final g = HardwareGuard(
      HardwareActions(
        setCameraForeground: (_) {},
        closeCamera: () async => throw StateError('camera gone'),
        setMicForeground: (_) {},
        stopMic: () async => throw StateError('mic gone'),
        stopBackgroundListening: () async => service = false,
        micEnabled: () => true,
      ),
    );
    await g.releaseAll();
    expect(service, isFalse);
  });
}
