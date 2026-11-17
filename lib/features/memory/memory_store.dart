import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/backend_client.dart' show KeyValueStore;

class MemoryItem {
  MemoryItem({
    required this.id,
    required this.kind,
    required this.text,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;

  /// fact | chat_user | chat_sahbi
  final String kind;
  String text;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static MemoryItem fromJson(Map<String, dynamic> j) => MemoryItem(
    id: '${j['id']}',
    kind: '${j['kind']}',
    text: '${j['text']}',
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
    updatedAt: DateTime.tryParse('${j['updatedAt']}'),
  );
}

/// Where the encrypted blob lives (file in the app, memory in tests).
abstract class BlobStorage {
  Future<Uint8List?> read();
  Future<void> write(Uint8List data);
  Future<void> delete();
}

class FileBlobStorage implements BlobStorage {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/sahbi_memory.enc');
  }

  @override
  Future<Uint8List?> read() async {
    final f = await _file();
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(Uint8List data) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

class InMemoryBlobStorage implements BlobStorage {
  Uint8List? data;
  @override
  Future<Uint8List?> read() async => data;
  @override
  Future<void> write(Uint8List d) async => data = d;
  @override
  Future<void> delete() async => data = null;
}

/// Local-only memory, encrypted at rest with AES-256-GCM.
/// The 256-bit key is generated on first use and kept in Android Keystore-
/// backed flutter_secure_storage. Nothing here is synced anywhere.
class MemoryStore extends ChangeNotifier {
  MemoryStore({required KeyValueStore keyStore, required BlobStorage blob})
    : _keys = keyStore,
      _blob = blob;

  final KeyValueStore _keys;
  final BlobStorage _blob;
  final _aes = AesGcm.with256bits();

  bool loaded = false;
  bool consentFacts = false;
  bool consentHistory = false;
  DateTime? consentedAt;
  final List<MemoryItem> _items = [];
  String? loadError;

  static const maxHistory = 200;

  List<MemoryItem> get items => List.unmodifiable(_items);
  List<MemoryItem> get facts => _items.where((i) => i.kind == 'fact').toList();
  List<MemoryItem> get history =>
      _items.where((i) => i.kind != 'fact').toList();
  bool get anyConsent => consentFacts || consentHistory;

  Future<SecretKey> _key() async {
    var b64 = await _keys.read('memory_key_v1');
    if (b64 == null) {
      final r = Random.secure();
      final bytes = List<int>.generate(32, (_) => r.nextInt(256));
      b64 = base64Encode(bytes);
      await _keys.write('memory_key_v1', b64);
    }
    return SecretKey(base64Decode(b64));
  }

  Future<void> load() async {
    try {
      final data = await _blob.read();
      if (data != null && data.length > 28) {
        final box = SecretBox.fromConcatenation(
          data,
          nonceLength: 12,
          macLength: 16,
        );
        final clear = await _aes.decrypt(box, secretKey: await _key());
        final j = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
        consentFacts = j['consentFacts'] == true;
        consentHistory = j['consentHistory'] == true;
        consentedAt = DateTime.tryParse('${j['consentedAt']}');
        _items
          ..clear()
          ..addAll([
            for (final i in (j['items'] as List? ?? const []))
              MemoryItem.fromJson(i as Map<String, dynamic>),
          ]);
      }
      loadError = null;
    } catch (e) {
      // Wrong key / corrupt file: never guess, start empty and report it.
      loadError = 'memory_unreadable';
      _items.clear();
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> _toJson() => {
    'v': 1,
    'consentFacts': consentFacts,
    'consentHistory': consentHistory,
    'consentedAt': consentedAt?.toIso8601String(),
    'items': [for (final i in _items) i.toJson()],
  };

  Future<void> _save() async {
    final clear = utf8.encode(jsonEncode(_toJson()));
    final box = await _aes.encrypt(clear, secretKey: await _key());
    await _blob.write(box.concatenation());
    notifyListeners();
  }

  /// Raw stored bytes (for the "encrypted at rest" test).
  Future<Uint8List?> rawBlob() => _blob.read();

  Future<void> setConsent({required bool facts, required bool history}) async {
    consentFacts = facts;
    consentHistory = history;
    consentedAt = (facts || history) ? DateTime.now() : null;
    if (!history) _items.removeWhere((i) => i.kind != 'fact');
    if (!facts) _items.removeWhere((i) => i.kind == 'fact');
    await _save();
  }

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  /// Returns false (and stores nothing) without consent.
  Future<bool> addFact(String text) async {
    final t = text.trim();
    if (!consentFacts || t.isEmpty) return false;
    _items.add(
      MemoryItem(
        id: _id(),
        kind: 'fact',
        text: t.length > 300 ? t.substring(0, 300) : t,
        createdAt: DateTime.now(),
      ),
    );
    await _save();
    return true;
  }

  Future<bool> addChat(String role, String text) async {
    if (!consentHistory || text.trim().isEmpty) return false;
    _items.add(
      MemoryItem(
        id: _id(),
        kind: role == 'user' ? 'chat_user' : 'chat_sahbi',
        text: text.trim(),
        createdAt: DateTime.now(),
      ),
    );
    final hist = history;
    if (hist.length > maxHistory) {
      final drop = hist.take(hist.length - maxHistory).map((e) => e.id).toSet();
      _items.removeWhere((i) => drop.contains(i.id));
    }
    await _save();
    return true;
  }

  Future<void> update(String id, String text) async {
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _items[i].text = text.trim();
    _items[i].updatedAt = DateTime.now();
    await _save();
  }

  Future<void> delete(String id) async {
    _items.removeWhere((x) => x.id == id);
    await _save();
  }

  /// Deletes every item AND the encryption key; consent is kept as chosen.
  Future<void> deleteAll() async {
    _items.clear();
    await _blob.delete();
    await _keys.delete('memory_key_v1');
    await _save();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'exported_at': DateTime.now().toIso8601String(),
    'app': 'SAHBI',
    ..._toJson(),
  });

  /// Facts sent to the AI, only with consent.
  List<String> factsForBrain() =>
      consentFacts ? facts.map((f) => f.text).take(30).toList() : const [];
}
