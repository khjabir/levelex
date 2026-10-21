import '../../../core/utils/date_utils.dart';
import '../models/lift_log.dart';

/// One calendar week of weigh-ins.
typedef WeeklyWeight = ({DateTime weekStart, double mean, int count});

/// Pure statistics over body-weight entries. Entries may arrive in any
/// order; one entry per day is assumed but not required.
abstract final class BodyWeightStats {
  /// The most recent weigh-in, or null without entries.
  static BodyWeightEntry? latest(Iterable<BodyWeightEntry> entries) {
    BodyWeightEntry? best;
    for (final e in entries) {
      if (best == null || e.date.isAfter(best.date)) best = e;
    }
    return best;
  }

  /// Mean weight per Monday-to-Sunday week, oldest first.
  static List<WeeklyWeight> weeklyMeans(Iterable<BodyWeightEntry> entries) {
    final sums = <DateTime, ({double sum, int count})>{};
    for (final e in entries) {
      final week = weekStart(e.date);
      final acc = sums[week] ?? (sum: 0, count: 0);
      sums[week] = (sum: acc.sum + e.kg, count: acc.count + 1);
    }
    final weeks = sums.keys.toList()..sort();
    return [
      for (final week in weeks)
        (
          weekStart: week,
          mean: sums[week]!.sum / sums[week]!.count,
          count: sums[week]!.count,
        ),
    ];
  }

  /// Least-squares slope in kg per week over the last [days] days. Null
  /// with fewer than three weigh-ins in that window.
  static double? trendKgPerWeek(
    Iterable<BodyWeightEntry> entries, {
    int days = 28,
    DateTime? now,
  }) {
    final today = AppDateUtils.dateOnly(now ?? DateTime.now());
    final from = AppDateUtils.addDays(today, -days);
    final points = [
      for (final e in entries)
        if (!e.date.isBefore(from) && !e.date.isAfter(today)) e,
    ]..sort((a, b) => a.date.compareTo(b.date));
    if (points.length < 3) return null;

    final origin = points.first.date;
    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
    for (final p in points) {
      final x = AppDateUtils.daysBetween(origin, p.date).toDouble();
      sumX += x;
      sumY += p.kg;
      sumXY += x * p.kg;
      sumXX += x * x;
    }
    final n = points.length;
    final denominator = n * sumXX - sumX * sumX;
    if (denominator == 0) return null;
    final perDay = (n * sumXY - sumX * sumY) / denominator;
    return perDay * 7;
  }

  /// Latest weight minus the weigh-in closest to [days] ago (the latest
  /// itself excluded). Null with fewer than two entries.
  static double? change(
    Iterable<BodyWeightEntry> entries, {
    int days = 7,
    DateTime? now,
  }) {
    final last = latest(entries);
    if (last == null) return null;
    final target = AppDateUtils.addDays(
      AppDateUtils.dateOnly(now ?? DateTime.now()),
      -days,
    );
    BodyWeightEntry? closest;
    var closestDistance = 0;
    for (final e in entries) {
      if (identical(e, last)) continue;
      final distance = AppDateUtils.daysBetween(target, e.date).abs();
      if (closest == null ||
          distance < closestDistance ||
          (distance == closestDistance && e.date.isBefore(closest.date))) {
        closest = e;
        closestDistance = distance;
      }
    }
    if (closest == null) return null;
    return last.kg - closest.kg;
  }

  /// Signed distance from the latest weight to [goalKg]: negative means
  /// there is weight to lose, positive to gain. Null without entries.
  static double? toGoal(Iterable<BodyWeightEntry> entries, double goalKg) {
    final last = latest(entries);
    if (last == null) return null;
    return goalKg - last.kg;
  }

  /// Local midnight of the Monday of the week containing [date].
  static DateTime weekStart(DateTime date) =>
      AppDateUtils.addDays(AppDateUtils.dateOnly(date), 1 - date.weekday);
}
