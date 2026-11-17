/// A single turn sent to the brain.
class Turn {
  const Turn(this.role, this.text);
  final String role; // 'user' | 'assistant'
  final String text;
  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

/// Keeps the last [maxTurns] turns plus a rolling summary of older ones.
/// When the window overflows, the oldest turns are moved to [pendingForSummary]
/// and the caller asks the backend to fold them into [summary].
class ConversationContext {
  ConversationContext({this.maxTurns = 12, this.maxChars = 6000});

  final int maxTurns;
  final int maxChars;
  final List<Turn> _turns = [];
  final List<Turn> pendingForSummary = [];
  String? summary;

  List<Turn> get turns => List.unmodifiable(_turns);

  void add(String role, String text) {
    if (text.trim().isEmpty) return;
    _turns.add(Turn(role, text.trim()));
    _trim();
  }

  void _trim() {
    int chars() => _turns.fold(0, (a, t) => a + t.text.length);
    while (_turns.length > maxTurns ||
        (chars() > maxChars && _turns.length > 2)) {
      pendingForSummary.add(_turns.removeAt(0));
    }
  }

  bool get needsSummary => pendingForSummary.length >= 4;

  /// Applies a summary produced by the backend for [pendingForSummary].
  void applySummary(String newSummary) {
    summary = newSummary;
    pendingForSummary.clear();
  }

  /// If summarising failed, older turns are simply dropped (never invented).
  void dropPending() => pendingForSummary.clear();

  void clear() {
    _turns.clear();
    pendingForSummary.clear();
    summary = null;
  }
}
