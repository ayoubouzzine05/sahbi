/// MIMO's autonomous moods. Pure data: no Flutter, no phone UI, so the same
/// engine can drive a physical robot (servos / display) over BLE or Wi-Fi.
enum MimoState { idle, curious, playful, sleepy, bored, listening }

/// How the eyes behave in a state (the face renderer — phone or robot
/// display — applies it on top of the current emotion).
class EyeStyle {
  const EyeStyle({
    required this.blinkMin,
    required this.blinkMax,
    required this.lookMin,
    required this.lookMax,
    this.doubleBlink = 0.15,
    this.lookRange = 0.8,
    this.lid = 0,
    this.widen = 0,
    this.blinks = true,
  });

  /// Seconds between blinks (random in [blinkMin, blinkMax]).
  final double blinkMin;
  final double blinkMax;

  /// Chance that a blink is doubled.
  final double doubleBlink;

  /// Seconds between glances when nothing else drives the gaze.
  final double lookMin;
  final double lookMax;

  /// How far the eyes wander (0 = straight ahead, 1 = edges).
  final double lookRange;

  /// Upper lids drooping (0..1): bored / sleepy.
  final double lid;

  /// Eyes opened wider (0..1): curious / listening.
  final double widen;

  /// False = no blinking (staring while listening).
  final bool blinks;

  static const idle = EyeStyle(
    blinkMin: 3,
    blinkMax: 5.5,
    lookMin: 5,
    lookMax: 11,
    lookRange: 0.7,
  );
  static const curious = EyeStyle(
    blinkMin: 4,
    blinkMax: 7,
    lookMin: 0.5,
    lookMax: 1.4,
    lookRange: 1,
    widen: 0.7,
    doubleBlink: 0.05,
  );
  static const playful = EyeStyle(
    blinkMin: 1.6,
    blinkMax: 3.2,
    lookMin: 0.8,
    lookMax: 2,
    lookRange: 0.9,
    widen: 0.3,
    doubleBlink: 0.4,
  );
  static const bored = EyeStyle(
    blinkMin: 4,
    blinkMax: 8,
    lookMin: 4,
    lookMax: 9,
    lookRange: 1,
    lid: 0.45,
    doubleBlink: 0.05,
  );
  static const sleepy = EyeStyle(
    blinkMin: 1.8,
    blinkMax: 3.5,
    lookMin: 7,
    lookMax: 14,
    lookRange: 0.3,
    lid: 0.75,
    doubleBlink: 0,
  );
  static const listening = EyeStyle(
    blinkMin: 6,
    blinkMax: 10,
    lookMin: 30,
    lookMax: 60,
    lookRange: 0.1,
    widen: 0.5,
    blinks: false,
    doubleBlink: 0,
  );

  static EyeStyle of(MimoState s) => switch (s) {
    MimoState.idle => idle,
    MimoState.curious => curious,
    MimoState.playful => playful,
    MimoState.bored => bored,
    MimoState.sleepy => sleepy,
    MimoState.listening => listening,
  };
}

/// What happened around MIMO.
enum BehaviorEvent {
  /// "MIMO" heard.
  wake,

  /// The user said / typed something.
  userSpoke,

  /// Touched (tap, stroke).
  touched,

  /// Something moved in front of the eyes.
  motion,
  conversationStart,
  conversationEnd,
  listenStart,
  listenEnd,
  gameStart,
  gameEnd,
  fellAsleep,
  wokeUp,
}

/// Something MIMO decides to do on its own.
enum InitiativeKind {
  /// A short Darija remark (AI when online, pre-written offline).
  remark,

  /// "7ajitek majitek" riddle.
  riddle,

  /// A 3-choice question.
  trivia,

  /// Tap-when-the-eyes-turn-green game.
  reaction,
}

/// Output of the engine, for any body (phone face, robot over BLE/Wi-Fi).
sealed class BodyCommand {
  const BodyCommand();
}

/// The mood changed: show it.
class SetMood extends BodyCommand {
  const SetMood(this.state, this.eyes);
  final MimoState state;
  final EyeStyle eyes;
}

/// Look somewhere (-1..1 both axes; 0,0 = straight at the user).
class LookAt extends BodyCommand {
  const LookAt(this.x, this.y, {this.holdMs = 1500});
  final double x;
  final double y;
  final int holdMs;
}

/// Play a little silent scene by name (eat, yawn, sparkle…).
class PlaySkit extends BodyCommand {
  const PlaySkit(this.name);
  final String name;
}

/// Start talking / playing on its own.
class TakeInitiative extends BodyCommand {
  const TakeInitiative(this.kind);
  final InitiativeKind kind;
}
