import '../../../models/exercise.dart';

/// Joint angle the generic tracker follows.
enum JointKind {
  /// shoulder → elbow → wrist
  elbow,

  /// hip → knee → ankle
  knee,

  /// shoulder → hip → knee
  hip,

  /// hip → shoulder → wrist (arm raised away from the torso)
  shoulderRaise,
}

/// How left and right measurements combine into one signal.
enum SideAggregate { mean, min, max }

/// How the camera tracks a movement.
sealed class TrackingSpec {
  const TrackingSpec();

  bool get usesCamera => this is! TimerTracking;
}

/// One of the seven purpose-built analyzers.
class ExerciseTracking extends TrackingSpec {
  const ExerciseTracking(this.type);

  final ExerciseType type;
}

/// Counts reps on a joint angle with hysteresis (generic gym movements).
class AngleTracking extends TrackingSpec {
  const AngleTracking({
    required this.joint,
    required this.restAngle,
    required this.workAngle,
    this.requireUpright = false,
    this.aggregate = SideAggregate.mean,
    this.minGap = 15,
  });

  final JointKind joint;
  final double restAngle;
  final double workAngle;

  /// Shoulders must be above the hips (standing / seated movements).
  final bool requireUpright;

  /// How the two sides combine: mean for bilateral movements, min/max for
  /// alternating ones (high knees, mountain climbers).
  final SideAggregate aggregate;

  /// Smallest distance kept between the rest and work thresholds (degrees).
  final double minGap;

  bool get restIsHigh => restAngle > workAngle;
}

/// Time accrues while a joint angle stays inside a range (wall sit).
class HoldTracking extends TrackingSpec {
  const HoldTracking({
    required this.joint,
    required this.minAngle,
    required this.maxAngle,
  });

  final JointKind joint;
  final double minAngle;
  final double maxAngle;
}

/// No camera: a countdown with the 3D guide (cardio machines, stretches).
class TimerTracking extends TrackingSpec {
  const TimerTracking();
}
