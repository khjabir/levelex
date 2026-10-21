import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/plates.dart';

void main() {
  group('BarType', () {
    test('carries its weight and label', () {
      expect(BarType.olympic.kg, 20);
      expect(BarType.womens.kg, 15);
      expect(BarType.technique.kg, 10);
      expect(BarType.ezBar.kg, 7.5);
      expect(BarType.trapBar.kg, 25);
      expect(BarType.smith.kg, 7);
      expect(BarType.none.kg, 0);
      expect(BarType.womens.label, "Women's bar");
      expect(BarType.none.label, 'No bar');
    });
  });

  group('PlateCalculator.solve', () {
    test('loads heaviest first per side', () {
      final load = PlateCalculator.solve(targetKg: 100);
      expect(load.perSide, [25, 15]);
      expect(load.achievedKg, 100);
      expect(load.targetKg, 100);
      expect(load.barKg, 20);
      expect(load.remainderKg, 0);
      expect(load.isExact, isTrue);
      expect(load.perSideKg, 40);
      expect(load.label, '25 + 15 per side');
    });

    test('uses the small plates when needed', () {
      final load = PlateCalculator.solve(targetKg: 62.5);
      expect(load.perSide, [20, 1.25]);
      expect(load.achievedKg, 62.5);
      expect(load.label, '20 + 1.25 per side');
    });

    test('an empty bar is labelled as such', () {
      final load = PlateCalculator.solve(targetKg: 20);
      expect(load.perSide, isEmpty);
      expect(load.achievedKg, 20);
      expect(load.label, 'Empty bar');
    });

    test('never passes the target and reports the remainder', () {
      final load = PlateCalculator.solve(targetKg: 61);
      expect(load.perSide, [20]);
      expect(load.achievedKg, 60);
      expect(load.remainderKg, 1);
      expect(load.isExact, isFalse);
    });

    test('a bar heavier than the target comes back empty', () {
      final load = PlateCalculator.solve(targetKg: 15);
      expect(load.perSide, isEmpty);
      expect(load.achievedKg, 20);
      expect(load.remainderKg, -5);
    });

    test('honours a different bar and plate set', () {
      final load = PlateCalculator.solve(
        targetKg: 47.5,
        barKg: BarType.womens.kg,
        plates: const [10, 5, 2.5, 1.25],
      );
      expect(load.perSide, [10, 5, 1.25]);
      expect(load.achievedKg, 47.5);
    });

    test('sorts plates given in any order', () {
      final load = PlateCalculator.solve(
        targetKg: 70,
        plates: const [2.5, 20, 5, 10],
      );
      expect(load.perSide, [20, 5]);
    });

    test('respects pair limits and falls back to lighter plates', () {
      final load = PlateCalculator.solve(
        targetKg: 100,
        pairsAvailable: {25: 1, 10: 2, 5: 1, 2.5: 1},
      );
      expect(load.perSide, [25, 10, 5]);
      expect(load.achievedKg, 100);
    });

    test('uses several pairs of one size when owned', () {
      final load = PlateCalculator.solve(
        targetKg: 100,
        pairsAvailable: {20: 2},
      );
      expect(load.perSide, [20, 20]);
      expect(load.achievedKg, 100);
    });

    test('plates missing from the inventory are unavailable', () {
      final load = PlateCalculator.solve(
        targetKg: 100,
        pairsAvailable: {20: 1},
      );
      expect(load.perSide, [20]);
      expect(load.achievedKg, 60);
      expect(load.remainderKg, 40);
    });

    test('ignores non-positive plate sizes', () {
      final load = PlateCalculator.solve(
        targetKg: 30,
        plates: const [0, -5, 5],
      );
      expect(load.perSide, [5]);
    });
  });

  group('PlateCalculator.nearestLoadable', () {
    test('rounds down when that is closer', () {
      expect(PlateCalculator.nearestLoadable(targetKg: 61), 60);
    });

    test('rounds up when that is closer', () {
      expect(PlateCalculator.nearestLoadable(targetKg: 62), 62.5);
    });

    test('keeps an exact target', () {
      expect(PlateCalculator.nearestLoadable(targetKg: 100), 100);
    });

    test('ties go to the lighter load', () {
      // 61.25 sits exactly between 60 and 62.5.
      expect(PlateCalculator.nearestLoadable(targetKg: 61.25), 60);
    });

    test('works within an inventory', () {
      expect(
        PlateCalculator.nearestLoadable(
          targetKg: 68,
          pairsAvailable: {20: 1, 5: 1},
        ),
        70,
      );
      expect(
        PlateCalculator.nearestLoadable(
          targetKg: 63,
          pairsAvailable: {20: 1, 5: 1},
        ),
        60,
      );
    });
  });

  group('PlateCalculator.dumbbellSteps', () {
    test('defaults to a 2–50 kg rack in 2 kg steps', () {
      final steps = PlateCalculator.dumbbellSteps();
      expect(steps.length, 25);
      expect(steps.first, 2);
      expect(steps.last, 50);
      expect(steps[1], 4);
    });

    test('accepts a custom rack', () {
      expect(PlateCalculator.dumbbellSteps(min: 2.5, max: 12.5, step: 2.5), [
        2.5,
        5,
        7.5,
        10,
        12.5,
      ]);
    });

    test('degrades to the minimum on a bad step or range', () {
      expect(PlateCalculator.dumbbellSteps(step: 0), [2]);
      expect(PlateCalculator.dumbbellSteps(min: 10, max: 5), [10]);
    });
  });

  group('PlateCalculator.formatKg', () {
    test('drops trailing zeros', () {
      expect(PlateCalculator.formatKg(20), '20');
      expect(PlateCalculator.formatKg(2.5), '2.5');
      expect(PlateCalculator.formatKg(1.25), '1.25');
      expect(PlateCalculator.formatKg(0), '0');
    });
  });
}
