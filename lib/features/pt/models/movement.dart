import '../../../models/exercise.dart';
import 'equipment.dart';
import 'muscle_group.dart';

/// Reps or a timed effort.
enum MovementKind { reps, time }

/// Which part of a session a movement belongs to.
enum PlanPhase {
  warmUp('Warm-up'),
  main('Workout'),
  coolDown('Cool-down');

  const PlanPhase(this.label);

  final String label;
}

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
  });

  final JointKind joint;
  final double restAngle;
  final double workAngle;

  /// Shoulders must be above the hips (standing / seated movements).
  final bool requireUpright;

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

/// An exercise MY PT can prescribe.
class Movement {
  const Movement({
    required this.id,
    required this.name,
    required this.kind,
    required this.phases,
    required this.primary,
    this.secondary = const {},
    this.equipmentOptions = const [],
    required this.cues,
    required this.tracking,
    required this.clip,
    this.secondsPerRep = 3.0,
    this.baseReps = 12,
    this.baseSeconds = 40,
    this.equipmentHint,
    this.compound = false,
  });

  final String id;
  final String name;
  final MovementKind kind;
  final Set<PlanPhase> phases;
  final Set<MuscleGroup> primary;
  final Set<MuscleGroup> secondary;

  /// Alternative equipment sets; any one of them satisfies the movement.
  /// Empty means bodyweight only.
  final List<Set<Equipment>> equipmentOptions;
  final List<String> cues;
  final TrackingSpec tracking;

  /// Mannequin clip id (see `MannequinClips`).
  final String clip;
  final double secondsPerRep;
  final int baseReps;
  final int baseSeconds;

  /// What to grab, e.g. "a pair you can press for 10 clean reps".
  final String? equipmentHint;

  /// Multi-joint movement, scheduled before isolation work.
  final bool compound;

  bool get isTimed => kind == MovementKind.time;
  bool get bodyweight => equipmentOptions.isEmpty;

  /// The equipment set to use given what is [available], or null when the
  /// movement cannot be done.
  Set<Equipment>? equipmentFor(Set<Equipment> available) {
    if (equipmentOptions.isEmpty) return const {};
    for (final option in equipmentOptions) {
      if (option.every(available.contains)) return option;
    }
    return null;
  }

  bool canDoWith(Set<Equipment> available) => equipmentFor(available) != null;

  Set<MuscleGroup> get muscles => {...primary, ...secondary};
}
