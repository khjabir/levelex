import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/one_rm.dart';
import 'package:levelex/features/strength/models/lift_log.dart';

LiftEntry entry(String id, int day, List<LiftSet> sets) => LiftEntry(
  id: id,
  movementId: 'bb_bench_press',
  startTime: DateTime(2026, 1, day),
  sets: sets,
);

void main() {
  group('OneRm formulas', () {
    test('match the published equations for 100 kg × 10', () {
      expect(OneRm.epley(100, 10), closeTo(133.33, 0.01));
      expect(OneRm.brzycki(100, 10), closeTo(133.33, 0.01));
      expect(OneRm.lombardi(100, 10), closeTo(125.89, 0.01));
      expect(OneRm.oconner(100, 10), closeTo(125.0, 0.001));
      expect(OneRm.mayhew(100, 10), closeTo(130.94, 0.05));
      expect(OneRm.wathan(100, 10), closeTo(134.75, 0.05));
      expect(OneRm.lander(100, 10), closeTo(134.07, 0.05));
    });

    test('every formula has a label', () {
      for (final f in OneRmFormula.values) {
        expect(f.label, isNotEmpty);
      }
      expect(OneRmFormula.oconner.label, "O'Conner");
    });
  });

  group('OneRm.estimate', () {
    test('defaults to Epley', () {
      expect(OneRm.estimate(100, 5), closeTo(OneRm.epley(100, 5), 1e-9));
    });

    test('honours the formula argument', () {
      expect(
        OneRm.estimate(80, 8, formula: OneRmFormula.brzycki),
        closeTo(OneRm.brzycki(80, 8), 1e-9),
      );
      expect(
        OneRm.estimate(80, 8, formula: OneRmFormula.wathan),
        closeTo(OneRm.wathan(80, 8), 1e-9),
      );
    });

    test('a single rep is already the max', () {
      for (final f in OneRmFormula.values) {
        expect(OneRm.estimate(120, 1, formula: f), 120);
      }
    });

    test('returns null outside the trusted range', () {
      expect(OneRm.estimate(100, 0), isNull);
      expect(OneRm.estimate(100, -2), isNull);
      expect(OneRm.estimate(100, OneRm.repCap + 1), isNull);
      expect(OneRm.estimate(100, OneRm.repCap), isNotNull);
      expect(OneRm.estimate(0, 5), isNull);
      expect(OneRm.estimate(-10, 5), isNull);
    });

    test('rep cap is 12', () {
      expect(OneRm.repCap, 12);
    });
  });

  group('OneRm.bestForEntry', () {
    test('takes the best qualifying work set', () {
      final e = entry('a', 1, const [
        LiftSet(weightKg: 40, reps: 10, warmUp: true),
        LiftSet(weightKg: 80, reps: 8),
        LiftSet(weightKg: 90, reps: 3),
        LiftSet(weightKg: 60, reps: 20),
      ]);
      // 80 × 8 → 101.3; 90 × 3 → 99; 60 × 20 is over the cap; warm-up ignored.
      expect(OneRm.bestForEntry(e), closeTo(OneRm.epley(80, 8), 1e-9));
    });

    test('ignores warm-ups even when they would be the best', () {
      final e = entry('a', 1, const [
        LiftSet(weightKg: 100, reps: 5, warmUp: true),
        LiftSet(weightKg: 60, reps: 5),
      ]);
      expect(OneRm.bestForEntry(e), closeTo(OneRm.epley(60, 5), 1e-9));
    });

    test('is null when no set qualifies', () {
      expect(OneRm.bestForEntry(entry('a', 1, const [])), isNull);
      expect(
        OneRm.bestForEntry(
          entry('b', 1, const [LiftSet(weightKg: 0, reps: 15)]),
        ),
        isNull,
      );
      expect(
        OneRm.bestForEntry(
          entry('c', 1, const [LiftSet(weightKg: 50, reps: 15)]),
        ),
        isNull,
      );
    });
  });

  group('OneRm.bestInHistory', () {
    test('is the best over every entry', () {
      final history = [
        entry('a', 1, const [LiftSet(weightKg: 60, reps: 5)]),
        entry('b', 2, const [LiftSet(weightKg: 70, reps: 5)]),
        entry('c', 3, const [LiftSet(weightKg: 65, reps: 5)]),
      ];
      expect(OneRm.bestInHistory(history), closeTo(OneRm.epley(70, 5), 1e-9));
      expect(
        OneRm.bestInHistory(history, formula: OneRmFormula.lander),
        closeTo(OneRm.lander(70, 5), 1e-9),
      );
    });

    test('is null for an empty or unqualified history', () {
      expect(OneRm.bestInHistory(const []), isNull);
      expect(
        OneRm.bestInHistory([
          entry('a', 1, const [LiftSet(weightKg: 0, reps: 10)]),
        ]),
        isNull,
      );
    });
  });
}
