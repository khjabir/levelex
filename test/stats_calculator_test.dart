import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/date_utils.dart';
import 'package:levelex/core/utils/stats_calculator.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/workout_session.dart';

WorkoutSession session(
  DateTime at, {
  int reps = 10,
  int target = 10,
  SessionStatus? status,
}) {
  return WorkoutSession(
    id: at.toIso8601String(),
    startTime: at,
    endTime: at.add(const Duration(minutes: 1)),
    targetReps: target,
    completedReps: reps,
    status:
        status ??
        (reps >= target ? SessionStatus.completed : SessionStatus.incomplete),
  );
}

WorkoutSession skipped(DateTime at) => WorkoutSession(
  id: 'skip-${at.toIso8601String()}',
  startTime: at,
  targetReps: 10,
  completedReps: 0,
  status: SessionStatus.skipped,
);

void main() {
  final today = DateTime(2026, 3, 10, 15, 30);

  group('StatsCalculator.statsForDay', () {
    test('sums reps and counts completed, skipped and attempted sessions', () {
      final sessions = [
        session(DateTime(2026, 3, 10, 9)),
        session(DateTime(2026, 3, 10, 10), reps: 12),
        session(DateTime(2026, 3, 10, 11), reps: 4), // incomplete
        skipped(DateTime(2026, 3, 10, 12)),
        session(DateTime(2026, 3, 9, 9)), // other day
      ];
      final stats = StatsCalculator.statsForDay(sessions, today);
      expect(stats.date, DateTime(2026, 3, 10));
      expect(stats.totalPushUps, 26);
      expect(stats.completedSessions, 2);
      expect(stats.attemptedSessions, 3);
      expect(stats.skippedSessions, 1);
      expect(stats.isCompletedDay, isTrue);
    });

    test('timed holds count as sessions but not as reps', () {
      final sessions = [
        session(DateTime(2026, 3, 10, 9), reps: 12),
        WorkoutSession(
          id: 'plank',
          startTime: DateTime(2026, 3, 10, 10),
          endTime: DateTime(2026, 3, 10, 10, 1),
          targetReps: 30,
          completedReps: 30,
          status: SessionStatus.completed,
          exercise: ExerciseType.plank,
        ),
      ];
      final stats = StatsCalculator.statsForDay(sessions, today);
      expect(stats.totalPushUps, 12);
      expect(stats.completedSessions, 2);
      expect(stats.attemptedSessions, 2);
    });

    test('skipped sessions can be excluded', () {
      final sessions = [skipped(DateTime(2026, 3, 10, 12))];
      final stats = StatsCalculator.statsForDay(
        sessions,
        today,
        includeSkipped: false,
      );
      expect(stats.skippedSessions, 0);
    });

    test('empty day yields zeros', () {
      final stats = StatsCalculator.statsForDay(const [], today);
      expect(stats.totalPushUps, 0);
      expect(stats.isCompletedDay, isFalse);
    });

    test('sessions right before and after midnight land on different days', () {
      final sessions = [
        session(DateTime(2026, 3, 9, 23, 59, 59)),
        session(DateTime(2026, 3, 10, 0, 0, 1)),
      ];
      final byDay = StatsCalculator.statsByDay(sessions);
      expect(byDay.length, 2);
      expect(byDay[DateTime(2026, 3, 9)]!.totalPushUps, 10);
      expect(byDay[DateTime(2026, 3, 10)]!.totalPushUps, 10);
    });
  });

  group('StatsCalculator.currentStreak', () {
    test('zero when nothing completed', () {
      expect(StatsCalculator.currentStreak(const [], today), 0);
    });

    test('counts consecutive days ending today', () {
      final sessions = [
        session(DateTime(2026, 3, 7, 9)),
        session(DateTime(2026, 3, 8, 9)),
        session(DateTime(2026, 3, 9, 9)),
        session(DateTime(2026, 3, 10, 9)),
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 4);
    });

    test('carries over from yesterday when today is not done yet', () {
      final sessions = [
        session(DateTime(2026, 3, 8, 9)),
        session(DateTime(2026, 3, 9, 9)),
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 2);
    });

    test('breaks when yesterday and today are both missing', () {
      final sessions = [
        session(DateTime(2026, 3, 7, 9)),
        session(DateTime(2026, 3, 8, 9)),
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 0);
    });

    test('multiple workouts on one day count as a single streak day', () {
      final sessions = [
        session(DateTime(2026, 3, 10, 9)),
        session(DateTime(2026, 3, 10, 10)),
        session(DateTime(2026, 3, 10, 11)),
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 1);
    });

    test('incomplete and skipped sessions do not extend the streak', () {
      final sessions = [
        session(DateTime(2026, 3, 9, 9), reps: 3),
        skipped(DateTime(2026, 3, 9, 10)),
        session(DateTime(2026, 3, 10, 9)),
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 1);
    });

    test('a gap breaks the streak', () {
      final sessions = [
        session(DateTime(2026, 3, 6, 9)),
        session(DateTime(2026, 3, 7, 9)),
        // 8th missing
        session(DateTime(2026, 3, 9, 9)),
        session(DateTime(2026, 3, 10, 9)),
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 2);
    });

    test('handles month and year boundaries', () {
      final sessions = [
        session(DateTime(2025, 12, 30, 9)),
        session(DateTime(2025, 12, 31, 9)),
        session(DateTime(2026, 1, 1, 9)),
      ];
      expect(
        StatsCalculator.currentStreak(sessions, DateTime(2026, 1, 1, 20)),
        3,
      );
      expect(
        StatsCalculator.currentStreak(sessions, DateTime(2026, 1, 2, 8)),
        3,
      );
      expect(
        StatsCalculator.currentStreak(sessions, DateTime(2026, 1, 3, 8)),
        0,
      );
    });

    test('a session at 23:59 followed by one at 00:01 spans two days', () {
      final sessions = [
        session(DateTime(2026, 3, 9, 23, 59)),
        session(DateTime(2026, 3, 10, 0, 1)),
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 2);
    });
  });

  group('StatsCalculator.longestStreak', () {
    test('finds the longest run anywhere in history', () {
      final sessions = [
        session(DateTime(2026, 1, 1, 9)),
        session(DateTime(2026, 1, 2, 9)),
        session(DateTime(2026, 1, 3, 9)),
        session(DateTime(2026, 2, 1, 9)),
        session(DateTime(2026, 2, 2, 9)),
      ];
      expect(StatsCalculator.longestStreak(sessions), 3);
    });
  });

  group('AppDateUtils', () {
    test('daysBetween ignores time of day', () {
      expect(
        AppDateUtils.daysBetween(
          DateTime(2026, 3, 9, 23, 59),
          DateTime(2026, 3, 10, 0, 1),
        ),
        1,
      );
    });

    test('addDays crosses month boundaries', () {
      expect(
        AppDateUtils.addDays(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 1),
      );
      expect(
        AppDateUtils.addDays(DateTime(2026, 3, 1), -1),
        DateTime(2026, 2, 28),
      );
    });

    test('dayKey round-trips', () {
      final day = DateTime(2026, 7, 4);
      expect(AppDateUtils.parseDayKey(AppDateUtils.dayKey(day)), day);
      expect(AppDateUtils.dayKey(day), '2026-07-04');
    });
  });
}
