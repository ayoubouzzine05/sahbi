import 'dart:async';

import 'protocol.dart';
import 'robot_transport.dart';

/// The phone itself is the "robot": face commands are rendered on screen.
class LocalPhoneTransport extends RobotTransport with AckTracker {
  LocalPhoneTransport({required this.onFace});

  /// Receives face.* commands to render on the phone.
  final void Function(RobotMessage message) onFace;
  final _events = StreamController<RobotMessage>.broadcast();
  final _conn = StreamController<RobotConnection>.broadcast();
  RobotConnection _state = RobotConnection.disconnected;

  @override
  String get id => 'local';
  @override
  String get label => 'This phone';
  @override
  RobotConnection get connection => _state;
  @override
  Stream<RobotConnection> get connectionChanges => _conn.stream;
  @override
  Stream<RobotMessage> get events => _events.stream;
  @override
  RobotInfo? get info => _state == RobotConnection.connected
      ? const RobotInfo(deviceId: 'phone', firmware: 'app', capabilities: {'face', 'audio'})
      : null;

  @override
  Future<void> connect() async {
    _state = RobotConnection.connected;
    _conn.add(_state);
  }

  @override
  Future<void> disconnect() async {
    _state = RobotConnection.disconnected;
    _conn.add(_state);
  }

  @override
  Future<RobotMessage?> send(RobotMessage message, {bool awaitAck = false, Duration timeout = const Duration(seconds: 2)}) async {
    RobotCodec.validate(message);
    final seq = nextSeq();
    if (message.type.startsWith('face.')) {
      onFace(message.withSeq(seq));
      return awaitAck ? RobotMessage(type: 'ack', seq: seq, payload: {'ref': seq}) : null;
    }
    final err = RobotMessage(type: 'error', seq: seq, payload: {'ref': seq, 'code': RobotError.unknownCommand});
    _events.add(err);
    return awaitAck ? err : null;
  }
}
