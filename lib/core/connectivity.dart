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
    this.failStreak = 0,
  });

  /// OS reports a network interface (not proof of internet).
  final bool hasNetwork;

  /// null = not checked yet / no backend URL.
  final bool? backendReachable;
  final HealthStatus? health;
  final BackendErrorCode? lastError;
  final DateTime? lastCheck;

  /// Health checks failed in a row (one slow check, e.g. a cold start, is
  /// not reported as "unreachable" when the backend was working).
  final int failStreak;

  bool get online => hasNetwork && backendReachable == true;
  bool get aiConfigured => online && (health?.configured('llm') ?? false);
  bool get searchConfigured =>
      online && (health?.configured('search') ?? false);
  bool get cloudSttConfigured => online && (health?.configured('stt') ?? false);
  bool get cloudTtsConfigured => online && (health?.configured('tts') ?? false);
  bool get liveConfigured => online && (health?.configured('live') ?? false);
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
  Timer? _retry;
  Future<void>? _inflight;

  /// Delay of the quick re-check after a single failed health check.
  Duration retryAfter = const Duration(seconds: 5);

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
    c
        .checkConnectivity()
        .then((r) {
          value = NetState(
            hasNetwork: r.any((x) => x != ConnectivityResult.none),
            backendReachable: value.backendReachable,
            health: value.health,
            lastCheck: value.lastCheck,
          );
          check();
        })
        .catchError((Object _) {
          check();
        });
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => check());
  }

  /// Re-checks backend reachability. Concurrent callers share one request.
  Future<void> check({Duration timeout = const Duration(seconds: 6)}) =>
      _inflight ??= _check(timeout).whenComplete(() => _inflight = null);

  /// Free hosting (e.g. Render) sleeps when idle and needs ~1 min to wake.
  /// Waits for any in-flight check, then retries health with a long timeout.
  Future<void> wake({Duration timeout = const Duration(seconds: 90)}) async {
    final running = _inflight;
    if (running != null) await running;
    if (value.backendReachable == true || !value.hasNetwork) return;
    await check(timeout: timeout);
  }

  Future<void> _check(Duration timeout) async {
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
      final h = await _client.health(timeout: timeout);
      value = NetState(
        hasNetwork: true,
        backendReachable: true,
        health: h,
        lastCheck: DateTime.now(),
      );
    } on BackendException catch (e) {
      _failed(e.code);
    } catch (_) {
      _failed(BackendErrorCode.server);
    }
  }

  /// A backend that was working survives ONE failed check (keeps its last
  /// health, so the voice and the face do not flip); a quick re-check
  /// follows, and a second failure in a row marks it unreachable.
  void _failed(BackendErrorCode code) {
    final streak = value.failStreak + 1;
    final tolerate =
        value.backendReachable == true && streak < 2 && value.hasNetwork;
    value = NetState(
      hasNetwork: value.hasNetwork,
      backendReachable: tolerate ? true : false,
      health: tolerate ? value.health : null,
      lastError: code,
      lastCheck: DateTime.now(),
      failStreak: streak,
    );
    if (tolerate) {
      _retry?.cancel();
      _retry = Timer(retryAfter, () => unawaited(check()));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}
