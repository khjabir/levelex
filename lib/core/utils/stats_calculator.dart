import '../../features/pt/models/pt_record.dart';
import '../../models/daily_stats.dart';
import '../../models/workout_session.dart';
import 'date_utils.dart';

/// Pure aggregation of sessions into per-day statistics and streaks.
abstract final class StatsCalculator {
  /// Aggregates [sessions] and [ptRecords] for the calendar day of [day].
  /// MY PT reps are included in the day's total.
  static DailyStats statsForDay(
    Iterable<WorkoutSession> sessions,
    DateTime day, {
    bool includeSkipped = true,
    Iterable<PtRecord> ptRecords = const [],
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
      if (s.isCompleted && s.verified) completed++;
      if (s.completedReps > 0) attempted++;
    }
    var pt = 0;
    var ptCompleted = 0;
    for (final r in ptRecords) {
      if (!AppDateUtils.isSameDay(r.startTime, date)) continue;
      pt++;
      if (r.isCompleted) ptCompleted++;
      reps += r.totalReps;
    }
    return DailyStats(
      date: date,
      totalPushUps: reps,
      completedSessions: completed,
      skippedSessions: skipped,
      attemptedSessions: attempted,
      ptSessions: pt,
      ptCompletedSessions: ptCompleted,
    );
  }

  /// Aggregates all sessions into a map keyed by local midnight.
  static Map<DateTime, DailyStats> statsByDay(
    Iterable<WorkoutSession> sessions, {
    bool includeSkipped = true,
    Iterable<PtRecord> ptRecords = const [],
  }) {
    final days = <DateTime>{};
    for (final s in sessions) {
      days.add(AppDateUtils.dateOnly(s.startTime));
    }
    for (final r in ptRecords) {
      days.add(AppDateUtils.dateOnly(r.startTime));
    }
    return {
      for (final d in days)
        d: statsForDay(
          sessions,
          d,
          includeSkipped: includeSkipped,
          ptRecords: ptRecords,
        ),
    };
  }

  /// Days (local midnight) on which at least one set or MY PT session was
  /// completed.
  static Set<DateTime> completedDays(
    Iterable<WorkoutSession> sessions, {
    Iterable<PtRecord> ptRecords = const [],
  }) => {
    for (final s in sessions)
      if (s.isCompleted && s.verified) AppDateUtils.dateOnly(s.startTime),
    for (final r in ptRecords)
      if (r.isCompleted) AppDateUtils.dateOnly(r.startTime),
  };

  /// Number of consecutive completed days ending today or yesterday.
  ///
  /// If today has no completed set yet, the streak carries over from
  /// yesterday (the user still has time today). Multiple sessions on one day
  /// count as a single day.
  ///
  /// A day whose weekday is in [restWeekdays] ([DateTime.monday]..
  /// [DateTime.sunday]) never breaks the streak: when nothing was completed
  /// on it the walk skips over it; when something was, it counts like any
  /// other day.
  static int currentStreak(
    Iterable<WorkoutSession> sessions,
    DateTime today, {
    Iterable<PtRecord> ptRecords = const [],
    Set<int> restWeekdays = const {},
  }) {
    final days = completedDays(sessions, ptRecords: ptRecords);
    if (days.isEmpty) return 0;
    final earliest = days.reduce((a, b) => a.isBefore(b) ? a : b);
    var cursor = AppDateUtils.dateOnly(today);
    if (!days.contains(cursor)) {
      cursor = AppDateUtils.addDays(cursor, -1);
    }
    var streak = 0;
    while (!cursor.isBefore(earliest)) {
      if (days.contains(cursor)) {
        streak++;
      } else if (!restWeekdays.contains(cursor.weekday)) {
        break;
      }
      cursor = AppDateUtils.addDays(cursor, -1);
    }
    return streak;
  }

  /// The longest run of consecutive completed days ever recorded. Days whose
  /// weekday is in [restWeekdays] may sit between two completed days without
  /// ending the run (they add nothing to it).
  static int longestStreak(
    Iterable<WorkoutSession> sessions, {
    Iterable<PtRecord> ptRecords = const [],
    Set<int> restWeekdays = const {},
  }) {
    final days = completedDays(sessions, ptRecords: ptRecords).toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days) {
      if (previous != null && _bridged(previous, day, restWeekdays)) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      previous = day;
    }
    return best;
  }

  /// Whether every day strictly between [from] and [to] is a rest weekday.
  static bool _bridged(DateTime from, DateTime to, Set<int> restWeekdays) {
    final gap = AppDateUtils.daysBetween(from, to);
    if (gap <= 1) return gap == 1;
    if (restWeekdays.length >= DateTime.daysPerWeek) return true;
    // Any seven consecutive days contain a non-rest weekday.
    if (gap > DateTime.daysPerWeek) return false;
    for (var i = 1; i < gap; i++) {
      final between = AppDateUtils.addDays(from, i);
      if (!restWeekdays.contains(between.weekday)) return false;
    }
    return true;
  }
}
