/// A wall-clock time of day (hour + minute) that is independent of Flutter's
/// `TimeOfDay`, so it can be used in pure Dart logic and persisted easily.
class ReminderTime implements Comparable<ReminderTime> {
  const ReminderTime({required this.hour, required this.minute})
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  factory ReminderTime.fromMinutes(int minutesSinceMidnight) {
    final m = minutesSinceMidnight.clamp(0, 24 * 60 - 1);
    return ReminderTime(hour: m ~/ 60, minute: m % 60);
  }

  factory ReminderTime.fromDateTime(DateTime dt) =>
      ReminderTime(hour: dt.hour, minute: dt.minute);

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  /// Combines this time with the calendar date of [day] (local time).
  DateTime onDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  /// 12-hour formatted label, e.g. `9:00 AM`.
  String get label {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final mm = minute.toString().padLeft(2, '0');
    final suffix = hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $suffix';
  }

  @override
  int compareTo(ReminderTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  bool operator <(ReminderTime other) => compareTo(other) < 0;
  bool operator <=(ReminderTime other) => compareTo(other) <= 0;
  bool operator >(ReminderTime other) => compareTo(other) > 0;
  bool operator >=(ReminderTime other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'ReminderTime($label)';
}
