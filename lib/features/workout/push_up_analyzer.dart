import '../../core/constants/app_constants.dart';
import '../../core/utils/geometry.dart';
import '../../models/exercise.dart';
import '../../models/form_status.dart';
import '../../models/pose_result.dart';
import 'analysis/exercise_analyzer.dart';
import 'analysis/rep_cycle_counter.dart';
import 'analysis/signals.dart';

export 'analysis/exercise_analyzer.dart';
export 'analysis/rep_cycle_counter.dart' show CyclePhase, CycleRejection;

/// Push-up counter.
///
/// Signal: how high the shoulders are above the hands, as a fraction of
/// that height at the top of the rep (1 = arms straight, ~0.35 = chest at
/// the floor). Unlike the elbow angle, this reads the same with the phone at
/// the side, in front of the head or on a diagonal: from the front the
/// elbows bend towards the camera where a 2D angle cannot see it. Rest =
/// near the top, work = below [PushUpThresholds.pushUpDropRatio]; the
/// thresholds adapt to the user's own range of motion within limits.
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
          restDefault: 0.92,
          workDefault: thresholds.pushUpDropRatio,
          minRange: 0.15,
          margin: thresholds.adaptiveMargin,
          adaptive: thresholds.adaptiveThresholds,
          minGap: 0.06,
          decayPerFrame: 0.0015,
          maxAdaptiveLoosening: 0.06,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: thresholds.minRepDuration,
          cooldown: thresholds.repCooldown,
          shallowFraction: thresholds.shallowFraction,
        ),
      );

  final DropRatio _drop = DropRatio();

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
    if (arms.isEmpty) return null;
    final h = pose.heightBetween(
      arms.map((s) => s.shoulder),
      arms.map((s) => s.wrist),
    );
    return _drop.update(h, pose.timestamp);
  }

  /// Mean elbow angle of the trackable arms (for the coach and the report).
  double? elbowAngle(PoseResult pose) {
    var sum = 0.0;
    var n = 0;
    for (final side in _arms(pose)) {
      final a = pose.elbowAngle(side);
      if (a == null) continue;
      sum += a;
      n++;
    }
    return n == 0 ? null : sum / n;
  }

  @override
  void reset() {
    super.reset();
    _drop.reset();
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
