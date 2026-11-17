import 'dart:async';

import 'package:flutter/foundation.dart';

import '../personality/companion_controller.dart';
import 'protocol.dart';
import 'robot_transport.dart';

/// Mirrors the companion's face state to the active transport and surfaces
/// robot events (touch wakes Sahbi up, etc.).
class RobotLinkController extends ChangeNotifier {
  RobotLinkController({required this.companion});

  final CompanionController companion;
  RobotTransport? transport;
  RobotConnection connection = RobotConnection.disconnected;
  final List<String> eventLog = [];
  String? lastError;
  StreamSubscription<RobotMessage>? _events;
  StreamSubscription<RobotConnection>? _conn;
  String? _lastSentEmotion;

  Future<void> use(RobotTransport t) async {
    await disconnect();
    transport = t;
    _conn = t.connectionChanges.listen((c) {
      connection = c;
      notifyListeners();
    });
    _events = t.events.listen((m) {
      eventLog.insert(
        0,
        '${DateTime.now().toIso8601String().substring(11, 19)} ${m.type} ${m.payload}',
      );
      if (eventLog.length > 50) eventLog.removeLast();
      if (m.type == 'sensor.touch' ||
          (m.type == 'sensor.presence' && m.payload['present'] == true)) {
        companion.interact();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> connect() async {
    final t = transport;
    if (t == null) return;
    lastError = null;
    try {
      await t.connect();
      companion.addListener(_mirror);
      _mirror();
    } catch (e) {
      lastError = '$e';
    }
    connection = t.connection;
    notifyListeners();
  }

  void _mirror() {
    final t = transport;
    if (t == null || t.connection != RobotConnection.connected) return;
    final e = companion.emotion.name;
    if (e == _lastSentEmotion) return;
    _lastSentEmotion = e;
    t
        .send(
          RobotMessage(
            type: 'face.set_emotion',
            payload: {'emotion': e, 'intensity': companion.intensity},
          ),
        )
        .catchError((Object err) {
          lastError = '$err';
          notifyListeners();
          return null;
        });
  }

  Future<RobotMessage?> send(RobotMessage m) async {
    final t = transport;
    if (t == null) return null;
    try {
      return await t.send(m, awaitAck: true);
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return null;
    }
  }

  Future<void> disconnect() async {
    companion.removeListener(_mirror);
    _lastSentEmotion = null;
    await transport?.disconnect();
    await _events?.cancel();
    await _conn?.cancel();
    connection = RobotConnection.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    companion.removeListener(_mirror);
    _events?.cancel();
    _conn?.cancel();
    super.dispose();
  }
}
