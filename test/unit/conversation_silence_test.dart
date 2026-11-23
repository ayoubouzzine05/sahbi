import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/personality/voice_state.dart';
import 'package:sahbi/features/voice/conversation_session.dart';

class _Voice extends ChangeNotifier {
  VoiceState state = VoiceState.idle;
  void go(VoiceState s) {
    state = s;
    notifyListeners();
  }
}

Future<void> _tick([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _Voice voice;
  late DateTime now;
  late int listens;
  late ConversationSession c;

  setUp(() {
    voice = _Voice();
    now = DateTime(2026, 11, 23, 12);
    listens = 0;
    c = ConversationSession(
      voiceState: () => voice.state,
      voiceChanges: voice,
      listen: () async {
        listens++;
        voice.go(VoiceState.listening);
      },
      chatBusy: () => false,
      musicPlaying: () => false,
      blocked: () => false,
      followUpDelay: const Duration(milliseconds: 5),
      silenceTimeout: () => const Duration(seconds: 20),
      clock: () => now,
    );
  });
  tearDown(() => c.dispose());

  Future<void> silentListen(int seconds) async {
    now = now.add(Duration(seconds: seconds));
    voice.go(VoiceState.idle); // listen ended without words
    await _tick();
  }

  test('keeps listening through short silences, ends after 20 s', () async {
    c.start(listenNow: true);
    await _tick();
    expect(listens, 1);
    await silentListen(7);
    expect(c.active, isTrue, reason: '7 s');
    await silentListen(7);
    expect(c.active, isTrue, reason: '14 s');
    await silentListen(7);
    expect(c.active, isFalse, reason: '21 s of silence');
  });

  test('anything the user says restarts the 20 s', () async {
    c.start(listenNow: true);
    await _tick();
    await silentListen(15);
    expect(c.handleFinalText('chno ljaw?'), isFalse);
    voice.go(VoiceState.thinking);
    voice.go(VoiceState.speaking);
    voice.go(VoiceState.idle);
    await _tick();
    await silentListen(15);
    expect(c.active, isTrue);
  });

  test('"safi sir" still ends it at once', () async {
    c.start(listenNow: true);
    await _tick();
    expect(c.handleFinalText('safi sir'), isTrue);
    expect(c.active, isFalse);
  });
}
