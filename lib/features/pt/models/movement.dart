import '../../workout/analysis/tracking_spec.dart';
import 'equipment.dart';

export '../../workout/analysis/tracking_spec.dart';
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

  /// Equipment whose load is a number worth logging and progressing.
  static const loadBearing = {
    Equipment.dumbbells,
    Equipment.barbell,
    Equipment.kettlebell,
    Equipment.cableMachine,
    Equipment.medicineBall,
  };

  /// Whether this movement, done with [equipment], carries a load in kg.
  bool loadedWith(Set<Equipment> equipment) =>
      equipment.any(loadBearing.contains);

  /// Whether any option for this movement is a loaded one.
  bool get canBeLoaded =>
      equipmentOptions.any((o) => o.any(loadBearing.contains));

  Set<MuscleGroup> get muscles => {...primary, ...secondary};
}
