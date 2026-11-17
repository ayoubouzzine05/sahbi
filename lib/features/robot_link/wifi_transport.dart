import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';
import 'robot_transport.dart';

/// Wi-Fi WebSocket transport (ws(s)://host:port/sahbi). JSON text frames,
/// same message schema as BLE without fragmentation. Untested against real
/// hardware (none exists yet).
class WifiTransport extends RobotTransport with AckTracker {
  WifiTransport({required this.url, this.authToken});

  final Uri url;

  /// Pairing token obtained out of band (e.g. QR code on the robot screen).
  final String? authToken;
  final _events = StreamController<RobotMessage>.broadcast();
  final _conn = StreamController<RobotConnection>.broadcast();
  RobotConnection _state = RobotConnection.disconnected;
  RobotInfo? _info;
  WebSocket? _ws;
  Timer? _heartbeat;
  DateTime _lastSeen = DateTime.now();
  Completer<RobotMessage>? _hello;

  @override
  String get id => 'wifi';
  @override
  String get label => 'Wi-Fi (WebSocket)';
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
    _set(RobotConnection.connecting);
    try {
      _ws = await WebSocket.connect(
        url.toString(),
        headers: {if (authToken != null) 'authorization': 'Bearer $authToken'},
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      _set(RobotConnection.failed);
      rethrow;
    }
    _ws!.listen(
      _onData,
      onDone: () => disconnect(),
      onError: (_) => disconnect(),
    );
    _hello = Completer<RobotMessage>();
    await send(
      const RobotMessage(
        type: 'system.hello',
        payload: {'protocol': RobotProtocol.version, 'app': 'sahbi'},
      ),
    );
    final ack = await _hello!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        throw ProtocolException(RobotError.timeout, 'no hello_ack');
      },
    );
    _info = RobotInfo.fromHelloAck(ack.payload);
    _set(RobotConnection.connected);
    _heartbeat = Timer.periodic(RobotProtocol.heartbeatInterval, (_) {
      if (DateTime.now().difference(_lastSeen) >
          RobotProtocol.heartbeatTimeout) {
        disconnect();
      } else {
        send(const RobotMessage(type: 'system.ping')).ignore();
      }
    });
  }

  void _onData(dynamic data) {
    try {
      final m = RobotCodec.decode(
        data is String ? utf8.encode(data) : data as List<int>,
      );
      _lastSeen = DateTime.now();
      if (m.type == 'system.hello_ack') {
        _hello?.complete(m);
        return;
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
    failAllPending();
    await _ws?.close();
    _ws = null;
    _info = null;
    if (_state != RobotConnection.disconnected) {
      _set(RobotConnection.disconnected);
    }
  }

  @override
  Future<RobotMessage?> send(
    RobotMessage message, {
    bool awaitAck = false,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final ws = _ws;
    if (ws == null) {
      throw ProtocolException(RobotError.timeout, 'not connected');
    }
    final seq = nextSeq();
    final m = message.withSeq(seq);
    final ack = trackAck(seq, awaitAck, timeout);
    ws.add(utf8.decode(RobotCodec.encode(m)));
    return ack;
  }
}
