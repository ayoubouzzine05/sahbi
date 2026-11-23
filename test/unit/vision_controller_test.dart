import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/vision/robot_eyes.dart';
import 'package:sahbi/features/vision/vision_controller.dart';

class FakeVisionCam implements VisionCamera {
  FakeVisionCam(this.lens, this.log);
  @override
  final CameraLens lens;
  final List<String> log;
  bool disposed = false;
  @override
  CameraController? get controller => null;
  @override
  Future<Uint8List?> grab() async =>
      disposed ? null : Uint8List.fromList([lens.index]);
  @override
  Future<void> dispose() async {
    // Real cameras take a moment to close.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    disposed = true;
    log.add('close ${lens.name}');
  }
}

void main() {
  late List<String> log;
  late bool enabled;
  late VisionController v;

  setUp(() {
    log = [];
    enabled = true;
    v = VisionController(
      enabled: () => enabled,
      factory: (lens, preset, {description}) async {
        log.add('open ${lens.name}');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return FakeVisionCam(lens, log);
      },
    );
  });

  test('switching front → back always closes first: never two open', () async {
    await v.acquire(VisionOwner.eyes);
    await v.acquire(VisionOwner.inspect, lens: CameraLens.back);
    // The eyes cannot take it from a running back-camera look…
    expect(await v.acquire(VisionOwner.eyes), isNull);
    // …only after the look is done.
    await v.release(VisionOwner.inspect);
    await v.acquire(VisionOwner.eyes);
    expect(log, [
      'open front',
      'close front',
      'open back',
      'close back',
      'open front',
    ]);
    expect(v.maxOpen, 1);
  });

  test('parallel requests are serialised (still one camera)', () async {
    await Future.wait([
      v.acquire(VisionOwner.eyes),
      v.acquire(VisionOwner.inspect, lens: CameraLens.back),
      v.acquire(VisionOwner.live, lens: CameraLens.back),
    ]);
    expect(v.maxOpen, 1);
    expect(v.owner, VisionOwner.live);
  });

  test(
    'a lower priority cannot take the camera from the live screen',
    () async {
      await v.acquire(VisionOwner.live, lens: CameraLens.back);
      expect(await v.acquire(VisionOwner.eyes), isNull);
      expect(v.owner, VisionOwner.live);
    },
  );

  test('the camera toggle off closes it now and refuses new opens', () async {
    var revoked = 0;
    await v.acquire(VisionOwner.eyes, onRevoked: () => revoked++);
    enabled = false;
    v.refresh();
    await v.releaseAll();
    expect(v.isOpen, isFalse);
    expect(revoked, 1);
    expect(log.last, 'close front');
    expect(await v.acquire(VisionOwner.eyes), isNull);
  });

  test('background closes the camera; nothing opens until visible', () async {
    await v.acquire(VisionOwner.live, lens: CameraLens.back);
    v.setForeground(false);
    await v.releaseAll();
    expect(v.isOpen, isFalse);
    expect(await v.acquire(VisionOwner.eyes), isNull);
    v.setForeground(true);
    expect(await v.acquire(VisionOwner.eyes), isNotNull);
  });

  test('eyes: back-camera look, then the front eyes come back', () async {
    final eyes = RobotEyes(
      camera: VisionEyeCamera(v),
      busy: () => false,
      onGaze: (_) {},
      onReact: (_) async {},
      interval: const Duration(hours: 1),
    );
    await eyes.setWanted(true);
    expect(v.lens, CameraLens.front);
    final jpeg = await eyes.inspect();
    expect(jpeg, [CameraLens.back.index]);
    expect(v.lens, CameraLens.front, reason: 'eyes reopened');
    expect(eyes.active, isTrue);
    expect(v.maxOpen, 1);
    eyes.dispose();
  });

  test('eyes stop when the camera is taken away', () async {
    final eyes = RobotEyes(
      camera: VisionEyeCamera(v),
      busy: () => false,
      onGaze: (_) {},
      onReact: (_) async {},
      interval: const Duration(hours: 1),
    );
    await eyes.setWanted(true);
    expect(eyes.active, isTrue);
    enabled = false;
    await v.releaseAll();
    expect(eyes.active, isFalse);
    eyes.dispose();
  });
}
