import '../../../core/utils/date_utils.dart';
import '../models/routine.dart';

/// One completed routine day: which routine, which day, when it started.
typedef RoutineRun = ({String routineId, String dayId, DateTime at});

/// Answers "what do I train today?" for a [Routine].
abstract final class RoutineScheduler {
  /// The day scheduled on [date], or null on a rest day.
  ///
  /// Fixed weekdays: the day mapped to that weekday. Rotation: the day after
  /// the most recent run of this routine on or before [date] (wrapping), or
  /// the first day when nothing has been run yet. A rotation routine never
  /// returns null while it has days, even when that day was run today.
  static RoutineDay? dayFor(
    Routine routine,
    DateTime date,
    Iterable<RoutineRun> runs,
  ) {
    switch (routine.schedule) {
      case RoutineSchedule.weekdays:
        return routine.day(routine.weekdays[date.weekday]);
      case RoutineSchedule.rotation:
        if (routine.days.isEmpty) return null;
        final last = _lastRun(routine, runs, until: date);
        if (last == null) return routine.days.first;
        final index = routine.days.indexWhere((d) => d.id == last.dayId);
        if (index < 0) return routine.days.first;
        return routine.days[(index + 1) % routine.days.length];
    }
  }

  /// True when nothing is scheduled on [date]. Rotation routines never rest.
  static bool isRestDay(Routine routine, DateTime date) =>
      routine.schedule == RoutineSchedule.weekdays &&
      routine.day(routine.weekdays[date.weekday]) == null;

  /// The next calendar day (local midnight) with a training day, starting
  /// with [from] itself. Null when a weekdays routine has no training days.
  static DateTime? nextTrainingDate(Routine routine, DateTime from) {
    final start = AppDateUtils.dateOnly(from);
    switch (routine.schedule) {
      case RoutineSchedule.rotation:
        return routine.days.isEmpty ? null : start;
      case RoutineSchedule.weekdays:
        for (var i = 0; i < 7; i++) {
          final candidate = AppDateUtils.addDays(start, i);
          if (!isRestDay(routine, candidate)) return candidate;
        }
        return null;
    }
  }

  /// How many distinct routine days were run in the Monday–Sunday week that
  /// contains [weekOf].
  static int weekProgress(
    Routine routine,
    DateTime weekOf,
    Iterable<RoutineRun> runs,
  ) {
    final start = weekStart(weekOf);
    final end = AppDateUtils.addDays(start, 7);
    final days = <String>{};
    for (final run in runs) {
      if (run.routineId != routine.id) continue;
      if (run.at.isBefore(start) || !run.at.isBefore(end)) continue;
      days.add(run.dayId);
    }
    return days.length;
  }

  /// Local midnight of the Monday of the week that contains [date].
  static DateTime weekStart(DateTime date) =>
      AppDateUtils.addDays(AppDateUtils.dateOnly(date), 1 - date.weekday);

  /// The most recent run of [routine] that started before the end of the
  /// calendar day of [until].
  static RoutineRun? _lastRun(
    Routine routine,
    Iterable<RoutineRun> runs, {
    required DateTime until,
  }) {
    final cutoff = AppDateUtils.addDays(AppDateUtils.dateOnly(until), 1);
    RoutineRun? last;
    for (final run in runs) {
      if (run.routineId != routine.id) continue;
      if (!run.at.isBefore(cutoff)) continue;
      if (last == null || run.at.isAfter(last.at)) last = run;
    }
    return last;
  }
}
