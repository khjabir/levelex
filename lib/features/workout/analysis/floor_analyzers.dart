import '../../../core/constants/app_constants.dart';
import '../../../core/utils/geometry.dart';
import '../../../models/exercise.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import 'exercise_analyzer.dart';
import 'rep_cycle_counter.dart';

/// Sit-ups: torso angle (shoulder→hip→knee). With the knees bent, lying
/// back measures ≈ 125°+ (rest) and sitting up ≈ 60° (work). The hips stay
/// planted while the shoulders travel.
class SitUpAnalyzer extends CycleExerciseAnalyzer {
  SitUpAnalyzer({super.thresholds = const PushUpThresholds(), int? targetReps})
    : super(
        target: targetReps,
        cycle: CycleConfig(
          restDefault: 120,
          workDefault: 80,
          minRange: 35,
          margin: 0.3,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: const Duration(milliseconds: 250),
          cooldown: const Duration(milliseconds: 400),
        ),
      );

  Vec3? _shoulderAtRest;
  Vec3? _hipAtRest;

  @override
  ExerciseType get type => ExerciseType.sitUp;

  List<BodySide> _sides(PoseResult pose) => [
    for (final side in BodySide.values)
      if (jointsOk(pose, [side.shoulder, side.hip, side.knee])) side,
  ];

  @override
  int limbsUsed(PoseResult pose) => _sides(pose).length;

  @override
  bool countable(PoseResult pose) => _sides(pose).isNotEmpty;

  /// Knees bent (hip→knee→ankle well under 160°) and hips lower than the
  /// shoulders are not required: any lying/sitting body with bent knees.
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final knee = pose.kneeAngle(side);
    if (knee != null && knee > 165) return false; // legs straight: not set up
    if (pose.hasGravity) {
      final tilt = pose.bodyTiltDegrees(side);
      // Standing bodies are excluded; lying/sitting bodies pass.
      if (tilt != null && tilt > 75) return false;
    }
    return true;
  }

  @override
  double? signal(PoseResult pose) {
    var sum = 0.0;
    var n = 0;
    for (final side in _sides(pose)) {
      final a = pose.torsoAngle(side);
      if (a == null) continue;
      sum += a;
      n++;
    }
    return n == 0 ? null : sum / n;
  }

  @override
  void onRestFrame(PoseResult pose) {
    final s = _sides(pose);
    _shoulderAtRest = pose.mean2D(s.map((x) => x.shoulder));
    _hipAtRest = pose.mean2D(s.map((x) => x.hip));
  }

  @override
  bool vetoWork(PoseResult pose) {
    final s = _sides(pose);
    final shoulder = pose.mean2D(s.map((x) => x.shoulder));
    final hip = pose.mean2D(s.map((x) => x.hip));
    final torso = meanSegment(pose, (x) => x.shoulder, (x) => x.hip);
    final refS = _shoulderAtRest;
    final refH = _hipAtRest;
    if (shoulder == null ||
        hip == null ||
        refS == null ||
        refH == null ||
        torso == 0) {
      return false;
    }
    final shoulderTravel = Geometry.distance3(shoulder, refS);
    final hipTravel = Geometry.distance3(hip, refH);
    if (shoulderTravel < 0.25 * torso) {
      diagnostics.reject('shouldersDidNotMove');
      return true;
    }
    if (hipTravel > 0.8 * shoulderTravel && hipTravel > 0.3 * torso) {
      diagnostics.reject('hipsMoved');
      return true;
    }
    return false;
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      FormStatus.goodForm;
}

/// Burpees: standing (body vertical) is rest, the floor position (body
/// horizontal, hands down) is work. Uses the body tilt, which is measured
/// against real gravity when the sensor is available.
class BurpeeAnalyzer extends CycleExerciseAnalyzer {
  BurpeeAnalyzer({super.thresholds = const PushUpThresholds(), int? targetReps})
    : super(
        target: targetReps,
        cycle: CycleConfig(
          restDefault: 60, // tilt ≥ 60° from horizontal = standing
          workDefault: 30, // tilt ≤ 30° = on the floor
          adaptive: false,
          minGap: 20,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: const Duration(milliseconds: 300),
          cooldown: const Duration(milliseconds: 600),
        ),
      );

  @override
  ExerciseType get type => ExerciseType.burpee;

  @override
  bool countable(PoseResult pose) =>
      bodyPresent(pose, BodySide.left) || bodyPresent(pose, BodySide.right);

  /// Any visible body qualifies; the signal itself decides.
  @override
  bool inPosition(PoseResult pose) => true;

  @override
  double? signal(PoseResult pose) {
    var sum = 0.0;
    var n = 0;
    for (final side in BodySide.values) {
      if (!bodyPresent(pose, side)) continue;
      final t = pose.bodyTiltDegrees(side);
      if (t == null) continue;
      sum += t;
      n++;
    }
    return n == 0 ? null : sum / n;
  }

  /// On the floor the hands must be down by the shoulders, not overhead.
  @override
  bool vetoWork(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final ratio = pose.wristBelowShoulderRatio(side);
    if (ratio != null && ratio < thresholds.maxHandsRaisedRatio) {
      diagnostics.reject('handsNotDown');
      return true;
    }
    return false;
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      FormStatus.goodForm;
}

/// Jumping jacks: openness = arms raised + feet spread. Closed is rest.
class JumpingJackAnalyzer extends CycleExerciseAnalyzer {
  JumpingJackAnalyzer({
    super.thresholds = const PushUpThresholds(),
    int? targetReps,
  }) : super(
         target: targetReps,
         cycle: CycleConfig(
           restDefault: 0.3,
           workDefault: 1.3,
           restIsHigh: false,
           adaptive: false,
           minGap: 0.4,
           decayPerFrame: 0.005,
           minFrames: thresholds.minFramesForTransition,
           minWorkDuration: const Duration(milliseconds: 120),
           cooldown: const Duration(milliseconds: 250),
         ),
       );

  static const _needed = [
    LandmarkType.leftShoulder,
    LandmarkType.rightShoulder,
    LandmarkType.leftWrist,
    LandmarkType.rightWrist,
    LandmarkType.leftHip,
    LandmarkType.rightHip,
    LandmarkType.leftAnkle,
    LandmarkType.rightAnkle,
  ];

  @override
  ExerciseType get type => ExerciseType.jumpingJack;

  @override
  int limbsUsed(PoseResult pose) => 2;

  @override
  bool countable(PoseResult pose) => jointsOk(pose, _needed);

  /// Standing upright, facing roughly towards the camera.
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return false;
    final up = pose.heightAbove(side.shoulder, side.hip, torso);
    return up != null && up > 0.5;
  }

  /// 0 ≈ closed (hands down, feet together); ~2 ≈ fully open.
  @override
  double? signal(PoseResult pose) {
    final shoulders = pose.mean2D([
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    ]);
    final hips = pose.mean2D([LandmarkType.leftHip, LandmarkType.rightHip]);
    final wrists = pose.mean2D([
      LandmarkType.leftWrist,
      LandmarkType.rightWrist,
    ]);
    final la = pose.position2D(LandmarkType.leftAnkle);
    final ra = pose.position2D(LandmarkType.rightAnkle);
    final lh = pose.position2D(LandmarkType.leftHip);
    final rh = pose.position2D(LandmarkType.rightHip);
    if (shoulders == null ||
        hips == null ||
        wrists == null ||
        la == null ||
        ra == null ||
        lh == null ||
        rh == null) {
      return null;
    }
    final torso = Geometry.distance3(shoulders, hips);
    if (torso == 0) return null;
    final up2 = Vec3(pose.up.x, pose.up.y, 0);
    final upUnit = up2.length == 0 ? const Vec3(0, -1, 0) : up2.normalized;
    final handsUp = ((wrists - shoulders).dot(upUnit) / torso).clamp(-0.6, 1.2);
    final hipWidth = Geometry.distance3(lh, rh);
    final spread = hipWidth == 0
        ? 0.0
        : ((Geometry.distance3(la, ra) / hipWidth - 1.0) / 1.5).clamp(0.0, 1.0);
    return handsUp + spread;
  }

  /// At the open position the hands should be clearly above the shoulders.
  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) {
    if (counter.phase != CyclePhase.work) return FormStatus.goodForm;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return FormStatus.goodForm;
    final wrists = pose.mean2D([
      LandmarkType.leftWrist,
      LandmarkType.rightWrist,
    ]);
    final shoulders = pose.mean2D([
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    ]);
    if (wrists == null || shoulders == null) return FormStatus.goodForm;
    final up2 = Vec3(pose.up.x, pose.up.y, 0);
    final upUnit = up2.length == 0 ? const Vec3(0, -1, 0) : up2.normalized;
    final handsUp = (wrists - shoulders).dot(upUnit) / torso;
    return handsUp < 0.45 ? FormStatus.armsNotOverhead : FormStatus.goodForm;
  }
}
