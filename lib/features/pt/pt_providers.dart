import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/streak_nudge.dart';
import 'data/pt_repository.dart';
import 'models/equipment.dart';
import 'models/pt_record.dart';
import 'models/workout_plan.dart';
import 'planner/workout_planner.dart';

/// Overridden at startup with the opened Hive repository.
final ptRepositoryProvider = Provider<PtRepository>(
  (ref) => InMemoryPtRepository(),
);

/// The user's equipment inventory.
class GymProfileNotifier extends Notifier<GymProfile> {
  @override
  GymProfile build() => ref.watch(ptRepositoryProvider).profile;

  Future<void> set(GymProfile profile) async {
    state = profile;
    await ref.read(ptRepositoryProvider).saveProfile(profile);
  }

  Future<void> toggle(Equipment type) => set(state.toggle(type));

  Future<void> update(EquipmentItem item) => set(state.update(item));

  Future<void> clear() => set(const GymProfile());
}

final gymProfileProvider = NotifierProvider<GymProfileNotifier, GymProfile>(
  GymProfileNotifier.new,
);

/// Completed MY PT sessions.
class PtRecordsNotifier extends Notifier<List<PtRecord>> {
  @override
  List<PtRecord> build() => ref.watch(ptRepositoryProvider).records();

  Future<void> add(PtRecord record) async {
    await ref.read(ptRepositoryProvider).upsertRecord(record);
    state = ref.read(ptRepositoryProvider).records();
    unawaited(ref.read(streakNudgeProvider).sync());
  }

  /// Saves many records (backup import) with one state refresh and one
  /// nudge sync, instead of re-reading everything per record.
  Future<void> addAll(Iterable<PtRecord> records) async {
    final repo = ref.read(ptRepositoryProvider);
    var any = false;
    for (final r in records) {
      await repo.upsertRecord(r);
      any = true;
    }
    if (!any) return;
    state = repo.records();
    unawaited(ref.read(streakNudgeProvider).sync());
  }

  Future<void> clear() async {
    await ref.read(ptRepositoryProvider).clearRecords();
    state = const [];
  }
}

final ptRecordsProvider = NotifierProvider<PtRecordsNotifier, List<PtRecord>>(
  PtRecordsNotifier.new,
);

/// What the user is asking for on the MY PT home screen.
class PtRequestNotifier extends Notifier<PtRequest> {
  @override
  PtRequest build() {
    // Read, not watch: watching would rebuild the request and wipe the
    // user's choices whenever they toggle equipment. BUILD passes the
    // current equipment in anyway.
    final equipment = ref.read(gymProfileProvider).available;
    final records = ref.read(ptRecordsProvider);
    final last = records.isEmpty ? null : records.last;
    return PtRequest(
      equipment: equipment,
      mode: last?.mode ?? WorkoutMode.fullBody,
      duration: Duration(minutes: last?.plannedMinutes ?? 30),
    );
  }

  void update(PtRequest Function(PtRequest) change) => state = change(state);
}

final ptRequestProvider = NotifierProvider<PtRequestNotifier, PtRequest>(
  PtRequestNotifier.new,
);

final workoutPlannerProvider = Provider<WorkoutPlanner>(
  (_) => const WorkoutPlanner(),
);

/// The plan currently being previewed or performed.
class PtPlanNotifier extends Notifier<WorkoutPlan?> {
  @override
  WorkoutPlan? build() => null;

  WorkoutPlan generate(PtRequest request) {
    final plan = ref.read(workoutPlannerProvider).build(request);
    state = plan;
    return plan;
  }

  void shuffle() {
    final current = state;
    if (current == null) return;
    final request = current.request.copyWith(seed: current.request.seed + 1);
    ref.read(ptRequestProvider.notifier).update((_) => request);
    state = ref.read(workoutPlannerProvider).build(request);
  }

  /// Replaces [item] with a different movement for the same muscles.
  ///
  /// Screens show the annotated plan (suggested loads), whose items are
  /// copies, so [item] is matched back to this plan's own item; matching by
  /// identity alone silently swapped nothing for every loaded movement.
  bool swap(PlanItem item) {
    final current = state;
    if (current == null) return false;
    final own = _ownItem(current, item);
    if (own == null) return false;
    final alt = ref
        .read(workoutPlannerProvider)
        .alternative(current, own, seed: DateTime.now().millisecond);
    if (alt == null) return false;
    state = current.replace(own, alt);
    return true;
  }

  static PlanItem? _ownItem(WorkoutPlan plan, PlanItem item) {
    for (final i in plan.all) {
      if (identical(i, item)) return i;
    }
    for (final i in plan.items(item.phase)) {
      if (i.movement.id == item.movement.id && i.sets == item.sets) return i;
    }
    for (final i in plan.items(item.phase)) {
      if (i.movement.id == item.movement.id) return i;
    }
    return null;
  }

  void set(WorkoutPlan plan) => state = plan;
}

final ptPlanProvider = NotifierProvider<PtPlanNotifier, WorkoutPlan?>(
  PtPlanNotifier.new,
);
