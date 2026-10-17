/// Small date helpers that make day-boundary logic explicit and testable.
abstract final class AppDateUtils {
  /// Returns a [DateTime] at local midnight for the calendar day of [dt].
  static DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// True when [a] and [b] fall on the same local calendar day.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Adds whole calendar [days] to [day] without being affected by DST
  /// shifts (uses the date constructor rather than `Duration` arithmetic).
  static DateTime addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  /// Number of whole calendar days from [from] to [to] (negative if earlier).
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// A stable `yyyy-MM-dd` key for maps keyed by day.
  static String dayKey(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  /// Parses a key produced by [dayKey].
  static DateTime parseDayKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}
