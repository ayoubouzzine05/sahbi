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
}

/// In-app YouTube playback through the official embedded player (shown on
/// screen, never in the background, as YouTube's embed terms require).
class YoutubeController extends ChangeNotifier {
  YoutubeController({required this.search});

  /// Backend search (`/v1/music/youtube`). Throws when unavailable.
  final Future<List<YoutubeVideo>> Function(String query) search;

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
    notifyListeners();
    return ActionResult.ok('Playing on YouTube "${found.first.title}"');
  }

  Future<ActionResult> pause() async {
    if (state != YoutubeState.playing) {
      return const ActionResult.fail('not_playing');
    }
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
    notifyListeners();
    return ActionResult.ok('Playing on YouTube "${current!.title}"');
  }

  Future<ActionResult> previous() async {
    if (results.isEmpty) return const ActionResult.fail('queue_empty');
    if (index > 0) index--;
    state = YoutubeState.playing;
    notifyListeners();
    return ActionResult.ok('Playing on YouTube "${current!.title}"');
  }

  /// Reported by the player: this video cannot be played here.
  void onVideoError() {
    if (index + 1 < results.length) {
      index++;
      state = YoutubeState.playing;
    } else {
      state = YoutubeState.error;
    }
    notifyListeners();
  }

  /// Reported by the player: the video finished.
  void onEnded() {
    state = YoutubeState.idle;
    results = const [];
    notifyListeners();
  }

  /// Reported by the player when the user used its own controls.
  void onPlayerState({required bool playingNow}) {
    if (state == YoutubeState.playing && !playingNow) {
      state = YoutubeState.paused;
      notifyListeners();
    } else if (state == YoutubeState.paused && playingNow) {
      state = YoutubeState.playing;
      notifyListeners();
    }
  }

  void dismissError() {
    if (state != YoutubeState.error) return;
    state = YoutubeState.idle;
    notifyListeners();
  }
}
