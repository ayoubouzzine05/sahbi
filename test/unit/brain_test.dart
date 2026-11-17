import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/backend_client.dart';
import 'package:sahbi/features/brain/brain_models.dart';
import 'package:sahbi/features/brain/text_normalizer.dart';
import 'package:sahbi/features/personality/emotion.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/voice_types.dart';

Map<String, dynamic> validReply() => {
  'display_text': 'Salam! Ana Sahbi.',
  'tts_text': 'سلام! أنا صاحبي.',
  'language': 'darija',
  'emotion': 'happy',
  'intensity': 0.7,
  'actions': [
    {
      'type': 'music.play',
      'args': {'query': 'nass el ghiwane'},
    },
  ],
  'sources': [
    {
      'id': 1,
      'title': 'Hespress',
      'url': 'https://www.hespress.com/x',
      'date': '2026-11-15',
      'kind': 'web',
    },
  ],
  'verification': 'confirmed',
  'used_tools': ['web_search'],
  'search_unavailable': false,
};

Stream<List<int>> sse(String s, {int chunk = 7}) async* {
  final b = utf8.encode(s);
  for (var i = 0; i < b.length; i += chunk) {
    yield b.sublist(i, i + chunk > b.length ? b.length : i + chunk);
  }
}

void main() {
  group('normalizeText', () {
    test('lowercases, strips accents and punctuation, unifies sh→ch', () {
      expect(normalizeText('Arrête la Musique!!'), 'arete la musique');
      expect(normalizeText('Shokran'), 'chokran');
    });
    test('collapses stretched letters only when asked', () {
      expect(normalizeText('Wqeeef'), 'wqef');
      expect(normalizeText('Wqeeef', collapse: false), isNot('wqef'));
    });
    test('Arabic: removes tashkeel/tatweel and unifies letter forms', () {
      expect(normalizeText('أَهْلاً'), 'اهلا');
      expect(normalizeText('موسيقـــى'), 'موسيقي');
      expect(normalizeText('الدارجة'), 'الدارجه');
    });
    test('isArabicScript', () {
      expect(isArabicScript('شعل ليا'), isTrue);
      expect(isArabicScript('ch3el lia'), isFalse);
    });
  });

  group('BrainReply.fromJson', () {
    test('parses a valid reply', () {
      final r = BrainReply.fromJson(validReply());
      expect(r.emotion, Emotion.happy);
      expect(r.actions.single.type, 'music.play');
      expect(r.sources.single.domain, 'hespress.com');
      expect(r.verification, Verification.confirmed);
      expect(r.usedTools, ['web_search']);
    });
    for (final bad in <String, Object?>{
      'display_text': '',
      'tts_text': null,
      'language': 'de',
      'intensity': 3,
    }.entries) {
      test('rejects bad ${bad.key}', () {
        final j = validReply()..[bad.key] = bad.value;
        expect(() => BrainReply.fromJson(j), throwsFormatException);
      });
    }
    test(
      'unknown emotion falls back to neutral; unknown verification → none',
      () {
        final j = validReply()
          ..['emotion'] = 'ecstatic'
          ..['verification'] = '???';
        final r = BrainReply.fromJson(j);
        expect(r.emotion, Emotion.neutral);
        expect(r.verification, Verification.none);
      },
    );
  });

  group('BackendClient.parseSse', () {
    test('status → delta → final, split across arbitrary chunks', () async {
      final body =
          'event: status\ndata: {"phase":"searching"}\n\n'
          'event: delta\ndata: {"text":"Sal"}\n\n'
          'event: delta\ndata: {"text":"am"}\n\n'
          ': keep-alive comment\n\n'
          'event: final\ndata: ${jsonEncode(validReply())}\n\n';
      final events = await BackendClient.parseSse(sse(body, chunk: 5)).toList();
      expect(
        events[0],
        isA<BrainStatus>().having((e) => e.phase, 'phase', 'searching'),
      );
      expect(events.whereType<BrainDelta>().map((e) => e.text).join(), 'Salam');
      expect(events.last, isA<BrainFinal>());
    });
    test('error event becomes a typed BackendException', () async {
      final body =
          'event: error\ndata: {"code":"not_configured","message":"LLM not configured"}\n\n';
      await expectLater(
        BackendClient.parseSse(sse(body)).toList(),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            BackendErrorCode.notConfigured,
          ),
        ),
      );
    });
    test('invalid final payload → invalidOutput', () async {
      final body = 'event: final\ndata: {"display_text":""}\n\n';
      await expectLater(
        BackendClient.parseSse(sse(body)).toList(),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            BackendErrorCode.invalidOutput,
          ),
        ),
      );
    });
    test('UTF-8 Arabic split mid-character survives', () async {
      final body = 'event: delta\ndata: {"text":"صاحبي"}\n\n';
      final events = await BackendClient.parseSse(sse(body, chunk: 1)).toList();
      expect((events.single as BrainDelta).text, 'صاحبي');
    });
  });

  group('codeFromString', () {
    test('maps backend error codes', () {
      expect(
        BackendClient.codeFromString('not_configured'),
        BackendErrorCode.notConfigured,
      );
      expect(
        BackendClient.codeFromString('upstream_timeout'),
        BackendErrorCode.timeout,
      );
      expect(
        BackendClient.codeFromString('rate_limited'),
        BackendErrorCode.rateLimited,
      );
      expect(
        BackendClient.codeFromString('invalid_output'),
        BackendErrorCode.invalidOutput,
      );
      expect(
        BackendClient.codeFromString('unauthorized'),
        BackendErrorCode.unauthorized,
      );
      expect(BackendClient.codeFromString('whatever'), BackendErrorCode.server);
    });
  });

  group('AppSettings', () {
    test('defaults: Arabic UI, Darija replies, wake word off, no backend', () {
      const s = AppSettings();
      expect(s.uiLocale, 'ar');
      expect(s.replyLanguage, 'darija');
      expect(s.wakeWordEnabled, isFalse);
      expect(
        s.backendUrl,
        isEmpty,
      ); // no SAHBI_BACKEND_URL dart-define in tests
    });
    test('JSON round trip keeps every field', () {
      final s = const AppSettings().copyWith(
        uiLocale: 'fr',
        replyLanguage: 'en',
        darijaScript: 'latin',
        sttMode: SttMode.device,
        ttsMode: TtsMode.off,
        deviceVoiceName: 'ar-xa-x-arz-local',
        speechRate: 0.7,
        humor: 0.2,
        userName: 'Yassine',
        sendToAi: false,
        robotExperimental: true,
      );
      final back = AppSettings.decode(s.encode());
      expect(back.toJson(), s.toJson());
    });
    test('corrupt / missing JSON falls back to defaults', () {
      expect(AppSettings.decode(null).toJson(), const AppSettings().toJson());
      expect(
        AppSettings.decode('{not json').toJson(),
        const AppSettings().toJson(),
      );
    });
    test('clearDeviceVoice resets to the default voice', () {
      final s = const AppSettings().copyWith(
        deviceVoiceName: 'x',
        deviceVoiceLocale: 'ar-MA',
      );
      final c = s.copyWith(clearDeviceVoice: true);
      expect(c.deviceVoiceName, isNull);
      expect(c.deviceVoiceLocale, isNull);
    });
  });

  group('pickLocale', () {
    test('Darija prefers ar-MA, then other Arabic', () {
      expect(pickLocale(['fr-FR', 'ar_SA', 'ar_MA'], 'darija'), 'ar_MA');
      expect(pickLocale(['fr-FR', 'ar-EG'], 'darija'), 'ar-EG');
    });
    test('falls back to language prefix', () {
      expect(pickLocale(['ar-JO'], 'darija'), 'ar-JO');
      expect(pickLocale(['en-IN'], 'en'), 'en-IN');
    });
    test(
      'null when nothing matches',
      () => expect(pickLocale(['de-DE'], 'fr'), isNull),
    );
  });
}
