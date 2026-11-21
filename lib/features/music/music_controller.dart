import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform_bridge.dart';
import 'music_models.dart';
import 'streaming_links.dart';
import 'youtube_controller.dart';

/// Demo tracks bundled with the app (original, CC0 — see ASSETS_LICENSES.md).
const demoTracks = [
  Track(
    id: 'demo-1',
    uri: 'asset:///assets/audio/sahbi_demo_atlas_breeze.wav',
    title: 'Atlas Breeze (demo)',
    artist: 'SAHBI demo — CC0',
    source: 'demo',
  ),
  Track(
    id: 'demo-2',
    uri: 'asset:///assets/audio/sahbi_demo_medina_steps.wav',
    title: 'Medina Steps (demo)',
    artist: 'SAHBI demo — CC0',
    source: 'demo',
  ),
];

/// Music state + commands. Every command returns a real [ActionResult].
class MusicController extends ChangeNotifier {
  MusicController({
    required this.engine,
    required this.bridge,
    this.links = const StreamingLinks(),
    this.youtube,
    SharedPreferences? prefs,
  }) : _prefs = prefs {
    youtube?.addListener(notifyListeners);
    _sub = engine.snapshots.listen((s) {
      snapshot = s;
      notifyListeners();
    });
    _loadLibrary();
  }

  final MusicEngine engine;
  final PlatformBridge bridge;
  final StreamingLinks links;

  /// In-app YouTube player (null when the backend can't search YouTube).
  final YoutubeController? youtube;
  bool get _yt => youtube?.active ?? false;
  final SharedPreferences? _prefs;
  late final StreamSubscription<PlaybackSnapshot> _sub;

  PlaybackSnapshot snapshot = const PlaybackSnapshot();
  List<Track> library = [];
  AudioOutputInfo output = AudioOutputInfo.unknown;
  double? systemVolume;
  bool _ducked = false;
  double _preDuckVolume = 1;

  bool get playing => snapshot.playing || (youtube?.playing ?? false);
  List<Track> get allTracks => [...library, ...demoTracks];

  void _loadLibrary() {
    final raw = _prefs?.getString('music_library');
    if (raw == null) return;
    try {
      library = [
        for (final j in jsonDecode(raw) as List)
          Track.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      library = [];
    }
  }

  Future<void> _saveLibrary() async {
    await _prefs?.setString(
      'music_library',
      jsonEncode([for (final t in library) t.toJson()]),
    );
  }

  Future<ActionResult> importFiles() async {
    try {
      final picked = await bridge.pickAudioFiles();
      return await _addPicked(picked);
    } catch (e) {
      return ActionResult.fail('picker_failed: $e');
    }
  }

  Future<ActionResult> importFolder() async {
    try {
      final picked = await bridge.pickAudioFolder();
      return await _addPicked(picked);
    } catch (e) {
      return ActionResult.fail('picker_failed: $e');
    }
  }

  Future<ActionResult> _addPicked(List<PickedAudio> picked) async {
    if (picked.isEmpty) return const ActionResult.fail('nothing_selected');
    final ids = library.map((t) => t.id).toSet();
    final added = [for (final p in picked) Track.fromPicked(p)]
        .where((t) => ids.add(t.id))
        .toList();
    library = [...library, ...added];
    await _saveLibrary();
    notifyListeners();
    return ActionResult.ok('${added.length} track(s) added');
  }

  Future<void> removeTrack(Track t) async {
    library = library.where((x) => x.id != t.id).toList();
    await _saveLibrary();
    notifyListeners();
  }

  Future<ActionResult> playTracks(List<Track> tracks, {int start = 0}) async {
    if (tracks.isEmpty) return const ActionResult.fail('no_tracks');
    if (_yt) await youtube!.stop();
    try {
      await engine.setQueue(tracks, start: start);
      await engine.play();
      return ActionResult.ok('Playing "${tracks[start].title}"');
    } catch (e) {
      return ActionResult.fail('could_not_play: $e');
    }
  }

  /// Searches YouTube and plays the first embeddable result inside the app.
  Future<ActionResult> playYoutube(String query) async {
    final yt = youtube;
    if (yt == null) return const ActionResult.fail('youtube_unavailable');
    if (snapshot.playing || snapshot.queue.isNotEmpty) await engine.stop();
    return yt.playSearch(query);
  }

  /// "Ch3el lia chi music [query]": local library first (title/artist match),
  /// then YouTube inside the app; without a query all local + demo tracks.
  Future<ActionResult> playQuery(String? query) async {
    final all = allTracks;
    final wanted = query?.trim() ?? '';
    final hasQuery = wanted.isNotEmpty;
    if (hasQuery && youtube != null) {
      final q = wanted.toLowerCase();
      final local = all.where(
        (t) =>
            t.title.toLowerCase().contains(q) ||
            (t.artist?.toLowerCase().contains(q) ?? false),
      );
      if (local.isEmpty) return playYoutube(wanted);
    }
    if (all.isEmpty) return const ActionResult.fail('no_tracks');
    if (hasQuery) {
      final q = wanted.toLowerCase();
      final matches = all
          .where(
            (t) =>
                t.title.toLowerCase().contains(q) ||
                (t.artist?.toLowerCase().contains(q) ?? false),
          )
          .toList();
      if (matches.isEmpty) return ActionResult.fail('no_local_match:$query');
      return playTracks(matches);
    }
    if (snapshot.queue.isNotEmpty && !snapshot.playing) return resume();
    return playTracks(all);
  }

  Future<ActionResult> pause() async {
    if (_yt) return youtube!.pause();
    if (!snapshot.playing) return const ActionResult.fail('not_playing');
    await engine.pause();
    return const ActionResult.ok('Paused');
  }

  Future<ActionResult> resume() async {
    if (_yt) return youtube!.resume();
    if (snapshot.queue.isEmpty) return const ActionResult.fail('queue_empty');
    await engine.play();
    return const ActionResult.ok('Resumed');
  }

  Future<ActionResult> stop() async {
    if (_yt) return youtube!.stop();
    if (snapshot.queue.isEmpty && !snapshot.playing) {
      return const ActionResult.fail('not_playing');
    }
    await engine.stop();
    return const ActionResult.ok('Stopped');
  }

  Future<ActionResult> next() async {
    if (_yt) return youtube!.next();
    final i = snapshot.index ?? 0;
    if (i + 1 >= snapshot.queue.length) {
      return const ActionResult.fail('end_of_queue');
    }
    await engine.next();
    return const ActionResult.ok('Next track');
  }

  Future<ActionResult> previous() async {
    if (_yt) return youtube!.previous();
    if (snapshot.queue.isEmpty) return const ActionResult.fail('queue_empty');
    await engine.previous();
    return const ActionResult.ok('Previous track');
  }

  Future<void> seek(Duration d) => engine.seek(d);
  Future<void> skipTo(int i) => engine.skipTo(i);

  /// System media volume (affects Spotify/YouTube Music too).
  Future<ActionResult> volumeStep(int direction) async {
    try {
      final v = await bridge.adjustMediaVolume(direction);
      if (v == null) return const ActionResult.fail('volume_unavailable');
      systemVolume = v;
      notifyListeners();
      return ActionResult.ok('Volume ${(v * 100).round()}%');
    } catch (e) {
      return ActionResult.fail('volume_failed: $e');
    }
  }

  Future<ActionResult> setVolume(double level) async {
    try {
      final v = await bridge.setMediaVolume(level.clamp(0.0, 1.0));
      if (v == null) return const ActionResult.fail('volume_unavailable');
      systemVolume = v;
      notifyListeners();
      return ActionResult.ok('Volume ${(v * 100).round()}%');
    } catch (e) {
      return ActionResult.fail('volume_failed: $e');
    }
  }

  Future<void> refreshOutput() async {
    try {
      output = await bridge.activeOutput();
      systemVolume = await bridge.getMediaVolume();
    } catch (_) {
      output = AudioOutputInfo.unknown;
    }
    notifyListeners();
  }

  /// Lower Sahbi's own player while Sahbi speaks.
  Future<void> duck(bool on) async {
    if (on == _ducked) return;
    _ducked = on;
    unawaited(youtube?.duck(on));
    if (on) {
      _preDuckVolume = snapshot.volume;
      if (snapshot.playing) await engine.setVolume(_preDuckVolume * 0.25);
    } else {
      await engine.setVolume(_preDuckVolume);
    }
  }

  @override
  void dispose() {
    youtube?.removeListener(notifyListeners);
    _sub.cancel();
    super.dispose();
  }
}
