import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/backend_client.dart';
import 'package:sahbi/features/voice/live_voice_tts.dart';
import 'package:sahbi/features/voice/voice_types.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('LiveVoiceTts', () {
    late List<_FakeSocket> sockets;
    late _FakeSpeaker speaker;
    late int tokens;

    LiveVoiceTts make({Duration firstAudio = const Duration(seconds: 2)}) {
      sockets = [];
      speaker = _FakeSpeaker();
      tokens = 0;
      return LiveVoiceTts(
        isConfigured: () => true,
        token: () async {
          tokens++;
          return const LiveTokenInfo(
            token: 'auth_tokens/x',
            wsUrl: 'wss://example/ws',
            model: 'gemini-3.8-live',
            voice: 'Algenib',
          );
        },
        speaker: speaker,
        connector: (uri) {
          final f = _FakeSocket(uri);
          sockets.add(f);
          return f;
        },
        firstAudioTimeout: firstAudio,
        tail: Duration.zero,
      );
    }

    Future<void> until(bool Function() cond) async {
      for (var i = 0; i < 200 && !cond(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(cond(), isTrue);
    }

    bool sentText(_FakeSocket s, String t) => s.sent.any(
      (m) => (jsonDecode(m) as Map)['realtimeInput']?['text'] == t,
    );

    Map<String, dynamic> audio(int bytes) => {
      'serverContent': {
        'modelTurn': {
          'parts': [
            {
              'inlineData': {
                'mimeType': 'audio/pcm;rate=24000',
                'data': base64Encode(Uint8List(bytes)),
              },
            },
          ],
        },
      },
    };

    test('streams one line, reuses the session for the next', () async {
      final tts = make();
      final events = <TtsEvent>[];
      final done = tts
          .speak('salam a sahbi', language: 'ar-MA')
          .forEach(events.add);
      await until(() => sockets.isNotEmpty);
      sockets.single.server({'setupComplete': {}});
      await until(() => sentText(sockets.single, 'salam a sahbi'));
      sockets.single.server(audio(2400));
      sockets.single.server({
        'serverContent': {'turnComplete': true},
      });
      await done;
      expect(events.first, isA<TtsStarted>());
      expect(events.last, isA<TtsDone>());
      expect((events.last as TtsDone).interrupted, isFalse);
      expect(speaker.rates, [liveVoiceOutputRate]);
      expect(liveVoiceOutputRate, 25680);
      expect(speaker.fed, greaterThan(0));

      final second = <TtsEvent>[];
      final done2 = tts.speak('labas?', language: 'ar-MA').forEach(second.add);
      await until(() => sentText(sockets.single, 'labas?'));
      sockets.single.server(audio(2400));
      sockets.single.server({
        'serverContent': {'turnComplete': true},
      });
      await done2;
      expect(second.last, isA<TtsDone>());
      expect(sockets, hasLength(1), reason: 'same session');
      expect(tokens, 1, reason: 'single-use tokens are not wasted');
      await tts.close();
    });

    test('no audio in time → failure, and the session is dropped', () async {
      final tts = make(firstAudio: const Duration(milliseconds: 100));
      final events = <TtsEvent>[];
      final done = tts.speak('wa fin', language: 'ar-MA').forEach(events.add);
      await until(() => sockets.isNotEmpty);
      sockets.single.server({'setupComplete': {}});
      await done;
      expect(events.single, isA<TtsFailure>());

      unawaited(tts.speak('3awd', language: 'ar-MA').drain<void>());
      await until(() => sockets.length == 2);
      expect(tokens, 2);
      await tts.close();
    });

    test('stop() ends the line as interrupted', () async {
      final tts = make();
      final events = <TtsEvent>[];
      final done = tts.speak('twila', language: 'ar-MA').forEach(events.add);
      await until(() => sockets.isNotEmpty);
      sockets.single.server({'setupComplete': {}});
      await until(() => sentText(sockets.single, 'twila'));
      sockets.single.server(audio(2400));
      await until(() => events.isNotEmpty);
      await tts.stop();
      await done;
      expect((events.last as TtsDone).interrupted, isTrue);
      await tts.close();
    });
  });

  group('FallbackTts', () {
    test('primary failing before sound → secondary, then cooldown', () async {
      var now = DateTime(2026, 11, 16, 12);
      final p = _ScriptTts('live', fail: true);
      final s = _ScriptTts('cloud');
      final failures = <String>[];
      final f = FallbackTts(
        p,
        s,
        clock: () => now,
        onPrimaryFailure: failures.add,
      );

      final e1 = await f.speak('a', language: 'ar').toList();
      expect(e1.last, isA<TtsDone>());
      expect(p.calls, 1);
      expect(s.calls, 1);
      expect(failures, hasLength(1));

      await f.speak('b', language: 'ar').toList();
      expect(p.calls, 1, reason: 'primary cooling down');
      expect(s.calls, 2);

      now = now.add(const Duration(seconds: 61));
      p.fail = false;
      await f.speak('c', language: 'ar').toList();
      expect(p.calls, 2);
      expect(s.calls, 2);
    });

    test('a failure after the voice started is not re-spoken', () async {
      final p = _ScriptTts('live', failAfterStart: true);
      final s = _ScriptTts('cloud');
      final e = await FallbackTts(p, s).speak('x', language: 'ar').toList();
      expect(e.last, isA<TtsFailure>());
      expect(s.calls, 0);
    });
  });
}

class _ScriptTts implements TtsProvider {
  _ScriptTts(this.id, {this.fail = false, this.failAfterStart = false});
  @override
  final String id;
  bool fail;
  final bool failAfterStart;
  int calls = 0;

  @override
  Future<ProviderAvailability> availability() async =>
      ProviderAvailability.available;

  @override
  Future<List<TtsVoice>> voices() async => const [];

  @override
  Stream<TtsEvent> speak(String text, {required String language}) async* {
    calls++;
    if (fail) {
      yield const TtsFailure('down');
      return;
    }
    yield const TtsStarted();
    if (failAfterStart) {
      yield const TtsFailure('cut');
      return;
    }
    yield const TtsDone();
  }

  @override
  Future<void> stop() async {}
}

class _FakeSpeaker implements PcmSpeaker {
  final rates = <int>[];
  int fed = 0;

  @override
  Future<void> open(int sampleRate) async => rates.add(sampleRate);

  @override
  Future<void> feed(Uint8List pcm) async => fed += pcm.length;

  @override
  Future<void> close() async {}
}

/// Minimal in-memory WebSocketChannel.
class _FakeSocket extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeSocket(this.uri) {
    _out.stream.listen((m) => sent.add(m as String));
  }
  final Uri uri;
  final sent = <String>[];
  final _in = StreamController<dynamic>();
  final _out = StreamController<dynamic>();

  void server(Map<String, dynamic> m) => _in.add(jsonEncode(m));

  @override
  Stream<dynamic> get stream => _in.stream;

  @override
  WebSocketSink get sink => _FakeSink(_out, _in);

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._out, this._in);
  final StreamController<dynamic> _out;
  final StreamController<dynamic> _in;

  @override
  void add(dynamic data) => _out.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_in.isClosed) await _in.close();
  }

  @override
  Future<void> get done => _in.done;
}
