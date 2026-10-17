import '../../models/daily_stats.dart';
import '../../models/workout_session.dart';
import 'date_utils.dart';

/// Pure aggregation of sessions into per-day statistics and streaks.
abstract final class StatsCalculator {
  /// Aggregates [sessions] for the calendar day of [day].
  static DailyStats statsForDay(
    Iterable<WorkoutSession> sessions,
    DateTime day, {
    bool includeSkipped = true,
  }) {
    final date = AppDateUtils.dateOnly(day);
    var reps = 0;
    var completed = 0;
    var skipped = 0;
    var attempted = 0;
    for (final s in sessions) {
      if (!AppDateUtils.isSameDay(s.startTime, date)) continue;
      if (s.skipped) {
        if (includeSkipped) skipped++;
        continue;
      }
      if (!s.exercise.isTimed) reps += s.completedReps;
      if (s.isCompleted) completed++;
      if (s.completedReps > 0) attempted++;
    }
    return DailyStats(
      date: date,
      totalPushUps: reps,
      completedSessions: completed,
      skippedSessions: skipped,
      attemptedSessions: attempted,
    );
  }

  /// Aggregates all sessions into a map keyed by local midnight.
  static Map<DateTime, DailyStats> statsByDay(
    Iterable<WorkoutSession> sessions, {
    bool includeSkipped = true,
  }) {
    final days = <DateTime>{};
    for (final s in sessions) {
      days.add(AppDateUtils.dateOnly(s.startTime));
    }
    return {
      for (final d in days)
        d: statsForDay(sessions, d, includeSkipped: includeSkipped),
    };
  }

  /// Days (local midnight) on which at least one set was completed.
  static Set<DateTime> completedDays(Iterable<WorkoutSession> sessions) => {
    for (final s in sessions)
      if (s.isCompleted) AppDateUtils.dateOnly(s.startTime),
  };

  /// Number of consecutive completed days ending today or yesterday.
  ///
  /// If today has no completed set yet, the streak carries over from
  /// yesterday (the user still has time today). Multiple sessions on one day
  /// count as a single day.
  static int currentStreak(Iterable<WorkoutSession> sessions, DateTime today) {
    final days = completedDays(sessions);
    var cursor = AppDateUtils.dateOnly(today);
    if (!days.contains(cursor)) {
      cursor = AppDateUtils.addDays(cursor, -1);
      if (!days.contains(cursor)) return 0;
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = AppDateUtils.addDays(cursor, -1);
    }
    return streak;
  }

  /// The longest run of consecutive completed days ever recorded.
  static int longestStreak(Iterable<WorkoutSession> sessions) {
    final days = completedDays(sessions).toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days) {
      if (previous != null && AppDateUtils.daysBetween(previous, day) == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      previous = day;
    }
    return best;
  }
}
