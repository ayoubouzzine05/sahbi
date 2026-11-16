import 'package:url_launcher/url_launcher.dart';

import 'music_models.dart';

typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultOpen(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens Spotify / YouTube Music through public deep links only.
/// No playback control API is used (YouTube Music has none; Spotify App
/// Remote is an optional, not-bundled feature).
class StreamingLinks {
  const StreamingLinks({UrlOpener? open}) : _open = open ?? _defaultOpen;
  final UrlOpener _open;

  static Uri spotifyApp(String? query) => query == null || query.isEmpty
      ? Uri.parse('spotify:')
      : Uri.parse('spotify:search:${Uri.encodeComponent(query)}');

  static Uri spotifyWeb(String? query) => query == null || query.isEmpty
      ? Uri.parse('https://open.spotify.com/')
      : Uri.parse('https://open.spotify.com/search/${Uri.encodeComponent(query)}');

  static Uri youtubeMusic(String? query) => query == null || query.isEmpty
      ? Uri.parse('https://music.youtube.com/')
      : Uri.https('music.youtube.com', '/search', {'q': query});

  Future<ActionResult> openSpotify(String? query) async {
    if (await _open(spotifyApp(query))) {
      return const ActionResult.ok('Opened Spotify');
    }
    if (await _open(spotifyWeb(query))) {
      return const ActionResult.ok('Spotify app not found — opened open.spotify.com');
    }
    return const ActionResult.fail('Could not open Spotify');
  }

  Future<ActionResult> openYouTubeMusic(String? query) async {
    // An https link opens the YouTube Music app if installed (app links),
    // otherwise the browser.
    if (await _open(youtubeMusic(query))) {
      return const ActionResult.ok('Opened YouTube Music');
    }
    return const ActionResult.fail('Could not open YouTube Music');
  }
}
