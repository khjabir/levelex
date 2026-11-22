import 'dart:math' as math;

import '../../features/pt/models/pt_record.dart';
import '../../features/strength/logic/records.dart';
import '../../features/strength/models/lift_log.dart';
import '../../models/workout_session.dart';
import '../levels/level_system.dart';
import '../utils/date_utils.dart';
import '../utils/stats_calculator.dart';
import 'daily_challenge.dart';

/// What happened in one Monday-to-Sunday week.
class WeeklyReport {
  const WeeklyReport({
    required this.weekStart,
    required this.goal,
    required this.workouts,
    required this.activeDays,
    required this.activeWeekdays,
    required this.reps,
    required this.activeMinutes,
    required this.xp,
    required this.prs,
    required this.dailyChallenges,
  });

  /// Monday, local midnight.
  final DateTime weekStart;

  /// Active days the user aimed for.
  final int goal;

  /// Completed verified sets plus attempted MY PT sessions.
  final int workouts;

  /// Days with a completed verified set or a completed MY PT session.
  final int activeDays;

  /// The weekdays ([DateTime.monday]..[DateTime.sunday]) of those days.
  final Set<int> activeWeekdays;

  /// Reps of non-timed sets plus MY PT reps.
  final int reps;

  /// Minutes spent in sets and MY PT sessions.
  final int activeMinutes;

  /// XP from sets, MY PT sessions and daily challenges.
  final int xp;

  /// Strength personal records set in the week.
  final int prs;

  /// Daily challenges completed in the week.
  final int dailyChallenges;

  /// Sunday, local midnight.
  DateTime get weekEnd => AppDateUtils.addDays(weekStart, 6);

  /// `0..1` towards the active-day goal.
  double get goalProgress => goal <= 0 ? 1 : math.min(1, activeDays / goal);

  bool get goalMet => activeDays >= goal;

  @override
  String toString() =>
      'WeeklyReport($weekStart, $activeDays/$goal days, $workouts workouts, '
      '$reps reps, $activeMinutes min, $xp xp, $prs prs, '
      '$dailyChallenges challenges)';
}

/// Builds [WeeklyReport]s from history.
abstract final class WeeklyReports {
  /// Local midnight of the Monday of the week containing [d].
  static DateTime weekStartOf(DateTime d) =>
      AppDateUtils.addDays(AppDateUtils.dateOnly(d), 1 - d.weekday);

  /// The report of the week containing [weekOf].
  static WeeklyReport build({
    required DateTime weekOf,
    required Iterable<WorkoutSession> sessions,
    required Iterable<PtRecord> ptRecords,
    required Iterable<LiftEntry> lifts,
    required Set<DateTime> challengeDays,
    required int goal,
  }) {
    final start = weekStartOf(weekOf);
    final end = AppDateUtils.addDays(start, 7);
    bool inWeek(DateTime t) => !t.isBefore(start) && t.isBefore(end);

    var workouts = 0;
    var reps = 0;
    var xp = 0;
    var active = Duration.zero;
    final activeDays = <DateTime>{};

    for (final s in sessions) {
      if (s.skipped || !inWeek(s.startTime)) continue;
      if (s.isCompleted && s.verified) {
        workouts++;
        activeDays.add(AppDateUtils.dateOnly(s.startTime));
      }
      if (!s.exercise.isTimed) reps += s.completedReps;
      xp += LevelSystem.xpForSession(s);
      final length = s.duration;
      if (length != null && length > Duration.zero) active += length;
    }

    for (final r in ptRecords) {
      if (!inWeek(r.startTime)) continue;
      if (r.isAttempted) workouts++;
      if (r.isCompleted) activeDays.add(AppDateUtils.dateOnly(r.startTime));
      reps += r.totalReps;
      xp += LevelSystem.xpForPtRecord(r);
      if (r.duration > Duration.zero) active += r.duration;
    }

    var challenges = 0;
    for (final d in challengeDays) {
      if (inWeek(d)) challenges++;
    }
    xp += challenges * DailyChallenge.bonusXp;

    var prs = 0;
    for (final pr in RecordBook.recent(lifts, limit: 1000)) {
      // A first log is a baseline, not a record beaten.
      if (pr.previous != null && inWeek(pr.date)) prs++;
    }

    return WeeklyReport(
      weekStart: start,
      goal: goal,
      workouts: workouts,
      activeDays: activeDays.length,
      activeWeekdays: {for (final d in activeDays) d.weekday},
      reps: reps,
      activeMinutes: active.inMinutes,
      xp: xp,
      prs: prs,
      dailyChallenges: challenges,
    );
  }

  /// How many weeks in a row the active-day [goal] has been met, counting
  /// back from the week of [through]. The current week counts when it is
  /// already met; otherwise the count starts from the previous week.
  static int consecutiveWeeksMet({
    required DateTime through,
    required Iterable<WorkoutSession> sessions,
    required Iterable<PtRecord> ptRecords,
    required int goal,
  }) {
    final days = StatsCalculator.completedDays(sessions, ptRecords: ptRecords);
    if (days.isEmpty) return 0;
    final earliest = days.reduce((a, b) => a.isBefore(b) ? a : b);
    final firstWeek = weekStartOf(earliest);

    final perWeek = <DateTime, int>{};
    for (final d in days) {
      final week = weekStartOf(d);
      perWeek[week] = (perWeek[week] ?? 0) + 1;
    }
    bool met(DateTime week) => (perWeek[week] ?? 0) >= goal;

    var week = weekStartOf(through);
    if (!met(week)) week = AppDateUtils.addDays(week, -7);
    var count = 0;
    while (!week.isBefore(firstWeek) && met(week)) {
      count++;
      week = AppDateUtils.addDays(week, -7);
    }
    return count;
  }
}
