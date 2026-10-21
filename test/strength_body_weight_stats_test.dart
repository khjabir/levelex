import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/body_weight_stats.dart';
import 'package:levelex/features/strength/models/lift_log.dart';

// 2026-10-12 is a Monday.
final now = DateTime(2026, 10, 12, 8, 30);

BodyWeightEntry at(int daysAgo, double kg) =>
    BodyWeightEntry(date: DateTime(2026, 10, 12 - daysAgo), kg: kg);

void main() {
  test('latest is the newest entry regardless of order', () {
    expect(BodyWeightStats.latest(const []), isNull);
    final entries = [at(3, 80), at(0, 79), at(10, 82)];
    expect(BodyWeightStats.latest(entries)!.kg, 79);
  });

  test('weeklyMeans groups by Monday week, oldest first', () {
    final entries = [
      at(0, 78), // Mon 12 Oct
      at(1, 79), // Sun 11 Oct (week of 5 Oct)
      at(2, 81), // Sat 10 Oct
      at(7, 80), // Mon 5 Oct
      at(14, 84), // Mon 28 Sep
    ];
    final weeks = BodyWeightStats.weeklyMeans(entries);
    expect(weeks.length, 3);
    expect(weeks[0].weekStart, DateTime(2026, 9, 28));
    expect(weeks[0].mean, 84);
    expect(weeks[0].count, 1);
    expect(weeks[1].weekStart, DateTime(2026, 10, 5));
    expect(weeks[1].mean, 80);
    expect(weeks[1].count, 3);
    expect(weeks[2].weekStart, DateTime(2026, 10, 12));
    expect(weeks[2].mean, 78);
    expect(BodyWeightStats.weeklyMeans(const []), isEmpty);
  });

  test('trendKgPerWeek is the least-squares slope over the window', () {
    // Losing exactly 0.1 kg a day for ten days.
    final entries = [for (var d = 0; d < 10; d++) at(d, 80 + d * 0.1)];
    expect(
      BodyWeightStats.trendKgPerWeek(entries, now: now),
      closeTo(-0.7, 1e-9),
    );
    // Gaps and noise still give the fitted slope.
    final sparse = [at(0, 80), at(2, 80.2), at(6, 80.6), at(20, 82)];
    expect(
      BodyWeightStats.trendKgPerWeek(sparse, now: now),
      closeTo(-0.7, 1e-9),
    );
    // Older entries are outside the 28-day window.
    final withOld = [...sparse, at(60, 70)];
    expect(
      BodyWeightStats.trendKgPerWeek(withOld, now: now),
      closeTo(-0.7, 1e-9),
    );
    expect(
      BodyWeightStats.trendKgPerWeek(withOld, days: 90, now: now),
      isNot(closeTo(-0.7, 1e-3)),
    );
  });

  test('trend needs three points', () {
    expect(BodyWeightStats.trendKgPerWeek(const [], now: now), isNull);
    expect(
      BodyWeightStats.trendKgPerWeek([at(0, 80), at(1, 81)], now: now),
      isNull,
    );
    // Three points, but only two inside the window.
    expect(
      BodyWeightStats.trendKgPerWeek([
        at(0, 80),
        at(1, 81),
        at(40, 85),
      ], now: now),
      isNull,
    );
    expect(
      BodyWeightStats.trendKgPerWeek([
        at(0, 80),
        at(1, 81),
        at(2, 82),
      ], now: now),
      closeTo(-7, 1e-9),
    );
  });

  test('change compares the latest with the entry closest to N days ago', () {
    final entries = [at(0, 78), at(6, 79.5), at(9, 80), at(30, 83)];
    expect(BodyWeightStats.change(entries, now: now), closeTo(-1.5, 1e-9));
    expect(
      BodyWeightStats.change(entries, days: 28, now: now),
      closeTo(-5, 1e-9),
    );
    expect(
      BodyWeightStats.change(entries, days: 10, now: now),
      closeTo(-2, 1e-9),
    );
    // The latest entry is never its own baseline.
    expect(BodyWeightStats.change([at(0, 78)], now: now), isNull);
    expect(
      BodyWeightStats.change([at(0, 78), at(1, 79)], days: 28, now: now),
      closeTo(-1, 1e-9),
    );
    expect(BodyWeightStats.change(const [], now: now), isNull);
  });

  test('toGoal is signed: negative to lose, positive to gain', () {
    final entries = [at(0, 80), at(5, 81)];
    expect(BodyWeightStats.toGoal(entries, 75), -5);
    expect(BodyWeightStats.toGoal(entries, 85), 5);
    expect(BodyWeightStats.toGoal(const [], 75), isNull);
  });
}
