import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/stats_calculator.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/strength/models/lift_log.dart';
import 'package:levelex/features/strength/screens/progress_screen.dart';
import 'package:levelex/models/workout_session.dart';

/// A MY PT session with one item; [sets], [reps] and [seconds] of work done.
PtRecord pt(
  DateTime at, {
  int sets = 0,
  int reps = 0,
  int seconds = 0,
  bool skipped = false,
  bool verified = false,
}) => PtRecord(
  id: 'pt-${at.toIso8601String()}',
  startTime: at,
  endTime: at.add(const Duration(minutes: 5)),
  mode: WorkoutMode.fullBody,
  plannedMinutes: 20,
  items: [
    PtItemResult(
      movementId: 'push_up',
      phase: PlanPhase.main,
      setsPlanned: 3,
      setsDone: sets,
      reps: reps,
      seconds: seconds,
      skipped: skipped,
    ),
  ],
  verified: verified,
  plannedItems: 6,
);

void main() {
  final day = DateTime(2026, 11, 22, 14);

  group('PtRecord.hasWork', () {
    test('a session ended before any work has none', () {
      expect(pt(day).hasWork, isFalse);
      expect(pt(day, skipped: true).hasWork, isFalse);
    });

    test('a finished set, reps or seconds count as work', () {
      expect(pt(day, sets: 1).hasWork, isTrue);
      expect(pt(day, reps: 4).hasWork, isTrue);
      expect(pt(day, seconds: 30).hasWork, isTrue);
    });

    test('unverified work is still work', () {
      expect(pt(day, sets: 2, reps: 20).hasWork, isTrue);
      expect(pt(day, sets: 2, reps: 20).isAttempted, isFalse);
    });
  });

  group('Progress heatmap', () {
    test('an empty MY PT session does not light up the day', () {
      final activity = activityByDay(
        sessions: const [],
        ptRecords: [pt(day)],
        lifts: const [],
      );
      expect(activity, isEmpty);
    });

    test('counts sets, MY PT work and hand-logged lifts once each', () {
      final activity = activityByDay(
        sessions: [
          WorkoutSession(
            id: 's1',
            startTime: day,
            targetReps: 10,
            completedReps: 10,
            status: SessionStatus.completed,
          ),
        ],
        ptRecords: [pt(day, sets: 1, reps: 10), pt(day)],
        lifts: [
          LiftEntry(
            id: 'l1',
            movementId: 'bb_bench_press',
            startTime: day,
            sets: const [LiftSet(weightKg: 60, reps: 8)],
          ),
          // MY PT's own copy is already counted through the session.
          LiftEntry(
            id: 'l2',
            movementId: 'bb_bench_press',
            startTime: day,
            sets: const [LiftSet(weightKg: 60, reps: 8)],
            source: LiftSource.pt,
          ),
        ],
      );
      expect(activity, {DateTime(2026, 11, 22): 3});
    });
  });

  test('History calendar ignores an empty MY PT session', () {
    final stats = StatsCalculator.statsByDay(
      const [],
      ptRecords: [pt(day), pt(day.add(const Duration(hours: 1)), sets: 1)],
    )[DateTime(2026, 11, 22)]!;
    expect(stats.ptSessions, 1);
  });
}
