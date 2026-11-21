import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/error_log.dart';
import 'package:sahbi/features/chat/chat_models.dart';
import 'package:sahbi/features/live/scene_watcher.dart';
import 'package:sahbi/features/music/youtube_controller.dart';
import 'package:sahbi/features/personality/voice_state.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/conversation_session.dart';
import 'package:sahbi/features/voice/voice_types.dart';
import 'package:sahbi/features/voice/wake_name.dart';

class _Voice extends ChangeNotifier {
  VoiceState state = VoiceState.idle;
  void go(VoiceState s) {
    state = s;
    notifyListeners();
  }
}

class _Surface implements YoutubeSurface {
  int resumes = 0;
  int pauses = 0;
  final volumes = <int>[];
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> resume() async => resumes++;
  @override
  Future<void> setVolume(int volume) async => volumes.add(volume);
}

Future<void> _tick([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('isStopPhrase ("safi sir" ends the conversation)', () {
    test('goodbyes in Darija (both scripts), French and English', () {
      for (final t in [
        'safi sir',
        'Safi sir!',
        'safiii siiir',
        'safi',
        'safi barak',
        'safi chokran',
        'sir t3ess',
        'baraka',
        'bslama',
        'صافي سير',
        'صافي',
        'سير تعس',
        'بسلامة',
        'safi sir a sahbi',
        'ya sahbi safi sir',
        'c\'est bon merci',
        'au revoir',
        'goodbye',
        'bye bye',
        'good night',
      ]) {
        expect(isStopPhrase(t), isTrue, reason: t);
      }
    });
    test('the robot\'s own name around the goodbye', () {
      expect(isStopPhrase('Zizou safi sir', robotName: 'Zizou'), isTrue);
      expect(isStopPhrase('safi a zizou', robotName: 'Zizou'), isTrue);
    });
    test('normal sentences keep the conversation going', () {
      for (final t in [
        'safi chno ljaw lyoum?',
        'sir l dar dyali',
        'wach kayn chi music',
        'salut',
        'safi sir 3la rassek wjib lia atay', // more than a goodbye
        '',
        'baraka mn lhdra 3la lmatch, chno kayn jdid?',
      ]) {
        expect(isStopPhrase(t), isFalse, reason: t);
      }
    });
  });

  group('ConversationSession', () {
    late _Voice voice;
    late int listens;
    late bool music;
    late bool blocked;
    late bool busy;
    late List<bool> activeChanges;
    late int goodbyes;
    late ConversationSession c;

    setUp(() {
      voice = _Voice();
      listens = 0;
      music = false;
      blocked = false;
      busy = false;
      activeChanges = [];
      goodbyes = 0;
      c = ConversationSession(
        voiceState: () => voice.state,
        voiceChanges: voice,
        listen: () async {
          listens++;
          voice.go(VoiceState.listening);
        },
        chatBusy: () => busy,
        musicPlaying: () => music,
        blocked: () => blocked,
        onActiveChanged: activeChanges.add,
        onGoodbye: () async => goodbyes++,
        followUpDelay: const Duration(milliseconds: 5),
      );
    });
    tearDown(() => c.dispose());

    Future<void> userTurn() async {
      voice.go(VoiceState.thinking); // words heard
      voice.go(VoiceState.speaking);
      voice.go(VoiceState.idle);
      await _tick();
    }

    test('after the answer the mic reopens without the name', () async {
      c.start();
      expect(activeChanges, [true]);
      voice.go(VoiceState.listening); // the wake flow opened the mic
      await userTurn();
      expect(listens, 1);
      await userTurn();
      expect(listens, 2);
      expect(c.active, isTrue);
    });

    test('two silent listens in a row end it', () async {
      c.start();
      voice.go(VoiceState.listening);
      voice.go(VoiceState.idle); // nothing heard
      await _tick();
      expect(listens, 1, reason: 'one more chance');
      voice.go(VoiceState.idle);
      await _tick();
      expect(c.active, isFalse);
      expect(activeChanges, [true, false]);
      expect(listens, 1);
    });

    test('words reset the silence count; errors count as silence', () async {
      c.start();
      voice.go(VoiceState.listening);
      voice.go(VoiceState.idle);
      await _tick(); // silent 1 → listening again
      await userTurn(); // words → reset
      expect(c.active, isTrue);
      voice.go(VoiceState.error);
      voice.go(VoiceState.idle);
      await _tick();
      expect(c.active, isTrue, reason: 'only one silent listen since words');
    });

    test('"safi sir" ends it, says goodbye, and is not sent on', () async {
      c.start();
      expect(c.handleFinalText('wach kayn chi jdid?'), isFalse);
      expect(c.handleFinalText('safi sir'), isTrue);
      await _tick(1);
      expect(c.active, isFalse);
      expect(goodbyes, 1);
      // Outside a conversation nothing is intercepted.
      expect(c.handleFinalText('safi sir'), isFalse);
    });

    test('music or another screen ends it instead of listening', () async {
      c.start();
      voice.go(VoiceState.listening);
      music = true;
      await userTurn();
      expect(listens, 0);
      expect(c.active, isFalse);

      music = false;
      c.start();
      voice.go(VoiceState.listening);
      blocked = true;
      await userTurn();
      expect(listens, 0);
      expect(c.active, isFalse);
    });

    test('waits while the chat is still busy', () async {
      c.start();
      voice.go(VoiceState.listening);
      busy = true;
      await userTurn();
      expect(listens, 0);
      busy = false;
      await _tick(600);
      expect(listens, 1);
    });

    test('robot-initiated: listens now, one silence ends it, an answer '
        'turns it into a real conversation', () async {
      c.start(robotInitiated: true, listenNow: true);
      expect(c.robotInitiated, isTrue);
      await _tick();
      expect(listens, 1);
      voice.go(VoiceState.idle); // no answer
      await _tick();
      expect(c.active, isFalse);

      c.start(robotInitiated: true, listenNow: true);
      await _tick();
      expect(c.handleFinalText('hhh zwina'), isFalse);
      expect(c.robotInitiated, isFalse);
    });
  });

  group('WakeNameController and music', () {
    test('does not listen for the name while music plays', () async {
      var playing = true;
      var listens = 0;
      final w = WakeNameController(
        listen: (_) {
          listens++;
          return const Stream<SttEvent>.empty();
        },
        cancel: () async {},
        settings: () => const AppSettings(),
        voiceState: () => VoiceState.idle,
        micGranted: () async => true,
        onWake: () async {},
        onCommand: (_) {},
        log: ErrorLog(),
        musicPlaying: () => playing,
        restartDelay: const Duration(milliseconds: 5),
      );
      w.refresh();
      await _tick();
      expect(listens, 0);
      playing = false;
      w.refresh();
      await _tick();
      expect(listens, greaterThan(0));
      w.setConversation(true);
      expect(w.active, isFalse);
      expect(w.externallyBlocked, isFalse);
      w.suspend();
      expect(w.externallyBlocked, isTrue);
      w.dispose();
    });
  });

  group('YoutubeController auto-resume', () {
    late DateTime now;
    late YoutubeController yt;
    late _Surface surface;
    late bool micFree;

    setUp(() async {
      now = DateTime(2026, 11, 21, 12);
      micFree = true;
      surface = _Surface();
      yt = YoutubeController(
        search: (_) async => const [
          YoutubeVideo(id: 'aaaaaaaaaaa', title: 'A'),
          YoutubeVideo(id: 'bbbbbbbbbbb', title: 'B'),
        ],
        clock: () => now,
        canAutoResume: () => micFree,
        resumeEvery: const Duration(milliseconds: 5),
      )..surface = surface;
      await yt.playSearch('x');
    });
    tearDown(() => yt.dispose());

    test('a pause the user did not ask for is resumed', () async {
      yt.onPlayerState(playingNow: false);
      expect(yt.state, YoutubeState.playing);
      expect(yt.interrupted, isTrue);
      await _tick();
      expect(surface.resumes, greaterThan(0));
      yt.onPlayerState(playingNow: true);
      expect(yt.interrupted, isFalse);
    });

    test('waits while the mic is listening', () async {
      micFree = false;
      yt.onPlayerState(playingNow: false);
      await _tick();
      expect(surface.resumes, 0);
      micFree = true;
      await _tick();
      expect(surface.resumes, greaterThan(0));
      yt.onPlayerState(playingNow: true);
    });

    test('a pause right after touching the player is respected', () async {
      yt.userTouchedPlayer();
      now = now.add(const Duration(milliseconds: 800));
      yt.onPlayerState(playingNow: false);
      expect(yt.state, YoutubeState.paused);
      expect(yt.interrupted, isFalse);
      await _tick();
      expect(surface.resumes, 0);
    });

    test('our own pause is respected', () async {
      await yt.pause();
      yt.onPlayerState(playingNow: false);
      expect(yt.state, YoutubeState.paused);
      expect(yt.interrupted, isFalse);
    });

    test('gives up after maxAutoResumes (play button still works)', () async {
      yt.onPlayerState(playingNow: false);
      await _tick(200);
      expect(surface.resumes, YoutubeController.maxAutoResumes);
      expect(yt.state, YoutubeState.paused);
      expect(yt.interrupted, isFalse);
      // A new song gets a fresh budget.
      await yt.next();
      expect(yt.autoResumes, 0);
    });

    test('ducks the song while the robot talks', () async {
      await yt.duck(true);
      await yt.duck(false);
      expect(surface.volumes, [25, 100]);
    });

    test('stop cancels a pending resume', () async {
      micFree = false;
      yt.onPlayerState(playingNow: false);
      await yt.stop();
      micFree = true;
      await _tick();
      expect(surface.resumes, 0);
    });
  });

  group('SceneWatcher (camera explains without being asked)', () {
    late DateTime now;
    late SceneWatcher w;
    SceneSignature flat(int v) =>
        Uint8List.fromList(List.filled(sceneSigW * sceneSigH, v));
    SceneSignature pattern(int seed) => Uint8List.fromList([
      for (var i = 0; i < sceneSigW * sceneSigH; i++)
        ((i * 37 + seed * 91) % 251),
    ]);

    setUp(() {
      now = DateTime(2026, 11, 21, 12);
      w = SceneWatcher(clock: () => now);
    });

    bool feed(SceneSignature s, {bool busy = false}) {
      now = now.add(const Duration(seconds: 1));
      return w.onFrame(s, robotBusy: busy);
    }

    test('explains once when held still, not again for the same view', () {
      final a = pattern(1);
      expect(feed(a), isFalse); // first frame
      expect(feed(a), isFalse); // stable 1
      expect(feed(a), isTrue); // stable 2 → explain
      for (var i = 0; i < 10; i++) {
        expect(feed(a), isFalse);
      }
    });

    test('a new steady view is explained after the gap', () {
      final a = pattern(1), b = pattern(2);
      feed(a);
      feed(a);
      expect(feed(a), isTrue);
      expect(feed(b), isFalse); // moving
      expect(feed(b), isFalse);
      expect(feed(b), isFalse, reason: 'stable, but within minGap (7 s)');
      for (var i = 0; i < 4; i++) {
        feed(b);
      }
      expect(feed(b), isFalse, reason: 'already explained when gap passed');
    });

    test('not while moving, while the robot talks, or right after the user '
        'spoke about it', () {
      final a = pattern(3), b = pattern(4);
      for (var i = 0; i < 6; i++) {
        expect(feed(i.isEven ? a : b), isFalse);
      }
      feed(a);
      feed(a);
      expect(feed(a, busy: true), isFalse);
      w
        ..userSpoke()
        ..markDescribed();
      expect(feed(a), isFalse);
      expect(feed(a), isFalse);
    });

    test('brightness changes alone are not motion', () {
      expect(sceneDistance(flat(100), flat(140)), 0);
      expect(sceneDistance(pattern(1), pattern(2)), greaterThan(22));
    });
  });

  test('ChatImage only accepts Wikimedia image hosts over https', () {
    expect(
      ChatImage.fromJson({'url': 'https://upload.wikimedia.org/a.jpg'}),
      isNotNull,
    );
    expect(
      ChatImage.fromJson({
        'url': 'https://thumb.wikimedia.org/a.jpg?utm_source=x',
      }),
      isNotNull,
    );
    expect(
      ChatImage.fromJson({'url': 'http://upload.wikimedia.org/a.jpg'}),
      isNull,
    );
    expect(ChatImage.fromJson({'url': 'https://evil.example/a.jpg'}), isNull);
    expect(ChatImage.fromJson('nope'), isNull);
  });

  test('settings: proactive talk and live auto-describe default on and '
      'persist', () {
    const d = AppSettings();
    expect(d.proactiveTalk, isTrue);
    expect(d.liveAutoDescribe, isTrue);
    final back = AppSettings.decode(
      d.copyWith(proactiveTalk: false, liveAutoDescribe: false).encode(),
    );
    expect(back.proactiveTalk, isFalse);
    expect(back.liveAutoDescribe, isFalse);
  });
}
