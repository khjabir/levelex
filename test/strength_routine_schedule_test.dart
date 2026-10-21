import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/routine_schedule.dart';
import 'package:levelex/features/strength/models/routine.dart';

const dayA = RoutineDay(id: 'a', name: 'A');
const dayB = RoutineDay(id: 'b', name: 'B');
const dayC = RoutineDay(id: 'c', name: 'C');

final weekly = Routine(
  id: 'w',
  name: 'Weekly',
  days: const [dayA, dayB],
  weekdays: const {DateTime.monday: 'a', DateTime.thursday: 'b'},
  createdAt: DateTime(2026, 1, 1),
);

final rotating = Routine(
  id: 'r',
  name: 'Rotation',
  days: const [dayA, dayB, dayC],
  schedule: RoutineSchedule.rotation,
  createdAt: DateTime(2026, 1, 1),
);

RoutineRun run(String routineId, String dayId, DateTime at) =>
    (routineId: routineId, dayId: dayId, at: at);

// 2026-10-12 is a Monday.
final monday = DateTime(2026, 10, 12, 9);
final tuesday = DateTime(2026, 10, 13, 9);
final wednesday = DateTime(2026, 10, 14, 9);
final thursday = DateTime(2026, 10, 15, 9);
final sunday = DateTime(2026, 10, 18, 9);

void main() {
  group('weekdays schedule', () {
    test('dayFor follows the weekday map', () {
      expect(RoutineScheduler.dayFor(weekly, monday, const [])?.id, 'a');
      expect(RoutineScheduler.dayFor(weekly, thursday, const [])?.id, 'b');
      expect(RoutineScheduler.dayFor(weekly, tuesday, const []), isNull);
      expect(RoutineScheduler.dayFor(weekly, sunday, const []), isNull);
    });

    test('rest days are the unmapped weekdays', () {
      expect(RoutineScheduler.isRestDay(weekly, monday), isFalse);
      expect(RoutineScheduler.isRestDay(weekly, tuesday), isTrue);
      expect(RoutineScheduler.isRestDay(weekly, sunday), isTrue);
    });

    test('a weekday pointing at a deleted day is a rest day', () {
      final broken = weekly.copyWith(days: const [dayA]);
      expect(RoutineScheduler.dayFor(broken, thursday, const []), isNull);
      expect(RoutineScheduler.isRestDay(broken, thursday), isTrue);
    });

    test('nextTrainingDate includes today and returns local midnight', () {
      expect(
        RoutineScheduler.nextTrainingDate(weekly, monday),
        DateTime(2026, 10, 12),
      );
      expect(
        RoutineScheduler.nextTrainingDate(weekly, tuesday),
        DateTime(2026, 10, 15),
      );
      // Sunday rolls over into next week's Monday.
      expect(
        RoutineScheduler.nextTrainingDate(weekly, sunday),
        DateTime(2026, 10, 19),
      );
      final empty = weekly.copyWith(weekdays: const {});
      expect(RoutineScheduler.nextTrainingDate(empty, monday), isNull);
    });

    test('weekProgress counts distinct days in the Mon–Sun week', () {
      final runs = [
        run('w', 'a', monday),
        run('w', 'a', monday.add(const Duration(hours: 2))),
        run('w', 'b', thursday),
        run('other', 'a', wednesday),
        run('w', 'a', DateTime(2026, 10, 19, 7)), // next Monday
        run('w', 'b', DateTime(2026, 10, 11, 23)), // previous Sunday
      ];
      expect(RoutineScheduler.weekProgress(weekly, wednesday, runs), 2);
      expect(RoutineScheduler.weekProgress(weekly, sunday, runs), 2);
      expect(
        RoutineScheduler.weekProgress(weekly, DateTime(2026, 10, 19), runs),
        1,
      );
      expect(
        RoutineScheduler.weekProgress(weekly, DateTime(2026, 10, 11), runs),
        1,
      );
      expect(RoutineScheduler.weekProgress(weekly, monday, const []), 0);
    });

    test('weekStart is the Monday at midnight', () {
      expect(RoutineScheduler.weekStart(sunday), DateTime(2026, 10, 12));
      expect(RoutineScheduler.weekStart(monday), DateTime(2026, 10, 12));
    });
  });

  group('rotation schedule', () {
    test('starts with the first day and never rests', () {
      expect(RoutineScheduler.dayFor(rotating, monday, const [])?.id, 'a');
      expect(RoutineScheduler.isRestDay(rotating, monday), isFalse);
      expect(RoutineScheduler.isRestDay(rotating, sunday), isFalse);
      expect(
        RoutineScheduler.nextTrainingDate(rotating, tuesday),
        DateTime(2026, 10, 13),
      );
    });

    test('advances past the most recent run and wraps', () {
      final runs = [run('r', 'a', monday)];
      expect(RoutineScheduler.dayFor(rotating, tuesday, runs)?.id, 'b');

      final more = [
        run('r', 'a', monday),
        run('r', 'b', tuesday),
        run('r', 'c', wednesday),
      ];
      expect(RoutineScheduler.dayFor(rotating, thursday, more)?.id, 'a');

      // Order of the input does not matter; the latest run wins.
      final shuffled = [more[2], more[0], more[1]];
      expect(RoutineScheduler.dayFor(rotating, thursday, shuffled)?.id, 'a');
    });

    test('a run earlier today still moves the rotation on', () {
      final runs = [run('r', 'a', monday)];
      expect(
        RoutineScheduler.dayFor(
          rotating,
          monday.add(const Duration(hours: 3)),
          runs,
        )?.id,
        'b',
      );
      // Looking back at a day before the run shows the day it started with.
      expect(
        RoutineScheduler.dayFor(rotating, DateTime(2026, 10, 11), runs)?.id,
        'a',
      );
    });

    test('ignores other routines and unknown day ids', () {
      expect(
        RoutineScheduler.dayFor(rotating, tuesday, [run('w', 'b', monday)])?.id,
        'a',
      );
      expect(
        RoutineScheduler.dayFor(rotating, tuesday, [
          run('r', 'zzz', monday),
        ])?.id,
        'a',
      );
    });

    test('an empty rotation has nothing to offer', () {
      final empty = rotating.copyWith(days: const []);
      expect(RoutineScheduler.dayFor(empty, monday, const []), isNull);
      expect(RoutineScheduler.nextTrainingDate(empty, monday), isNull);
    });
  });
}
