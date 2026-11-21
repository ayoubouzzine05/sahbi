import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/live/live_player.dart';
import 'package:sahbi/features/voice/cloud_stt.dart';

void main() {
  group('LivePlayer', () {
    late DateTime now;
    late List<int> fed;
    LivePlayer make() => LivePlayer(
      clock: () => now,
      feed: (pcm) async {
        await Future<void>.delayed(Duration.zero);
        fed.add(pcm.length);
      },
    );
    // 24 kHz 16-bit mono: 48 bytes per ms.
    Uint8List ms(int n) => Uint8List(48 * n);

    setUp(() {
      now = DateTime(2026, 11, 21, 12);
      fed = [];
    });

    test(
      'holds the start of a reply until 200 ms are buffered, in order',
      () async {
        final p = make();
        p.add(ms(80));
        p.add(ms(80));
        await p.drain();
        expect(fed, isEmpty, reason: '160 ms < prebuffer');
        expect(p.micShouldBeMuted, isTrue, reason: 'audio is waiting');
        p.add(ms(80));
        await p.drain();
        expect(fed, [48 * 240], reason: 'one ordered block once 200 ms are in');
        expect(p.playing, isTrue);
        p.add(ms(40));
        await p.drain();
        expect(fed, [
          48 * 240,
          48 * 40,
        ], reason: 'while playing, no more waiting');
        expect(p.playUntil, now.add(const Duration(milliseconds: 280)));
      },
    );

    test(
      'turn complete flushes a short reply; odd byte counts are trimmed',
      () async {
        final p = make();
        p.add(Uint8List(481));
        p.turnComplete();
        await p.drain();
        expect(fed, [480]);
      },
    );

    test(
      'a short reply also starts after maxWait without turnComplete',
      () async {
        final p = make();
        p.add(ms(50));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await p.drain();
        expect(fed, [48 * 50]);
      },
    );

    test('mic is muted while playing and for the echo tail after it', () async {
      final p = make();
      expect(p.micShouldBeMuted, isFalse);
      p.add(ms(500));
      await p.drain();
      now = now.add(const Duration(milliseconds: 499));
      expect(p.micShouldBeMuted, isTrue);
      now = now.add(const Duration(milliseconds: 600));
      expect(p.playing, isFalse);
      expect(p.micShouldBeMuted, isTrue, reason: 'echo tail');
      now = now.add(const Duration(milliseconds: 200));
      expect(p.micShouldBeMuted, isFalse);
    });

    test('clear drops queued audio and unmutes', () async {
      final p = make();
      p.add(ms(100));
      p.clear();
      p.turnComplete();
      await p.drain();
      expect(fed, isEmpty);
      expect(p.micShouldBeMuted, isFalse);
    });
  });

  group('EndOfSpeech', () {
    int stopAfter(List<double> dbs, EndOfSpeech v) {
      for (var i = 0; i < dbs.length; i++) {
        if (v.add(dbs[i])) return (i + 1) * 100;
      }
      return -1;
    }

    test('quiet room: stops 0.9 s after the user stops talking', () {
      final v = EndOfSpeech();
      final dbs = [
        ...List.filled(5, -60.0),
        ...List.filled(15, -25.0),
        ...List.filled(20, -60.0),
      ];
      expect(stopAfter(dbs, v), 2900);
      expect(v.heardSpeech, isTrue);
    });

    test(
      'noisy room (TV at -32 dB) still ends instead of running to the limit',
      () {
        final v = EndOfSpeech();
        final dbs = [
          ...List.filled(10, -32.0),
          ...List.filled(15, -14.0),
          ...List.filled(30, -32.0),
        ];
        expect(stopAfter(dbs, v), 3400);
      },
    );

    test('short pauses between words do not end the utterance', () {
      final v = EndOfSpeech();
      final dbs = [
        ...List.filled(5, -60.0),
        ...List.filled(5, -25.0),
        ...List.filled(5, -60.0), // 0.5 s pause
        ...List.filled(5, -25.0),
        ...List.filled(12, -60.0),
      ];
      expect(stopAfter(dbs, v), 2900);
    });

    test('a click is not speech; nobody talking gives up after 7 s', () {
      final v = EndOfSpeech();
      final dbs = [-60.0, -20.0, ...List.filled(100, -60.0)];
      expect(stopAfter(dbs, v), 7000);
      expect(v.heardSpeech, isFalse);
    });

    test('talking from the very first reading is still speech', () {
      final v = EndOfSpeech();
      final dbs = [...List.filled(15, -25.0), ...List.filled(12, -60.0)];
      expect(stopAfter(dbs, v), 2400);
      expect(v.heardSpeech, isTrue);
    });

    test('hard limit of 15 s', () {
      expect(stopAfter(List.filled(200, -15.0), EndOfSpeech()), 15000);
    });
  });
}
