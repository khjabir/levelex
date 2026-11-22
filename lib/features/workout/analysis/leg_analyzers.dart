import '../../../core/constants/app_constants.dart';
import '../../../core/utils/geometry.dart';
import '../../../models/exercise.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import 'exercise_analyzer.dart';
import 'rep_cycle_counter.dart';
import 'signals.dart';

/// Shared behaviour for standing leg exercises (squats, lunges): the body is
/// upright, the feet stay planted and the hips travel down and up.
abstract class _StandingLegAnalyzer extends CycleExerciseAnalyzer {
  _StandingLegAnalyzer({
    required super.thresholds,
    required super.cycle,
    super.target,
  });

  Vec3? _hipAtRest;
  Vec3? _ankleAtRest;

  List<BodySide> legs(PoseResult pose) => [
    for (final side in BodySide.values)
      if (jointsOk(pose, [side.hip, side.knee, side.ankle])) side,
  ];

  @override
  int limbsUsed(PoseResult pose) => legs(pose).length;

  @override
  bool countable(PoseResult pose) =>
      legs(pose).isNotEmpty &&
      (above(pose, LandmarkType.leftShoulder, thresholds.presenceConfidence) ||
          above(
            pose,
            LandmarkType.rightShoulder,
            thresholds.presenceConfidence,
          ));

  /// Upright body: shoulders above hips along "up".
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return false;
    final shoulderAboveHip = pose.heightAbove(side.shoulder, side.hip, torso);
    if (shoulderAboveHip == null || shoulderAboveHip < 0.5) return false;
    if (pose.hasGravity) {
      final tilt = pose.bodyTiltDegrees(side);
      if (tilt != null && tilt < 35) return false; // lying or planking
    }
    return true;
  }

  @override
  void onRestFrame(PoseResult pose) {
    final l = legs(pose);
    _hipAtRest = pose.mean2D(l.map((s) => s.hip));
    _ankleAtRest = pose.mean2D(l.map((s) => s.ankle));
  }

  /// Hips must travel and the feet must stay where they were.
  @override
  bool vetoWork(PoseResult pose) {
    final l = legs(pose);
    final hip = pose.mean2D(l.map((s) => s.hip));
    final ankle = pose.mean2D(l.map((s) => s.ankle));
    final thigh = meanSegment(pose, (s) => s.hip, (s) => s.knee);
    final refHip = _hipAtRest;
    final refAnkle = _ankleAtRest;
    if (hip == null ||
        ankle == null ||
        refHip == null ||
        refAnkle == null ||
        thigh == 0) {
      return false;
    }
    final hipTravel = Geometry.distance3(hip, refHip);
    final ankleTravel = Geometry.distance3(ankle, refAnkle);
    if (hipTravel < 0.15 * thigh) {
      diagnostics.reject('hipsDidNotMove');
      return true;
    }
    if (ankleTravel > 0.8 * hipTravel && ankleTravel > 0.3 * thigh) {
      diagnostics.reject('feetMoved');
      return true;
    }
    return false;
  }

  /// Legs exercises: the torso should stay reasonably upright. A shoulder
  /// that sits less than 0.55 torso lengths above the hip (≈ 57° of lean)
  /// means the user is folding forward.
  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) {
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return FormStatus.goodForm;
    final up = pose.heightAbove(side.shoulder, side.hip, torso);
    if (up != null && up < 0.55) return FormStatus.torsoLeaning;
    return FormStatus.goodForm;
  }
}

/// Squats: how high the hips are above the ankles, as a fraction of the
/// standing height (1 standing, ~0.55 thighs parallel). The knee angle is
/// blind from the front, where the knees bend towards the camera; the hips
/// dropping is visible from every side.
class SquatAnalyzer extends _StandingLegAnalyzer {
  SquatAnalyzer({super.thresholds = const PushUpThresholds(), int? targetReps})
    : super(
        target: targetReps,
        cycle: CycleConfig(
          restDefault: 0.9,
          workDefault: thresholds.squatDropRatio,
          minRange: 0.2,
          margin: 0.3,
          minGap: 0.08,
          decayPerFrame: 0.0015,
          maxAdaptiveLoosening: 0.05,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: const Duration(milliseconds: 250),
          cooldown: const Duration(milliseconds: 400),
          shallowFraction: thresholds.shallowFraction,
        ),
      );

  final DropRatio _drop = DropRatio();

  @override
  ExerciseType get type => ExerciseType.squat;

  @override
  double? signal(PoseResult pose) {
    final l = legs(pose);
    if (l.isEmpty) return null;
    final h = pose.heightBetween(l.map((s) => s.hip), l.map((s) => s.ankle));
    return _drop.update(h, pose.timestamp);
  }

  @override
  void reset() {
    super.reset();
    _drop.reset();
  }
}

/// Lunges: how high the hips are above the planted (lower) foot, as a
/// fraction of the standing height, like the squat. The back heel lifts, so
/// the lower ankle is the reference. Either leg counts.
class LungeAnalyzer extends _StandingLegAnalyzer {
  LungeAnalyzer({super.thresholds = const PushUpThresholds(), int? targetReps})
    : super(
        target: targetReps,
        cycle: CycleConfig(
          restDefault: 0.9,
          workDefault: thresholds.squatDropRatio + 0.04,
          minRange: 0.18,
          margin: 0.3,
          minGap: 0.07,
          decayPerFrame: 0.0015,
          maxAdaptiveLoosening: 0.05,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: const Duration(milliseconds: 200),
          cooldown: const Duration(milliseconds: 400),
          shallowFraction: thresholds.shallowFraction,
        ),
      );

  final DropRatio _drop = DropRatio();

  @override
  ExerciseType get type => ExerciseType.lunge;

  @override
  double? signal(PoseResult pose) {
    final l = legs(pose);
    if (l.isEmpty) return null;
    double? lowest;
    for (final side in l) {
      final h = pose.heightBetween(l.map((s) => s.hip), [side.ankle]);
      if (h == null) continue;
      lowest = lowest == null || h > lowest ? h : lowest;
    }
    return _drop.update(lowest, pose.timestamp);
  }

  @override
  void reset() {
    super.reset();
    _drop.reset();
  }

  /// Lunges step forward, so the feet are allowed to move.
  @override
  bool vetoWork(PoseResult pose) {
    final l = legs(pose);
    final hip = pose.mean2D(l.map((s) => s.hip));
    final thigh = meanSegment(pose, (s) => s.hip, (s) => s.knee);
    final refHip = _hipAtRest;
    if (hip == null || refHip == null || thigh == 0) return false;
    if (Geometry.distance3(hip, refHip) < 0.12 * thigh) {
      diagnostics.reject('hipsDidNotMove');
      return true;
    }
    return false;
  }
}

/// Squat jumps: the same knee-angle cycle as a squat; the flight phase is
/// just a fast return to "rest". Reported as its own exercise.
class SquatJumpAnalyzer extends SquatAnalyzer {
  SquatJumpAnalyzer({super.thresholds, super.targetReps});

  @override
  ExerciseType get type => ExerciseType.squatJump;
}
