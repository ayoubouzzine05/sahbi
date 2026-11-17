import 'dart:convert';
import 'dart:typed_data';

/// SAHBI Robot Protocol v1 — see docs/ROBOT_PROTOCOL.md.
abstract final class RobotProtocol {
  static const version = 1;

  /// Custom 128-bit UUIDs (randomly generated for SAHBI, not assigned by SIG).
  static const serviceUuid = '7a1b0001-5a48-4249-9c3e-6d0b5e1f2a10';
  static const commandCharUuid =
      '7a1b0002-5a48-4249-9c3e-6d0b5e1f2a10'; // write
  static const eventCharUuid = '7a1b0003-5a48-4249-9c3e-6d0b5e1f2a10'; // notify
  static const telemetryCharUuid =
      '7a1b0004-5a48-4249-9c3e-6d0b5e1f2a10'; // notify

  static const heartbeatInterval = Duration(seconds: 2);
  static const heartbeatTimeout = Duration(seconds: 6);
  static const motorWatchdog = Duration(milliseconds: 500);

  /// Safety limits enforced on BOTH sides (app clamps, firmware must too).
  static const maxMotorSpeed = 0.5; // normalised -1..1 → capped
  static const maxMotorDurationMs = 2000;

  static const commands = {
    'system.hello',
    'system.ping',
    'system.reboot',
    'system.ota_info',
    'face.set_emotion',
    'face.look',
    'face.speak_start',
    'face.speak_stop',
    'face.viseme',
    'audio.play',
    'audio.stop',
    'audio.volume',
    'audio.stream',
    'sensor.subscribe',
    'motor.move',
    'motor.stop',
  };

  static const events = {
    'system.hello_ack',
    'system.pong',
    'system.ota_info',
    'ack',
    'error',
    'sensor.touch',
    'sensor.presence',
    'sensor.imu',
    'sensor.battery',
    'telemetry',
  };
}

/// Protocol error codes.
abstract final class RobotError {
  static const unsupportedVersion = 1;
  static const unknownCommand = 2;
  static const badPayload = 3;
  static const busy = 4;
  static const safetyLimit = 5;
  static const auth = 6;
  static const lowBattery = 7;
  static const internal = 8;
  static const timeout = 9;
}

class ProtocolException implements Exception {
  ProtocolException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'ProtocolException($code: $message)';
}

class RobotMessage {
  const RobotMessage({
    required this.type,
    this.seq = 0,
    this.payload = const {},
    this.ackRequested = false,
    this.v = RobotProtocol.version,
  });

  final int v;
  final int seq;
  final String type;
  final Map<String, dynamic> payload;
  final bool ackRequested;

  Map<String, dynamic> toJson() => {
    'v': v,
    'seq': seq,
    'type': type,
    if (payload.isNotEmpty) 'payload': payload,
    if (ackRequested) 'ack': true,
  };

  RobotMessage withSeq(int s) => RobotMessage(
    type: type,
    seq: s,
    payload: payload,
    ackRequested: ackRequested,
    v: v,
  );

  @override
  String toString() => 'RobotMessage(#$seq $type $payload)';
}

/// JSON message codec (WebSocket uses this directly; BLE wraps it in frames).
abstract final class RobotCodec {
  static Uint8List encode(RobotMessage m) {
    validate(m);
    return Uint8List.fromList(utf8.encode(jsonEncode(m.toJson())));
  }

  static RobotMessage decode(List<int> bytes) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw ProtocolException(RobotError.badPayload, 'invalid JSON');
    }
    if (j is! Map<String, dynamic>) {
      throw ProtocolException(RobotError.badPayload, 'not an object');
    }
    final v = j['v'];
    if (v is! int) throw ProtocolException(RobotError.badPayload, 'missing v');
    if (v != RobotProtocol.version) {
      throw ProtocolException(RobotError.unsupportedVersion, 'version $v');
    }
    final type = j['type'];
    final seq = j['seq'];
    if (type is! String || seq is! int || seq < 0 || seq > 0xFFFF) {
      throw ProtocolException(RobotError.badPayload, 'missing type/seq');
    }
    if (!RobotProtocol.commands.contains(type) &&
        !RobotProtocol.events.contains(type)) {
      throw ProtocolException(RobotError.unknownCommand, type);
    }
    final payload = j['payload'];
    if (payload != null && payload is! Map<String, dynamic>) {
      throw ProtocolException(
        RobotError.badPayload,
        'payload must be an object',
      );
    }
    final m = RobotMessage(
      v: v,
      seq: seq,
      type: type,
      payload: (payload as Map<String, dynamic>?) ?? const {},
      ackRequested: j['ack'] == true,
    );
    validate(m);
    return m;
  }

  /// Payload validation + safety limits.
  static void validate(RobotMessage m) {
    final p = m.payload;
    void need(bool ok, String what) {
      if (!ok) {
        throw ProtocolException(RobotError.badPayload, '${m.type}: $what');
      }
    }

    switch (m.type) {
      case 'face.set_emotion':
        need(p['emotion'] is String, 'emotion');
        final i = p['intensity'];
        need(i == null || (i is num && i >= 0 && i <= 1), 'intensity 0..1');
      case 'face.look':
        need(p['x'] is num && p['y'] is num, 'x,y');
        need(
          (p['x'] as num).abs() <= 1 && (p['y'] as num).abs() <= 1,
          'x,y in -1..1',
        );
      case 'audio.volume':
        need(
          p['level'] is num &&
              (p['level'] as num) >= 0 &&
              (p['level'] as num) <= 1,
          'level 0..1',
        );
      case 'motor.move':
        need(
          p['left'] is num && p['right'] is num && p['duration_ms'] is int,
          'left,right,duration_ms',
        );
        final l = (p['left'] as num).abs();
        final r = (p['right'] as num).abs();
        final d = p['duration_ms'] as int;
        if (l > RobotProtocol.maxMotorSpeed ||
            r > RobotProtocol.maxMotorSpeed ||
            d <= 0 ||
            d > RobotProtocol.maxMotorDurationMs) {
          throw ProtocolException(
            RobotError.safetyLimit,
            'motor.move exceeds limits',
          );
        }
      case 'sensor.subscribe':
        need(p['sensors'] is List, 'sensors');
      case 'error':
        need(p['code'] is int, 'code');
    }
  }
}

/// CRC-16/CCITT-FALSE.
int crc16(List<int> data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc ^= (b & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}

/// BLE framing: 6-byte header + chunk; CRC16 of the whole message is appended
/// to the message before fragmentation.
///
/// header: [0] version, [1] flags (bit0 first, bit1 last), [2..3] seq (BE),
///         [4] fragment index, [5] fragment count
abstract final class BleFraming {
  static const headerSize = 6;

  static List<Uint8List> fragment(Uint8List message, int seq, {int mtu = 23}) {
    // ATT payload = MTU - 3.
    final chunk = mtu - 3 - headerSize;
    if (chunk < 1) throw ArgumentError('MTU too small');
    final crc = crc16(message);
    final body = Uint8List.fromList([...message, crc >> 8, crc & 0xFF]);
    final count = (body.length / chunk).ceil();
    if (count > 255) {
      throw ProtocolException(RobotError.badPayload, 'message too large');
    }
    return [
      for (var i = 0; i < count; i++)
        Uint8List.fromList([
          RobotProtocol.version,
          (i == 0 ? 1 : 0) | (i == count - 1 ? 2 : 0),
          (seq >> 8) & 0xFF,
          seq & 0xFF,
          i,
          count,
          ...body.sublist(
            i * chunk,
            (i + 1) * chunk > body.length ? body.length : (i + 1) * chunk,
          ),
        ]),
    ];
  }
}

/// Reassembles BLE fragments (any order) and checks the CRC.
class BleReassembler {
  final Map<int, Map<int, List<int>>> _parts = {};
  final Map<int, int> _counts = {};

  /// Returns the full message when the last missing fragment arrives.
  Uint8List? add(List<int> frame) {
    if (frame.length < BleFraming.headerSize) {
      throw ProtocolException(RobotError.badPayload, 'short frame');
    }
    if (frame[0] != RobotProtocol.version) {
      throw ProtocolException(
        RobotError.unsupportedVersion,
        'frame version ${frame[0]}',
      );
    }
    final seq = (frame[2] << 8) | frame[3];
    final index = frame[4];
    final count = frame[5];
    if (count == 0 || index >= count) {
      throw ProtocolException(RobotError.badPayload, 'bad fragment index');
    }
    _counts[seq] = count;
    (_parts[seq] ??= {})[index] = frame.sublist(BleFraming.headerSize);
    if (_parts[seq]!.length < count) return null;
    final body = <int>[for (var i = 0; i < count; i++) ..._parts[seq]![i]!];
    _parts.remove(seq);
    _counts.remove(seq);
    if (body.length < 2) {
      throw ProtocolException(RobotError.badPayload, 'empty');
    }
    final msg = body.sublist(0, body.length - 2);
    final crc = (body[body.length - 2] << 8) | body[body.length - 1];
    if (crc16(msg) != crc) {
      throw ProtocolException(RobotError.badPayload, 'CRC mismatch');
    }
    return Uint8List.fromList(msg);
  }

  int get pending => _parts.length;
}
