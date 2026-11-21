import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/error_log.dart';
import 'package:sahbi/features/brain/command_parser.dart';
import 'package:sahbi/features/live/live_session.dart';
import 'package:sahbi/features/personality/personality_responses.dart';
import 'package:sahbi/features/personality/voice_state.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/device_tts.dart';
import 'package:sahbi/features/voice/voice_types.dart';
import 'package:sahbi/features/voice/wake_name.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('phoneticKey / matchWakeName', () {
    test('Arabic and Latin spellings share a skeleton', () {
      expect(phoneticKey('صاحبي'), 'shb');
      expect(phoneticKey('Sahbi'), 'shb');
      expect(phoneticKey('sa7bi'), 'shb');
      expect(phoneticKey('Zizou'), 'zz');
      expect(phoneticKey('زيزو'), 'zz');
      expect(phoneticKey('Chouchou'), 'cc');
      expect(phoneticKey('Sahhbi'), 'shb');
      expect(phoneticKey('Mustapha'), phoneticKey('Mostafa'));
      expect(phoneticKey('Khalid'), phoneticKey('خالد'));
    });

    test('name alone → wake with empty rest', () {
      expect(matchWakeName('Zizou', 'Zizou')?.rest, '');
      expect(matchWakeName('زيزو', 'Zizou')?.rest, '');
      expect(matchWakeName('يا صاحبي', 'صاحبي')?.rest, '');
      expect(matchWakeName('ياصاحبي', 'صاحبي')?.rest, '');
      expect(matchWakeName('ya sahbi', 'sahbi')?.rest, '');
    });

    test('name + command → the command is returned', () {
      expect(
        matchWakeName('Zizou chno ljaw lyoum', 'Zizou')?.rest,
        'chno ljaw lyoum',
      );
      expect(
        matchWakeName('زيزو، شنو الجو اليوم؟', 'Zizou')?.rest,
        'شنو الجو اليوم',
      );
      expect(
        matchWakeName('Robo Star chghel music', 'Robo Star')?.rest,
        'chghel music',
      );
    });

    test('no false wake on unrelated speech', () {
      expect(matchWakeName('chno ljaw lyoum', 'Zizou'), isNull);
      expect(matchWakeName('kanbghi nmchi lsouk', 'Bobo'), isNull);
      expect(matchWakeName('', 'Zizou'), isNull);
      expect(matchWakeName('salam', ''), isNull);
    });

    test('long names tolerate one recogniser slip', () {
      expect(matchWakeName('Mustapha', 'Moustafa'), isNotNull);
      expect(
        matchWakeName('Mostafa ach katdir', 'Mustapha')?.rest,
        'ach katdir',
      );
    });

    test('default names when the user did not pick one', () {
      expect(wakeNamesFor(const AppSettings()), contains('صاحبي'));
      expect(wakeNamesFor(const AppSettings(robotName: 'Bobo')), ['Bobo']);
    });
  });

  group('WakeNameController', () {
    late StreamController<SttEvent> ctrl;
    late AppSettings settings;
    late VoiceState state;
    late int wakes;
    late List<String> commands;
    late int listens;
    late int cancels;
    late bool mic;

    WakeNameController make() => WakeNameController(
      listen: (_) {
        listens++;
        ctrl = StreamController<SttEvent>();
        return ctrl.stream;
      },
      cancel: () async {
        cancels++;
        if (!ctrl.isClosed) await ctrl.close();
      },
      settings: () => settings,
      voiceState: () => state,
      micGranted: () async => mic,
      onWake: () async => wakes++,
      onCommand: commands.add,
      log: ErrorLog(),
      restartDelay: const Duration(milliseconds: 1),
    );

    setUp(() {
      settings = const AppSettings(wakeByName: true, robotName: 'Zizou');
      state = VoiceState.idle;
      wakes = 0;
      commands = [];
      listens = 0;
      cancels = 0;
      mic = true;
    });

    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    test('switched off / without mic permission nothing listens', () async {
      settings = const AppSettings(wakeByName: false);
      final w = make()..refresh();
      await tick();
      expect(listens, 0);
      settings = const AppSettings(wakeByName: true);
      mic = false;
      w.refresh();
      await tick();
      expect(listens, 0);
      expect(w.lastError, 'no_permission');
      w.dispose();
    });

    test('the name is also found in the recogniser alternates', () async {
      final w = make()..refresh();
      await tick();
      ctrl.add(const SttFinal('zero chno ljaw', alternates: ['زيزو شنو الجو']));
      await tick();
      expect(commands, ['شنو الجو']);
      w.dispose();
    });

    test('hearing the name opens the mic; words after it are sent', () async {
      final w = make()..refresh();
      await tick();
      expect(listens, 1);
      expect(w.active, isTrue);
      ctrl.add(const SttPartial('zizou'));
      await tick();
      expect(wakes, 1);
      expect(cancels, greaterThan(0));
      expect(w.active, isFalse);

      // Next round: name + command arrives as a final result.
      w.refresh();
      await tick();
      ctrl.add(const SttPartial('زيزو شنو'));
      await tick();
      expect(commands, isEmpty, reason: 'waits for the final result');
      ctrl.add(const SttFinal('زيزو شنو الجو'));
      await tick();
      expect(commands, ['شنو الجو']);
      expect(wakes, 1);
      w.dispose();
    });

    test(
      'restarts after a silent session, pauses while busy/background',
      () async {
        final w = make()..refresh();
        await tick();
        ctrl.add(const SttFinal('salam labas'));
        await ctrl.close();
        await tick();
        expect(listens, 2, reason: 'restarted after no name');
        state = VoiceState.speaking;
        w.refresh();
        await tick();
        expect(w.active, isFalse);
        state = VoiceState.idle;
        w.setForeground(false);
        await tick();
        expect(w.active, isFalse);
        w.setForeground(true);
        await tick();
        expect(w.active, isTrue);
        w.suspend();
        await tick();
        expect(w.active, isFalse);
        w.resume();
        await tick();
        expect(w.active, isTrue);
        w.dispose();
      },
    );

    test('yieldMic releases the recogniser before push-to-talk', () async {
      final w = make()..refresh();
      await tick();
      final before = cancels;
      await w.yieldMic();
      expect(cancels, before + 1);
      expect(w.active, isFalse);
      w.dispose();
    });

    test('a missing recogniser does not spin', () async {
      final w = make()..refresh();
      await tick();
      ctrl.add(const SttFailure('not_available', 'none'));
      await ctrl.close();
      await tick();
      await tick();
      expect(listens, 1);
      expect(w.lastError, 'not_available');
      w.dispose();
    });
  });

  group('AppSettings robot name / voice', () {
    test('defaults: male voice, no custom name, wake by name on', () {
      const s = AppSettings();
      expect(s.voiceGender, 'male');
      expect(s.robotName, '');
      expect(s.wakeByName, isTrue);
      // Old installs saved the V1 default (off): wake by name is now on, but
      // a choice saved with the new key is kept.
      expect(
        AppSettings.decode('{"wakeByName": false, "robotName": "Zizou"}')
            .wakeByName,
        isTrue,
      );
      expect(AppSettings.decode('{"wakeByNameV2": false}').wakeByName, isFalse);
      expect(s.keepScreenOn, isTrue);
      expect(s.displayRobotName('صاحبي'), 'صاحبي');
    });

    test('name is cleaned, capped and round-trips through JSON', () {
      final s = const AppSettings().copyWith(
        robotName: '  Zi"zou\n {x}  ',
        voiceGender: 'female',
        wakeByName: true,
      );
      expect(s.robotName, 'Zi zou x');
      final back = AppSettings.decode(s.encode());
      expect(back.robotName, 'Zi zou x');
      expect(back.voiceGender, 'female');
      expect(back.wakeByName, isTrue);
      expect(
        const AppSettings().copyWith(robotName: 'x' * 50).robotName.length,
        AppSettings.maxRobotNameLength,
      );
      expect(
        AppSettings.fromJson({'voiceGender': 'robot'}).voiceGender,
        'male',
      );
    });
  });

  group('device TTS gender', () {
    test('picks a voice that says male / female for the locale', () {
      const voices = [
        TtsVoice('ar-xa-x-arc-local', 'ar'),
        TtsVoice('ar-SA-female-1', 'ar-SA'),
        TtsVoice('ar-SA-male-2', 'ar-SA'),
        TtsVoice('fr-FR-male-1', 'fr-FR'),
      ];
      expect(pickGenderVoice(voices, 'ar-SA', 'male')?.name, 'ar-SA-male-2');
      expect(
        pickGenderVoice(voices, 'ar-MA', 'female')?.name,
        'ar-SA-female-1',
      );
      expect(pickGenderVoice(voices, 'en-US', 'male'), isNull);
      expect(maleFallbackPitch, lessThan(1));
    });
  });

  group('camera command + named who-are-you', () {
    const p = CommandParser();
    test('Darija / French / Arabic camera requests', () {
      for (final s in [
        '7el camera',
        'hel lcamera',
        'ouvre la caméra',
        'حل الكاميرا',
        'camera',
        'chouf hadi',
        'شوف هادي',
        'look at this',
      ]) {
        expect(p.parse(s)?.type, CommandType.openCamera, reason: s);
      }
      expect(p.parse('chno hiya camera li mzyana?'), isNull);
    });

    test('who-are-you uses the chosen name', () {
      final r = PersonalityResponses();
      final line = r.forIntent(
        OfflineIntent.whoAreYou,
        DateTime(2026),
        robotName: 'Zizou',
      );
      expect(line.darijaAr, contains('Zizou'));
      expect(line.en, contains('Zizou'));
      expect(
        r.forIntent(OfflineIntent.whoAreYou, DateTime(2026)).darijaAr,
        contains('صاحبي'),
      );
    });
  });

  group('LiveSession protocol', () {
    test('parses server messages', () {
      final pcm = Uint8List.fromList([1, 0, 2, 0]);
      final ev = parseServerMessage({
        'serverContent': {
          'interrupted': true,
          'inputTranscription': {'text': 'chno hada'},
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/pcm;rate=24000',
                  'data': base64Encode(pcm),
                },
              },
            ],
          },
          'outputTranscription': {'text': 'هادي تفاحة'},
          'turnComplete': true,
        },
      });
      expect(ev[0], isA<LiveInterrupted>());
      expect((ev[1] as LiveTranscript).fromUser, isTrue);
      expect((ev[2] as LiveAudio).pcm, pcm);
      expect((ev[3] as LiveTranscript).text, 'هادي تفاحة');
      expect(ev[4], isA<LiveTurnComplete>());
      expect(
        parseServerMessage({'setupComplete': {}}).single,
        isA<LiveReady>(),
      );
    });

    test('client messages use the documented realtimeInput shapes', () {
      final a = LiveSession.audioMessage(Uint8List.fromList([1, 2]));
      expect(a['realtimeInput']['audio']['mimeType'], 'audio/pcm;rate=16000');
      final v = LiveSession.imageMessage(Uint8List.fromList([255, 216]));
      expect(v['realtimeInput']['video']['mimeType'], 'image/jpeg');
    });

    test(
      'setup → ready → streams; resumes after goAway with the handle',
      () async {
        final sockets = <_FakeSocket>[];
        final s = LiveSession(
          wsUrl: 'wss://example/ws',
          token: 'auth_tokens/a b',
          model: 'gemini-3.8-live',
          connector: (uri) {
            final f = _FakeSocket(uri);
            sockets.add(f);
            return f;
          },
        );
        final events = <LiveEvent>[];
        s.events.listen(events.add);
        await s.start();
        await pumpEventQueue();
        expect(
          sockets.single.uri.queryParameters['access_token'],
          'auth_tokens/a b',
        );
        final setup = jsonDecode(sockets.single.sent.first) as Map;
        expect(setup['setup']['model'], 'models/gemini-3.8-live');
        expect(setup['setup']['sessionResumption'], isEmpty);

        s.sendAudio(Uint8List.fromList([1, 2]));
        expect(
          sockets.single.sent,
          hasLength(1),
          reason: 'nothing before ready',
        );

        sockets.single.server({'setupComplete': {}});
        sockets.single.server({
          'sessionResumptionUpdate': {'newHandle': 'h1', 'resumable': true},
        });
        await pumpEventQueue();
        expect(s.ready, isTrue);
        expect(s.resumeHandle, 'h1');
        s.sendImage(Uint8List.fromList([255, 216, 1]));
        await pumpEventQueue();
        expect(sockets.single.sent, hasLength(2));

        sockets.single.server({
          'goAway': {'timeLeft': '5s'},
        });
        await pumpEventQueue();
        expect(sockets, hasLength(2));
        final resume = jsonDecode(sockets[1].sent.first) as Map;
        expect(resume['setup']['sessionResumption']['handle'], 'h1');
        expect(events.whereType<LiveReconnecting>(), hasLength(1));
        sockets[1].server({'setupComplete': {}});
        await pumpEventQueue();
        expect(events.whereType<LiveReady>(), hasLength(2));
        expect(events.whereType<LiveClosed>(), isEmpty);
        await s.close();
      },
    );

    test('a refused connection is reported as closed with an error', () async {
      final s = LiveSession(
        wsUrl: 'wss://example/ws',
        token: 't',
        model: 'm',
        connector: (uri) => _FakeSocket(uri, failReady: true),
      );
      final events = <LiveEvent>[];
      s.events.listen(events.add);
      await s.start();
      await pumpEventQueue();
      expect(events.whereType<LiveClosed>().single.error, isNotNull);
      await s.close();
    });
  });
}

/// Minimal in-memory WebSocketChannel.
class _FakeSocket extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeSocket(this.uri, {this.failReady = false}) {
    _out.stream.listen((m) => sent.add(m as String));
    if (failReady) {
      scheduleMicrotask(() {
        _in.addError(Exception('refused'));
        _in.close();
      });
    }
  }
  final Uri uri;
  final bool failReady;
  final sent = <String>[];
  final _in = StreamController<dynamic>();
  final _out = StreamController<dynamic>();

  void server(Map<String, dynamic> m) => _in.add(jsonEncode(m));

  @override
  Stream<dynamic> get stream => _in.stream;

  @override
  WebSocketSink get sink => _FakeSink(_out, _in);

  @override
  Future<void> get ready =>
      failReady ? Future.error(Exception('refused')) : Future.value();

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
  Future<void> get done => Future.value();
}
