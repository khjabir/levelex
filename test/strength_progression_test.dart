import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/progression.dart';
import 'package:levelex/features/strength/models/lift_log.dart';
import 'package:levelex/features/strength/models/progression_rule.dart';

/// Session number [n] (one per day) with (weight, reps) work sets.
LiftEntry session(int n, List<(double, int)> sets) => LiftEntry(
  id: 's$n',
  movementId: 'bb_bench_press',
  startTime: DateTime(2026, 1, n),
  sets: [for (final (w, r) in sets) LiftSet(weightKg: w, reps: r)],
);

/// Session [n] of timed holds in seconds (reps 0, as a timer logs them).
LiftEntry timed(int n, List<int> seconds, {double weightKg = 0}) => LiftEntry(
  id: 't$n',
  movementId: 'plank',
  startTime: DateTime(2026, 1, n),
  sets: [
    for (final s in seconds) LiftSet(weightKg: weightKg, reps: 0, seconds: s),
  ],
);

/// [count] identical sessions starting at session [from].
List<LiftEntry> repeat(int from, int count, List<(double, int)> sets) => [
  for (var i = 0; i < count; i++) session(from + i, sets),
];

const linear = ProgressionRule(
  policy: ProgressionPolicy.linear,
  incrementKg: 2.5,
  repsMin: 5,
  repsMax: 5,
  sets: 3,
);
const greyskull = ProgressionRule(
  policy: ProgressionPolicy.greyskull,
  incrementKg: 2.5,
  repsMin: 5,
  repsMax: 5,
  sets: 3,
);
const double_ = ProgressionRule(
  policy: ProgressionPolicy.double_,
  incrementKg: 2.5,
  repsMin: 8,
  repsMax: 12,
  sets: 3,
);
const triple = ProgressionRule(
  policy: ProgressionPolicy.triple,
  incrementKg: 2.5,
  repsMin: 8,
  repsMax: 12,
  sets: 3,
  setsMax: 5,
);
const time = ProgressionRule(
  policy: ProgressionPolicy.time,
  sets: 3,
  seconds: 30,
  secondsStep: 5,
);

Prescription next(ProgressionRule rule, List<LiftEntry> history) =>
    ProgressionEngine.next(rule: rule, history: history);

void main() {
  group('first session', () {
    test('linear aims at repsMax with no weight', () {
      final p = next(linear, const []);
      expect(p.kind, PrescriptionKind.first);
      expect(p.weightKg, isNull);
      expect(p.sets, 3);
      expect(p.reps, 5);
      expect(p.repsMin, isNull);
      expect(p.basedOn, isNull);
      expect(p.why, 'Nothing logged yet, so this session sets the baseline.');
    });

    test('double and triple start at the bottom of the range', () {
      expect(next(double_, const []).reps, 8);
      expect(next(double_, const []).repsMin, 8);
      expect(next(triple, const []).reps, 8);
    });

    test('time carries the rule seconds', () {
      final p = next(time, const []);
      expect(p.kind, PrescriptionKind.first);
      expect(p.seconds, 30);
      expect(p.weightKg, isNull);
    });

    test('entries with only warm-up sets do not count', () {
      final warm = LiftEntry(
        id: 'w',
        movementId: 'bb_bench_press',
        startTime: DateTime(2026),
        sets: const [LiftSet(weightKg: 40, reps: 5, warmUp: true)],
      );
      expect(next(linear, [warm]).kind, PrescriptionKind.first);
    });
  });

  group('off', () {
    test('repeats the last weight with the rule reps', () {
      final rule = linear.copyWith(policy: ProgressionPolicy.off);
      final p = next(rule, [
        session(1, [(60, 5), (60, 5), (60, 2)]),
      ]);
      expect(p.kind, PrescriptionKind.off);
      expect(p.weightKg, 60);
      expect(p.sets, 3);
      expect(p.reps, 5);
      expect(p.basedOn?.id, 's1');
      expect(p.why, 'Progression is off: same prescription as last time.');
      expect(ProgressionEngine.stallCount(rule, const []), 0);
    });

    test('has no weight without history', () {
      final rule = double_.copyWith(policy: ProgressionPolicy.off);
      final p = next(rule, const []);
      expect(p.kind, PrescriptionKind.off);
      expect(p.weightKg, isNull);
      expect(p.reps, 12);
      expect(p.repsMin, 8);
    });
  });

  group('linear', () {
    test('every set at target goes up by the increment', () {
      final p = next(linear, [
        session(1, [(60, 5), (60, 5), (60, 5)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 62.5);
      expect(p.reps, 5);
      expect(p.sets, 3);
      expect(p.basedOn?.id, 's1');
      expect(p.why, 'All 3 sets hit 5 at 60 kg last time, so add 2.5 kg.');
    });

    test('a missed rep holds the weight', () {
      final p = next(linear, [
        session(1, [(60, 5), (60, 5), (60, 4)]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.weightKg, 60);
      expect(
        p.why,
        'You got 5, 5, 4 at 60 kg, miss 1 of 3: hold the weight and chase 5.',
      );
    });

    test('fewer sets than asked is a miss', () {
      final p = next(linear, [
        session(1, [(60, 5), (60, 5)]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.why, contains('only 2 of 3 sets at 60 kg (5, 5)'));
    });

    test('sets below the session weight do not count', () {
      final p = next(linear, [
        session(1, [(60, 5), (60, 5), (55, 5)]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.weightKg, 60);
    });

    test('extra sets beyond the rule count towards the verdict', () {
      final p = next(linear, [
        session(1, [(60, 5), (60, 5), (60, 5), (60, 5)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.why, startsWith('All 4 sets hit 5'));
    });

    test('three misses at one weight deload 10 % snapped down', () {
      final history = repeat(1, 3, [(60, 5), (60, 4), (60, 3)]);
      expect(ProgressionEngine.stallCount(linear, history), 3);
      final p = next(linear, history);
      expect(p.kind, PrescriptionKind.deload);
      expect(p.weightKg, 52.5); // 54 snapped down to the 2.5 grid
      expect(p.reps, 5);
      expect(p.basedOn?.id, 's3');
      expect(
        p.why,
        'Missed reps 3 sessions running at 60 kg, so deload 10 % to 52.5 kg.',
      );
    });

    test('a weight change resets the streak', () {
      final history = [
        ...repeat(1, 2, [(60, 5), (60, 4), (60, 3)]),
        session(3, [(62.5, 5), (62.5, 4), (62.5, 3)]),
      ];
      expect(ProgressionEngine.stallCount(linear, history), 1);
      final p = next(linear, history);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.weightKg, 62.5);
      expect(p.why, contains('miss 1 of 3'));
    });

    test('a hit between misses breaks the streak', () {
      final history = [
        session(1, [(60, 5), (60, 4), (60, 3)]),
        session(2, [(60, 5), (60, 5), (60, 5)]),
        session(3, [(60, 5), (60, 4), (60, 3)]),
        session(4, [(60, 5), (60, 4), (60, 3)]),
      ];
      expect(ProgressionEngine.stallCount(linear, history), 2);
      expect(next(linear, history).kind, PrescriptionKind.hold);
    });

    test('history order does not matter', () {
      final history = [
        session(3, [(60, 5), (60, 4), (60, 3)]),
        session(1, [(55, 5), (55, 5), (55, 5)]),
        session(2, [(60, 5), (60, 5), (60, 4)]),
      ];
      final p = next(linear, history);
      expect(p.basedOn?.id, 's3');
      expect(p.kind, PrescriptionKind.hold);
      expect(ProgressionEngine.stallCount(linear, history), 2);
    });

    test('a deload never lands above the current weight minus one step', () {
      final rule = linear.copyWith(deloadFraction: 0.01);
      final p = next(rule, repeat(1, 3, [(61, 4), (61, 4), (61, 4)]));
      // 1 % of 61 is 60.39, which snaps to 60, but that is less than one
      // increment below 61, so it drops to 57.5.
      expect(p.weightKg, 57.5);
    });

    test('a deload floors at one increment', () {
      final p = next(linear, repeat(1, 3, [(2.5, 4), (2.5, 4), (2.5, 4)]));
      expect(p.kind, PrescriptionKind.deload);
      expect(p.weightKg, 2.5);
    });

    test('a custom stall limit is honoured', () {
      final rule = linear.copyWith(stallLimit: 2);
      final p = next(rule, repeat(1, 2, [(60, 4), (60, 4), (60, 4)]));
      expect(p.kind, PrescriptionKind.deload);
    });
  });

  group('linear at bodyweight', () {
    const rule = ProgressionRule(
      policy: ProgressionPolicy.linear,
      repsMin: 12,
      repsMax: 12,
      sets: 3,
    );

    test('up means one more rep', () {
      final p = next(rule, [
        session(1, [(0, 12), (0, 12), (0, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 0);
      expect(p.reps, 13);
      expect(
        p.why,
        'All 3 sets hit 12 at bodyweight last time, so aim for 13 reps.',
      );
    });

    test('a miss holds the rep target', () {
      final p = next(rule, [
        session(1, [(0, 12), (0, 10), (0, 9)]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.weightKg, 0);
      expect(p.reps, 12);
      expect(
        p.why,
        'You got 12, 10, 9 at bodyweight, miss 1 of 3: hold and chase 12.',
      );
    });

    test('a stall eases the rep target instead of the weight', () {
      final p = next(rule, repeat(1, 3, [(0, 10), (0, 9), (0, 8)]));
      expect(p.kind, PrescriptionKind.deload);
      expect(p.weightKg, 0);
      expect(p.reps, 10);
      expect(p.why, contains('ease the target 10 % to 10 reps'));
    });
  });

  group('greyskull', () {
    test('beating the target on the last set adds one increment', () {
      final p = next(greyskull, [
        session(1, [(60, 5), (60, 5), (60, 7)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 62.5);
      expect(
        p.why,
        'Last set went 7 against a 5 target at 60 kg with the earlier sets '
        'at 5, 5, so add 2.5 kg.',
      );
    });

    test('exactly the target on the last set still goes up', () {
      final p = next(greyskull, [
        session(1, [(60, 5), (60, 5), (60, 5)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 62.5);
    });

    test('doubling the target on the last set adds two increments', () {
      final p = next(greyskull, [
        session(1, [(60, 5), (60, 5), (60, 10)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 65);
      expect(
        p.why,
        'Last set went 10, double the 5 target, at 60 kg with the earlier '
        'sets at 5, 5, so add 5 kg.',
      );
    });

    test('a single miss deloads at once', () {
      final history = [
        session(1, [(60, 5), (60, 5), (60, 4)]),
      ];
      expect(ProgressionEngine.stallCount(greyskull, history), 1);
      final p = next(greyskull, history);
      expect(p.kind, PrescriptionKind.deload);
      expect(p.weightKg, 52.5);
      expect(
        p.why,
        'You got 5, 5, 4 at 60 kg against a 5 target, and Greyskull resets '
        'on the first miss, so deload 10 % to 52.5 kg.',
      );
    });

    test('a missed straight set deloads even with a big last set', () {
      final p = next(greyskull, [
        session(1, [(60, 5), (60, 4), (60, 10)]),
      ]);
      expect(p.kind, PrescriptionKind.deload);
    });

    test('fewer sets than asked deloads', () {
      final p = next(greyskull, [
        session(1, [(60, 5), (60, 8)]),
      ]);
      expect(p.kind, PrescriptionKind.deload);
    });

    test('at bodyweight the jump is in reps', () {
      final p = next(greyskull, [
        session(1, [(0, 5), (0, 5), (0, 10)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 0);
      expect(p.reps, 7);
    });
  });

  group('double progression', () {
    test('the top of the range in every set goes up and resets the range', () {
      final p = next(double_, [
        session(1, [(40, 12), (40, 12), (40, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 42.5);
      expect(p.reps, 12);
      expect(p.repsMin, 8);
      expect(p.repLabel, '8–12');
      expect(
        p.why,
        'All 3 sets hit 12 at 40 kg last time, so add 2.5 kg and start '
        'again at 8–12.',
      );
    });

    test('inside the range holds the weight', () {
      final history = [
        session(1, [(40, 10), (40, 9), (40, 8)]),
      ];
      expect(ProgressionEngine.stallCount(double_, history), 0);
      final p = next(double_, history);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.weightKg, 40);
      expect(p.reps, 12);
      expect(p.repsMin, 8);
      expect(
        p.why,
        'You got 10, 9, 8 at 40 kg, your first go at this weight: hold the '
        'weight and chase 12.',
      );
    });

    test('a set under the bottom of the range is a miss', () {
      final p = next(double_, [
        session(1, [(40, 12), (40, 12), (40, 7)]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
    });

    test('not beating the best set at this weight is a stall', () {
      final history = repeat(1, 2, [(40, 10), (40, 9), (40, 8)]);
      expect(ProgressionEngine.stallCount(double_, history), 1);
      final p = next(double_, history);
      expect(p.kind, PrescriptionKind.hold);
      expect(
        p.why,
        'You got 10, 9, 8 at 40 kg, no better than your best 10 here '
        '(stall 1 of 3): hold the weight and chase 12.',
      );
    });

    test('beating the best set breaks the streak', () {
      final history = [
        ...repeat(1, 3, [(40, 10), (40, 9), (40, 8)]),
        session(4, [(40, 11), (40, 9), (40, 8)]),
      ];
      expect(ProgressionEngine.stallCount(double_, history), 0);
      final p = next(double_, history);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.why, contains('best set up from 10'));
    });

    test('three stalls deload', () {
      final history = repeat(1, 4, [(40, 10), (40, 9), (40, 8)]);
      expect(ProgressionEngine.stallCount(double_, history), 3);
      final p = next(double_, history);
      expect(p.kind, PrescriptionKind.deload);
      expect(p.weightKg, 35);
      expect(p.reps, 12);
      expect(p.repsMin, 8);
      expect(
        p.why,
        'Stalled 3 sessions running at 40 kg (best set 10, target 12), so '
        'deload 10 % to 35 kg.',
      );
    });

    test('earlier sessions at the same weight count towards the best', () {
      final history = [
        session(1, [(40, 11), (40, 9), (40, 8)]),
        session(2, [(42.5, 8), (42.5, 7), (42.5, 6)]),
        session(3, [(40, 11), (40, 10), (40, 9)]),
      ];
      // Best at 40 kg before session 3 was 11; 11 is not better.
      expect(ProgressionEngine.stallCount(double_, history), 1);
    });

    test('at bodyweight up means one more rep', () {
      final p = next(double_, [
        session(1, [(0, 12), (0, 12), (0, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 0);
      expect(p.reps, 13);
      expect(p.repsMin, 8);
    });
  });

  group('triple progression', () {
    test('all sets at the top adds a set before any weight', () {
      final p = next(triple, [
        session(1, [(20, 12), (20, 12), (20, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 20);
      expect(p.sets, 4);
      expect(p.reps, 12);
      expect(p.repsMin, 8);
      expect(
        p.why,
        'All 3 sets hit 12 at 20 kg last time, so add a set: 4 × 8–12 (the '
        'weight goes up after 5 sets).',
      );
    });

    test('keeps adding sets up to setsMax', () {
      final p = next(triple, [
        session(1, [(20, 12), (20, 12), (20, 12), (20, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 20);
      expect(p.sets, 5);
    });

    test('all of setsMax at the top goes up and returns to the base sets', () {
      final p = next(triple, [
        session(1, [(20, 12), (20, 12), (20, 12), (20, 12), (20, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 22.5);
      expect(p.sets, 3);
      expect(
        p.why,
        'All 5 sets hit 12 at 20 kg last time, so add 2.5 kg and go back to '
        '3 sets at 8–12.',
      );
    });

    test('a hold keeps the set count reached', () {
      final p = next(triple, [
        session(1, [(20, 12), (20, 12), (20, 12), (20, 10)]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.weightKg, 20);
      expect(p.sets, 4);
      expect(p.why, contains('chase 12 in all 4 sets'));
    });

    test('a hold never asks for fewer than the base sets', () {
      final p = next(triple, [
        session(1, [(20, 12), (20, 10)]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.sets, 3);
    });

    test('without setsMax it behaves like double progression', () {
      final rule = triple.copyWith(clearSetsMax: true);
      final p = next(rule, [
        session(1, [(20, 12), (20, 12), (20, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 22.5);
      expect(p.sets, 3);
    });

    test('a deload returns to the base sets', () {
      final history = repeat(1, 4, [(20, 10), (20, 10), (20, 10), (20, 9)]);
      expect(ProgressionEngine.stallCount(triple, history), 3);
      final p = next(triple, history);
      expect(p.kind, PrescriptionKind.deload);
      expect(p.weightKg, 17.5);
      expect(p.sets, 3);
    });

    test('at bodyweight the final step is one more rep', () {
      final p = next(triple, [
        session(1, [(0, 12), (0, 12), (0, 12), (0, 12), (0, 12)]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 0);
      expect(p.reps, 13);
      expect(p.sets, 3);
    });
  });

  group('time', () {
    test('every hold at target adds the step', () {
      final p = next(time, [
        timed(1, [30, 32, 30]),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.seconds, 35);
      expect(p.sets, 3);
      expect(p.weightKg, 0);
      expect(p.basedOn?.id, 't1');
      expect(
        p.why,
        'All 3 holds reached 30 s last time (30, 32, 30 s), so add 5 s: aim '
        'for 35 s.',
      );
    });

    test('a short hold keeps the target', () {
      final history = [
        timed(1, [30, 28, 25]),
      ];
      expect(ProgressionEngine.stallCount(time, history), 1);
      final p = next(time, history);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.seconds, 30);
      expect(
        p.why,
        'You held 30, 28, 25 s against a 30 s target, miss 1 of 3: hold at '
        '30 s.',
      );
    });

    test('fewer holds than asked is a miss', () {
      final p = next(time, [
        timed(1, [30, 30]),
      ]);
      expect(p.kind, PrescriptionKind.hold);
      expect(p.why, contains('only 2 of 3 holds (30, 30 s)'));
    });

    test('three misses ease the target back by the step', () {
      final history = [
        for (var i = 1; i <= 3; i++) timed(i, [25, 25, 25]),
      ];
      expect(ProgressionEngine.stallCount(time, history), 3);
      final p = next(time, history);
      expect(p.kind, PrescriptionKind.deload);
      expect(p.seconds, 25);
      expect(
        p.why,
        'Missed 30 s 3 sessions running, so ease back 5 s to 25 s.',
      );
    });

    test('the target never drops below 10 s', () {
      final rule = time.copyWith(seconds: 12);
      final history = [
        for (var i = 1; i <= 3; i++) timed(i, [5, 5, 5]),
      ];
      final p = next(rule, history);
      expect(p.kind, PrescriptionKind.deload);
      expect(p.seconds, 10);
      expect(p.why, contains('ease back 2 s to 10 s'));
      final floor = next(time.copyWith(seconds: 10), history);
      expect(floor.seconds, 10);
      expect(floor.why, contains('10 s is the floor'));
    });

    test('the logged load is passed through', () {
      final p = next(time, [
        timed(1, [40, 40, 40], weightKg: 10),
      ]);
      expect(p.kind, PrescriptionKind.up);
      expect(p.weightKg, 10);
    });

    test('a hit between misses breaks the streak', () {
      final history = [
        timed(1, [20, 20, 20]),
        timed(2, [30, 30, 30]),
        timed(3, [20, 20, 20]),
      ];
      expect(ProgressionEngine.stallCount(time, history), 1);
    });
  });

  group('snapping', () {
    test('snap goes to the nearest multiple', () {
      expect(ProgressionEngine.snap(61, 2.5), 60);
      expect(ProgressionEngine.snap(61.3, 2.5), 62.5);
      expect(ProgressionEngine.snap(61.3, 1.25), 61.25);
      expect(ProgressionEngine.snap(52.5, 2.5), 52.5);
      expect(ProgressionEngine.snap(7, 2), 8);
    });

    test('snapDown never rounds up', () {
      expect(ProgressionEngine.snapDown(54, 2.5), 52.5);
      expect(ProgressionEngine.snapDown(52.5, 2.5), 52.5);
      expect(ProgressionEngine.snapDown(54.99, 5), 50);
      expect(ProgressionEngine.snapDown(0.3, 2.5), 0);
    });

    test('a non-positive step just rounds to two decimals', () {
      expect(ProgressionEngine.snap(61.237, 0), 61.24);
      expect(ProgressionEngine.snapDown(61.237, -1), 61.24);
    });
  });
}
