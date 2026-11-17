import '../../core/platform_bridge.dart';

class Track {
  const Track({
    required this.id,
    required this.uri,
    required this.title,
    this.artist,
    this.album,
    this.artUri,
    this.duration,
    this.source = 'local',
  });

  final String id;

  /// asset:///..., content://..., file://...
  final String uri;
  final String title;
  final String? artist;
  final String? album;
  final String? artUri;
  final Duration? duration;

  /// demo | local
  final String source;

  static Track fromPicked(PickedAudio p) => Track(
    id: p.uri,
    uri: p.uri,
    title: (p.title?.trim().isNotEmpty ?? false) ? p.title!.trim() : p.name,
    artist: p.artist,
    album: p.album,
    artUri: p.artPath == null ? null : Uri.file(p.artPath!).toString(),
    duration: p.durationMs == null
        ? null
        : Duration(milliseconds: p.durationMs!),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'uri': uri,
    'title': title,
    'artist': artist,
    'album': album,
    'artUri': artUri,
    'durationMs': duration?.inMilliseconds,
    'source': source,
  };

  static Track fromJson(Map<String, dynamic> j) => Track(
    id: '${j['id']}',
    uri: '${j['uri']}',
    title: '${j['title']}',
    artist: j['artist'] as String?,
    album: j['album'] as String?,
    artUri: j['artUri'] as String?,
    duration: j['durationMs'] == null
        ? null
        : Duration(milliseconds: (j['durationMs'] as num).toInt()),
    source: (j['source'] as String?) ?? 'local',
  );
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.queue = const [],
    this.index,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration,
    this.volume = 1,
    this.error,
  });

  final List<Track> queue;
  final int? index;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration? duration;
  final double volume;
  final String? error;

  Track? get current => index != null && index! >= 0 && index! < queue.length
      ? queue[index!]
      : null;

  PlaybackSnapshot copyWith({
    List<Track>? queue,
    int? index,
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
    double? volume,
    String? error,
    bool clearError = false,
  }) => PlaybackSnapshot(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Result of an action the app executed — reported back honestly.
class ActionResult {
  const ActionResult.ok(this.message) : ok = true;
  const ActionResult.fail(this.message) : ok = false;
  final bool ok;
  final String message;
  @override
  String toString() => '${ok ? 'OK' : 'FAIL'}: $message';
}

/// Abstraction over the playback engine so it can be faked in tests.
abstract class MusicEngine {
  Stream<PlaybackSnapshot> get snapshots;
  PlaybackSnapshot get snapshot;
  Future<void> setQueue(List<Track> tracks, {int start = 0});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> skipTo(int index);
  Future<void> setVolume(double volume);
}
