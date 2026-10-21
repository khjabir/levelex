import '../../features/pt/models/pt_record.dart';
import '../../models/reminder_time.dart';
import '../../models/user_settings.dart';
import '../../models/workout_session.dart';
import 'date_utils.dart';

/// Pure reminder schedule maths: which times of day reminders fire, when the
/// next one is, and which reminders were missed.
class ReminderSchedule {
  const ReminderSchedule({
    required this.interval,
    required this.start,
    required this.end,
    required this.enabled,
  }) : assert(interval > Duration.zero);

  factory ReminderSchedule.fromSettings(UserSettings s) => ReminderSchedule(
    interval: s.reminderInterval,
    start: s.reminderStartTime,
    end: s.reminderEndTime,
    enabled: s.remindersEnabled,
  );

  final Duration interval;
  final ReminderTime start;
  final ReminderTime end;
  final bool enabled;

  /// Reminder times within a day, from [start] to [end] inclusive, stepping
  /// by [interval]. If [end] is not after [start], only [start] is returned.
  List<ReminderTime> get dailySlots {
    final slots = <ReminderTime>[];
    final step = interval.inMinutes;
    final endMinutes = end > start ? end.minutesSinceMidnight : -1;
    var m = start.minutesSinceMidnight;
    if (endMinutes < 0) return [start];
    while (m <= endMinutes && m < 24 * 60) {
      slots.add(ReminderTime.fromMinutes(m));
      m += step;
    }
    return slots;
  }

  int get slotsPerDay => dailySlots.length;

  /// Concrete reminder moments on the calendar day of [day] (local time).
  List<DateTime> slotsOn(DateTime day) =>
      dailySlots.map((t) => t.onDay(day)).toList();

  /// The next reminder strictly after [now], or null if reminders are off.
  DateTime? nextReminderAfter(DateTime now) {
    if (!enabled) return null;
    for (final slot in slotsOn(now)) {
      if (slot.isAfter(now)) return slot;
    }
    final tomorrow = AppDateUtils.addDays(now, 1);
    return slotsOn(tomorrow).first;
  }

  /// Upcoming reminder moments after [now], up to [count] of them.
  List<DateTime> upcoming(DateTime now, int count) {
    final result = <DateTime>[];
    var day = AppDateUtils.dateOnly(now);
    // Guard against an empty slot list looping forever.
    if (dailySlots.isEmpty || count <= 0) return result;
    while (result.length < count) {
      for (final slot in slotsOn(day)) {
        if (slot.isAfter(now)) result.add(slot);
        if (result.length >= count) break;
      }
      day = AppDateUtils.addDays(day, 1);
    }
    return result;
  }

  /// Reminders whose window `[slot, slot + interval)` has fully elapsed by
  /// [now], started at or after [from], and in which the user attempted no
  /// workout. These are the sessions the user "skipped". A MY PT session
  /// covers every window it overlaps.
  ///
  /// A reminder's window is closed only once a full [interval] has passed,
  /// so the user always gets the whole interval to respond. Windows that
  /// ended at or before [evaluatedUntil] were already judged earlier and
  /// are excluded, so repeated evaluations never double count.
  List<DateTime> skippedSlots({
    required DateTime from,
    required DateTime now,
    required Iterable<WorkoutSession> sessions,
    Iterable<PtRecord> ptRecords = const [],
    DateTime? evaluatedUntil,
  }) {
    if (!enabled) return const [];
    final attempted = sessions
        .where((s) => s.isAttempted)
        .map((s) => s.startTime)
        .toList();
    final ptAttempted = ptRecords.where((r) => r.isAttempted).toList();

    final skipped = <DateTime>[];
    var day = AppDateUtils.dateOnly(from);
    final lastDay = AppDateUtils.dateOnly(now);
    while (!day.isAfter(lastDay)) {
      for (final slot in slotsOn(day)) {
        if (slot.isBefore(from)) continue;
        final windowEnd = slot.add(interval);
        if (windowEnd.isAfter(now)) continue; // Window still open.
        if (evaluatedUntil != null && !windowEnd.isAfter(evaluatedUntil)) {
          continue; // Already evaluated.
        }
        final attemptedInWindow =
            attempted.any((t) => !t.isBefore(slot) && t.isBefore(windowEnd)) ||
            ptAttempted.any(
              (r) =>
                  r.startTime.isBefore(windowEnd) && !r.endTime.isBefore(slot),
            );
        if (!attemptedInWindow) skipped.add(slot);
      }
      day = AppDateUtils.addDays(day, 1);
    }
    return skipped;
  }
}
