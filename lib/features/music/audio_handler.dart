import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'music_models.dart';

/// audio_service handler around just_audio: media notification, lock screen
/// controls, headset buttons and audio focus (via audio_session).
class SahbiAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements MusicEngine {
  SahbiAudioHandler() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  final _snap = StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot _s = const PlaybackSnapshot();
  List<Track> _tracks = const [];

  @override
  Stream<PlaybackSnapshot> get snapshots => _snap.stream;
  @override
  PlaybackSnapshot get snapshot => _s;

  void _emit(PlaybackSnapshot s) {
    _s = s;
    _snap.add(s);
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // Pause on headphones unplugged.
    session.becomingNoisyEventStream.listen((_) => _player.pause());

    _player.playbackEventStream.listen(
      (event) {
        final playing = _player.playing;
        playbackState.add(
          playbackState.value.copyWith(
            controls: [
              MediaControl.skipToPrevious,
              if (playing) MediaControl.pause else MediaControl.play,
              MediaControl.stop,
              MediaControl.skipToNext,
            ],
            systemActions: const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
            androidCompactActionIndices: const [0, 1, 3],
            processingState: const {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_player.processingState]!,
            playing: playing,
            updatePosition: _player.position,
            bufferedPosition: _player.bufferedPosition,
            speed: _player.speed,
            queueIndex: event.currentIndex,
          ),
        );
        _emit(
          _s.copyWith(
            playing: playing,
            loading:
                _player.processingState == ProcessingState.loading ||
                _player.processingState == ProcessingState.buffering,
            index: event.currentIndex,
            duration: _player.duration,
          ),
        );
      },
      onError: (Object e, StackTrace _) {
        _emit(_s.copyWith(error: 'playback_error: $e', playing: false));
      },
    );
    _player.currentIndexStream.listen((i) {
      if (i != null && i < _tracks.length) {
        mediaItem.add(_toMediaItem(_tracks[i]));
      }
    });
    _player.positionStream.listen((p) => _emit(_s.copyWith(position: p)));
    _player.volumeStream.listen((v) => _emit(_s.copyWith(volume: v)));
    _player.processingStateStream.listen((st) {
      if (st == ProcessingState.completed) {
        _emit(_s.copyWith(playing: false));
      }
    });
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: t.duration,
    artUri: t.artUri == null ? null : Uri.parse(t.artUri!),
  );

  AudioSource _source(Track t) {
    if (t.uri.startsWith('asset:///')) {
      return AudioSource.asset(
        t.uri.substring('asset:///'.length),
        tag: _toMediaItem(t),
      );
    }
    return AudioSource.uri(Uri.parse(t.uri), tag: _toMediaItem(t));
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int start = 0}) async {
    _tracks = List.of(tracks);
    queue.add([for (final t in tracks) _toMediaItem(t)]);
    _emit(_s.copyWith(queue: _tracks, index: start, clearError: true));
    try {
      await _player.setAudioSources([
        for (final t in tracks) _source(t),
      ], initialIndex: start);
    } catch (e) {
      _emit(_s.copyWith(error: 'load_failed: $e'));
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    _emit(_s.copyWith(clearError: true));
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
    _emit(_s.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> next() => skipToNext();

  @override
  Future<void> previous() => skipToPrevious();

  @override
  Future<void> skipTo(int index) => skipToQueueItem(index);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));
}
