import 'dart:async';
import 'dart:typed_data';

import 'protocol.dart';
import 'robot_transport.dart';

/// Minimal BLE abstraction. v1 ships NO implementation (no BLE plugin is
/// bundled); a future build plugs one in (e.g. flutter_reactive_ble).
abstract class BleLink {
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<int> requestMtu(int mtu);
  Future<void> write(String characteristicUuid, Uint8List data);
  Stream<Uint8List> notifications(String characteristicUuid);
}

/// Skeleton (no BLE plugin bundled) behind the "Robot (experimental)" flag.
class BleTransport extends RobotTransport with AckTracker {
  BleTransport({this.link, required this.deviceId});

  final BleLink? link;
  final String deviceId;
  final _events = StreamController<RobotMessage>.broadcast();
  final _conn = StreamController<RobotConnection>.broadcast();
  final _reassembler = BleReassembler();
  RobotConnection _state = RobotConnection.disconnected;
  RobotInfo? _info;
  int _mtu = 23;
  StreamSubscription<Uint8List>? _notifySub;
  Timer? _heartbeat;
  DateTime _lastSeen = DateTime.now();

  @override
  String get id => 'ble';
  @override
  String get label => 'Bluetooth LE';
  @override
  RobotConnection get connection => _state;
  @override
  Stream<RobotConnection> get connectionChanges => _conn.stream;
  @override
  Stream<RobotMessage> get events => _events.stream;
  @override
  RobotInfo? get info => _info;

  void _set(RobotConnection s) {
    _state = s;
    _conn.add(s);
  }

  @override
  Future<void> connect() async {
    final l = link;
    if (l == null) {
      _set(RobotConnection.failed);
      throw UnsupportedError(
        'No BLE implementation is bundled in this build (v1).',
      );
    }
    _set(RobotConnection.connecting);
    await l.connect(deviceId);
    _mtu = await l.requestMtu(247);
    _notifySub = l.notifications(RobotProtocol.eventCharUuid).listen(_onFrame);
    final ack = await send(
      const RobotMessage(
        type: 'system.hello',
        payload: {'protocol': RobotProtocol.version, 'app': 'sahbi'},
      ),
      awaitAck: true,
    );
    if (ack?.type != 'ack' && ack?.type != 'system.hello_ack') {
      _set(RobotConnection.failed);
      return;
    }
    _info = RobotInfo.fromHelloAck(ack!.payload);
    _set(RobotConnection.connected);
    _heartbeat = Timer.periodic(RobotProtocol.heartbeatInterval, (_) {
      if (DateTime.now().difference(_lastSeen) >
          RobotProtocol.heartbeatTimeout) {
        disconnect();
        return;
      }
      send(const RobotMessage(type: 'system.ping')).ignore();
    });
  }

  void _onFrame(Uint8List frame) {
    try {
      final full = _reassembler.add(frame);
      if (full == null) return;
      final m = RobotCodec.decode(full);
      _lastSeen = DateTime.now();
      if (m.type == 'system.hello_ack') {
        resolveAck(RobotMessage(type: 'ack', payload: m.payload));
      }
      resolveAck(m);
      _events.add(m);
    } on ProtocolException catch (e) {
      _events.add(
        RobotMessage(
          type: 'error',
          payload: {'code': e.code, 'message': e.message},
        ),
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _heartbeat?.cancel();
    await _notifySub?.cancel();
    failAllPending();
    await link?.disconnect();
    _info = null;
    _set(RobotConnection.disconnected);
  }

  @override
  Future<RobotMessage?> send(
    RobotMessage message, {
    bool awaitAck = false,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final l = link;
    if (l == null) throw UnsupportedError('No BLE implementation bundled');
    final seq = nextSeq();
    final bytes = RobotCodec.encode(message.withSeq(seq));
    final ack = trackAck(seq, awaitAck, timeout);
    for (final f in BleFraming.fragment(bytes, seq, mtu: _mtu)) {
      await l.write(RobotProtocol.commandCharUuid, f);
    }
    return ack;
  }
}
