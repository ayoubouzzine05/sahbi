import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/robot_link/protocol.dart';
import 'package:sahbi/features/robot_link/robot_transport.dart';
import 'package:sahbi/features/robot_link/simulated_robot_transport.dart';

Matcher throwsProtocol(int code) =>
    throwsA(isA<ProtocolException>().having((e) => e.code, 'code', code));

Uint8List raw(Map<String, dynamic> j) =>
    Uint8List.fromList(utf8.encode(jsonEncode(j)));

void main() {
  group('crc16 (CCITT-FALSE)', () {
    test('standard check value for "123456789" is 0x29B1', () {
      expect(crc16(ascii.encode('123456789')), 0x29B1);
    });
    test(
      'empty input is the init value',
      () => expect(crc16(const []), 0xFFFF),
    );
  });

  group('RobotCodec', () {
    test('round-trips a command with payload and ack flag', () {
      const m = RobotMessage(
        type: 'face.set_emotion',
        seq: 42,
        payload: {'emotion': 'happy', 'intensity': 0.7},
        ackRequested: true,
      );
      final back = RobotCodec.decode(RobotCodec.encode(m));
      expect(back.type, 'face.set_emotion');
      expect(back.seq, 42);
      expect(back.payload['emotion'], 'happy');
      expect(back.ackRequested, isTrue);
    });
    test('omits empty payload and false ack from the wire format', () {
      final j = jsonDecode(
        utf8.decode(
          RobotCodec.encode(const RobotMessage(type: 'system.ping', seq: 1)),
        ),
      );
      expect(j, {'v': 1, 'seq': 1, 'type': 'system.ping'});
    });
    test('rejects invalid JSON / non-objects', () {
      expect(
        () => RobotCodec.decode(utf8.encode('{nope')),
        throwsProtocol(RobotError.badPayload),
      );
      expect(
        () => RobotCodec.decode(utf8.encode('[1,2]')),
        throwsProtocol(RobotError.badPayload),
      );
    });
    test('rejects other protocol versions', () {
      expect(
        () => RobotCodec.decode(raw({'v': 2, 'seq': 1, 'type': 'system.ping'})),
        throwsProtocol(RobotError.unsupportedVersion),
      );
    });
    test('rejects missing/out-of-range seq', () {
      expect(
        () => RobotCodec.decode(raw({'v': 1, 'type': 'system.ping'})),
        throwsProtocol(RobotError.badPayload),
      );
      expect(
        () => RobotCodec.decode(
          raw({'v': 1, 'seq': 70000, 'type': 'system.ping'}),
        ),
        throwsProtocol(RobotError.badPayload),
      );
    });
    test('rejects unknown commands', () {
      expect(
        () => RobotCodec.decode(raw({'v': 1, 'seq': 1, 'type': 'laser.fire'})),
        throwsProtocol(RobotError.unknownCommand),
      );
    });
    test('rejects non-object payloads', () {
      expect(
        () => RobotCodec.decode(
          raw({
            'v': 1,
            'seq': 1,
            'type': 'system.ping',
            'payload': [1],
          }),
        ),
        throwsProtocol(RobotError.badPayload),
      );
    });
  });

  group('validation & safety limits', () {
    void bad(String type, Map<String, dynamic> p, int code) => expect(
      () => RobotCodec.validate(RobotMessage(type: type, payload: p)),
      throwsProtocol(code),
    );
    void ok(String type, Map<String, dynamic> p) => expect(
      () => RobotCodec.validate(RobotMessage(type: type, payload: p)),
      returnsNormally,
    );

    test('face.set_emotion', () {
      ok('face.set_emotion', {'emotion': 'sad'});
      bad('face.set_emotion', {}, RobotError.badPayload);
      bad('face.set_emotion', {
        'emotion': 'sad',
        'intensity': 1.5,
      }, RobotError.badPayload);
    });
    test('face.look coordinates are within -1..1', () {
      ok('face.look', {'x': -1, 'y': 0.5});
      bad('face.look', {'x': 2, 'y': 0}, RobotError.badPayload);
    });
    test('audio.volume 0..1', () {
      ok('audio.volume', {'level': 0});
      bad('audio.volume', {'level': -0.1}, RobotError.badPayload);
    });
    test('motor.move speed is capped at 0.5 and duration 1..2000 ms', () {
      ok('motor.move', {'left': 0.5, 'right': -0.5, 'duration_ms': 2000});
      bad('motor.move', {
        'left': 0.6,
        'right': 0,
        'duration_ms': 100,
      }, RobotError.safetyLimit);
      bad('motor.move', {
        'left': 0.1,
        'right': 0.1,
        'duration_ms': 2001,
      }, RobotError.safetyLimit);
      bad('motor.move', {
        'left': 0.1,
        'right': 0.1,
        'duration_ms': 0,
      }, RobotError.safetyLimit);
      bad('motor.move', {
        'left': 0.1,
        'right': 0.1,
        'duration_ms': 1.5,
      }, RobotError.badPayload);
    });
    test('the encoder refuses unsafe commands before they hit the wire', () {
      expect(
        () => RobotCodec.encode(
          const RobotMessage(
            type: 'motor.move',
            payload: {'left': 1, 'right': 1, 'duration_ms': 100},
          ),
        ),
        throwsProtocol(RobotError.safetyLimit),
      );
    });
  });

  group('BLE framing', () {
    Uint8List msg(int n) =>
        Uint8List.fromList(List.generate(n, (i) => (i * 7) & 0xFF));

    test(
      'frames never exceed the ATT payload (MTU - 3) and carry the header',
      () {
        for (final mtu in [23, 64, 185, 247]) {
          final frames = BleFraming.fragment(msg(500), 0x1234, mtu: mtu);
          for (var i = 0; i < frames.length; i++) {
            final f = frames[i];
            expect(f.length, lessThanOrEqualTo(mtu - 3), reason: 'mtu $mtu');
            expect(f[0], RobotProtocol.version);
            expect((f[2] << 8) | f[3], 0x1234);
            expect(f[4], i);
            expect(f[5], frames.length);
            expect(f[1] & 1, i == 0 ? 1 : 0, reason: 'first flag');
            expect(
              f[1] & 2,
              i == frames.length - 1 ? 2 : 0,
              reason: 'last flag',
            );
          }
        }
      },
    );
    test('reassembles in order and out of order', () {
      final m = msg(300);
      final frames = BleFraming.fragment(m, 7);
      final r1 = BleReassembler();
      Uint8List? out;
      for (final f in frames) {
        out = r1.add(f);
      }
      expect(out, m);
      final r2 = BleReassembler();
      Uint8List? out2;
      for (final f in frames.reversed) {
        out2 = r2.add(f) ?? out2;
      }
      expect(out2, m);
    });
    test('interleaved messages with different seq do not mix', () {
      final a = msg(100), b = Uint8List.fromList(List.filled(90, 9));
      final fa = BleFraming.fragment(a, 1), fb = BleFraming.fragment(b, 2);
      final r = BleReassembler();
      final done = <Uint8List>[];
      for (var i = 0; i < fa.length || i < fb.length; i++) {
        if (i < fa.length) r.add(fa[i]).let(done.add);
        if (i < fb.length) r.add(fb[i]).let(done.add);
      }
      expect(done, containsAll([a, b]));
    });
    test('a corrupted byte is caught by the CRC', () {
      final frames = BleFraming.fragment(msg(40), 3);
      frames.first[8] ^= 0xFF;
      final r = BleReassembler();
      expect(() {
        for (final f in frames) {
          r.add(f);
        }
      }, throwsProtocol(RobotError.badPayload));
    });
    test('short frames and wrong frame versions are rejected', () {
      expect(
        () => BleReassembler().add([1, 2, 3]),
        throwsProtocol(RobotError.badPayload),
      );
      final f = BleFraming.fragment(msg(5), 1).first..[0] = 9;
      expect(
        () => BleReassembler().add(f),
        throwsProtocol(RobotError.unsupportedVersion),
      );
    });
  });

  group('SimulatedRobotTransport (end-to-end over simulated BLE frames)', () {
    late SimulatedRobotTransport sim;
    setUp(() => sim = SimulatedRobotTransport());
    tearDown(() => sim.disconnect());

    test('handshake: hello → hello_ack populates device info', () async {
      final states = <RobotConnection>[];
      sim.connectionChanges.listen(states.add);
      await sim.connect();
      expect(sim.connection, RobotConnection.connected);
      expect(sim.info, isNotNull);
      expect(sim.info!.deviceId, 'SIM-0001');
      expect(sim.log.first, 'system.hello');
      await Future<void>.delayed(Duration.zero);
      expect(states, [RobotConnection.connecting, RobotConnection.connected]);
    });
    test('commands are acked and change simulated device state', () async {
      await sim.connect();
      final ack = await sim.send(
        const RobotMessage(
          type: 'face.set_emotion',
          payload: {'emotion': 'happy'},
        ),
        awaitAck: true,
      );
      expect(ack!.type, 'ack');
      expect(sim.faceEmotion, 'happy');
      await sim.send(
        const RobotMessage(type: 'audio.volume', payload: {'level': 0.2}),
        awaitAck: true,
      );
      expect(sim.volume, 0.2);
    });
    test(
      'motor watchdog stops the motor within 500 ms even for longer moves',
      () async {
        await sim.connect();
        await sim.send(
          const RobotMessage(
            type: 'motor.move',
            payload: {'left': 0.3, 'right': 0.3, 'duration_ms': 2000},
          ),
          awaitAck: true,
        );
        expect(sim.motorRunning, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(sim.motorRunning, isFalse);
      },
    );
    test('motor.stop stops immediately', () async {
      await sim.connect();
      await sim.send(
        const RobotMessage(
          type: 'motor.move',
          payload: {'left': 0.3, 'right': 0.3, 'duration_ms': 400},
        ),
        awaitAck: true,
      );
      await sim.send(const RobotMessage(type: 'motor.stop'), awaitAck: true);
      expect(sim.motorRunning, isFalse);
    });
    test('ping produces a pong event referencing the request', () async {
      await sim.connect();
      final pong = sim.events.firstWhere((e) => e.type == 'system.pong');
      await sim.send(const RobotMessage(type: 'system.ping'), awaitAck: true);
      expect((await pong).payload['ref'], isA<int>());
    });
    test('works with a large MTU too', () async {
      final big = SimulatedRobotTransport(mtu: 247);
      await big.connect();
      expect(big.connection, RobotConnection.connected);
      await big.disconnect();
    });
    test('sending while disconnected fails honestly', () async {
      expect(
        () => sim.send(const RobotMessage(type: 'system.ping')),
        throwsProtocol(RobotError.timeout),
      );
    });
  });
}

extension<T extends Object> on T? {
  void let(void Function(T) f) {
    final v = this;
    if (v != null) f(v);
  }
}
