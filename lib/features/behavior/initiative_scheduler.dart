/// Limits on MIMO starting things by itself, so it feels alive without
/// being annoying (and saves the free AI quota):
///
/// - at least [minGap] between two spoken initiatives;
/// - at most [perHour] per hour and [perDay] per day;
/// - a game at most every [gameGap];
/// - never during quiet hours ([isQuiet]).
class InitiativeScheduler {
  InitiativeScheduler({
    required this.isQuiet,
    DateTime Function()? clock,
    this.minGap = const Duration(minutes: 3),
    this.perHour = 12,
    this.perDay = 60,
    this.gameGap = const Duration(minutes: 20),
  }) : _clock = clock ?? DateTime.now;

  /// True at this local hour (0..23) inside the quiet hours.
  final bool Function(int hour) isQuiet;
  final DateTime Function() _clock;
  final Duration minGap;
  final int perHour;
  final int perDay;
  final Duration gameGap;

  final List<DateTime> _done = [];
  DateTime? _lastGame;

  bool quietNow() => isQuiet(_clock().hour);

  /// May MIMO say something by itself right now?
  bool canSpeak() {
    final now = _clock();
    if (isQuiet(now.hour)) return false;
    _done.removeWhere((t) => now.difference(t) > const Duration(days: 1));
    if (_done.length >= perDay) return false;
    if (_done.isNotEmpty && now.difference(_done.last) < minGap) return false;
    final lastHour = _done
        .where((t) => now.difference(t) < const Duration(hours: 1))
        .length;
    return lastHour < perHour;
  }

  /// May MIMO start a game right now?
  bool canPlay() {
    if (!canSpeak()) return false;
    final g = _lastGame;
    return g == null || _clock().difference(g) >= gameGap;
  }

  /// Record that an initiative happened.
  void record({bool game = false}) {
    final now = _clock();
    _done.add(now);
    if (game) _lastGame = now;
  }

  /// Initiatives in the last 24 h (for tests / debug).
  int get today => _done.length;
}
