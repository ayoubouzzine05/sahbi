import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/face/face_act.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sahbi/core/backend_client.dart';
import 'package:sahbi/core/connectivity.dart';
import 'package:sahbi/core/error_log.dart';
import 'package:sahbi/features/chat/chat_controller.dart';
import 'package:sahbi/features/chat/chat_models.dart';
import 'package:sahbi/features/memory/memory_store.dart';
import 'package:sahbi/features/music/music_controller.dart';
import 'package:sahbi/features/personality/companion_controller.dart';
import 'package:sahbi/features/personality/emotion.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/voice_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart' as f;
import '../support/music_fakes.dart';

String sse(List<(String, Object)> events) =>
    events.map((e) => 'event: ${e.$1}\ndata: ${jsonEncode(e.$2)}\n\n').join();

Map<String, dynamic> reply({
  String display = 'Salam a sahbi!',
  String tts = 'سلام أ صاحبي',
  String emotion = 'happy',
  List<Map<String, dynamic>> actions = const [],
}) => {
  'display_text': display,
  'tts_text': tts,
  'language': 'darija',
  'emotion': emotion,
  'intensity': 0.7,
  'actions': actions,
  'sources': <Object>[],
  'verification': 'none',
};

final healthy = HealthStatus(
  version: 't',
  promptVersion: 't',
  services: const {'llm': ServiceHealth(configured: true, provider: 'test')},
  checkedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> calls;
  late http.Response Function(http.Request) respond;
  late AppSettings settings;
  late NetState net;
  late String baseUrl;
  late f.FakeTts tts;
  late FakeEngine engine;
  late MemoryStore memory;
  late ChatController chat;
  late List<AppSettings> settingUpdates;
  // When set, the mock backend waits on this before answering (simulates a
  // slow/stuck network request).
  Future<void>? Function(int call)? hold;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    respond = (_) => http.Response.bytes(
      utf8.encode(sse([('final', reply())])),
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );
    settings = const AppSettings(cloudVoiceEnabled: false);
    net = NetState(hasNetwork: true, backendReachable: true, health: healthy);
    baseUrl = 'http://sahbi.test';
    settingUpdates = [];
    hold = null;

    final store = MemoryKeyValueStore()..data['install_token'] = 'v1.test';
    final backend = BackendClient(
      baseUrl: () => baseUrl,
      store: store,
      client: MockClient((req) async {
        calls.add(req);
        final h = hold?.call(calls.length);
        if (h != null) await h;
        return respond(req);
      }),
    );
    tts = f.FakeTts('device');
    final log = ErrorLog();
    final voice = VoiceController(
      deviceStt: f.FakeStt('device'),
      cloudStt: f.FakeStt('cloud'),
      deviceTts: tts,
      cloudTts: f.FakeTts('cloud'),
      settings: () => settings,
      cloudSttReady: () => false,
      cloudTtsReady: () => false,
      log: log,
    );
    engine = FakeEngine();
    final music = MusicController(
      engine: engine,
      bridge: FakeBridge(),
      prefs: await SharedPreferences.getInstance(),
    );
    memory = MemoryStore(
      keyStore: MemoryKeyValueStore(),
      blob: InMemoryBlobStorage(),
    );
    await memory.load();
    chat = ChatController(
      backend: backend,
      settings: () => settings,
      net: () => net,
      voice: voice,
      music: music,
      memory: memory,
      companion: CompanionController(),
      log: log,
      hooks: ChatHooks(
        updateSettings: (u) {
          settings = u(settings);
          settingUpdates.add(settings);
        },
      ),
    );
  });

  ChatMessage last() => chat.messages.last;
  Map<String, dynamic> lastBody() =>
      jsonDecode(calls.last.body) as Map<String, dynamic>;

  group('honest offline mode (no network call, labelled reason)', () {
    Future<void> expectOffline(String reason) async {
      await chat.send('kifach dayr?');
      expect(calls, isEmpty);
      expect(last().kind, ChatKind.offline);
      expect(last().errorCode, reason);
      expect(last().text, isNotEmpty);
      expect(
        tts.spoken,
        isNotEmpty,
        reason: 'offline replies are still spoken',
      );
    }

    test('AI disabled in privacy settings', () async {
      settings = const AppSettings(sendToAi: false, cloudVoiceEnabled: false);
      await expectOffline('ai_disabled');
    });
    test('no backend URL', () async {
      baseUrl = '';
      await expectOffline('backend_not_set');
    });
    test('no network', () async {
      net = const NetState(hasNetwork: false);
      await expectOffline('no_internet');
    });
    test('server unreachable', () async {
      net = const NetState(hasNetwork: true, backendReachable: false);
      await expectOffline('server_unreachable');
    });
    test('server up but no LLM key configured', () async {
      net = const NetState(hasNetwork: true, backendReachable: true);
      await expectOffline('ai_not_configured');
    });
  });

  group('local commands run offline and report real results', () {
    test('"ch3el lia chi music" plays demo tracks and stays quiet', () async {
      net = const NetState(hasNetwork: false);
      await chat.send('ch3el lia chi music');
      expect(calls, isEmpty);
      expect(last().kind, ChatKind.command);
      expect(last().results.single.ok, isTrue);
      expect(engine.calls, contains('play'));
      expect(
        tts.spoken,
        isEmpty,
        reason: 'does not talk over the music it just started',
      );
    });
    test('pause with nothing playing is reported as a failure', () async {
      await chat.send('pause');
      expect(last().results.single.ok, isFalse);
      expect(calls, isEmpty);
    });
    test('changing reply language goes through settings', () async {
      await chat.send('hder m3aya b lfransawiya');
      expect(settingUpdates.last.replyLanguage, 'fr');
    });
    test('commands never reach the AI even when it is available', () async {
      await chat.send('7bes lmusic');
      expect(calls, isEmpty);
      expect(last().kind, ChatKind.command);
    });
    test('"3qel 3la" without memory consent stores nothing', () async {
      await chat.send('3qel 3la smiti Yassine');
      expect(last().results.single.message, 'memory_off');
      expect(memory.facts, isEmpty);
    });
    test('"3qel 3la" with consent stores the fact', () async {
      await memory.setConsent(facts: true, history: false);
      await chat.send('3qel 3la smiti Yassine');
      expect(last().results.single.ok, isTrue);
      expect(memory.facts.single.text, contains('yassine'));
    });
  });

  group('AI brain over SSE', () {
    test(
      'streams status/delta, then shows and speaks the validated reply',
      () async {
        respond = (_) => http.Response.bytes(
          utf8.encode(
            sse([
              ('status', {'phase': 'thinking'}),
              ('delta', {'text': 'Sal'}),
              ('final', reply()),
            ]),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
        await chat.send('salam');
        expect(calls.single.url.path, '/v1/chat');
        expect(calls.single.headers['authorization'], 'Bearer v1.test');
        expect(last().kind, ChatKind.ai);
        expect(last().streaming, isFalse);
        expect(last().text, 'Salam a sahbi!');
        expect(
          tts.spoken.single,
          'darija:سلام أ صاحبي',
          reason: 'TTS uses tts_text (Arabic script)',
        );
        expect(chat.context.turns.length, 2);
      },
    );

    test(
      'request carries settings, history and memory only with consent',
      () async {
        settings = const AppSettings(
          cloudVoiceEnabled: false,
          userName: 'Yassine',
          darijaScript: 'latin',
        );
        await chat.send('salam');
        var body = lastBody();
        expect(body['message'], 'salam');
        expect(body['settings']['user_name'], 'Yassine');
        expect(body['settings']['darija_script'], 'latin');
        expect(body.containsKey('memory'), isFalse);
        await memory.setConsent(facts: true, history: false);
        await memory.addFact('kaybghi atay');
        await chat.send('chno kan3ref 3lik?');
        body = lastBody();
        expect(body['memory']['facts'], ['kaybghi atay']);
        expect((body['history'] as List).length, 2);
      },
    );

    test(
      'actions are executed locally and their REAL results recorded',
      () async {
        respond = (_) => http.Response.bytes(
          utf8.encode(
            sse([
              (
                'final',
                reply(
                  actions: [
                    // Flat shape, exactly as the backend's zod schema emits it.
                    {'type': 'music.pause'},
                    {'type': 'set_volume', 'level': 0.3},
                    {'type': 'unsupported.thing'},
                  ],
                ),
              ),
            ]),
          ),
          200,
        );
        await chat.send('ana 3iyan bzaf lyoum, dir chi 7aja');
        expect(
          calls,
          hasLength(1),
          reason: 'went to the AI, not the local parser',
        );
        final r = last().results;
        expect(
          r.length,
          2,
          reason: 'unsupported actions are ignored, not faked',
        );
        expect(
          r[0].ok,
          isFalse,
          reason: 'nothing was playing — never claim success',
        );
        expect(r[1].ok, isTrue);
      },
    );

    test(
      'server error event → retryable error bubble, nothing spoken',
      () async {
        respond = (_) => http.Response.bytes(
          utf8.encode(
            sse([
              ('error', {'code': 'rate_limited', 'message': 'slow down'}),
            ]),
          ),
          200,
        );
        await chat.send('salam');
        expect(last().kind, ChatKind.error);
        expect(last().errorCode, 'rateLimited');
        expect(last().retryText, 'salam');
        expect(tts.spoken, isEmpty);

        respond = (_) =>
            http.Response.bytes(utf8.encode(sse([('final', reply())])), 200);
        await chat.retry(last());
        expect(last().kind, ChatKind.ai);
        expect(chat.messages.where((m) => m.kind == ChatKind.error), isEmpty);
      },
    );

    test('invalid model output is surfaced as invalid_output', () async {
      respond = (_) => http.Response.bytes(
        utf8.encode(
          sse([
            ('final', {'display_text': 'x'}),
          ]),
        ),
        200,
      );
      await chat.send('salam');
      expect(last().kind, ChatKind.error);
      expect(last().errorCode, 'invalidOutput');
    });

    test(
      'stream that ends without a final reply is an error, not silence',
      () async {
        respond = (_) => http.Response.bytes(
          utf8.encode(
            sse([
              ('delta', {'text': 'half'}),
            ]),
          ),
          200,
        );
        await chat.send('salam');
        expect(last().kind, ChatKind.error);
        expect(last().text, isEmpty);
      },
    );

    test('HTTP 503 not_configured maps to its code', () async {
      respond = (_) => http.Response(
        jsonEncode({
          'error': {'code': 'not_configured', 'message': 'x'},
        }),
        503,
      );
      await chat.send('salam');
      expect(last().errorCode, 'notConfigured');
    });

    test('a camera photo is sent as base64 JPEG and answered', () async {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3, 0xFF, 0xD9]);
      final at = await chat.sendPhoto(jpeg, 'chno hada?');
      expect(at, 0);
      expect(chat.messages[0].role, ChatRole.user);
      expect(chat.messages[0].text, contains('chno hada?'));
      final body = lastBody();
      expect(body['message'], 'chno hada?');
      expect(body['image'], {'mime': 'image/jpeg', 'data': base64Encode(jpeg)});
      expect(last().kind, ChatKind.ai);
      expect(last().text, 'Salam a sahbi!');
      expect(tts.spoken, isNotEmpty);
    });

    test('plain messages never carry an image; failed photos are not '
        'retried as text', () async {
      await chat.send('kifach dayr?');
      expect(lastBody().containsKey('image'), isFalse);
      respond = (_) =>
          http.Response('{"error":{"code":"x","message":"y"}}', 500);
      await chat.sendPhoto(
        Uint8List.fromList(List.filled(20, 7)),
        'chno hada?',
      );
      expect(last().kind, ChatKind.error);
      expect(last().retryText, isNull);
    });

    test('LLM emotion drives the face', () async {
      respond = (_) => http.Response.bytes(
        utf8.encode(sse([('final', reply(emotion: 'surprised'))])),
        200,
      );
      await chat.send('wach 3reft?');
      expect(chat.companion.emotion, Emotion.surprised);
    });

    test('clear() wipes messages and context', () async {
      await chat.send('salam');
      chat.clear();
      expect(chat.messages, isEmpty);
      expect(chat.context.turns, isEmpty);
    });
  });

  group('superseded / stopped requests', () {
    bool isStreaming(ChatMessage m) => m.role == ChatRole.sahbi && m.streaming;

    test(
      'a new message while the AI is stuck does not hang either send',
      () async {
        final never = Completer<void>();
        // only the /v1/chat call #1 hangs
        hold = (n) => n == 1 ? never.future : null;
        var firstDone = false;
        unawaited(chat.send('first').then((_) => firstDone = true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(chat.busy, isTrue);

        await chat.send('second').timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(firstDone, isTrue, reason: 'superseded send() must complete');
        expect(chat.busy, isFalse);
        expect(
          chat.messages.where(isStreaming),
          isEmpty,
          reason: 'no bubble may stay in "thinking" forever',
        );
        expect(chat.messages.last.text, 'Salam a sahbi!');
      },
    );

    test('superseded request then offline input still clears busy', () async {
      final never = Completer<void>();
      hold = (n) => n == 1 ? never.future : null;
      unawaited(chat.send('first'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      net = NetState(hasNetwork: false, backendReachable: false);
      await chat.send('second').timeout(const Duration(seconds: 2));
      expect(chat.busy, isFalse);
      expect(chat.messages.last.kind, ChatKind.offline);
      expect(chat.messages.where(isStreaming), isEmpty);
    });

    test(
      'stop() cancels a pending AI request (stop button is not dead)',
      () async {
        final never = Completer<void>();
        hold = (_) => never.future;
        var done = false;
        unawaited(chat.send('salam').then((_) => done = true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(chat.busy, isTrue);

        await chat.stop().timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(done, isTrue);
        expect(chat.busy, isFalse);
        expect(chat.messages.where(isStreaming), isEmpty);
        expect(
          chat.messages.last.role,
          ChatRole.user,
          reason: 'the empty "thinking" bubble is removed, nothing is faked',
        );
      },
    );
  });

  group('sleeping backend (free hosting wakes in ~1 min)', () {
    void withWake(Future<void> Function() wake) {
      chat.hooks = ChatHooks(updateSettings: (_) {}, wakeBackend: wake);
    }

    bool isStreaming(ChatMessage m) => m.role == ChatRole.sahbi && m.streaming;

    test(
      'shows "waking", then answers with the AI once the server is up',
      () async {
        net = const NetState(hasNetwork: true, backendReachable: false);
        final gate = Completer<void>();
        var wakeCalls = 0;
        withWake(() async {
          wakeCalls++;
          await gate.future;
          net = NetState(
            hasNetwork: true,
            backendReachable: true,
            health: healthy,
          );
        });
        final sending = chat.send('salam');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(chat.busy, isTrue);
        expect(chat.messages.last.phase, 'waking');
        expect(
          calls,
          isEmpty,
          reason: 'no chat request before the server is awake',
        );

        gate.complete();
        await sending;
        expect(wakeCalls, 1);
        expect(chat.messages.where((m) => m.phase == 'waking'), isEmpty);
        expect(chat.messages.last.kind, ChatKind.ai);
        expect(chat.messages.last.text, 'Salam a sahbi!');
        expect(chat.busy, isFalse);
      },
    );

    test('server still down after waiting: honest offline reply', () async {
      net = const NetState(hasNetwork: true, backendReachable: false);
      withWake(() async {});
      await chat.send('salam');
      expect(chat.messages.last.kind, ChatKind.offline);
      expect(chat.messages.last.errorCode, 'server_unreachable');
      expect(chat.messages.where(isStreaming), isEmpty);
      expect(chat.busy, isFalse);
      expect(calls, isEmpty);
    });

    test('woke up but AI key missing: says "AI not configured"', () async {
      net = const NetState(hasNetwork: true, backendReachable: false);
      withWake(() async {
        net = const NetState(hasNetwork: true, backendReachable: true);
      });
      await chat.send('salam');
      expect(chat.messages.last.errorCode, 'ai_not_configured');
    });

    test(
      'stop while waking cancels cleanly (no offline line, no bubble)',
      () async {
        net = const NetState(hasNetwork: true, backendReachable: false);
        withWake(() => Completer<void>().future); // never wakes
        var done = false;
        unawaited(chat.send('salam').then((_) => done = true));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await chat.stop().timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(done, isTrue);
        expect(chat.busy, isFalse);
        expect(chat.messages.where(isStreaming), isEmpty);
        expect(chat.messages.last.role, ChatRole.user);
      },
    );

    test('other offline reasons never trigger a wake', () async {
      net = const NetState(hasNetwork: false);
      var woke = false;
      withWake(() async => woke = true);
      await chat.send('salam');
      expect(woke, isFalse);
      expect(chat.messages.last.errorCode, 'no_internet');
    });
  });

  group('follow-up 6: proactive lines and photos', () {
    test(
      'proactive() asks in proactive mode, speaks, adds no user turn',
      () async {
        respond = (_) => http.Response.bytes(
          utf8.encode(sse([('final', reply(display: 'Nokta: ...'))])),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
        final spoke = await chat.proactive();
        expect(spoke, isTrue);
        expect(lastBody()['mode'], 'proactive');
        expect(chat.messages.where((m) => m.role == ChatRole.user), isEmpty);
        expect(last().proactive, isTrue);
        expect(last().text, 'Nokta: ...');
        expect(tts.spoken, isNotEmpty);
        expect(chat.robotTalking, isFalse);
        // Only the robot's line goes into the conversation context.
        expect(chat.context.turns.map((t) => t.role), ['assistant']);
      },
    );

    test('proactive() stays silent offline and on server errors', () async {
      net = const NetState(hasNetwork: false);
      expect(await chat.proactive(), isFalse);
      expect(calls, isEmpty);
      expect(chat.messages, isEmpty);
      net = NetState(hasNetwork: true, backendReachable: true, health: healthy);
      respond = (_) => http.Response('{"error":{"code":"x"}}', 500);
      expect(await chat.proactive(), isFalse);
      expect(chat.messages, isEmpty, reason: 'no error bubble');
    });

    test('proactive lines never run music or settings actions', () async {
      respond = (_) => http.Response.bytes(
        utf8.encode(
          sse([
            (
              'final',
              reply(
                actions: [
                  {'type': 'music.play', 'query': 'x'},
                ],
              ),
            ),
          ]),
        ),
        200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
      await chat.proactive();
      expect(engine.calls, isNot(contains('play')));
    });

    test('image.show fetches photos and attaches them', () async {
      respond = (req) {
        if (req.url.path == '/v1/images') {
          expect(req.url.queryParameters['q'], 'Chefchaouen');
          return http.Response(
            jsonEncode({
              'images': [
                {
                  'url': 'https://upload.wikimedia.org/a/800px-Chef.jpg',
                  'title': 'Chefchaouen',
                  'page': 'https://en.wikipedia.org/wiki/Chefchaouen',
                  'source': 'Wikipedia',
                },
                {'url': 'https://evil.example/x.jpg', 'title': 'bad'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            sse([
              (
                'final',
                reply(
                  display: 'Chefchaouen, lmdina zer9a!',
                  actions: [
                    {'type': 'image.show', 'query': 'Chefchaouen'},
                  ],
                ),
              ),
            ]),
          ),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      };
      await chat.send('wrini tswira dyal chefchaouen');
      final m = last();
      expect(m.images.map((i) => i.url), [
        'https://upload.wikimedia.org/a/800px-Chef.jpg',
      ], reason: 'only Wikimedia image hosts are accepted');
      expect(m.results.single.ok, isTrue);
      expect(chat.shownImages, hasLength(1));
      expect(chat.shownImagesQuery, 'Chefchaouen');
      expect(tts.spoken.single, contains('سلام'));
      // A new message clears the photos from the face screen.
      respond = (_) => http.Response.bytes(
        utf8.encode(sse([('final', reply())])),
        200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
      await chat.send('chokran');
      expect(chat.shownImages, isEmpty);
      expect(m.images, hasLength(1), reason: 'still in the chat history');
    });

    test('image.show with no results reports it honestly', () async {
      respond = (req) => req.url.path == '/v1/images'
          ? http.Response('{"images":[]}', 200)
          : http.Response.bytes(
              utf8.encode(
                sse([
                  (
                    'final',
                    reply(
                      actions: [
                        {'type': 'image.show', 'query': 'zzzz'},
                      ],
                    ),
                  ),
                ]),
              ),
              200,
              headers: {'content-type': 'text/event-stream; charset=utf-8'},
            );
      await chat.send('wrini zzzz');
      expect(last().images, isEmpty);
      expect(last().results.single.ok, isFalse);
      expect(last().results.single.message, startsWith('images_not_found'));
    });
  });

  group('strong character (temper)', () {
    test('an insult: he sulks at once, no AI request', () async {
      await chat.send('nta 7mar');
      expect(calls, isEmpty);
      expect(chat.companion.temper.sulking, isTrue);
      expect(last().role, ChatRole.sahbi);
      expect(last().text, isNotEmpty);
      expect(chat.companion.lookAt, isNotNull, reason: 'turned away');
    });

    test(
      'sulking: refuses a skit; "sme7 li" makes up; then he does it',
      () async {
        await chat.send('ya bhim');
        await chat.send('haz ydik');
        expect(calls, isEmpty);
        expect(chat.companion.act, isNot(FaceAct.handsUp));
        expect(last().text, isNotEmpty);
        await chat.send('sme7 li');
        expect(calls, isEmpty);
        expect(chat.companion.temper.sulking, isFalse);
        expect(chat.companion.act, FaceAct.love);
        await chat.send('haz ydik 3afak');
        expect(chat.companion.act, FaceAct.handsUp);
      },
    );

    test('real requests still go to the AI, with the mood', () async {
      await chat.send('nta 7mar');
      await chat.send('chno hiya 3asima dyal lyaban?');
      expect(calls, isNotEmpty);
      final state = (lastBody()['client'] as Map)['app_state'] as String;
      expect(state, contains('SULKING'));
    });
  });
}
