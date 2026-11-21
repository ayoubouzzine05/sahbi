import 'dart:async';

import 'package:flutter/foundation.dart';

import 'music_models.dart';

/// A YouTube video that the backend checked is public and embeddable.
class YoutubeVideo {
  const YoutubeVideo({
    required this.id,
    required this.title,
    this.author = '',
    this.thumbnail = '',
  });

  final String id;
  final String title;
  final String author;
  final String thumbnail;

  factory YoutubeVideo.fromJson(Map<String, dynamic> j) => YoutubeVideo(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? '',
    author: (j['author'] as String?) ?? '',
    thumbnail: (j['thumbnail'] as String?) ?? '',
  );

  static final validId = RegExp(r'^[A-Za-z0-9_-]{11}$');
}

enum YoutubeState { idle, searching, playing, paused, error }

/// Commands the visible player widget understands. The widget registers
/// itself; when no widget is on screen the commands are no-ops.
abstract class YoutubeSurface {
  Future<void> pause();
  Future<void> resume();

  /// 0..100 (used to duck the song while the robot talks).
  Future<void> setVolume(int volume);
}

/// In-app YouTube playback through the official embedded player (shown on
/// screen, never in the background, as YouTube's embed terms require).
class YoutubeController extends ChangeNotifier {
  YoutubeController({
    required this.search,
    DateTime Function()? clock,
    this.canAutoResume,
    this.resumeEvery = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  /// Backend search (`/v1/music/youtube`). Throws when unavailable.
  final Future<List<YoutubeVideo>> Function(String query) search;
  final DateTime Function() _clock;

  /// False while something else needs the audio (the mic is listening):
  /// an interrupted song waits until it is true again.
  bool Function()? canAutoResume;
  final Duration resumeEvery;

  /// Max automatic resumes per song, so we never fight the user or the
  /// system forever.
  static const maxAutoResumes = 12;

  DateTime? _userTouch;
  DateTime? _expectPause;
  Timer? _resumeTimer;
  int _autoResumes = 0;

  /// True while a song that was paused by something other than the user
  /// (Android audio focus, the WebView) is being resumed.
  bool get interrupted => _resumeTimer != null;
  int get autoResumes => _autoResumes;

  YoutubeState state = YoutubeState.idle;
  List<YoutubeVideo> results = const [];
  int index = 0;
  String? query;
  YoutubeSurface? surface;
  int _gen = 0;

  YoutubeVideo? get current =>
      results.isEmpty || index >= results.length ? null : results[index];
  bool get active =>
      state == YoutubeState.playing ||
      state == YoutubeState.paused ||
      state == YoutubeState.searching;
  bool get playing => state == YoutubeState.playing;

  Future<ActionResult> playSearch(String q) async {
    final gen = ++_gen;
    query = q;
    results = const [];
    index = 0;
    state = YoutubeState.searching;
    notifyListeners();
    List<YoutubeVideo> found;
    try {
      found = (await search(q))
          .where((v) => YoutubeVideo.validId.hasMatch(v.id))
          .toList();
    } catch (e) {
      if (gen != _gen) return const ActionResult.fail('superseded');
      state = YoutubeState.error;
      notifyListeners();
      return ActionResult.fail('youtube_unavailable: $e');
    }
    if (gen != _gen) return const ActionResult.fail('superseded');
    if (found.isEmpty) {
      state = YoutubeState.idle;
      notifyListeners();
      return ActionResult.fail('youtube_not_found:$q');
    }
    results = found;
    state = YoutubeState.playing;
    _newSong();
    notifyListeners();
    return ActionResult.ok('Playing on YouTube "${found.first.title}"');
  }

  Future<ActionResult> pause() async {
    if (state != YoutubeState.playing) {
      return const ActionResult.fail('not_playing');
    }
    _cancelResume();
    _expectPause = _clock();
    await surface?.pause();
    state = YoutubeState.paused;
    notifyListeners();
    return const ActionResult.ok('Paused');
  }

  Future<ActionResult> resume() async {
    if (state != YoutubeState.paused) {
      return const ActionResult.fail('queue_empty');
    }
    await surface?.resume();
    state = YoutubeState.playing;
    notifyListeners();
    return const ActionResult.ok('Resumed');
  }

  Future<ActionResult> stop() async {
    if (!active) return const ActionResult.fail('not_playing');
    _cancelResume();
    _gen++;
    state = YoutubeState.idle;
    results = const [];
    index = 0;
    notifyListeners();
    return const ActionResult.ok('Stopped');
  }

  /// Next search result (the user's "next", or the current one failed).
  Future<ActionResult> next() async {
    if (index + 1 >= results.length) {
      return const ActionResult.fail('end_of_queue');
    }
    index++;
    state = YoutubeState.playing;
    _newSong();
    notifyListeners();
    return ActionResult.ok('Playing on YouTube "${current!.title}"');
  }

  Future<ActionResult> previous() async {
    if (results.isEmpty) return const ActionResult.fail('queue_empty');
    if (index > 0) index--;
    state = YoutubeState.playing;
    _newSong();
    notifyListeners();
    return ActionResult.ok('Playing on YouTube "${current!.title}"');
  }

  /// Reported by the player: this video cannot be played here.
  void onVideoError() {
    if (index + 1 < results.length) {
      index++;
      state = YoutubeState.playing;
      _newSong();
    } else {
      _cancelResume();
      state = YoutubeState.error;
    }
    notifyListeners();
  }

  /// Reported by the player: the video finished.
  void onEnded() {
    _cancelResume();
    state = YoutubeState.idle;
    results = const [];
    notifyListeners();
  }

  /// The user touched the player (its own pause button, the video…).
  void userTouchedPlayer() => _userTouch = _clock();

  bool _recent(DateTime? t, int ms) =>
      t != null && _clock().difference(t).inMilliseconds <= ms;

  /// Reported by the player. A pause right after the user touched the
  /// player (or after our own pause) is respected; any other pause comes
  /// from Android (another app or the speech recogniser took the audio) or
  /// the WebView, and the song is resumed as soon as the mic is free.
  void onPlayerState({required bool playingNow}) {
    if (playingNow) {
      _cancelResume();
      if (state == YoutubeState.paused) {
        state = YoutubeState.playing;
        notifyListeners();
      }
      return;
    }
    if (state != YoutubeState.playing) return;
    if (_recent(_userTouch, 2500) || _recent(_expectPause, 2500)) {
      _cancelResume();
      state = YoutubeState.paused;
      notifyListeners();
      return;
    }
    if (_autoResumes >= maxAutoResumes) {
      state = YoutubeState.paused; // give up: the play button still works
      notifyListeners();
      return;
    }
    if (_resumeTimer == null) {
      _resumeTimer = Timer.periodic(resumeEvery, (_) => _tryResume());
      notifyListeners();
    }
  }

  void _tryResume() {
    if (state != YoutubeState.playing) {
      _cancelResume();
      return;
    }
    if (!(canAutoResume?.call() ?? true)) return;
    if (_autoResumes >= maxAutoResumes) {
      _cancelResume();
      state = YoutubeState.paused;
      notifyListeners();
      return;
    }
    _autoResumes++;
    unawaited(surface?.resume());
  }

  void _cancelResume() {
    final t = _resumeTimer;
    if (t == null) return;
    t.cancel();
    _resumeTimer = null;
    notifyListeners();
  }

  void _newSong() {
    _cancelResume();
    _autoResumes = 0;
  }

  /// Lower the song while the robot talks.
  Future<void> duck(bool on) async {
    if (!active) return;
    await surface?.setVolume(on ? 25 : 100);
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    super.dispose();
  }

  void dismissError() {
    if (state != YoutubeState.error) return;
    state = YoutubeState.idle;
    notifyListeners();
  }
}
