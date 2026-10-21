import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/date_utils.dart';
import 'package:levelex/core/utils/stats_calculator.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
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

PtRecord ptRecord(
  DateTime start, {
  Duration length = const Duration(minutes: 30),
  bool verified = true,
  bool finished = true,
}) => PtRecord(
  id: 'pt-${start.toIso8601String()}',
  startTime: start,
  endTime: start.add(length),
  mode: WorkoutMode.fullBody,
  plannedMinutes: length.inMinutes,
  items: [
    PtItemResult(
      movementId: 'push_up',
      phase: PlanPhase.main,
      setsPlanned: 3,
      setsDone: finished ? 3 : 1,
      reps: finished ? 30 : 10,
      seconds: 0,
      skipped: false,
    ),
  ],
  verified: verified,
  plannedItems: 1,
);

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

    test('unverified sets add reps but never complete a day', () {
      final verified = session(DateTime(2026, 3, 9, 9));
      final bypassed = WorkoutSession(
        id: 'bypass',
        startTime: DateTime(2026, 3, 10, 9),
        endTime: DateTime(2026, 3, 10, 9, 1),
        targetReps: 10,
        completedReps: 10,
        status: SessionStatus.completed,
        verified: false,
      );
      final stats = StatsCalculator.statsForDay([bypassed], today);
      expect(stats.totalPushUps, 10);
      expect(stats.completedSessions, 0);
      expect(stats.attemptedSessions, 1);
      expect(stats.isCompletedDay, isFalse);
      expect(StatsCalculator.currentStreak([verified, bypassed], today), 1);
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

  group('MY PT and streaks', () {
    test('a finished, verified PT session keeps the streak alive', () {
      final sessions = [
        session(DateTime(2026, 3, 8, 9)),
        session(DateTime(2026, 3, 10, 9)),
      ];
      final pt = [ptRecord(DateTime(2026, 3, 9, 18))];
      expect(StatsCalculator.currentStreak(sessions, today), 1);
      expect(StatsCalculator.currentStreak(sessions, today, ptRecords: pt), 3);
      expect(StatsCalculator.longestStreak(sessions, ptRecords: pt), 3);
    });

    test('unverified or mostly unfinished PT sessions do not count', () {
      final pt = [
        ptRecord(DateTime(2026, 3, 10, 9), verified: false),
        ptRecord(DateTime(2026, 3, 9, 9), finished: false),
      ];
      expect(StatsCalculator.currentStreak(const [], today, ptRecords: pt), 0);
    });
  });

  group('MY PT in daily stats', () {
    test('PT sessions add a history day, reps and a completed day', () {
      final pt = [
        ptRecord(DateTime(2026, 3, 9, 18)),
        ptRecord(DateTime(2026, 3, 9, 20), verified: false),
      ];
      final byDay = StatsCalculator.statsByDay(const [], ptRecords: pt);
      final day = byDay[DateTime(2026, 3, 9)]!;
      expect(day.ptSessions, 2);
      expect(day.ptCompletedSessions, 1);
      expect(day.totalPushUps, 60);
      expect(day.isCompletedDay, isTrue);
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

  group('rest days', () {
    // 2026-03-10 (today) is a Tuesday.
    assert(today.weekday == DateTime.tuesday);
    const monday = {DateTime.monday};
    const weekend = {DateTime.sunday, DateTime.monday};

    test('a rest day between workouts keeps the streak but adds nothing', () {
      final sessions = [
        session(DateTime(2026, 3, 8, 9)), // Sunday
        session(DateTime(2026, 3, 10, 9)), // Tuesday
      ];
      expect(StatsCalculator.currentStreak(sessions, today), 1);
      expect(
        StatsCalculator.currentStreak(sessions, today, restWeekdays: monday),
        2,
      );
    });

    test('two rest weekdays in a row bridge the gap', () {
      final sessions = [
        session(DateTime(2026, 3, 7, 9)), // Saturday
        session(DateTime(2026, 3, 10, 9)), // Tuesday
      ];
      expect(
        StatsCalculator.currentStreak(sessions, today, restWeekdays: weekend),
        2,
      );
    });

    test('a gap on a non-rest day breaks the streak', () {
      final sessions = [
        session(DateTime(2026, 3, 7, 9)), // Saturday
        session(DateTime(2026, 3, 10, 9)), // Tuesday
      ];
      expect(
        StatsCalculator.currentStreak(
          sessions,
          today,
          restWeekdays: const {DateTime.sunday},
        ),
        1,
      );
    });

    test('today as a rest day carries yesterday\'s streak', () {
      final sessions = [
        session(DateTime(2026, 3, 8, 9)), // Sunday
        session(DateTime(2026, 3, 9, 9)), // Monday
      ];
      expect(
        StatsCalculator.currentStreak(
          sessions,
          today,
          restWeekdays: const {DateTime.tuesday},
        ),
        2,
      );
      // Today and yesterday both rest days, nothing done on either.
      final earlier = [
        session(DateTime(2026, 3, 7, 9)), // Saturday
        session(DateTime(2026, 3, 8, 9)), // Sunday
      ];
      expect(
        StatsCalculator.currentStreak(
          earlier,
          today,
          restWeekdays: const {DateTime.monday, DateTime.tuesday},
        ),
        2,
      );
      expect(StatsCalculator.currentStreak(earlier, today), 0);
    });

    test('a workout on a rest day counts like any other day', () {
      final sessions = [
        session(DateTime(2026, 3, 8, 9)), // Sunday
        session(DateTime(2026, 3, 9, 9)), // Monday (rest)
        session(DateTime(2026, 3, 10, 9)), // Tuesday
      ];
      expect(
        StatsCalculator.currentStreak(sessions, today, restWeekdays: monday),
        3,
      );
    });

    test('no completed days is still a zero streak', () {
      const all = {1, 2, 3, 4, 5, 6, 7};
      expect(
        StatsCalculator.currentStreak(const [], today, restWeekdays: all),
        0,
      );
      expect(
        StatsCalculator.currentStreak(
          [session(DateTime(2026, 3, 9, 9), reps: 3)],
          today,
          restWeekdays: all,
        ),
        0,
      );
      expect(StatsCalculator.longestStreak(const [], restWeekdays: all), 0);
    });

    test('every weekday a rest day bridges any gap', () {
      const all = {1, 2, 3, 4, 5, 6, 7};
      final sessions = [
        session(DateTime(2026, 2, 1, 9)),
        session(DateTime(2026, 3, 10, 9)),
      ];
      expect(
        StatsCalculator.currentStreak(sessions, today, restWeekdays: all),
        2,
      );
      expect(StatsCalculator.longestStreak(sessions, restWeekdays: all), 2);
    });

    test('longestStreak bridges rest weekdays', () {
      final sessions = [
        session(DateTime(2026, 3, 6, 9)), // Friday
        session(DateTime(2026, 3, 7, 9)), // Saturday
        // Sunday 8th: rest
        session(DateTime(2026, 3, 9, 9)), // Monday
        session(DateTime(2026, 3, 10, 9)), // Tuesday
      ];
      expect(StatsCalculator.longestStreak(sessions), 2);
      expect(
        StatsCalculator.longestStreak(
          sessions,
          restWeekdays: const {DateTime.sunday},
        ),
        4,
      );
      expect(StatsCalculator.longestStreak(sessions, restWeekdays: weekend), 4);
    });

    test('longestStreak does not bridge a gap with a non-rest day in it', () {
      final sessions = [
        session(DateTime(2026, 3, 6, 9)), // Friday
        // Saturday 7th missing, Sunday 8th rest, Monday 9th missing
        session(DateTime(2026, 3, 10, 9)), // Tuesday
        session(DateTime(2026, 3, 11, 9)), // Wednesday
      ];
      expect(
        StatsCalculator.longestStreak(
          sessions,
          restWeekdays: const {DateTime.sunday},
        ),
        2,
      );
      expect(
        StatsCalculator.longestStreak(
          sessions,
          restWeekdays: const {
            DateTime.saturday,
            DateTime.sunday,
            DateTime.monday,
          },
        ),
        3,
      );
    });

    test('a gap longer than a week never bridges with a free weekday', () {
      final sessions = [
        session(DateTime(2026, 3, 1, 9)),
        session(DateTime(2026, 3, 10, 9)),
      ];
      expect(
        StatsCalculator.longestStreak(
          sessions,
          restWeekdays: const {1, 2, 3, 4, 5, 6},
        ),
        1,
      );
    });
  });
}
