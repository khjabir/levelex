import '../../pt/models/equipment.dart';
import '../../pt/models/movement.dart';
import '../../pt/models/movement_library.dart';
import '../../pt/models/muscle_group.dart';
import '../../pt/models/workout_plan.dart';
import '../models/progression_rule.dart';
import '../models/routine.dart';

/// One exercise slot in a starter template.
class StarterSlot {
  const StarterSlot(
    this.movementId,
    this.sets,
    this.reps, {
    this.range = true,
    this.seconds,
    this.policy,
  });

  final String movementId;
  final int sets;

  /// Top of the rep range (the only target when [range] is false).
  final int reps;

  /// Hypertrophy slots work up through `reps - 2 … reps` (never below 5).
  final bool range;

  /// Timed holds: seconds per set. Falls back to the movement's base time.
  final int? seconds;
  final ProgressionPolicy? policy;

  /// The routine exercise for [movement], which may be a substitute.
  RoutineExercise toExercise(Movement movement) => RoutineExercise(
    movementId: movement.id,
    sets: sets,
    repsMin: range ? (reps - 2).clamp(5, reps) : reps,
    repsMax: reps,
    seconds: movement.isTimed ? (seconds ?? movement.baseSeconds) : null,
    policy: policy,
  );
}

/// One training day in a starter template.
class StarterDay {
  const StarterDay({
    required this.name,
    required this.mode,
    required this.slots,
    this.minutes = 50,
    this.weekday,
  });

  final String name;
  final WorkoutMode mode;
  final int minutes;

  /// `DateTime.monday` … `DateTime.sunday`; null on rotation plans.
  final int? weekday;
  final List<StarterSlot> slots;
}

/// A ready-made programme that builds a [Routine] fitted to the user's
/// equipment: any movement that cannot be done is swapped for the closest
/// one that can, or dropped.
class StarterPlan {
  const StarterPlan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.daysPerWeek,
    required this.days,
    this.schedule = RoutineSchedule.weekdays,
  });

  final String id;
  final String name;
  final String tagline;
  final String description;
  final int daysPerWeek;
  final RoutineSchedule schedule;
  final List<StarterDay> days;

  /// Builds the routine for [available] equipment. Ids come from [newId]
  /// when given (called once for the routine, then once per day), else from
  /// the clock.
  Routine build(Set<Equipment> available, {String Function()? newId}) {
    final createdAt = DateTime.now();
    var counter = 0;
    String nextId() => newId != null
        ? newId()
        : '${id}_${createdAt.microsecondsSinceEpoch}_${counter++}';

    final routineId = nextId();
    final built = <RoutineDay>[];
    final weekdays = <int, String>{};
    for (final day in days) {
      final exercises = fitDay(day, available);
      if (exercises.isEmpty) continue;
      final dayId = nextId();
      built.add(
        RoutineDay(
          id: dayId,
          name: day.name,
          mode: day.mode,
          minutes: day.minutes,
          exercises: exercises,
        ),
      );
      final weekday = day.weekday;
      if (schedule == RoutineSchedule.weekdays && weekday != null) {
        weekdays[weekday] = dayId;
      }
    }
    return Routine(
      id: routineId,
      name: name,
      description: description,
      days: built,
      schedule: schedule,
      weekdays: weekdays,
      starterId: id,
      createdAt: createdAt,
    );
  }

  /// The exercises of [day] that can be done with [available], substitutes
  /// included. Empty when nothing fits.
  static List<RoutineExercise> fitDay(
    StarterDay day,
    Set<Equipment> available,
  ) {
    // Reserve every original that fits so a substitute never takes a
    // movement a later slot on the same day already uses.
    final used = <String>{
      for (final slot in day.slots)
        if (MovementLibrary.byId(slot.movementId)?.canDoWith(available) ??
            false)
          slot.movementId,
    };
    final out = <RoutineExercise>[];
    for (final slot in day.slots) {
      final original = MovementLibrary.byId(slot.movementId);
      if (original == null) continue;
      Movement? chosen;
      if (original.canDoWith(available)) {
        chosen = original;
      } else {
        chosen = substituteFor(original, available, exclude: used);
        if (chosen != null) used.add(chosen.id);
      }
      if (chosen == null) continue;
      out.add(slot.toExercise(chosen));
    }
    return out;
  }

  /// The closest doable stand-in for [original]: largest primary-muscle
  /// overlap, then loaded for loaded, compound for compound, then id. Only
  /// main-phase movements qualify, never one in [exclude], and never a
  /// conditioning movement unless the original was one.
  static Movement? substituteFor(
    Movement original,
    Set<Equipment> available, {
    Set<String> exclude = const {},
  }) {
    final wantsCardio = original.primary.contains(MuscleGroup.cardio);
    final candidates = <(Movement, int)>[];
    for (final m in MovementLibrary.all) {
      if (m.id == original.id || exclude.contains(m.id)) continue;
      if (!m.phases.contains(PlanPhase.main)) continue;
      if (!m.canDoWith(available)) continue;
      if (!wantsCardio && m.primary.contains(MuscleGroup.cardio)) continue;
      final overlap = m.primary.intersection(original.primary).length;
      if (overlap == 0) continue;
      candidates.add((m, overlap));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byOverlap = b.$2.compareTo(a.$2);
      if (byOverlap != 0) return byOverlap;
      final loadedA = a.$1.bodyweight == original.bodyweight ? 1 : 0;
      final loadedB = b.$1.bodyweight == original.bodyweight ? 1 : 0;
      if (loadedA != loadedB) return loadedB.compareTo(loadedA);
      final compoundA = a.$1.compound == original.compound ? 1 : 0;
      final compoundB = b.$1.compound == original.compound ? 1 : 0;
      if (compoundA != compoundB) return compoundB.compareTo(compoundA);
      return a.$1.id.compareTo(b.$1.id);
    });
    return candidates.first.$1;
  }
}

/// The built-in starter programmes.
abstract final class StarterPlans {
  static const ppl = StarterPlan(
    id: 'ppl',
    name: 'Push / Pull / Legs',
    tagline: 'Three days, each muscle once a week with plenty of volume.',
    description:
        'Monday push, Wednesday pull, Friday legs. The classic split for '
        'building muscle on three gym days.',
    daysPerWeek: 3,
    days: [
      StarterDay(
        name: 'Push',
        mode: WorkoutMode.push,
        minutes: 55,
        weekday: DateTime.monday,
        slots: [
          StarterSlot('bb_bench_press', 4, 8),
          StarterSlot('db_shoulder_press', 3, 10),
          StarterSlot('db_floor_press', 3, 10),
          StarterSlot('db_lateral_raise', 3, 12),
          StarterSlot('cable_pushdown', 3, 12),
          StarterSlot('push_up', 3, 12),
        ],
      ),
      StarterDay(
        name: 'Pull',
        mode: WorkoutMode.pull,
        minutes: 50,
        weekday: DateTime.wednesday,
        slots: [
          StarterSlot('pull_up', 4, 8),
          StarterSlot('db_bent_row', 4, 8),
          StarterSlot('band_row', 3, 10),
          StarterSlot('db_curl', 3, 10),
          StarterSlot('band_pull_apart', 3, 15),
        ],
      ),
      StarterDay(
        name: 'Legs',
        mode: WorkoutMode.legs,
        minutes: 55,
        weekday: DateTime.friday,
        slots: [
          StarterSlot('bb_back_squat', 4, 8),
          StarterSlot('db_rdl', 3, 10),
          StarterSlot('db_lunge', 3, 12),
          StarterSlot('goblet_squat', 3, 12),
          StarterSlot('glute_bridge', 3, 15),
          StarterSlot('calf_raise', 4, 15),
        ],
      ),
    ],
  );

  static const upperLower = StarterPlan(
    id: 'upperLower',
    name: 'Upper / Lower',
    tagline: 'Four days, every muscle twice a week.',
    description:
        'Upper body Monday and Thursday, lower body Tuesday and Friday. '
        'Two different sessions for each half so nothing gets stale.',
    daysPerWeek: 4,
    days: [
      StarterDay(
        name: 'Upper A',
        mode: WorkoutMode.upper,
        weekday: DateTime.monday,
        slots: [
          StarterSlot('bb_bench_press', 3, 8),
          StarterSlot('db_bent_row', 3, 8),
          StarterSlot('db_shoulder_press', 3, 10),
          StarterSlot('db_curl', 2, 12),
          StarterSlot('cable_pushdown', 2, 12),
        ],
      ),
      StarterDay(
        name: 'Lower A',
        mode: WorkoutMode.lower,
        weekday: DateTime.tuesday,
        slots: [
          StarterSlot('bb_back_squat', 3, 8),
          StarterSlot('db_rdl', 3, 10),
          StarterSlot('db_lunge', 2, 12),
          StarterSlot('calf_raise', 3, 15),
        ],
      ),
      StarterDay(
        name: 'Upper B',
        mode: WorkoutMode.upper,
        weekday: DateTime.thursday,
        slots: [
          StarterSlot('pull_up', 3, 8),
          StarterSlot('db_floor_press', 3, 10),
          StarterSlot('band_row', 3, 10),
          StarterSlot('db_lateral_raise', 2, 12),
          StarterSlot('push_up', 2, 12),
        ],
      ),
      StarterDay(
        name: 'Lower B',
        mode: WorkoutMode.lower,
        weekday: DateTime.friday,
        slots: [
          StarterSlot('goblet_squat', 3, 12),
          StarterSlot('db_rdl', 3, 10),
          StarterSlot('glute_bridge', 2, 15),
          StarterSlot('db_lunge', 2, 12),
          StarterSlot('calf_raise', 3, 15),
        ],
      ),
    ],
  );

  static const fullBody = StarterPlan(
    id: 'fullBody',
    name: 'Full Body',
    tagline: 'Three days of squat, hinge, push, pull and core.',
    description:
        'Monday, Wednesday and Friday. Every session hits the whole body '
        'with one big movement per pattern. Ideal for beginners and busy '
        'weeks.',
    daysPerWeek: 3,
    days: [
      StarterDay(
        name: 'Full Body A',
        mode: WorkoutMode.fullBody,
        minutes: 45,
        weekday: DateTime.monday,
        slots: [
          StarterSlot('bb_back_squat', 3, 8),
          StarterSlot('bb_bench_press', 3, 8),
          StarterSlot('db_bent_row', 3, 10),
          StarterSlot('plank', 3, 12, seconds: 30),
        ],
      ),
      StarterDay(
        name: 'Full Body B',
        mode: WorkoutMode.fullBody,
        minutes: 45,
        weekday: DateTime.wednesday,
        slots: [
          StarterSlot('db_rdl', 3, 10),
          StarterSlot('db_shoulder_press', 3, 10),
          StarterSlot('pull_up', 3, 8),
          StarterSlot('glute_bridge', 3, 15),
          StarterSlot('sit_up', 3, 15),
        ],
      ),
      StarterDay(
        name: 'Full Body C',
        mode: WorkoutMode.fullBody,
        minutes: 45,
        weekday: DateTime.friday,
        slots: [
          StarterSlot('goblet_squat', 3, 12),
          StarterSlot('push_up', 3, 12),
          StarterSlot('band_row', 3, 12),
          StarterSlot('kb_swing', 3, 15),
          StarterSlot('bird_dog', 3, 12, seconds: 30),
        ],
      ),
    ],
  );

  static const fiveByFive = StarterPlan(
    id: 'fiveByFive',
    name: '5×5 Strength',
    tagline:
        'Two sessions in rotation, three times a week, add weight '
        'every time.',
    description:
        'Alternate A and B whenever you train (Monday, Wednesday, Friday '
        'works well). Five sets of five on the big barbell lifts with '
        'linear progression.',
    daysPerWeek: 3,
    schedule: RoutineSchedule.rotation,
    days: [
      StarterDay(
        name: 'Workout A',
        mode: WorkoutMode.fullBody,
        minutes: 60,
        slots: [
          StarterSlot(
            'bb_back_squat',
            5,
            5,
            range: false,
            policy: ProgressionPolicy.linear,
          ),
          StarterSlot(
            'bb_bench_press',
            5,
            5,
            range: false,
            policy: ProgressionPolicy.linear,
          ),
          StarterSlot(
            'db_bent_row',
            5,
            5,
            range: false,
            policy: ProgressionPolicy.linear,
          ),
        ],
      ),
      StarterDay(
        name: 'Workout B',
        mode: WorkoutMode.fullBody,
        minutes: 60,
        slots: [
          StarterSlot(
            'bb_back_squat',
            5,
            5,
            range: false,
            policy: ProgressionPolicy.linear,
          ),
          StarterSlot(
            'bb_overhead_press',
            5,
            5,
            range: false,
            policy: ProgressionPolicy.linear,
          ),
          StarterSlot(
            'bb_deadlift',
            5,
            5,
            range: false,
            policy: ProgressionPolicy.linear,
          ),
        ],
      ),
    ],
  );

  static const List<StarterPlan> all = [ppl, upperLower, fullBody, fiveByFive];

  static StarterPlan? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
