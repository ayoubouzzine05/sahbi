import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Events coming out of a [LiveSession].
sealed class LiveEvent {
  const LiveEvent();
}

class LiveReady extends LiveEvent {
  const LiveReady();
}

/// 24 kHz, mono, 16-bit little-endian PCM from the model.
class LiveAudio extends LiveEvent {
  const LiveAudio(this.pcm);
  final Uint8List pcm;
}

/// Transcript pieces: [fromUser] = what the user said, else the robot.
class LiveTranscript extends LiveEvent {
  const LiveTranscript(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

/// The user talked over the robot: drop queued audio now.
class LiveInterrupted extends LiveEvent {
  const LiveInterrupted();
}

class LiveTurnComplete extends LiveEvent {
  const LiveTurnComplete();
}

/// Reconnecting after a server goAway / dropped connection.
class LiveReconnecting extends LiveEvent {
  const LiveReconnecting();
}

class LiveClosed extends LiveEvent {
  const LiveClosed({this.error, this.code, this.reason});
  final String? error;
  final int? code;
  final String? reason;
}

typedef LiveConnector = WebSocketChannel Function(Uri uri);

/// Gemini Live API client over the ephemeral-token WebSocket
/// (BidiGenerateContentConstrained). Model, prompt and voice are locked in the
/// token by the backend; this class only adds session resumption.
/// Protocol: https://ai.google.dev/api/live
class LiveSession {
  LiveSession({
    required this.wsUrl,
    required this.token,
    required this.model,
    LiveConnector? connector,
    this.maxReconnects = 3,
  }) : _connect = connector ?? ((u) => WebSocketChannel.connect(u));

  final String wsUrl;
  final String token;
  final String model;
  final int maxReconnects;
  final LiveConnector _connect;

  final _events = StreamController<LiveEvent>.broadcast();
  Stream<LiveEvent> get events => _events.stream;

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  String? _resumeHandle;
  bool _ready = false;
  bool _closedByUser = false;
  bool _reconnecting = false;
  int _reconnects = 0;

  bool get ready => _ready;
  String? get resumeHandle => _resumeHandle;

  Uri get _uri =>
      Uri.parse('$wsUrl?access_token=${Uri.encodeComponent(token)}');

  Future<void> start() => _open();

  Future<void> _open() async {
    _ready = false;
    final ch = _connect(_uri);
    _ch = ch;
    _sub = ch.stream.listen(
      _onMessage,
      onError: (Object e) => _onDrop(error: '$e'),
      onDone: () => _onDrop(code: ch.closeCode, reason: ch.closeReason),
    );
    try {
      await ch.ready;
    } catch (e) {
      // onError/onDone handle reporting.
      return;
    }
    _send({
      'setup': {
        'model': model.startsWith('models/') ? model : 'models/$model',
        // Ask for resumption handles; resume when we already have one.
        'sessionResumption': {'handle': ?_resumeHandle},
      },
    });
  }

  void _onMessage(dynamic raw) {
    final String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw, allowMalformed: true);
    } else {
      return;
    }
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    for (final e in parseServerMessage(m)) {
      if (e is _ResumeUpdate) {
        if (e.handle != null) _resumeHandle = e.handle;
        continue;
      }
      if (e is _GoAway) {
        unawaited(_reconnect());
        continue;
      }
      if (e is LiveReady) {
        _ready = true;
        _reconnecting = false;
        _reconnects = 0;
      }
      _emit(e);
    }
  }

  void _onDrop({String? error, int? code, String? reason}) {
    if (_closedByUser) return;
    if (_reconnecting) return; // the old socket closing during a reconnect
    if (_resumeHandle != null && _reconnects < maxReconnects && _ready) {
      unawaited(_reconnect());
      return;
    }
    _ready = false;
    _emit(LiveClosed(error: error, code: code, reason: reason));
  }

  Future<void> _reconnect() async {
    if (_closedByUser || _reconnecting) return;
    if (_resumeHandle == null || _reconnects >= maxReconnects) {
      _emit(const LiveClosed(error: 'session_ended'));
      return;
    }
    _reconnecting = true;
    _reconnects++;
    _emit(const LiveReconnecting());
    final old = _ch;
    final oldSub = _sub;
    _ch = null;
    _sub = null;
    await oldSub?.cancel();
    unawaited(old?.sink.close());
    _reconnecting = true;
    await _open();
    // If the new socket fails before setupComplete, report it.
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (_reconnecting && !_ready && !_closedByUser) {
        _reconnecting = false;
        _emit(const LiveClosed(error: 'reconnect_failed'));
      }
    });
  }

  bool _closedEmitted = false;

  void _emit(LiveEvent e) {
    if (e is LiveClosed) {
      if (_closedEmitted) return; // error + done of one socket → one event
      _closedEmitted = true;
    } else if (e is LiveReady) {
      _closedEmitted = false;
    }
    if (!_events.isClosed) _events.add(e);
  }

  void _send(Map<String, dynamic> m) {
    final ch = _ch;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  /// 16 kHz mono 16-bit PCM from the mic.
  void sendAudio(Uint8List pcm16k) {
    if (!_ready || pcm16k.isEmpty) return;
    _send(audioMessage(pcm16k));
  }

  /// One camera frame (JPEG). Send at most ~1 per second.
  void sendImage(Uint8List jpeg) {
    if (!_ready || jpeg.isEmpty) return;
    _send(imageMessage(jpeg));
  }

  void sendText(String text) {
    if (!_ready || text.trim().isEmpty) return;
    _send({
      'realtimeInput': {'text': text.trim()},
    });
  }

  /// Tell the server the mic stream paused (mute), so it flushes audio.
  void audioStreamEnd() {
    if (!_ready) return;
    _send({
      'realtimeInput': {'audioStreamEnd': true},
    });
  }

  Future<void> close() async {
    _closedByUser = true;
    _ready = false;
    await _sub?.cancel();
    try {
      await _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _emit(const LiveClosed());
    if (!_events.isClosed) await _events.close();
  }

  static Map<String, dynamic> audioMessage(Uint8List pcm16k) => {
    'realtimeInput': {
      'audio': {
        'data': base64Encode(pcm16k),
        'mimeType': 'audio/pcm;rate=16000',
      },
    },
  };

  static Map<String, dynamic> imageMessage(Uint8List jpeg) => {
    'realtimeInput': {
      'video': {'data': base64Encode(jpeg), 'mimeType': 'image/jpeg'},
    },
  };
}

/// Protocol bookkeeping handled inside [LiveSession]; never emitted.
sealed class LiveInternal extends LiveEvent {
  const LiveInternal();
}

class _ResumeUpdate extends LiveInternal {
  const _ResumeUpdate(this.handle);
  final String? handle;
}

class _GoAway extends LiveInternal {
  const _GoAway();
}

/// Maps one server message to events (public for tests).
List<LiveEvent> parseServerMessage(Map<String, dynamic> m) {
  final out = <LiveEvent>[];
  if (m.containsKey('setupComplete')) out.add(const LiveReady());
  final sc = m['serverContent'];
  if (sc is Map) {
    if (sc['interrupted'] == true) out.add(const LiveInterrupted());
    final it = sc['inputTranscription'];
    if (it is Map &&
        it['text'] is String &&
        (it['text'] as String).isNotEmpty) {
      out.add(LiveTranscript(it['text'] as String, fromUser: true));
    }
    final turn = sc['modelTurn'];
    if (turn is Map && turn['parts'] is List) {
      for (final p in turn['parts'] as List) {
        if (p is! Map) continue;
        final d = p['inlineData'];
        if (d is Map &&
            d['data'] is String &&
            '${d['mimeType'] ?? ''}'.startsWith('audio/pcm')) {
          try {
            out.add(LiveAudio(base64Decode(d['data'] as String)));
          } catch (_) {}
        }
      }
    }
    final ot = sc['outputTranscription'];
    if (ot is Map &&
        ot['text'] is String &&
        (ot['text'] as String).isNotEmpty) {
      out.add(LiveTranscript(ot['text'] as String, fromUser: false));
    }
    if (sc['turnComplete'] == true) out.add(const LiveTurnComplete());
  }
  final ru = m['sessionResumptionUpdate'];
  if (ru is Map) {
    final h = ru['newHandle'];
    out.add(
      _ResumeUpdate(
        ru['resumable'] != false && h is String && h.isNotEmpty ? h : null,
      ),
    );
  }
  if (m.containsKey('goAway')) out.add(const _GoAway());
  return out;
}
