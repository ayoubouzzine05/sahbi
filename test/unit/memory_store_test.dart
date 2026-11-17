import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/core/backend_client.dart';
import 'package:sahbi/features/memory/memory_store.dart';

void main() {
  late MemoryKeyValueStore keys;
  late InMemoryBlobStorage blob;
  MemoryStore make() => MemoryStore(keyStore: keys, blob: blob);

  setUp(() {
    keys = MemoryKeyValueStore();
    blob = InMemoryBlobStorage();
  });

  test('nothing is stored without consent', () async {
    final s = make();
    await s.load();
    expect(await s.addFact('I love atay'), isFalse);
    expect(await s.addChat('user', 'salam'), isFalse);
    expect(s.items, isEmpty);
    expect(blob.data, isNull);
    expect(s.factsForBrain(), isEmpty);
  });

  test('stored data is encrypted at rest (no plaintext in the blob)', () async {
    final s = make();
    await s.setConsent(facts: true, history: true);
    await s.addFact('My sister is called Salma');
    final bytes = (await s.rawBlob())!;
    final asText = latin1.decode(bytes);
    expect(asText.contains('Salma'), isFalse);
    expect(asText.contains('consent'), isFalse);
    expect(bytes.length, greaterThan(28)); // 12-byte nonce + 16-byte tag + data
    expect(keys.data['memory_key_v1'], isNotNull);
    expect(base64Decode(keys.data['memory_key_v1']!).length, 32);
  });

  test('persists across restarts with the same key', () async {
    final a = make();
    await a.setConsent(facts: true, history: false);
    await a.addFact('Favourite team: Raja');
    final b = make();
    await b.load();
    expect(b.loadError, isNull);
    expect(b.consentFacts, isTrue);
    expect(b.consentHistory, isFalse);
    expect(b.facts.single.text, 'Favourite team: Raja');
  });

  test('a lost/wrong key is reported, never guessed', () async {
    final a = make();
    await a.setConsent(facts: true, history: false);
    await a.addFact('secret');
    keys.data['memory_key_v1'] = base64Encode(List.filled(32, 1));
    final b = make();
    await b.load();
    expect(b.loadError, 'memory_unreadable');
    expect(b.items, isEmpty);
  });

  test('edit, delete and revoking consent remove data', () async {
    final s = make();
    await s.setConsent(facts: true, history: true);
    await s.addFact('a');
    await s.addFact('b');
    await s.addChat('user', 'hi');
    await s.addChat('assistant', 'salam');
    expect(s.history.map((e) => e.kind), ['chat_user', 'chat_sahbi']);
    await s.update(s.facts.first.id, '  a2 ');
    expect(s.facts.first.text, 'a2');
    await s.delete(s.facts.last.id);
    expect(s.facts.map((f) => f.text), ['a2']);
    await s.setConsent(facts: true, history: false);
    expect(s.history, isEmpty);
    await s.setConsent(facts: false, history: false);
    expect(s.items, isEmpty);
    expect(s.consentedAt, isNull);
  });

  test('deleteAll wipes items and rotates the key', () async {
    final s = make();
    await s.setConsent(facts: true, history: false);
    await s.addFact('x');
    final oldKey = keys.data['memory_key_v1'];
    await s.deleteAll();
    expect(s.items, isEmpty);
    expect(keys.data['memory_key_v1'], isNot(oldKey));
  });

  test(
    'facts are trimmed, capped at 300 chars; history capped at maxHistory',
    () async {
      final s = make();
      await s.setConsent(facts: true, history: true);
      expect(await s.addFact('   '), isFalse);
      await s.addFact('x' * 400);
      expect(s.facts.single.text.length, 300);
      for (var i = 0; i < MemoryStore.maxHistory + 5; i++) {
        await s.addChat('user', 'm$i');
      }
      expect(s.history.length, MemoryStore.maxHistory);
      expect(s.history.first.text, 'm5');
    },
  );

  test('export is readable JSON with consent info and items', () async {
    final s = make();
    await s.setConsent(facts: true, history: false);
    await s.addFact('likes couscous on Friday');
    final j = jsonDecode(s.exportJson()) as Map<String, dynamic>;
    expect(j['app'], 'SAHBI');
    expect(j['consentFacts'], isTrue);
    expect((j['items'] as List).single['text'], 'likes couscous on Friday');
    expect(s.factsForBrain(), ['likes couscous on Friday']);
  });
}
