import 'dart:async';

import 'package:sahbi/core/platform_bridge.dart';
import 'package:sahbi/features/music/music_models.dart';

class FakeEngine implements MusicEngine {
  final _ctrl = StreamController<PlaybackSnapshot>.broadcast();
  @override
  PlaybackSnapshot snapshot = const PlaybackSnapshot();
  final calls = <String>[];
  bool failPlay = false;

  void _emit(PlaybackSnapshot s) {
    snapshot = s;
    _ctrl.add(s);
  }

  @override
  Stream<PlaybackSnapshot> get snapshots => _ctrl.stream;
  @override
  Future<void> setQueue(List<Track> tracks, {int start = 0}) async {
    calls.add('setQueue:${tracks.length}@$start');
    _emit(snapshot.copyWith(queue: tracks, index: start));
  }

  @override
  Future<void> play() async {
    calls.add('play');
    if (failPlay) throw StateError('decoder');
    _emit(snapshot.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _emit(snapshot.copyWith(playing: false));
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _emit(const PlaybackSnapshot());
  }

  @override
  Future<void> next() async {
    calls.add('next');
    _emit(snapshot.copyWith(index: (snapshot.index ?? 0) + 1));
  }

  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> seek(Duration position) async => calls.add('seek');
  @override
  Future<void> skipTo(int index) async => calls.add('skipTo:$index');
  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:${volume.toStringAsFixed(2)}');
    _emit(snapshot.copyWith(volume: volume));
  }
}

class FakeBridge extends PlatformBridge {
  FakeBridge() : super();
  List<PickedAudio> picked = const [];
  double? volumeResult = 0.6;
  Object? pickerError;
  @override
  Future<List<PickedAudio>> pickAudioFiles() async {
    if (pickerError != null) throw pickerError!;
    return picked;
  }

  @override
  Future<double?> adjustMediaVolume(int direction) async => volumeResult;
  @override
  Future<double?> setMediaVolume(double level) async =>
      volumeResult == null ? null : level;
  @override
  Future<AudioOutputInfo> activeOutput() async => const AudioOutputInfo(
    type: 'bluetooth',
    name: 'JBL Go',
    isBluetooth: true,
  );
  @override
  Future<double?> getMediaVolume() async => 0.4;
}
