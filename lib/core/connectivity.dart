import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'backend_client.dart';

@immutable
class NetState {
  const NetState({
    this.hasNetwork = true,
    this.backendReachable,
    this.health,
    this.lastError,
    this.lastCheck,
  });

  /// OS reports a network interface (not proof of internet).
  final bool hasNetwork;

  /// null = not checked yet / no backend URL.
  final bool? backendReachable;
  final HealthStatus? health;
  final BackendErrorCode? lastError;
  final DateTime? lastCheck;

  bool get online => hasNetwork && backendReachable == true;
  bool get aiConfigured => online && (health?.configured('llm') ?? false);
  bool get searchConfigured => online && (health?.configured('search') ?? false);
  bool get cloudSttConfigured => online && (health?.configured('stt') ?? false);
  bool get cloudTtsConfigured => online && (health?.configured('tts') ?? false);
}

/// connectivity_plus for interface changes + a real reachability check
/// against `/v1/health` (every 60 s and on every change).
class ConnectivityMonitor extends ValueNotifier<NetState> {
  ConnectivityMonitor(this._client, {Connectivity? connectivity})
      : _connectivity = connectivity,
        super(const NetState());

  final BackendClient _client;
  final Connectivity? _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  bool _checking = false;

  void start() {
    final c = _connectivity ?? Connectivity();
    _sub = c.onConnectivityChanged.listen((r) {
      final has = r.any((x) => x != ConnectivityResult.none);
      value = NetState(
        hasNetwork: has,
        backendReachable: has ? value.backendReachable : false,
        health: value.health,
        lastError: has ? value.lastError : BackendErrorCode.noInternet,
        lastCheck: value.lastCheck,
      );
      check();
    });
    c.checkConnectivity().then((r) {
      value = NetState(
        hasNetwork: r.any((x) => x != ConnectivityResult.none),
        backendReachable: value.backendReachable,
        health: value.health,
        lastCheck: value.lastCheck,
      );
      check();
    }).catchError((Object _) {
      check();
    });
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => check());
  }

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      if (!_client.hasBaseUrl) {
        value = NetState(
          hasNetwork: value.hasNetwork,
          backendReachable: null,
          lastError: BackendErrorCode.notConfigured,
          lastCheck: DateTime.now(),
        );
        return;
      }
      final h = await _client.health();
      value = NetState(
        hasNetwork: true,
        backendReachable: true,
        health: h,
        lastCheck: DateTime.now(),
      );
    } on BackendException catch (e) {
      value = NetState(
        hasNetwork: value.hasNetwork && e.code != BackendErrorCode.noInternet
            ? value.hasNetwork
            : value.hasNetwork,
        backendReachable: false,
        health: null,
        lastError: e.code,
        lastCheck: DateTime.now(),
      );
    } catch (_) {
      value = NetState(
        hasNetwork: value.hasNetwork,
        backendReachable: false,
        lastError: BackendErrorCode.server,
        lastCheck: DateTime.now(),
      );
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
