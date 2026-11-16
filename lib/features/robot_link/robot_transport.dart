import 'dart:async';

import 'protocol.dart';

enum RobotConnection { disconnected, connecting, connected, failed }

class RobotInfo {
  const RobotInfo({
    required this.deviceId,
    required this.firmware,
    required this.capabilities,
    this.battery,
  });
  final String deviceId;
  final String firmware;
  final Set<String> capabilities;
  final double? battery;

  static RobotInfo fromHelloAck(Map<String, dynamic> p) => RobotInfo(
        deviceId: '${p['device_id'] ?? 'unknown'}',
        firmware: '${p['fw'] ?? '?'}',
        capabilities: {for (final c in (p['capabilities'] as List? ?? const [])) '$c'},
        battery: (p['battery'] as num?)?.toDouble(),
      );
}

/// Transport-agnostic link to a face/ears/mouth device.
abstract class RobotTransport {
  String get id;
  String get label;
  RobotConnection get connection;
  Stream<RobotConnection> get connectionChanges;

  /// Events sent by the device (touch, presence, battery, acks, errors…).
  Stream<RobotMessage> get events;
  RobotInfo? get info;

  Future<void> connect();
  Future<void> disconnect();

  /// Sends a command; when [awaitAck] it completes with the ack/error or
  /// throws [ProtocolException] (timeout code) after [timeout].
  Future<RobotMessage?> send(
    RobotMessage message, {
    bool awaitAck = false,
    Duration timeout = const Duration(seconds: 2),
  });
}

/// Common seq/ack bookkeeping for transports.
mixin AckTracker on RobotTransport {
  int _seq = 0;
  final Map<int, Completer<RobotMessage>> _pending = {};

  int nextSeq() => _seq = (_seq + 1) & 0xFFFF;

  Future<RobotMessage?> trackAck(int seq, bool awaitAck, Duration timeout) {
    if (!awaitAck) return Future.value(null);
    final c = Completer<RobotMessage>();
    _pending[seq] = c;
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(seq);
      throw ProtocolException(RobotError.timeout, 'no ack for #$seq');
    });
  }

  /// Call for every incoming message.
  void resolveAck(RobotMessage m) {
    if (m.type != 'ack' && m.type != 'error') return;
    final ref = m.payload['ref'];
    if (ref is int) _pending.remove(ref)?.complete(m);
  }

  void failAllPending() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(ProtocolException(RobotError.timeout, 'disconnected'));
    }
    _pending.clear();
  }
}
