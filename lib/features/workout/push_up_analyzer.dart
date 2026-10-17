import '../../core/constants/app_constants.dart';
import '../../core/utils/geometry.dart';
import '../../models/exercise.dart';
import '../../models/form_status.dart';
import '../../models/pose_result.dart';
import 'analysis/exercise_analyzer.dart';
import 'analysis/rep_cycle_counter.dart';

export 'analysis/exercise_analyzer.dart';
export 'analysis/rep_cycle_counter.dart' show CyclePhase, CycleRejection;

/// Push-up counter.
///
/// Signal: elbow angle averaged over the trackable arms, measured in the
/// image plane unless the arm points at the camera (then depth is used).
/// Rest = arms extended, work = arms bent. Thresholds adapt to the user's
/// range of motion.
///
/// A descent is accepted only when the shoulders actually moved since the
/// last rest frame and the hands did not swing far more than the shoulders
/// (hands planted). The shared [BodyTracker] rejects skeleton jumps, so a
/// hand or a second person entering the frame cannot generate reps.
class PushUpAnalyzer extends CycleExerciseAnalyzer {
  PushUpAnalyzer({super.thresholds = const PushUpThresholds(), int? targetReps})
    : super(
        target: targetReps,
        cycle: CycleConfig(
          restDefault: thresholds.upAngle,
          workDefault: thresholds.downAngle,
          minRange: thresholds.adaptiveMinRange,
          margin: thresholds.adaptiveMargin,
          adaptive: thresholds.adaptiveThresholds,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: thresholds.minRepDuration,
          cooldown: thresholds.repCooldown,
          shallowFraction: thresholds.shallowFraction,
        ),
      );

  Vec3? _shoulderAtRest;
  Vec3? _wristAtRest;

  @override
  ExerciseType get type => ExerciseType.pushUp;

  List<BodySide> _arms(PoseResult pose) => [
    for (final side in BodySide.values)
      if (jointsOk(pose, [side.shoulder, side.elbow, side.wrist])) side,
  ];

  bool _hipOk(PoseResult pose) =>
      above(pose, LandmarkType.leftHip, thresholds.minLandmarkConfidence) ||
      above(pose, LandmarkType.rightHip, thresholds.minLandmarkConfidence);

  @override
  BodySide? chooseSide(PoseResult pose) {
    if (!pose.hasPose) return null;
    final arms = _arms(pose);
    if (arms.length == 1) return arms.first;
    return pose.preferredSide;
  }

  @override
  double? signal(PoseResult pose) {
    final arms = _arms(pose);
    var sum = 0.0;
    var n = 0;
    for (final side in arms) {
      final a = pose.elbowAngle(side);
      if (a == null) continue;
      sum += a;
      n++;
    }
    return n == 0 ? null : sum / n;
  }

  @override
  int limbsUsed(PoseResult pose) => _arms(pose).length;

  @override
  bool countable(PoseResult pose) => _arms(pose).isNotEmpty && _hipOk(pose);

  /// Hands at or below shoulder level (on the floor) and, when the real
  /// vertical is known, not standing upright.
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final wristRatio = pose.wristBelowShoulderRatio(side);
    if (wristRatio == null || wristRatio < thresholds.maxHandsRaisedRatio) {
      return false;
    }
    if (pose.hasGravity) {
      final tilt = pose.bodyTiltDegrees(side);
      if (tilt != null && tilt > thresholds.maxBodyTiltDegrees) return false;
    }
    return true;
  }

  Vec3? _meanArmPoint(PoseResult pose, LandmarkType Function(BodySide) pick) =>
      pose.mean2D(_arms(pose).map(pick));

  @override
  void onRestFrame(PoseResult pose) {
    _shoulderAtRest = _meanArmPoint(pose, (s) => s.shoulder);
    _wristAtRest = _meanArmPoint(pose, (s) => s.wrist);
  }

  @override
  bool vetoWork(PoseResult pose) {
    final refShoulder = _shoulderAtRest;
    final refWrist = _wristAtRest;
    final shoulder = _meanArmPoint(pose, (s) => s.shoulder);
    final wrist = _meanArmPoint(pose, (s) => s.wrist);
    final upperArm = meanSegment(pose, (s) => s.shoulder, (s) => s.elbow);
    if (refShoulder == null ||
        refWrist == null ||
        shoulder == null ||
        wrist == null ||
        upperArm == 0) {
      return false;
    }
    final shoulderTravel = Geometry.distance3(shoulder, refShoulder);
    final wristTravel = Geometry.distance3(wrist, refWrist);
    if (shoulderTravel < thresholds.minShoulderTravelRatio * upperArm) {
      diagnostics.reject('shouldersDidNotMove');
      return true;
    }
    // Hands planted: only reject clear arm swinging, where the wrists move
    // far more than the shoulders.
    if (wristTravel > thresholds.maxWristTravelRatio * shoulderTravel &&
        wristTravel > 0.3 * upperArm) {
      diagnostics.reject('handsMoved');
      return true;
    }
    return false;
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      evaluateAlignment(pose, side);
}
