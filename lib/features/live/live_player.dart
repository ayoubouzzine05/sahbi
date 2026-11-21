import 'dart:async';
import 'dart:typed_data';

/// Smooth playback of the Live model's 24 kHz PCM, plus echo protection.
///
/// * Chunks are fed to the speaker strictly one after another (concurrent
///   `feed` calls could arrive out of order and repeat/garble syllables).
/// * When the speaker is idle, the start of a new reply is held back until
///   [prebuffer] of audio has arrived (or [maxWait] passed) so the first word
///   does not stutter while the rest is still on the network.
/// * [micShouldBeMuted] stays true while the robot's voice is playing and a
///   short [echoTail] after it: the phone's speaker output is not removed by
///   every phone's echo canceller, and the model hearing itself makes it
///   interrupt and restart its own sentence in a loop.
class LivePlayer {
  LivePlayer({
    required this.feed,
    DateTime Function()? clock,
    this.sampleRate = 24000,
    this.prebuffer = const Duration(milliseconds: 200),
    this.maxWait = const Duration(milliseconds: 250),
    this.echoTail = const Duration(milliseconds: 700),
  }) : _clock = clock ?? DateTime.now;

  /// Sends 16-bit mono PCM to the speaker.
  final Future<void> Function(Uint8List pcm) feed;
  final DateTime Function() _clock;
  final int sampleRate;
  final Duration prebuffer;
  final Duration maxWait;
  final Duration echoTail;

  final List<Uint8List> _pending = [];
  int _pendingBytes = 0;
  Timer? _wait;
  Future<void> _chain = Future.value();
  DateTime _playUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _epoch = 0;

  int get _prebufferBytes => sampleRate * 2 * prebuffer.inMilliseconds ~/ 1000;

  /// True while queued audio is (approximately) still playing.
  bool get playing => _clock().isBefore(_playUntil);

  /// True while nothing heard by the mic should reach the model.
  bool get micShouldBeMuted =>
      _pendingBytes > 0 || _clock().isBefore(_playUntil.add(echoTail));

  /// When the queued audio ends (for tests / UI).
  DateTime get playUntil => _playUntil;

  void add(Uint8List pcm) {
    if (pcm.length < 2) return;
    final even = pcm.length.isEven ? pcm : pcm.sublist(0, pcm.length - 1);
    if (playing) {
      _enqueue(even);
      return;
    }
    _pending.add(even);
    _pendingBytes += even.length;
    if (_pendingBytes >= _prebufferBytes) {
      _flushPending();
    } else {
      _wait ??= Timer(maxWait, _flushPending);
    }
  }

  /// End of the model's turn: play whatever is still held back.
  void turnComplete() => _flushPending();

  /// Barge-in / close: drop everything not yet fed.
  void clear() {
    _epoch++;
    _wait?.cancel();
    _wait = null;
    _pending.clear();
    _pendingBytes = 0;
    // The user is talking (barge-in): open the mic now, no echo tail.
    _playUntil = _clock().subtract(echoTail);
  }

  void _flushPending() {
    _wait?.cancel();
    _wait = null;
    if (_pending.isEmpty) return;
    final all = BytesBuilder(copy: false);
    for (final p in _pending) {
      all.add(p);
    }
    _pending.clear();
    _pendingBytes = 0;
    _enqueue(all.takeBytes());
  }

  void _enqueue(Uint8List pcm) {
    final now = _clock();
    final start = now.isAfter(_playUntil) ? now : _playUntil;
    _playUntil = start.add(
      Duration(microseconds: pcm.length * 1000000 ~/ (sampleRate * 2)),
    );
    final epoch = _epoch;
    _chain = _chain.then((_) async {
      if (epoch != _epoch) return;
      try {
        await feed(pcm);
      } catch (_) {}
    });
  }

  /// Waits until every queued feed call has been made (tests).
  Future<void> drain() => _chain;
}
