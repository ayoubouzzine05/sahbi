import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../features/brain/brain_models.dart';
import '../features/music/youtube_controller.dart';

enum BackendErrorCode {
  notConfigured,
  noInternet,
  timeout,
  unauthorized,
  rateLimited,
  badRequest,
  invalidOutput,
  server,
}

class BackendException implements Exception {
  const BackendException(this.code, this.message);
  final BackendErrorCode code;
  final String message;
  @override
  String toString() => 'BackendException(${code.name}: $message)';
}

class ServiceHealth {
  const ServiceHealth({required this.configured, required this.provider});
  final bool configured;
  final String provider;
}

class HealthStatus {
  const HealthStatus({
    required this.version,
    required this.promptVersion,
    required this.services,
    required this.checkedAt,
  });
  final String version;
  final String promptVersion;
  final Map<String, ServiceHealth> services;
  final DateTime checkedAt;

  bool configured(String name) => services[name]?.configured ?? false;

  static HealthStatus fromJson(Map<String, dynamic> j) {
    final s = (j['services'] as Map?)?.cast<String, dynamic>() ?? {};
    return HealthStatus(
      version: '${j['version'] ?? '?'}',
      promptVersion: '${j['prompt_version'] ?? '?'}',
      services: {
        for (final e in s.entries)
          e.key: ServiceHealth(
            configured: (e.value as Map)['configured'] == true,
            provider: '${(e.value as Map)['provider'] ?? 'none'}',
          ),
      },
      checkedAt: DateTime.now(),
    );
  }
}

/// Simple async key-value store (secure storage in the app, a map in tests).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

String generateUuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Talks to the SAHBI backend. Holds no API keys: only an anonymous
/// per-install token obtained from `/v1/auth/anonymous`.
class BackendClient {
  BackendClient({
    required String Function() baseUrl,
    required KeyValueStore store,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _baseUrl = baseUrl,
       _store = store,
       _http = client ?? http.Client();

  final String Function() _baseUrl;
  final KeyValueStore _store;
  final http.Client _http;
  final Duration timeout;
  String? _token;

  String get baseUrl => _baseUrl().trim().replaceFirst(RegExp(r'/+$'), '');
  bool get hasBaseUrl => baseUrl.startsWith('http');

  Uri _uri(String path, [Map<String, String>? q]) {
    if (!hasBaseUrl) {
      throw const BackendException(
        BackendErrorCode.notConfigured,
        'Backend URL is not set',
      );
    }
    return Uri.parse('$baseUrl$path').replace(queryParameters: q);
  }

  Future<String> installId() async {
    var id = await _store.read('install_id');
    if (id == null) {
      id = generateUuidV4();
      await _store.write('install_id', id);
    }
    return id;
  }

  Future<String> _getToken({bool force = false}) async {
    if (!force) {
      _token ??= await _store.read('install_token');
      if (_token != null) return _token!;
    }
    final id = await installId();
    final res = await _guard(
      () => _http
          .post(
            _uri('/v1/auth/anonymous'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'install_id': id}),
          )
          .timeout(const Duration(seconds: 10)),
    );
    _check(res.statusCode, res.body);
    final token = (jsonDecode(res.body) as Map)['token'] as String;
    _token = token;
    await _store.write('install_token', token);
    return token;
  }

  Future<Map<String, String>> _authHeaders({bool force = false}) async => {
    'authorization': 'Bearer ${await _getToken(force: force)}',
  };

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on BackendException {
      rethrow;
    } on TimeoutException {
      throw const BackendException(
        BackendErrorCode.timeout,
        'Request timed out',
      );
    } on SocketException {
      throw const BackendException(BackendErrorCode.noInternet, 'No internet');
    } on HandshakeException {
      throw const BackendException(BackendErrorCode.noInternet, 'TLS failed');
    } on http.ClientException catch (e) {
      throw BackendException(BackendErrorCode.noInternet, e.message);
    }
  }

  static void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    String code = '';
    String msg = 'HTTP $status';
    try {
      final e = (jsonDecode(body) as Map)['error'] as Map;
      code = '${e['code']}';
      msg = '${e['message']}';
    } catch (_) {}
    throw BackendException(_mapCode(status, code), msg);
  }

  static BackendErrorCode codeFromString(String code) => switch (code) {
    'not_configured' => BackendErrorCode.notConfigured,
    'upstream_timeout' => BackendErrorCode.timeout,
    'invalid_output' => BackendErrorCode.invalidOutput,
    'rate_limited' => BackendErrorCode.rateLimited,
    'unauthorized' => BackendErrorCode.unauthorized,
    'bad_request' => BackendErrorCode.badRequest,
    _ => BackendErrorCode.server,
  };

  static BackendErrorCode _mapCode(int status, String code) {
    if (code == 'not_configured' || status == 503) {
      return BackendErrorCode.notConfigured;
    }
    if (status == 401) return BackendErrorCode.unauthorized;
    if (status == 429) return BackendErrorCode.rateLimited;
    if (status == 400 || status == 404 || status == 413) {
      return BackendErrorCode.badRequest;
    }
    if (status == 504 || code == 'upstream_timeout') {
      return BackendErrorCode.timeout;
    }
    if (code == 'invalid_output') return BackendErrorCode.invalidOutput;
    return BackendErrorCode.server;
  }

  Future<http.Response> _authed(
    Future<http.Response> Function(Map<String, String> h) send,
  ) async {
    var res = await _guard(() async => send(await _authHeaders()));
    if (res.statusCode == 401) {
      res = await _guard(() async => send(await _authHeaders(force: true)));
    }
    _check(res.statusCode, res.body);
    return res;
  }

  Future<HealthStatus> health({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final res = await _guard(
      () => _http.get(_uri('/v1/health')).timeout(timeout),
    );
    _check(res.statusCode, res.body);
    return HealthStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /v1/chat, parsed from Server-Sent Events.
  Stream<BrainEvent> chat(Map<String, dynamic> request) async* {
    Future<http.StreamedResponse> open(bool force) async {
      final req = http.Request('POST', _uri('/v1/chat'))
        ..headers.addAll({
          'content-type': 'application/json',
          'accept': 'text/event-stream',
          ...await _authHeaders(force: force),
        })
        ..body = jsonEncode(request);
      return _http.send(req).timeout(timeout);
    }

    var res = await _guard(() => open(false));
    if (res.statusCode == 401) {
      await res.stream.drain<void>();
      res = await _guard(() => open(true));
    }
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      _check(res.statusCode, body);
    }
    yield* parseSse(res.stream.timeout(timeout));
  }

  /// Exposed for tests.
  static Stream<BrainEvent> parseSse(Stream<List<int>> bytes) async* {
    String? event;
    final data = StringBuffer();
    try {
      await for (final line
          in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (event != null) {
            final ev = _toEvent(event, data.toString());
            if (ev != null) yield ev;
          }
          event = null;
          data.clear();
        } else if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trim());
        }
      }
    } on TimeoutException {
      throw const BackendException(
        BackendErrorCode.timeout,
        'Stream timed out',
      );
    }
  }

  static BrainEvent? _toEvent(String event, String data) {
    final j = data.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(data) as Map<String, dynamic>;
    switch (event) {
      case 'status':
        return BrainStatus('${j['phase']}');
      case 'delta':
        return BrainDelta('${j['text'] ?? ''}');
      case 'final':
        try {
          return BrainFinal(BrainReply.fromJson(j));
        } on FormatException catch (e) {
          throw BackendException(BackendErrorCode.invalidOutput, e.message);
        }
      case 'error':
        throw BackendException(
          codeFromString('${j['code']}'),
          '${j['message'] ?? 'error'}',
        );
    }
    return null;
  }

  Future<String> summarize(
    String? summary,
    List<Map<String, dynamic>> turns,
  ) async {
    final res = await _authed(
      (h) => _http
          .post(
            _uri('/v1/summarize'),
            headers: {...h, 'content-type': 'application/json'},
            body: jsonEncode({'summary': ?summary, 'turns': turns}),
          )
          .timeout(timeout),
    );
    return (jsonDecode(res.body) as Map)['summary'] as String;
  }

  Future<String> transcribe(Uint8List wav, String lang) async {
    final res = await _authed(
      (h) => _http
          .post(
            _uri('/v1/stt', {'lang': lang}),
            headers: {...h, 'content-type': 'audio/wav'},
            body: wav,
          )
          .timeout(timeout),
    );
    return ((jsonDecode(res.body) as Map)['text'] as String?) ?? '';
  }

  Future<Uint8List> synthesize({
    required String text,
    required String language,
    String? voice,
    String? gender,
    double? rate,
    double? pitch,
  }) async {
    final res = await _authed(
      (h) => _http
          .post(
            _uri('/v1/tts'),
            headers: {...h, 'content-type': 'application/json'},
            body: jsonEncode({
              'text': text,
              'language': language,
              'voice': ?voice,
              'gender': ?gender,
              'rate': ?rate,
              'pitch': ?pitch,
            }),
          )
          .timeout(timeout),
    );
    return res.bodyBytes;
  }

  /// GET /v1/music/youtube: embeddable YouTube videos for a song/artist.
  Future<List<YoutubeVideo>> youtubeSearch(String query) async {
    final res = await _authed(
      (h) => _http
          .get(_uri('/v1/music/youtube', {'q': query}), headers: h)
          .timeout(const Duration(seconds: 40)),
    );
    final list = (jsonDecode(res.body) as Map)['videos'] as List? ?? const [];
    return [
      for (final v in list)
        if (v is Map<String, dynamic>) YoutubeVideo.fromJson(v),
    ];
  }

  /// GET /v1/images: free photos (Wikipedia / Wikimedia Commons) of [query]
  /// as raw JSON maps; the caller validates them.
  Future<List<Object?>> images(String query) async {
    final res = await _authed(
      (h) => _http
          .get(_uri('/v1/images', {'q': query}), headers: h)
          .timeout(const Duration(seconds: 15)),
    );
    return (jsonDecode(res.body) as Map)['images'] as List? ?? const [];
  }

  /// Single-use Gemini Live token (camera mode). The backend locks model,
  /// prompt and voice into the token; the API key never reaches the app.
  Future<LiveTokenInfo> liveToken({
    String? robotName,
    String? userName,
    required String gender,
    required String replyLanguage,
  }) async {
    final res = await _authed(
      (h) => _http
          .post(
            _uri('/v1/live/token'),
            headers: {...h, 'content-type': 'application/json'},
            body: jsonEncode({
              'robot_name': ?robotName,
              'user_name': ?userName,
              'gender': gender,
              'reply_language': replyLanguage,
            }),
          )
          .timeout(timeout),
    );
    return LiveTokenInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

class LiveTokenInfo {
  const LiveTokenInfo({
    required this.token,
    required this.wsUrl,
    required this.model,
    required this.voice,
  });
  final String token;
  final String wsUrl;
  final String model;
  final String voice;

  static LiveTokenInfo fromJson(Map<String, dynamic> j) {
    final token = j['token'];
    final ws = j['ws_url'];
    if (token is! String || ws is! String || !ws.startsWith('wss://')) {
      throw const FormatException('bad live token response');
    }
    return LiveTokenInfo(
      token: token,
      wsUrl: ws,
      model: '${j['model'] ?? ''}',
      voice: '${j['voice'] ?? ''}',
    );
  }
}
