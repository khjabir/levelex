import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/muscle_group.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/strength/logic/recovery.dart';
import 'package:levelex/features/strength/models/lift_log.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/workout_session.dart';

final t0 = DateTime(2026, 10, 12, 18);

LiftEntry lift(String movementId, int sets, {DateTime? at, int warmUps = 0}) =>
    LiftEntry(
      id: '$movementId-${at ?? t0}',
      movementId: movementId,
      startTime: at ?? t0,
      sets: [
        for (var i = 0; i < warmUps; i++)
          const LiftSet(weightKg: 20, reps: 5, warmUp: true),
        for (var i = 0; i < sets; i++) const LiftSet(weightKg: 60, reps: 8),
      ],
    );

Map<MuscleGroup, MuscleStatus> compute({
  Iterable<LiftEntry> lifts = const [],
  Iterable<PtRecord> ptRecords = const [],
  Iterable<WorkoutSession> sessions = const [],
  DateTime? now,
}) => MuscleRecovery.compute(
  lifts: lifts,
  ptRecords: ptRecords,
  sessions: sessions,
  now: now ?? t0,
);

void main() {
  test('nothing logged: everything fresh and the map is complete', () {
    final statuses = compute();
    expect(statuses.length, MuscleGroup.values.length);
    for (final s in statuses.values) {
      expect(s.state, MuscleState.fresh);
      expect(s.fatigue, 0);
      expect(s.lastTrained, isNull);
    }
    expect(MuscleRecovery.exerciseMuscles.length, ExerciseType.values.length);
  });

  test('a hard chest session is worked, then recovering, then fresh', () {
    // 5 work sets of bench: chest stimulus 5/8 = 0.625.
    final lifts = [lift('bb_bench_press', 5, warmUps: 2)];

    final now0 = compute(lifts: lifts)[MuscleGroup.chest]!;
    expect(now0.state, MuscleState.trained);
    expect(now0.fatigue, closeTo(0.625, 1e-9));
    expect(now0.lastTrained, t0);
    expect(now0.hardSets7d, 5);

    // One chest half-life (30 h) later: 0.3125.
    final later = compute(
      lifts: lifts,
      now: t0.add(const Duration(hours: 30)),
    )[MuscleGroup.chest]!;
    expect(later.state, MuscleState.recovering);
    expect(later.fatigue, closeTo(0.3125, 1e-9));

    // Two half-lives: 0.156 → fresh, but lastTrained is remembered.
    final fresh = compute(
      lifts: lifts,
      now: t0.add(const Duration(hours: 60)),
    )[MuscleGroup.chest]!;
    expect(fresh.state, MuscleState.fresh);
    expect(fresh.lastTrained, t0);

    // Beyond 30 days nothing counts, lastTrained still remembered.
    final old = compute(
      lifts: lifts,
      now: t0.add(const Duration(days: 31)),
    )[MuscleGroup.chest]!;
    expect(old.fatigue, 0);
    expect(old.hardSets7d, 0);
    expect(old.lastTrained, t0);
  });

  test('secondary muscles get 0.4 of the sets', () {
    final statuses = compute(lifts: [lift('bb_bench_press', 5)]);
    // Bench: secondary triceps and shoulders → 2 weighted sets → 0.25.
    expect(statuses[MuscleGroup.triceps]!.fatigue, closeTo(0.25, 1e-9));
    expect(statuses[MuscleGroup.triceps]!.state, MuscleState.recovering);
    expect(statuses[MuscleGroup.triceps]!.hardSets7d, closeTo(2, 1e-9));
    expect(statuses[MuscleGroup.back]!.fatigue, 0);
  });

  test('legs decay more slowly than arms', () {
    final lifts = [lift('bb_back_squat', 4), lift('db_curl', 4)];
    final later = compute(lifts: lifts, now: t0.add(const Duration(hours: 24)));
    // 24 h: biceps (24 h half-life) halves, quads (48 h) only to 0.707.
    expect(later[MuscleGroup.biceps]!.fatigue, closeTo(0.25, 1e-9));
    expect(later[MuscleGroup.quads]!.fatigue, closeTo(0.5 * 0.70710678, 1e-6));
  });

  test('sets are capped at 12 per muscle per occasion', () {
    final statuses = compute(lifts: [lift('db_curl', 30)]);
    expect(statuses[MuscleGroup.biceps]!.fatigue, closeTo(12 / 8, 1e-9));
    expect(statuses[MuscleGroup.biceps]!.hardSets7d, 12);
  });

  test('PT records count setsDone of main-phase items only', () {
    PtItemResult item(
      String id,
      PlanPhase phase, {
      int sets = 3,
      bool skipped = false,
    }) => PtItemResult(
      movementId: id,
      phase: phase,
      setsPlanned: sets,
      setsDone: skipped ? 0 : sets,
      reps: 30,
      seconds: 0,
      skipped: skipped,
    );
    final record = PtRecord(
      id: 'p1',
      startTime: t0,
      endTime: t0.add(const Duration(minutes: 30)),
      mode: WorkoutMode.pull,
      plannedMinutes: 30,
      items: [
        item('inchworm', PlanPhase.warmUp),
        item('superman', PlanPhase.main, sets: 4),
        item('pull_up', PlanPhase.main, skipped: true),
        item('childs_pose', PlanPhase.coolDown),
      ],
      verified: true,
    );
    final statuses = compute(ptRecords: [record]);
    // Superman only: 4 sets on back, 0.4 × 4 on glutes.
    expect(statuses[MuscleGroup.back]!.fatigue, closeTo(0.5, 1e-9));
    expect(statuses[MuscleGroup.back]!.state, MuscleState.recovering);
    expect(statuses[MuscleGroup.glutes]!.fatigue, closeTo(0.2, 1e-9));
    expect(statuses[MuscleGroup.biceps]!.fatigue, 0);
    expect(statuses[MuscleGroup.hamstrings]!.fatigue, 0);
    expect(statuses[MuscleGroup.shoulders]!.fatigue, 0);
  });

  test('camera sets count one hard set per 10 reps, at least one', () {
    WorkoutSession session(ExerciseType type, int reps) => WorkoutSession(
      id: '${type.id}-$reps',
      startTime: t0,
      targetReps: 10,
      completedReps: reps,
      status: SessionStatus.completed,
      exercise: type,
    );
    final statuses = compute(
      sessions: [
        session(ExerciseType.pushUp, 40),
        session(ExerciseType.sitUp, 3),
        session(ExerciseType.wallSit, 0),
      ],
    );
    expect(statuses[MuscleGroup.chest]!.fatigue, closeTo(0.5, 1e-9));
    expect(statuses[MuscleGroup.core]!.fatigue, closeTo(0.2 + 0.125, 1e-9));
    expect(statuses[MuscleGroup.quads]!.fatigue, 0);
    expect(statuses[MuscleGroup.quads]!.lastTrained, isNull);
  });

  test('cardio and mobility are never trained', () {
    final session = WorkoutSession(
      id: 'jj',
      startTime: t0,
      targetReps: 20,
      completedReps: 200,
      status: SessionStatus.completed,
      exercise: ExerciseType.jumpingJack,
    );
    final statuses = compute(
      sessions: [session],
      lifts: [lift('jump_rope', 6), lift('cat_cow', 3)],
    );
    for (final m in [MuscleGroup.cardio, MuscleGroup.mobility]) {
      expect(statuses[m]!.state, MuscleState.fresh);
      expect(statuses[m]!.fatigue, 0);
      expect(statuses[m]!.lastTrained, isNull);
    }
    // The jumping jacks still touch the calves as a secondary muscle.
    expect(statuses[MuscleGroup.calves]!.fatigue, greaterThan(0));
  });

  test('occasions add up', () {
    final lifts = [
      lift('bb_bench_press', 3, at: t0.subtract(const Duration(hours: 30))),
      lift('db_floor_press', 3, at: t0),
    ];
    final chest = compute(lifts: lifts)[MuscleGroup.chest]!;
    expect(chest.fatigue, closeTo(3 / 8 / 2 + 3 / 8, 1e-9));
    expect(chest.state, MuscleState.trained);
    expect(chest.lastTrained, t0);
    expect(chest.hardSets7d, 6);
  });

  test('suggestNext lists fresh muscles, never trained first', () {
    final lifts = [
      lift('db_curl', 1, at: t0.subtract(const Duration(days: 10))),
      lift('calf_raise', 1, at: t0.subtract(const Duration(days: 5))),
      lift('bb_bench_press', 6, at: t0),
    ];
    final statuses = compute(lifts: lifts);
    final next = MuscleRecovery.suggestNext(statuses);

    expect(next, isNot(contains(MuscleGroup.chest)));
    expect(next, isNot(contains(MuscleGroup.cardio)));
    expect(next, isNot(contains(MuscleGroup.mobility)));

    final neverTrained = next.takeWhile(
      (m) => statuses[m]!.lastTrained == null,
    );
    expect(
      neverTrained,
      containsAll([MuscleGroup.back, MuscleGroup.quads, MuscleGroup.core]),
    );
    expect(
      next.indexOf(MuscleGroup.back),
      lessThan(next.indexOf(MuscleGroup.biceps)),
    );
    expect(
      next.indexOf(MuscleGroup.biceps),
      lessThan(next.indexOf(MuscleGroup.calves)),
    );
    expect(next.last, MuscleGroup.calves);
  });
}
