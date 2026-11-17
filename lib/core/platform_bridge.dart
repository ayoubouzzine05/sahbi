import 'package:flutter/services.dart';

class PickedAudio {
  const PickedAudio({
    required this.uri,
    required this.name,
    this.title,
    this.artist,
    this.album,
    this.artPath,
    this.durationMs,
  });
  final String uri;
  final String name;
  final String? title;
  final String? artist;
  final String? album;
  final String? artPath;
  final int? durationMs;

  static PickedAudio fromMap(Map<dynamic, dynamic> m) => PickedAudio(
    uri: '${m['uri']}',
    name: '${m['name'] ?? 'audio'}',
    title: m['title'] as String?,
    artist: m['artist'] as String?,
    album: m['album'] as String?,
    artPath: m['artPath'] as String?,
    durationMs: (m['durationMs'] as num?)?.toInt(),
  );
}

class AudioOutputInfo {
  const AudioOutputInfo({
    required this.type,
    required this.name,
    this.isBluetooth = false,
  });

  /// speaker | wired | bluetooth | usb | hdmi | other | unknown
  final String type;
  final String name;
  final bool isBluetooth;

  static const unknown = AudioOutputInfo(type: 'unknown', name: '');

  static AudioOutputInfo fromMap(Map<dynamic, dynamic> m) => AudioOutputInfo(
    type: '${m['type'] ?? 'unknown'}',
    name: '${m['name'] ?? ''}',
    isBluetooth: m['isBluetooth'] == true,
  );
}

/// Thin wrapper over the Kotlin MethodChannel in MainActivity.kt:
/// SAF pickers (no broad storage permission), audio output info,
/// system output switcher / Bluetooth settings, document export.
class PlatformBridge {
  const PlatformBridge([this._ch = const MethodChannel('ma.sahbi/platform')]);
  final MethodChannel _ch;

  Future<List<PickedAudio>> pickAudioFiles() async {
    final r = await _ch.invokeListMethod<Map<dynamic, dynamic>>(
      'pickAudioFiles',
    );
    return [for (final m in r ?? const []) PickedAudio.fromMap(m)];
  }

  Future<List<PickedAudio>> pickAudioFolder() async {
    final r = await _ch.invokeListMethod<Map<dynamic, dynamic>>(
      'pickAudioFolder',
    );
    return [for (final m in r ?? const []) PickedAudio.fromMap(m)];
  }

  Future<AudioOutputInfo> activeOutput() async {
    try {
      final r = await _ch.invokeMapMethod<dynamic, dynamic>(
        'getActiveAudioOutput',
      );
      return r == null ? AudioOutputInfo.unknown : AudioOutputInfo.fromMap(r);
    } on MissingPluginException {
      return AudioOutputInfo.unknown;
    }
  }

  /// Returns which UI was opened: 'output_switcher' | 'media_output_panel' | 'bluetooth_settings' | 'none'.
  Future<String> openOutputSwitcher() async =>
      await _ch.invokeMethod<String>('openOutputSwitcher') ?? 'none';

  Future<bool> openBluetoothSettings() async =>
      await _ch.invokeMethod<bool>('openBluetoothSettings') ?? false;

  /// System media (STREAM_MUSIC) volume. Returns the new level 0..1, or
  /// null if it could not be changed (e.g. fixed-volume device).
  Future<double?> adjustMediaVolume(int direction) async =>
      (await _ch.invokeMethod<num>('adjustMediaVolume', {
        'direction': direction,
      }))?.toDouble();

  Future<double?> setMediaVolume(double level) async =>
      (await _ch.invokeMethod<num>('setMediaVolume', {
        'level': level,
      }))?.toDouble();

  Future<double?> getMediaVolume() async =>
      (await _ch.invokeMethod<num>('getMediaVolume'))?.toDouble();

  /// Returns true if the user saved the file.
  Future<bool> saveDocument(
    String fileName,
    Uint8List bytes,
    String mime,
  ) async =>
      await _ch.invokeMethod<bool>('saveDocument', {
        'name': fileName,
        'bytes': bytes,
        'mime': mime,
      }) ??
      false;
}
