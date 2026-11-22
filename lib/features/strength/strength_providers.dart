import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../models/user_settings.dart';
import '../pt/models/workout_plan.dart';
import '../pt/pt_providers.dart';
import 'data/strength_repository.dart';
import 'logic/plan_advisor.dart';
import 'logic/routine_schedule.dart';
import 'models/lift_log.dart';
import 'models/progression_rule.dart';
import 'models/routine.dart';

/// Overridden at startup with the opened Hive repository.
final strengthRepositoryProvider = Provider<StrengthRepository>(
  (ref) => InMemoryStrengthRepository(),
);

/// The unit loads are shown in.
final weightUnitProvider = Provider<WeightUnit>(
  (ref) => ref.watch(settingsProvider.select((s) => s.weightUnit)),
);

// -----------------------------------------------------------------------------
// Lift log
// -----------------------------------------------------------------------------

class LiftLogNotifier extends Notifier<List<LiftEntry>> {
  @override
  List<LiftEntry> build() => ref.watch(strengthRepositoryProvider).lifts();

  StrengthRepository get _repo => ref.read(strengthRepositoryProvider);

  Future<void> add(LiftEntry entry) async {
    await _repo.upsertLift(entry);
    state = _repo.lifts();
  }

  Future<void> addAll(Iterable<LiftEntry> entries) async {
    if (entries.isEmpty) return;
    await _repo.upsertLifts(entries);
    state = _repo.lifts();
  }

  Future<void> remove(String id) async {
    await _repo.deleteLift(id);
    state = _repo.lifts();
  }

  /// Entries for one movement, oldest first.
  List<LiftEntry> forMovement(String movementId) => [
    for (final e in state)
      if (e.movementId == movementId) e,
  ];
}

final liftLogProvider = NotifierProvider<LiftLogNotifier, List<LiftEntry>>(
  LiftLogNotifier.new,
);

/// Lift history of one movement, oldest first.
final movementHistoryProvider = Provider.family<List<LiftEntry>, String>(
  (ref, movementId) => [
    for (final e in ref.watch(liftLogProvider))
      if (e.movementId == movementId) e,
  ],
);

// -----------------------------------------------------------------------------
// Body weight, goal and photos
// -----------------------------------------------------------------------------

class BodyWeightNotifier extends Notifier<List<BodyWeightEntry>> {
  @override
  List<BodyWeightEntry> build() =>
      ref.watch(strengthRepositoryProvider).bodyWeights();

  StrengthRepository get _repo => ref.read(strengthRepositoryProvider);

  Future<void> log(double kg, {DateTime? day, String? note}) async {
    final d = day ?? DateTime.now();
    await _repo.upsertBodyWeight(
      BodyWeightEntry(
        date: DateTime(d.year, d.month, d.day),
        kg: kg,
        note: note,
      ),
    );
    state = _repo.bodyWeights();
  }

  Future<void> addAll(Iterable<BodyWeightEntry> entries) async {
    for (final e in entries) {
      await _repo.upsertBodyWeight(e);
    }
    state = _repo.bodyWeights();
  }

  Future<void> remove(DateTime day) async {
    await _repo.deleteBodyWeight(day);
    state = _repo.bodyWeights();
  }
}

final bodyWeightProvider =
    NotifierProvider<BodyWeightNotifier, List<BodyWeightEntry>>(
      BodyWeightNotifier.new,
    );

class BodyGoalNotifier extends Notifier<double?> {
  @override
  double? build() => ref.watch(strengthRepositoryProvider).goalKg;

  Future<void> set(double? kg) async {
    await ref.read(strengthRepositoryProvider).setGoalKg(kg);
    state = kg;
  }
}

final bodyGoalProvider = NotifierProvider<BodyGoalNotifier, double?>(
  BodyGoalNotifier.new,
);

class ProgressPhotosNotifier extends Notifier<List<ProgressPhoto>> {
  @override
  List<ProgressPhoto> build() => ref.watch(strengthRepositoryProvider).photos();

  StrengthRepository get _repo => ref.read(strengthRepositoryProvider);

  Future<void> add(ProgressPhoto photo) async {
    await _repo.upsertPhoto(photo);
    state = _repo.photos();
  }

  Future<void> remove(String id) async {
    await _repo.deletePhoto(id);
    state = _repo.photos();
  }
}

final progressPhotosProvider =
    NotifierProvider<ProgressPhotosNotifier, List<ProgressPhoto>>(
      ProgressPhotosNotifier.new,
    );

// -----------------------------------------------------------------------------
// Routines
// -----------------------------------------------------------------------------

class RoutinesNotifier extends Notifier<List<Routine>> {
  @override
  List<Routine> build() => ref.watch(strengthRepositoryProvider).routines();

  StrengthRepository get _repo => ref.read(strengthRepositoryProvider);

  Future<void> save(Routine routine, {bool activate = false}) async {
    await _repo.upsertRoutine(routine);
    state = _repo.routines();
    if (activate) {
      await ref.read(activeRoutineIdProvider.notifier).set(routine.id);
    }
  }

  Future<void> addAll(Iterable<Routine> routines) async {
    for (final r in routines) {
      await _repo.upsertRoutine(r);
    }
    state = _repo.routines();
  }

  Future<void> remove(String id) async {
    await _repo.deleteRoutine(id);
    state = _repo.routines();
    ref.invalidate(activeRoutineIdProvider);
  }

  Routine? byId(String? id) {
    for (final r in state) {
      if (r.id == id) return r;
    }
    return null;
  }
}

final routinesProvider = NotifierProvider<RoutinesNotifier, List<Routine>>(
  RoutinesNotifier.new,
);

class ActiveRoutineIdNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(strengthRepositoryProvider).activeRoutineId;

  Future<void> set(String? id) async {
    await ref.read(strengthRepositoryProvider).setActiveRoutineId(id);
    state = id;
  }
}

final activeRoutineIdProvider =
    NotifierProvider<ActiveRoutineIdNotifier, String?>(
      ActiveRoutineIdNotifier.new,
    );

/// Routine runs derived from MY PT records, for the scheduler.
final routineRunsProvider = Provider<List<RoutineRun>>(
  (ref) => [
    for (final r in ref.watch(ptRecordsProvider))
      // A session ended before any work does not use up the routine day.
      if (r.routineId != null &&
          r.routineDayId != null &&
          r.items.any((i) => !i.skipped && i.setsDone > 0))
        (routineId: r.routineId!, dayId: r.routineDayId!, at: r.startTime),
  ],
);

/// Today's day of the active routine (null on a rest day or with no
/// routine).
final todayRoutineDayProvider = Provider<RoutineDay?>((ref) {
  final routine = ref.watch(activeRoutineProvider);
  if (routine == null) return null;
  return RoutineScheduler.dayFor(
    routine,
    // The app clock (refreshed on resume and at midnight), so the day
    // changes overnight instead of showing yesterday's routine day.
    ref.watch(clockProvider),
    ref.watch(routineRunsProvider),
  );
});

/// The routine the home screen follows, if any.
final activeRoutineProvider = Provider<Routine?>((ref) {
  final id = ref.watch(activeRoutineIdProvider);
  if (id == null) return null;
  for (final r in ref.watch(routinesProvider)) {
    if (r.id == id) return r;
  }
  return null;
});

// -----------------------------------------------------------------------------
// Progression rules
// -----------------------------------------------------------------------------

class ProgressionRulesNotifier extends Notifier<Map<String, ProgressionRule>> {
  @override
  Map<String, ProgressionRule> build() =>
      ref.watch(strengthRepositoryProvider).rules();

  Future<void> set(String movementId, ProgressionRule? rule) async {
    await ref.read(strengthRepositoryProvider).saveRule(movementId, rule);
    state = ref.read(strengthRepositoryProvider).rules();
  }

  Future<void> replaceAll(Map<String, ProgressionRule> rules) async {
    final repo = ref.read(strengthRepositoryProvider);
    for (final e in rules.entries) {
      await repo.saveRule(e.key, e.value);
    }
    state = repo.rules();
  }
}

final progressionRulesProvider =
    NotifierProvider<ProgressionRulesNotifier, Map<String, ProgressionRule>>(
      ProgressionRulesNotifier.new,
    );

// -----------------------------------------------------------------------------
// MY PT plan with loads
// -----------------------------------------------------------------------------

/// The current MY PT plan with suggested loads and rep targets written on
/// by each exercise's progression rule.
final annotatedPlanProvider = Provider<WorkoutPlan?>((ref) {
  final plan = ref.watch(ptPlanProvider);
  if (plan == null) return null;
  return PlanAdvisor.annotate(
    plan,
    lifts: ref.watch(liftLogProvider),
    rules: ref.watch(progressionRulesProvider),
  );
});
