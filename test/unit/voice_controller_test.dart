import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/error_log.dart';
import 'package:sahbi/features/personality/voice_state.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/voice_controller.dart';
import 'package:sahbi/features/voice/voice_types.dart';

import '../support/fakes.dart' as f;

void main() {
  late f.FakeStt dStt, cStt;
  late f.FakeTts dTts, cTts;
  late AppSettings settings;
  late bool cloudReady;
  late VoiceController v;
  late List<String> finals;
  late List<bool> ducks;

  setUp(() {
    dStt = f.FakeStt('device');
    cStt = f.FakeStt('cloud');
    dTts = f.FakeTts('device');
    cTts = f.FakeTts('cloud');
    settings = const AppSettings();
    cloudReady = true;
    finals = [];
    ducks = [];
    v = VoiceController(
      deviceStt: dStt,
      cloudStt: cStt,
      deviceTts: dTts,
      cloudTts: cTts,
      settings: () => settings,
      cloudSttReady: () => cloudReady,
      cloudTtsReady: () => cloudReady,
      log: ErrorLog(),
      onFinalText: finals.add,
      onDuckMusic: ducks.add,
    );
  });

  group('STT fallback order: cloud → device → typed', () {
    test('cloud when the backend has STT configured', () async {
      expect(await v.resolveStt(), 'cloud');
    });
    test('device when the server has no STT', () async {
      cloudReady = false;
      expect(await v.resolveStt(), 'device');
    });
    test('device when the user disabled cloud voice', () async {
      settings = const AppSettings(cloudVoiceEnabled: false);
      expect(await v.resolveStt(), 'device');
    });
    test('typed when no recogniser exists at all', () async {
      cloudReady = false;
      dStt.avail = ProviderAvailability.notInstalled;
      expect(await v.startListening(), 'typed');
      expect(v.lastError, 'no_recognizer');
      expect(v.state, VoiceState.idle);
    });
    test('mode=device never uses cloud; mode=typed never listens', () async {
      settings = const AppSettings(sttMode: SttMode.device);
      expect(await v.resolveStt(), 'device');
      settings = const AppSettings(sttMode: SttMode.typed);
      expect(await v.resolveStt(), 'typed');
    });
    test('mode=cloud does not silently use the device engine', () async {
      settings = const AppSettings(sttMode: SttMode.cloud);
      cStt.avail = ProviderAvailability.offline;
      expect(await v.resolveStt(), 'typed');
    });
    test(
      'a cloud network failure makes the next listen use the device',
      () async {
        expect(await v.startListening(), 'cloud');
        cStt.emit(const SttFailure('network', 'timeout'));
        await pumpEvents();
        expect(v.lastError, 'network');
        expect(v.state, VoiceState.idle);
        expect(await v.resolveStt(), 'device');
        v.resetFallbacks();
        expect(await v.resolveStt(), 'cloud');
      },
    );
  });

  group('listening', () {
    test(
      'final text goes to the shared pipeline; partials and level are exposed',
      () async {
        cloudReady = false;
        await v.startListening();
        expect(dStt.lastLocale, 'ar-MA');
        expect(v.micOpen, isTrue);
        dStt.emit(const SttLevel(0.7));
        dStt.emit(const SttPartial('chno'));
        await pumpEvents();
        expect(v.level, 0.7);
        expect(v.partial, 'chno');
        dStt.emit(const SttFinal('  chno l7al  '));
        await pumpEvents();
        expect(finals, ['chno l7al']);
        expect(v.micOpen, isFalse);
        expect(v.state, VoiceState.thinking);
      },
    );
    test('locale follows the reply language', () async {
      cloudReady = false;
      settings = const AppSettings(replyLanguage: 'fr');
      await v.startListening();
      expect(dStt.lastLocale, 'fr-FR');
    });
    test(
      'no_match returns quietly to idle; empty final sends nothing',
      () async {
        cloudReady = false;
        await v.startListening();
        dStt.emit(const SttFailure('no_match', ''));
        await pumpEvents();
        expect(v.state, VoiceState.idle);
        await v.startListening();
        dStt.emit(const SttFinal('   '));
        await pumpEvents();
        expect(finals, isEmpty);
      },
    );
    test('cancel aborts without a result', () async {
      cloudReady = false;
      await v.startListening();
      await v.cancelListening();
      expect(dStt.cancels, 1);
      expect(v.state, VoiceState.idle);
      expect(v.micOpen, isFalse);
    });
  });

  group('TTS', () {
    test('cloud TTS speaks, ducks music and reports word timings', () async {
      cTts.words = 3;
      expect(await v.speak('salam', language: 'darija'), isTrue);
      expect(cTts.spoken, ['darija:salam']);
      expect(v.hasWordTimings, isTrue);
      expect(v.wordPulse.value, 3);
      expect(ducks, [true, false]);
      expect(v.state, VoiceState.idle);
    });
    test('cloud failure falls back to the device engine and sticks', () async {
      cTts.mode = f.TtsMode.fail;
      expect(await v.speak('salam', language: 'darija'), isTrue);
      expect(cTts.spoken.length, 1);
      expect(dTts.spoken, ['darija:salam']);
      expect(v.activeTts, 'device');
      await v.speak('again', language: 'darija');
      expect(cTts.spoken.length, 1, reason: 'cloud is skipped after a failure');
    });
    test('off mode / no engine: nothing is spoken and it says so', () async {
      settings = const AppSettings(ttsMode: TtsMode.off);
      expect(await v.speak('x', language: 'darija'), isFalse);
      settings = const AppSettings(ttsMode: TtsMode.device);
      dTts.avail = ProviderAvailability.notInstalled;
      expect(await v.speak('x', language: 'darija'), isFalse);
      expect(v.activeTts, 'off');
    });
    test('interrupt stops speech immediately, completes speak(), and does NOT fall back', () async {
      cTts.mode = f.TtsMode.hang;
      final done = v.speak('long story', language: 'darija');
      await pumpEvents();
      expect(v.state, VoiceState.speaking);
      await v.interrupt();
      expect(await done.timeout(const Duration(seconds: 1)), isFalse);
      expect(cTts.stops, greaterThanOrEqualTo(1));
      expect(dTts.spoken, isEmpty, reason: 'must stay quiet after "stop"');
      expect(v.state, VoiceState.idle);
      expect(ducks.last, isFalse);
    });
    test('a new utterance replaces the current one', () async {
      cTts.mode = f.TtsMode.hang;
      final first = v.speak('one', language: 'darija');
      await pumpEvents();
      cTts.mode = f.TtsMode.finish;
      expect(await v.speak('two', language: 'darija'), isTrue);
      expect(await first.timeout(const Duration(seconds: 1)), isFalse);
      expect(dTts.spoken, isEmpty);
    });
    test('listening interrupts speaking (barge-in)', () async {
      cTts.mode = f.TtsMode.hang;
      final s = v.speak('long', language: 'darija');
      await pumpEvents();
      await v.startListening();
      expect(v.state, VoiceState.listening);
      expect(await s.timeout(const Duration(seconds: 1)), isFalse);
    });
  });
}

Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);
