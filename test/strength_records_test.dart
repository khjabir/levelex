import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/one_rm.dart';
import 'package:levelex/features/strength/logic/records.dart';
import 'package:levelex/features/strength/models/lift_log.dart';

/// An entry on day [day] of January 2026 with (weight, reps) work sets.
LiftEntry entry(
  String id,
  int day,
  List<(double, int)> sets, {
  String movementId = 'db_curl',
  int hour = 9,
}) => LiftEntry(
  id: id,
  movementId: movementId,
  startTime: DateTime(2026, 1, day, hour),
  sets: [for (final (w, r) in sets) LiftSet(weightKg: w, reps: r)],
);

PersonalRecord? only(List<PersonalRecord> prs, PrKind kind) {
  final matches = prs.where((p) => p.kind == kind).toList();
  expect(matches.length, lessThanOrEqualTo(1), reason: 'one $kind at most');
  return matches.isEmpty ? null : matches.single;
}

void main() {
  group('PrKind', () {
    test('labels', () {
      expect(PrKind.weight.label, 'Heaviest set');
      expect(PrKind.reps.label, 'Most reps at a weight');
      expect(PrKind.oneRm.label, 'Best estimated 1RM');
      expect(PrKind.volume.label, 'Most volume in a session');
    });
  });

  group('PersonalRecord.label', () {
    PersonalRecord pr(PrKind kind, double value, {double? weightKg}) =>
        PersonalRecord(
          movementId: 'db_curl',
          kind: kind,
          value: value,
          date: DateTime(2026),
          entryId: 'x',
          weightKg: weightKg,
        );

    test('formats each kind', () {
      expect(pr(PrKind.weight, 22.5).label, '22.5 kg');
      expect(pr(PrKind.weight, 60).label, '60 kg');
      expect(pr(PrKind.reps, 12, weightKg: 20).label, '12 reps @ 20 kg');
      expect(pr(PrKind.reps, 15, weightKg: 0).label, '15 reps @ bodyweight');
      expect(pr(PrKind.oneRm, 60).label, 'e1RM 60 kg');
      expect(pr(PrKind.oneRm, 60.33).label, 'e1RM 60.3 kg');
      expect(pr(PrKind.volume, 1200).label, '1,200 kg volume');
      expect(pr(PrKind.volume, 1234567.5).label, '1,234,567.5 kg volume');
    });

    test('gain is the distance to the previous best', () {
      expect(pr(PrKind.weight, 22.5).gain, isNull);
      final p = PersonalRecord(
        movementId: 'db_curl',
        kind: PrKind.weight,
        value: 22.5,
        previous: 20,
        date: DateTime(2026),
        entryId: 'x',
      );
      expect(p.gain, closeTo(2.5, 1e-9));
    });

    test('formatKg groups thousands and keeps one decimal', () {
      expect(PersonalRecord.formatKg(999), '999');
      expect(PersonalRecord.formatKg(1000), '1,000');
      expect(PersonalRecord.formatKg(1234.5), '1,234.5');
      expect(PersonalRecord.formatKg(0), '0');
      expect(PersonalRecord.formatKg(-1500), '-1,500');
    });
  });

  group('RecordBook.bestsFor', () {
    test('collects the bests of one movement only', () {
      final history = [
        entry('a', 1, [(20, 10), (20, 12)]),
        entry('b', 2, [(22.5, 8), (20, 11)]),
        entry('c', 3, [(50, 10)], movementId: 'bb_bench_press'),
        entry('d', 4, [(0, 20)]),
      ];
      final bests = RecordBook.bestsFor('db_curl', history);
      expect(bests.weight, 22.5);
      expect(bests.volume, 20 * 10 + 20 * 12);
      expect(bests.oneRm, closeTo(OneRm.epley(22.5, 8), 1e-9));
      expect(bests.repsAtWeight, {20.0: 12, 22.5: 8, 0.0: 20});
      expect(bests.isEmpty, isFalse);
    });

    test('is empty for an unknown movement', () {
      final bests = RecordBook.bestsFor('nope', [
        entry('a', 1, [(20, 10)]),
      ]);
      expect(bests.isEmpty, isTrue);
      expect(bests.weight, isNull);
      expect(bests.repsAtWeight, isEmpty);
    });

    test('ignores warm-up sets', () {
      final e = LiftEntry(
        id: 'a',
        movementId: 'db_curl',
        startTime: DateTime(2026),
        sets: const [
          LiftSet(weightKg: 30, reps: 5, warmUp: true),
          LiftSet(weightKg: 20, reps: 10),
        ],
      );
      final bests = RecordBook.bestsFor('db_curl', [e]);
      expect(bests.weight, 20);
      expect(bests.repsAtWeight, {20.0: 10});
    });
  });

  group('RecordBook.detect', () {
    test(
      'a first loaded entry sets weight, 1RM and volume with no previous',
      () {
        final e = entry('a', 1, [(20, 10), (20, 10)]);
        final prs = RecordBook.detect(e, [e]);
        expect(prs.map((p) => p.kind), [
          PrKind.weight,
          PrKind.oneRm,
          PrKind.volume,
        ]);
        expect(prs.every((p) => p.previous == null), isTrue);
        expect(prs.every((p) => p.entryId == 'a'), isTrue);
        expect(prs.every((p) => p.date == e.startTime), isTrue);
        expect(only(prs, PrKind.weight)!.value, 20);
        expect(only(prs, PrKind.volume)!.value, 400);
        expect(
          only(prs, PrKind.oneRm)!.value,
          closeTo(OneRm.epley(20, 10), 1e-9),
        );
      },
    );

    test('a first bodyweight entry sets nothing', () {
      final e = entry('a', 1, [(0, 15), (0, 12)]);
      expect(RecordBook.detect(e, const []), isEmpty);
    });

    test('an entry without work sets sets nothing', () {
      final e = LiftEntry(
        id: 'a',
        movementId: 'db_curl',
        startTime: DateTime(2026),
        sets: const [LiftSet(weightKg: 50, reps: 5, warmUp: true)],
      );
      expect(RecordBook.detect(e, const []), isEmpty);
    });

    test('more reps at the same weight is a reps record', () {
      final first = entry('a', 1, [(20, 10), (20, 10)]);
      final second = entry('b', 2, [(20, 12), (20, 9)]);
      final prs = RecordBook.detect(second, [first, second]);
      final reps = only(prs, PrKind.reps)!;
      expect(reps.value, 12);
      expect(reps.previous, 10);
      expect(reps.weightKg, 20);
      expect(reps.label, '12 reps @ 20 kg');
      expect(
        only(prs, PrKind.oneRm)!.previous,
        closeTo(OneRm.epley(20, 10), 1e-9),
      );
      expect(only(prs, PrKind.volume)!.value, 20 * 12 + 20 * 9);
      expect(only(prs, PrKind.weight), isNull);
    });

    test('bodyweight reps become a record once there is something to beat', () {
      final first = entry('a', 1, [(0, 12)]);
      final second = entry('b', 2, [(0, 15)]);
      final prs = RecordBook.detect(second, [first]);
      expect(prs.length, 1);
      expect(prs.single.kind, PrKind.reps);
      expect(prs.single.weightKg, 0);
      expect(prs.single.previous, 12);
      expect(prs.single.label, '15 reps @ bodyweight');
    });

    test('a tie is not a record', () {
      final first = entry('a', 1, [(20, 10), (20, 10)]);
      final same = entry('b', 2, [(20, 10), (20, 10)]);
      expect(RecordBook.detect(same, [first]), isEmpty);
    });

    test('a heavier top set is a weight record with the previous best', () {
      final first = entry('a', 1, [(20, 10)]);
      final second = entry('b', 2, [(22.5, 8)]);
      final prs = RecordBook.detect(second, [first]);
      final w = only(prs, PrKind.weight)!;
      expect(w.value, 22.5);
      expect(w.previous, 20);
      expect(w.label, '22.5 kg');
      // No earlier set at 22.5 kg, so no reps record.
      expect(only(prs, PrKind.reps), isNull);
    });

    test('a reps record is possible at several weights in one entry', () {
      final first = entry('a', 1, [(20, 10), (15, 15)]);
      final second = entry('b', 2, [(20, 11), (15, 16)]);
      final prs = RecordBook.detect(second, [first]);
      final reps = prs.where((p) => p.kind == PrKind.reps).toList();
      expect(reps.map((p) => p.weightKg), [20, 15]);
      expect(reps.map((p) => p.value), [11, 16]);
    });

    test('ignores itself, later entries and the same instant', () {
      final target = entry('b', 2, [(20, 10)]);
      final later = entry('c', 3, [(30, 10)]);
      final sameTime = entry('d', 2, [(30, 10)]);
      final prs = RecordBook.detect(target, [target, later, sameTime]);
      expect(only(prs, PrKind.weight)!.previous, isNull);
      expect(only(prs, PrKind.weight)!.value, 20);
    });

    test('ignores other movements', () {
      final other = entry('a', 1, [(50, 10)], movementId: 'bb_bench_press');
      final e = entry('b', 2, [(20, 10)]);
      final prs = RecordBook.detect(e, [other]);
      expect(only(prs, PrKind.weight)!.previous, isNull);
    });

    test('a 1RM record can come from a lighter set with more reps', () {
      final first = entry('a', 1, [(40, 3)]); // e1RM 44
      final second = entry('b', 2, [(35, 10)]); // e1RM 46.7
      final prs = RecordBook.detect(second, [first]);
      expect(only(prs, PrKind.weight), isNull);
      expect(
        only(prs, PrKind.oneRm)!.previous,
        closeTo(OneRm.epley(40, 3), 1e-9),
      );
    });
  });

  group('RecordBook.recent', () {
    test('replays the log in time order and returns newest first', () {
      final history = [
        entry('c', 3, [(25, 8)]),
        entry('a', 1, [(20, 10)]),
        entry('b', 2, [(20, 12)]),
      ];
      final prs = RecordBook.recent(history);
      expect(prs.first.entryId, 'c');
      expect(prs.last.entryId, 'a');
      // Day 1: weight, 1RM, volume (first ever). Day 2: reps, 1RM, volume.
      // Day 3: weight, 1RM (25 × 8 → 31.7 beats 20 × 12 → 28), no volume
      // (200 < 240).
      expect(prs.where((p) => p.entryId == 'a').map((p) => p.kind), [
        PrKind.weight,
        PrKind.oneRm,
        PrKind.volume,
      ]);
      expect(prs.where((p) => p.entryId == 'b').map((p) => p.kind), [
        PrKind.reps,
        PrKind.oneRm,
        PrKind.volume,
      ]);
      expect(prs.where((p) => p.entryId == 'c').map((p) => p.kind), [
        PrKind.weight,
        PrKind.oneRm,
      ]);
      expect(prs.length, 8);
    });

    test('matches detect for every entry', () {
      final history = [
        entry('a', 1, [(20, 10)]),
        entry('b', 2, [(20, 12)]),
        entry('c', 3, [(25, 8)]),
        entry('d', 4, [(0, 20)], movementId: 'push_up'),
        entry('e', 5, [(0, 25)], movementId: 'push_up'),
      ];
      final viaRecent = RecordBook.recent(history, limit: 100);
      final viaDetect = [
        for (final e in history.reversed) ...RecordBook.detect(e, history),
      ];
      expect(
        viaRecent.map((p) => '${p.entryId}/${p.kind.name}/${p.value}'),
        viaDetect.map((p) => '${p.entryId}/${p.kind.name}/${p.value}'),
      );
    });

    test('keeps movements apart', () {
      final history = [
        entry('a', 1, [(20, 10)]),
        entry('b', 2, [(50, 5)], movementId: 'bb_bench_press'),
      ];
      final prs = RecordBook.recent(history);
      final bench = prs.where((p) => p.movementId == 'bb_bench_press');
      expect(bench.every((p) => p.previous == null), isTrue);
    });

    test('honours the limit', () {
      final history = [
        for (var d = 1; d <= 10; d++) entry('e$d', d, [(20.0 + d, 10)]),
      ];
      final prs = RecordBook.recent(history, limit: 5);
      expect(prs.length, 5);
      expect(prs.first.entryId, 'e10');
      expect(RecordBook.recent(history, limit: 0), isEmpty);
    });

    test('is empty for an empty log', () {
      expect(RecordBook.recent(const []), isEmpty);
    });
  });
}
