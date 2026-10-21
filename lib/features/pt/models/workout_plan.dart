import 'equipment.dart';
import 'movement.dart';
import 'muscle_group.dart';

/// Standard session structures.
enum WorkoutMode {
  push('Push', 'Chest, shoulders, triceps', MuscleGroup.push),
  pull('Pull', 'Back, biceps', MuscleGroup.pull),
  legs('Legs', 'Quads, hamstrings, glutes, calves', MuscleGroup.legs),
  upper('Upper body', 'Everything above the hips', MuscleGroup.upper),
  lower('Lower body', 'Legs and core', MuscleGroup.lower),
  fullBody('Full body', 'Big movements, every muscle', MuscleGroup.full),
  core('Core & abs', 'Trunk strength and stability', {
    MuscleGroup.core,
    MuscleGroup.back,
    MuscleGroup.glutes,
  }),
  hiit('HIIT', 'Short, intense cardio rounds', {
    MuscleGroup.cardio,
    MuscleGroup.quads,
    MuscleGroup.core,
    MuscleGroup.chest,
  }),
  mobility('Mobility', 'Stretch, open up, recover', {
    MuscleGroup.mobility,
    MuscleGroup.hamstrings,
    MuscleGroup.shoulders,
    MuscleGroup.glutes,
  }),
  custom('Custom focus', 'Pick the muscles yourself', {});

  const WorkoutMode(this.label, this.description, this.muscles);

  final String label;
  final String description;
  final Set<MuscleGroup> muscles;

  static WorkoutMode fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => fullBody);
}

/// Training experience; drives volume and rest.
enum PtLevel {
  beginner('Beginner', 'New or returning; 2 sets, longer rests'),
  intermediate('Intermediate', 'Train a few times a week; 3 sets'),
  advanced('Advanced', 'Experienced; 4 sets, shorter rests');

  const PtLevel(this.label, this.description);

  final String label;
  final String description;

  int get sets => switch (this) {
    PtLevel.beginner => 2,
    PtLevel.intermediate => 3,
    PtLevel.advanced => 4,
  };

  double get repFactor => switch (this) {
    PtLevel.beginner => 0.8,
    PtLevel.intermediate => 1.0,
    PtLevel.advanced => 1.2,
  };

  Duration get rest => switch (this) {
    PtLevel.beginner => const Duration(seconds: 60),
    PtLevel.intermediate => const Duration(seconds: 45),
    PtLevel.advanced => const Duration(seconds: 35),
  };

  static PtLevel fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => intermediate);
}

/// An exercise a routine fixes for the main phase.
class FixedItem {
  const FixedItem({
    required this.movementId,
    required this.sets,
    required this.reps,
    this.repsMin,
    this.seconds,
    this.policy,
  });

  final String movementId;
  final int sets;

  /// Target reps per set (top of the range when [repsMin] is set).
  final int reps;
  final int? repsMin;
  final int? seconds;

  /// Progression policy name chosen in the routine (overrides the saved
  /// rule for this exercise), or null.
  final String? policy;
}

/// What the user asked for.
class PtRequest {
  const PtRequest({
    this.duration = const Duration(minutes: 30),
    this.mode = WorkoutMode.fullBody,
    this.focus = const {},
    this.level = PtLevel.intermediate,
    this.equipment = const {},
    this.seed = 1,
    this.quick = false,
    this.fixed = const [],
    this.routineId,
    this.routineDayId,
    this.title,
  });

  final Duration duration;
  final WorkoutMode mode;

  /// Muscles for [WorkoutMode.custom].
  final Set<MuscleGroup> focus;
  final PtLevel level;
  final Set<Equipment> equipment;

  /// Changes which movements are picked; "shuffle" bumps it.
  final int seed;

  /// One-tap quick workout: intros auto-start after a short countdown.
  final bool quick;

  /// Main-phase exercises prescribed by a routine day; the planner wraps
  /// them with a warm-up and cool-down instead of choosing its own.
  final List<FixedItem> fixed;
  final String? routineId;
  final String? routineDayId;

  /// Routine day name shown instead of the mode label.
  final String? title;

  bool get fromRoutine => fixed.isNotEmpty;

  Set<MuscleGroup> get targetMuscles =>
      mode == WorkoutMode.custom ? focus : mode.muscles;

  PtRequest copyWith({
    Duration? duration,
    WorkoutMode? mode,
    Set<MuscleGroup>? focus,
    PtLevel? level,
    Set<Equipment>? equipment,
    int? seed,
    bool? quick,
    List<FixedItem>? fixed,
    String? routineId,
    String? routineDayId,
    String? title,
  }) => PtRequest(
    duration: duration ?? this.duration,
    mode: mode ?? this.mode,
    focus: focus ?? this.focus,
    level: level ?? this.level,
    equipment: equipment ?? this.equipment,
    seed: seed ?? this.seed,
    quick: quick ?? this.quick,
    fixed: fixed ?? this.fixed,
    routineId: routineId ?? this.routineId,
    routineDayId: routineDayId ?? this.routineDayId,
    title: title ?? this.title,
  );
}

/// One prescribed block: a movement with sets, reps or seconds and rest.
class PlanItem {
  const PlanItem({
    required this.movement,
    required this.phase,
    required this.sets,
    required this.reps,
    required this.seconds,
    required this.rest,
    required this.equipment,
    this.repsMin,
    this.suggestedKg,
    this.suggestionWhy,
  });

  final Movement movement;
  final PlanPhase phase;
  final int sets;

  /// Bottom of a rep range (double progression); null for a fixed count.
  final int? repsMin;

  /// Load the progression rule suggests, with its one-line reason.
  final double? suggestedKg;
  final String? suggestionWhy;

  /// Reps per set (rep movements).
  final int reps;

  /// Seconds per set (timed movements).
  final int seconds;
  final Duration rest;

  /// Equipment to grab for this item (empty = bodyweight).
  final Set<Equipment> equipment;

  bool get isTimed => movement.isTimed;

  /// Whether the user lifts a measurable load for this item.
  bool get loaded => movement.loadedWith(equipment);

  /// Seconds of work in one set.
  double get workSecondsPerSet =>
      isTimed ? seconds.toDouble() : reps * movement.secondsPerRep;

  /// Whole block including rests between sets (not after the last set).
  Duration get estimated => Duration(
    seconds: (sets * workSecondsPerSet + (sets - 1) * rest.inSeconds).round(),
  );

  String get repLabel =>
      repsMin != null && repsMin != reps ? '$repsMin–$reps' : '$reps';

  String get prescription => isTimed
      ? (sets == 1 ? '${seconds}s' : '$sets × ${seconds}s')
      : (sets == 1 ? '$repLabel reps' : '$sets × $repLabel');

  PlanItem copyWith({
    Movement? movement,
    int? sets,
    int? reps,
    int? seconds,
    int? repsMin,
    double? suggestedKg,
    String? suggestionWhy,
    bool clearSuggestion = false,
  }) => PlanItem(
    movement: movement ?? this.movement,
    phase: phase,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    seconds: seconds ?? this.seconds,
    rest: rest,
    equipment: equipment,
    repsMin: repsMin ?? this.repsMin,
    suggestedKg: clearSuggestion ? null : (suggestedKg ?? this.suggestedKg),
    suggestionWhy: clearSuggestion
        ? null
        : (suggestionWhy ?? this.suggestionWhy),
  );
}

/// A complete session.
class WorkoutPlan {
  const WorkoutPlan({
    required this.request,
    required this.warmUp,
    required this.main,
    required this.coolDown,
    required this.rationale,
  });

  final PtRequest request;
  final List<PlanItem> warmUp;
  final List<PlanItem> main;
  final List<PlanItem> coolDown;

  /// The coach's explanation of the plan.
  final String rationale;

  List<PlanItem> get all => [...warmUp, ...main, ...coolDown];

  /// Routine day name, or the mode label.
  String get title => request.title ?? request.mode.label;

  /// Same plan with [main] replaced (used when loads are annotated).
  WorkoutPlan withMain(List<PlanItem> items) => WorkoutPlan(
    request: request,
    warmUp: warmUp,
    main: items,
    coolDown: coolDown,
    rationale: rationale,
  );

  List<PlanItem> items(PlanPhase phase) => switch (phase) {
    PlanPhase.warmUp => warmUp,
    PlanPhase.main => main,
    PlanPhase.coolDown => coolDown,
  };

  /// Includes a transition between items.
  Duration get estimatedTotal => Duration(
    seconds:
        all.fold<int>(0, (s, i) => s + i.estimated.inSeconds) +
        (all.length - 1).clamp(0, 999) * 20,
  );

  Set<MuscleGroup> get musclesCovered => {
    for (final i in main) ...i.movement.primary,
  };

  Set<Equipment> get equipmentNeeded => {for (final i in all) ...i.equipment};

  WorkoutPlan replace(PlanItem old, PlanItem replacement) => WorkoutPlan(
    request: request,
    warmUp: [for (final i in warmUp) identical(i, old) ? replacement : i],
    main: [for (final i in main) identical(i, old) ? replacement : i],
    coolDown: [for (final i in coolDown) identical(i, old) ? replacement : i],
    rationale: rationale,
  );
}
