import 'dart:async';
import 'dart:typed_data';

import 'protocol.dart';
import 'robot_transport.dart';

/// In-process mock robot used by tests and the debug screen.
/// Every message goes through the real codec AND BLE fragmentation at
/// MTU 23 to exercise the encoder/decoder end-to-end.
class SimulatedRobotTransport extends RobotTransport with AckTracker {
  SimulatedRobotTransport({this.mtu = 23, this.deviceId = 'SIM-0001'});

  final int mtu;
  final String deviceId;
  final _events = StreamController<RobotMessage>.broadcast();
  final _conn = StreamController<RobotConnection>.broadcast();
  final _toDevice = BleReassembler();
  final _toApp = BleReassembler();
  RobotConnection _state = RobotConnection.disconnected;
  RobotInfo? _info;
  Timer? _telemetry;
  Timer? _watchdog;
  int _deviceSeq = 0;

  // Simulated device state (inspectable in tests / debug screen).
  String faceEmotion = 'neutral';
  double volume = 0.5;
  double battery = 0.87;
  bool motorRunning = false;
  final List<String> log = [];

  @override
  String get id => 'sim';
  @override
  String get label => 'Simulated robot';
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
    final ack = await send(
      const RobotMessage(type: 'system.hello', payload: {'protocol': RobotProtocol.version, 'app': 'sahbi'}),
      awaitAck: true,
    );
    if (ack == null || ack.type != 'system.hello_ack') {
      _set(RobotConnection.failed);
      return;
    }
    _info = RobotInfo.fromHelloAck(ack.payload);
    _set(RobotConnection.connected);
    _telemetry = Timer.periodic(const Duration(seconds: 5), (_) {
      battery = (battery - 0.001).clamp(0, 1);
      _deviceEmit(RobotMessage(type: 'sensor.battery', payload: {'level': battery}));
    });
  }

  @override
  Future<void> disconnect() async {
    _telemetry?.cancel();
    _watchdog?.cancel();
    failAllPending();
    _info = null;
    _set(RobotConnection.disconnected);
  }

  @override
  Future<RobotMessage?> send(RobotMessage message, {bool awaitAck = false, Duration timeout = const Duration(seconds: 2)}) async {
    if (_state == RobotConnection.disconnected && message.type != 'system.hello') {
      throw ProtocolException(RobotError.timeout, 'not connected');
    }
    final seq = nextSeq();
    final m = message.withSeq(seq);
    final bytes = RobotCodec.encode(m);
    final ackFuture = m.type == 'system.hello'
        ? _helloAck(seq, timeout)
        : trackAck(seq, awaitAck || m.ackRequested, timeout);
    // App → device over "BLE".
    for (final f in BleFraming.fragment(bytes, seq, mtu: mtu)) {
      final full = _toDevice.add(f);
      if (full != null) scheduleMicrotask(() => _deviceHandle(full));
    }
    return ackFuture;
  }

  Completer<RobotMessage>? _hello;
  Future<RobotMessage?> _helloAck(int seq, Duration timeout) {
    _hello = Completer<RobotMessage>();
    return _hello!.future.timeout(timeout);
  }

  // ---- device side ------------------------------------------------------
  void _deviceHandle(Uint8List bytes) {
    RobotMessage m;
    try {
      m = RobotCodec.decode(bytes);
    } on ProtocolException catch (e) {
      _deviceEmit(RobotMessage(type: 'error', payload: {'ref': -1, 'code': e.code, 'message': e.message}));
      return;
    }
    log.add(m.type);
    void ack([Map<String, dynamic> extra = const {}]) =>
        _deviceEmit(RobotMessage(type: 'ack', payload: {'ref': m.seq, ...extra}));
    switch (m.type) {
      case 'system.hello':
        if (m.payload['protocol'] != RobotProtocol.version) {
          _deviceEmit(RobotMessage(type: 'error', payload: {'ref': m.seq, 'code': RobotError.unsupportedVersion}));
          return;
        }
        _deviceEmit(RobotMessage(type: 'system.hello_ack', payload: {
          'ref': m.seq,
          'protocol': RobotProtocol.version,
          'device_id': deviceId,
          'fw': 'sim-1.0.0',
          'capabilities': ['face', 'audio', 'touch', 'presence', 'imu', 'battery', 'motor'],
          'battery': battery,
        }));
      case 'system.ping':
        _deviceEmit(RobotMessage(type: 'system.pong', payload: {'ref': m.seq}));
        ack();
      case 'face.set_emotion':
        faceEmotion = '${m.payload['emotion']}';
        ack();
      case 'face.look' || 'face.speak_start' || 'face.speak_stop' || 'face.viseme' || 'sensor.subscribe' || 'audio.play' || 'audio.stop':
        ack();
      case 'audio.volume':
        volume = (m.payload['level'] as num).toDouble();
        ack();
      case 'motor.move':
        motorRunning = true;
        _watchdog?.cancel();
        // Watchdog: stops unless refreshed within the duration (capped).
        final d = m.payload['duration_ms'] as int;
        _watchdog = Timer(Duration(milliseconds: d.clamp(1, RobotProtocol.motorWatchdog.inMilliseconds)), () {
          motorRunning = false;
        });
        ack();
      case 'motor.stop':
        _watchdog?.cancel();
        motorRunning = false;
        ack();
      case 'system.ota_info':
        _deviceEmit(RobotMessage(type: 'system.ota_info', payload: {'ref': m.seq, 'fw': 'sim-1.0.0', 'update_available': false}));
        ack();
      case 'system.reboot':
        ack();
      default:
        _deviceEmit(RobotMessage(type: 'error', payload: {'ref': m.seq, 'code': RobotError.unknownCommand}));
    }
  }

  void _deviceEmit(RobotMessage m) {
    _deviceSeq = (_deviceSeq + 1) & 0xFFFF;
    final msg = m.withSeq(_deviceSeq);
    // Device → app over "BLE".
    for (final f in BleFraming.fragment(RobotCodec.encode(msg), _deviceSeq, mtu: mtu)) {
      final full = _toApp.add(f);
      if (full != null) {
        final decoded = RobotCodec.decode(full);
        if (decoded.type == 'system.hello_ack') {
          _hello?.complete(decoded);
        } else {
          resolveAck(decoded);
          _events.add(decoded);
        }
      }
    }
  }

  /// Debug helper: pretend the user touched the robot.
  void simulateTouch({String zone = 'head'}) =>
      _deviceEmit(RobotMessage(type: 'sensor.touch', payload: {'zone': zone}));

  void simulatePresence(bool present) =>
      _deviceEmit(RobotMessage(type: 'sensor.presence', payload: {'present': present}));
}
