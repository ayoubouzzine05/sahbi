import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sahbi/core/backend_client.dart';
import 'package:sahbi/core/connectivity.dart';

const healthJson = {
  'ok': true,
  'version': '0.1.0',
  'prompt_version': '1.0.0',
  'services': {
    'llm': {'configured': true, 'provider': 'openai'},
  },
};

void main() {
  late int calls;
  late bool up;

  ConnectivityMonitor monitor() => ConnectivityMonitor(
    BackendClient(
      baseUrl: () => 'https://sahbi.example',
      store: MemoryKeyValueStore(),
      client: MockClient((req) async {
        calls++;
        expect(req.url.path, '/v1/health');
        if (!up) throw http.ClientException('connection refused');
        return http.Response(jsonEncode(healthJson), 200);
      }),
    ),
  );

  setUp(() {
    calls = 0;
    up = false;
  });

  test('wake() re-checks a sleeping server and marks it reachable', () async {
    final m = monitor();
    await m.check();
    expect(m.value.backendReachable, isFalse);
    up = true; // the host finished spinning up
    await m.wake();
    expect(m.value.backendReachable, isTrue);
    expect(m.value.aiConfigured, isTrue);
    expect(calls, 2);
  });

  test('wake() does nothing when the server is already reachable', () async {
    up = true;
    final m = monitor();
    await m.check();
    await m.wake();
    expect(calls, 1);
  });

  test('concurrent checks share one request', () async {
    up = true;
    final m = monitor();
    await Future.wait([m.check(), m.check(), m.wake()]);
    expect(calls, 1);
  });

  test('one failed check after success is tolerated, two are not', () async {
    up = true;
    final m = monitor()..retryAfter = const Duration(hours: 1);
    await m.check();
    up = false;
    await m.check();
    expect(m.value.backendReachable, isTrue, reason: 'one slow check');
    expect(m.value.aiConfigured, isTrue, reason: 'last health kept');
    await m.check();
    expect(m.value.backendReachable, isFalse);
    expect(m.value.aiConfigured, isFalse);
    up = true;
    await m.check();
    expect(m.value.backendReachable, isTrue);
    expect(m.value.failStreak, 0);
    m.dispose();
  });
}
