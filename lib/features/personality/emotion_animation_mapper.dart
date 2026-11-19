import 'dart:ui' show Color;

import '../../core/theme.dart';
import '../face/face_params.dart';
import 'emotion.dart';

/// How the eyes move for a given emotion.
enum GazeBehavior {
  /// slow random look-around
  wander,

  /// mostly centred on the user, small saccades
  focus,

  /// quick darting glances
  dart,

  /// looks down and stays there
  down,

  /// looks up (thinking / curious)
  up,

  /// eyes closed or nearly closed; no gaze change
  rest,
}

class FaceSpec {
  const FaceSpec(this.params, this.gaze);
  final FaceParams params;
  final GazeBehavior gaze;
}

/// Table: (emotion, intensity) → face parameters + gaze behaviour.
///
/// Each emotion has a "full intensity" pose. The returned pose is
/// lerp(neutral, pose, 0.35 + 0.65 * intensity) so low intensity is a subtle
/// version of the same expression. Accent colour is not intensity-scaled.
class EmotionAnimationMapper {
  const EmotionAnimationMapper();

  static const neutral = FaceParams(
    eyeOpen: 1,
    eyeSmile: 0.05,
    eyeScale: 1,
    pupilSize: 0.5,
    browAngle: 0,
    browLift: 0.3,
    mouthCurve: 0.25,
    mouthOpen: 0,
    mouthWidth: 1,
    glow: 0.6,
    blush: 0,
    accent: SahbiColors.turquoise,
  );

  static const Map<Emotion, (FaceParams, GazeBehavior)> table = {
    Emotion.neutral: (neutral, GazeBehavior.wander),
    Emotion.happy: (
      FaceParams(
        eyeOpen: 0.9,
        eyeSmile: 0.75,
        eyeScale: 1.02,
        pupilSize: 0.6,
        browAngle: -0.1,
        browLift: 0.55,
        mouthCurve: 1,
        mouthOpen: 0.35,
        mouthWidth: 1.25,
        glow: 0.85,
        blush: 0.8,
        accent: Color(0xFFFFD54F),
      ),
      GazeBehavior.focus,
    ),
    Emotion.sad: (
      FaceParams(
        eyeOpen: 0.62,
        eyeSmile: 0,
        eyeScale: 0.95,
        pupilSize: 0.65,
        browAngle: -0.85,
        browLift: 0.45,
        mouthCurve: -0.8,
        mouthOpen: 0,
        mouthWidth: 0.85,
        glow: 0.35,
        blush: 0,
        accent: Color(0xFF4D7CFF),
      ),
      GazeBehavior.down,
    ),
    Emotion.curious: (
      FaceParams(
        eyeOpen: 1,
        eyeSmile: 0.1,
        eyeScale: 1.1,
        pupilSize: 0.7,
        browAngle: -0.3,
        browLift: 0.7,
        mouthCurve: 0.15,
        mouthOpen: 0.12,
        mouthWidth: 0.7,
        tilt: 0.12,
        glow: 0.75,
        blush: 0.1,
        accent: Color(0xFFB388FF),
      ),
      GazeBehavior.up,
    ),
    Emotion.surprised: (
      FaceParams(
        eyeOpen: 1,
        eyeSmile: 0,
        eyeScale: 1.28,
        pupilSize: 0.3,
        browAngle: -0.2,
        browLift: 1,
        mouthCurve: 0,
        mouthOpen: 0.8,
        mouthWidth: 0.6,
        glow: 1,
        blush: 0.2,
        accent: Color(0xFFFF8A3D),
      ),
      GazeBehavior.focus,
    ),
    Emotion.sleepy: (
      FaceParams(
        eyeOpen: 0.18,
        eyeSmile: 0.1,
        eyeScale: 0.95,
        pupilSize: 0.4,
        browAngle: -0.15,
        browLift: 0.1,
        mouthCurve: 0.05,
        mouthOpen: 0.05,
        mouthWidth: 0.7,
        tilt: -0.06,
        glow: 0.25,
        blush: 0,
        accent: Color(0xFF6F6FD8),
      ),
      GazeBehavior.rest,
    ),
    Emotion.angry: (
      FaceParams(
        eyeOpen: 0.7,
        eyeSmile: 0.25,
        eyeScale: 0.95,
        pupilSize: 0.35,
        browAngle: 0.9,
        browLift: 0.15,
        mouthCurve: -0.5,
        mouthOpen: 0.1,
        mouthWidth: 0.9,
        glow: 0.9,
        blush: 0,
        accent: Color(0xFFFF3B3B),
      ),
      GazeBehavior.focus,
    ),
    Emotion.listening: (
      FaceParams(
        eyeOpen: 1,
        eyeSmile: 0.15,
        eyeScale: 1.08,
        pupilSize: 0.75,
        browAngle: -0.15,
        browLift: 0.6,
        mouthCurve: 0.3,
        mouthOpen: 0,
        mouthWidth: 0.8,
        tilt: 0.08,
        glow: 0.95,
        blush: 0.1,
        accent: SahbiColors.green,
      ),
      GazeBehavior.focus,
    ),
    Emotion.speaking: (
      FaceParams(
        eyeOpen: 0.95,
        eyeSmile: 0.3,
        eyeScale: 1,
        pupilSize: 0.55,
        browAngle: 0,
        browLift: 0.45,
        mouthCurve: 0.45,
        mouthOpen: 0.15,
        mouthWidth: 1.05,
        glow: 0.8,
        blush: 0.2,
        accent: SahbiColors.turquoise,
      ),
      GazeBehavior.focus,
    ),
    Emotion.music: (
      FaceParams(
        eyeOpen: 0.35,
        eyeSmile: 0.9,
        eyeScale: 1,
        pupilSize: 0.5,
        browAngle: -0.1,
        browLift: 0.5,
        mouthCurve: 0.8,
        mouthOpen: 0.2,
        mouthWidth: 1.1,
        glow: 0.9,
        blush: 0.5,
        accent: SahbiColors.amber,
      ),
      GazeBehavior.rest,
    ),
  };

  FaceSpec map(Emotion emotion, double intensity) {
    final i = intensity.isNaN ? 0.5 : intensity.clamp(0.0, 1.0);
    final (pose, gaze) = table[emotion]!;
    if (emotion == Emotion.neutral) return FaceSpec(pose, gaze);
    final t = 0.35 + 0.65 * i;
    final p = FaceParams.lerp(neutral, pose, t).copyWith(accent: pose.accent);
    return FaceSpec(p, gaze);
  }
}
