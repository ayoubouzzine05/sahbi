/// Conversation/voice state machine.
enum VoiceState { idle, listening, thinking, speaking, error }

class IllegalTransition implements Exception {
  IllegalTransition(this.from, this.to);
  final VoiceState from;
  final VoiceState to;
  @override
  String toString() => 'IllegalTransition($from → $to)';
}

/// Legal transitions:
/// - idle → listening | thinking | speaking | error
/// - listening → idle (cancel/stop/no speech) | thinking (got text) | error
/// - thinking → speaking | idle (no speech output / interrupted) | error | listening (user barged in)
/// - speaking → idle (done/interrupted) | listening (barge-in) | thinking (new typed input) | error
/// - error → idle | listening | thinking
class VoiceStateMachine {
  VoiceStateMachine([this._state = VoiceState.idle]);

  VoiceState _state;
  VoiceState get state => _state;
  String? lastError;

  static const Map<VoiceState, Set<VoiceState>> legal = {
    VoiceState.idle: {
      VoiceState.listening,
      VoiceState.thinking,
      VoiceState.speaking,
      VoiceState.error,
    },
    VoiceState.listening: {
      VoiceState.idle,
      VoiceState.thinking,
      VoiceState.error,
    },
    VoiceState.thinking: {
      VoiceState.speaking,
      VoiceState.idle,
      VoiceState.error,
      VoiceState.listening,
    },
    VoiceState.speaking: {
      VoiceState.idle,
      VoiceState.listening,
      VoiceState.thinking,
      VoiceState.error,
    },
    VoiceState.error: {
      VoiceState.idle,
      VoiceState.listening,
      VoiceState.thinking,
    },
  };

  bool canTransition(VoiceState to) =>
      to == _state || legal[_state]!.contains(to);

  /// Throws [IllegalTransition] for transitions not in [legal].
  VoiceState transition(VoiceState to, {String? error}) {
    if (to == _state) return _state;
    if (!legal[_state]!.contains(to)) throw IllegalTransition(_state, to);
    _state = to;
    lastError = to == VoiceState.error ? (error ?? 'unknown') : null;
    return _state;
  }

  /// Like [transition] but returns false instead of throwing.
  bool tryTransition(VoiceState to, {String? error}) {
    if (!canTransition(to)) return false;
    transition(to, error: error);
    return true;
  }
}
