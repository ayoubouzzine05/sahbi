import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Where the offline wake model comes from. Our own GitHub release first
/// (a pre-release, so the APK "latest" link is untouched), the original
/// Alpha Cephei URL as a fallback. Same file, checked by SHA-256.
class WakeModelSource {
  static const name = 'vosk-model-small-fr-0.22';
  static const urls = [
    'https://github.com/ayoubouzzine05/sahbi/releases/download/wake-model-fr-0.22/vosk-model-small-fr-0.22.zip',
    'https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip',
  ];
  static const sha256 =
      'cabf6180e177eb9b3a9a9d43a437bd5e549f3a7d09525e5d69a3fed787be12ad';
  static const bytes = 42233323;
}

enum WakeModelStatus { missing, downloading, ready, failed }

/// Downloads (once, with progress) and unpacks the wake model into the
/// app's private storage. Nothing is sent anywhere.
class WakeModelManager extends ChangeNotifier {
  WakeModelManager({
    Future<Directory> Function()? baseDir,
    http.Client Function()? client,
    MethodChannel? channel,
  }) : _baseDir = baseDir ?? getApplicationSupportDirectory,
       _client = client ?? http.Client.new,
       _m = channel ?? const MethodChannel('ma.sahbi/mimo');

  final Future<Directory> Function() _baseDir;
  final http.Client Function() _client;
  final MethodChannel _m;

  WakeModelStatus status = WakeModelStatus.missing;
  double progress = 0;
  String? error;
  String? _path;
  bool _cancel = false;

  /// Folder with am/, conf/, graph/ once ready.
  String? get modelPath => status == WakeModelStatus.ready ? _path : null;

  Future<Directory> _root() async =>
      Directory('${(await _baseDir()).path}/wake');

  /// Checks the disk (call at start-up).
  Future<void> check() async {
    try {
      final dir = Directory('${(await _root()).path}/${WakeModelSource.name}');
      final ok =
          await File('${dir.path}/.complete').exists() &&
          await Directory('${dir.path}/am').exists();
      _path = dir.path;
      status = ok ? WakeModelStatus.ready : WakeModelStatus.missing;
    } catch (_) {
      status = WakeModelStatus.missing;
    }
    notifyListeners();
  }

  void cancel() => _cancel = true;

  /// Downloads and unpacks. Returns true when ready.
  Future<bool> download() async {
    if (status == WakeModelStatus.ready) return true;
    if (status == WakeModelStatus.downloading) return false;
    status = WakeModelStatus.downloading;
    progress = 0;
    error = null;
    _cancel = false;
    notifyListeners();
    final root = await _root();
    await root.create(recursive: true);
    final zip = File('${root.path}/model.zip.part');
    for (final url in WakeModelSource.urls) {
      final client = _client();
      try {
        final res = await client.send(http.Request('GET', Uri.parse(url)));
        if (res.statusCode != 200) {
          error = 'HTTP ${res.statusCode}';
          continue;
        }
        final total = res.contentLength ?? WakeModelSource.bytes;
        final sink = zip.openWrite();
        final hasher = Sha256().newHashSink();
        var got = 0;
        try {
          await for (final chunk in res.stream) {
            if (_cancel) throw const _Cancelled();
            sink.add(chunk);
            hasher.add(chunk);
            got += chunk.length;
            final p = (got / total).clamp(0.0, 1.0);
            if (p - progress >= 0.01 || p == 1) {
              progress = p;
              notifyListeners();
            }
          }
        } finally {
          await sink.close();
          hasher.close();
        }
        final digest = (await hasher.hash()).bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (digest != WakeModelSource.sha256) {
          error = 'checksum';
          continue;
        }
        final dir = Directory('${root.path}/${WakeModelSource.name}');
        if (await dir.exists()) await dir.delete(recursive: true);
        await _m.invokeMethod<bool>('unzip', {
          'zip': zip.path,
          'dest': root.path,
        });
        await File('${dir.path}/.complete').writeAsString('ok');
        _path = dir.path;
        status = WakeModelStatus.ready;
        progress = 1;
        notifyListeners();
        return true;
      } on _Cancelled {
        error = 'cancelled';
        break;
      } catch (e) {
        error = '$e';
      } finally {
        client.close();
        try {
          if (await zip.exists()) await zip.delete();
        } catch (_) {}
      }
    }
    status = WakeModelStatus.failed;
    notifyListeners();
    return false;
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
