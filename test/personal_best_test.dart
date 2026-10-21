import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/engagement/personal_best.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/workout_session.dart';

WorkoutSession session(
  String id,
  DateTime at,
  int reps, {
  ExerciseType exercise = ExerciseType.pushUp,
  int target = 10,
  bool verified = true,
  SessionStatus? status,
}) => WorkoutSession(
  id: id,
  startTime: at,
  endTime: at.add(const Duration(minutes: 1)),
  targetReps: target,
  completedReps: reps,
  status:
      status ??
      (reps >= target ? SessionStatus.completed : SessionStatus.incomplete),
  exercise: exercise,
  verified: verified,
);

void main() {
  final a = session('a', DateTime(2026, 1, 1, 9), 10);
  final b = session('b', DateTime(2026, 1, 3, 9), 15);
  final c = session('c', DateTime(2026, 1, 2, 9), 15);
  final unverified = session('d', DateTime(2026, 1, 4, 9), 20, verified: false);
  final skipped = session(
    'e',
    DateTime(2026, 1, 5, 9),
    0,
    status: SessionStatus.skipped,
  );
  final squat = session(
    'g',
    DateTime(2026, 1, 1, 10),
    12,
    exercise: ExerciseType.squat,
    target: 15,
  );
  final plank = session(
    'h',
    DateTime(2026, 1, 2, 10),
    40,
    exercise: ExerciseType.plank,
    target: 30,
  );
  final history = [a, b, c, unverified, skipped, squat, plank];

  group('PersonalBests.all', () {
    test('keeps the highest verified set per exercise, earliest on ties', () {
      final all = PersonalBests.all(history);
      expect(
        all.keys,
        unorderedEquals([
          ExerciseType.pushUp,
          ExerciseType.squat,
          ExerciseType.plank,
        ]),
      );
      final push = all[ExerciseType.pushUp]!;
      expect(push.best, 15);
      expect(push.sessionId, 'c');
      expect(push.date, DateTime(2026, 1, 2, 9));
      expect(push.exercise, ExerciseType.pushUp);
      expect(all[ExerciseType.squat]!.best, 12);
      expect(all[ExerciseType.squat]!.sessionId, 'g');
      expect(all[ExerciseType.plank]!.best, 40);
    });

    test('order of the history does not matter', () {
      final reversed = PersonalBests.all(history.reversed);
      expect(reversed[ExerciseType.pushUp]!.sessionId, 'c');
    });

    test(
      'incomplete sets with reps count, zero-rep and skipped ones do not',
      () {
        final incomplete = session(
          'i',
          DateTime(2026, 1, 6, 9),
          30,
          target: 50,
        );
        final zero = session('z', DateTime(2026, 1, 7, 9), 0, target: 10);
        expect(
          PersonalBests.all([incomplete, zero])[ExerciseType.pushUp]!.best,
          30,
        );
        expect(PersonalBests.all([zero, skipped]), isEmpty);
      },
    );

    test('unverified sets never set a best', () {
      expect(PersonalBests.all([unverified]), isEmpty);
    });

    test('empty history has no bests', () {
      expect(PersonalBests.all(const []), isEmpty);
    });
  });

  group('PersonalBests.forExercise', () {
    test('returns the best of one exercise', () {
      final best = PersonalBests.forExercise(history, ExerciseType.pushUp)!;
      expect(best.best, 15);
      expect(best.sessionId, 'c');
      expect(PersonalBests.forExercise(history, ExerciseType.plank)!.best, 40);
    });

    test('is null when the exercise has no verified set', () {
      expect(PersonalBests.forExercise(history, ExerciseType.burpee), isNull);
      expect(
        PersonalBests.forExercise([unverified], ExerciseType.pushUp),
        isNull,
      );
    });
  });

  group('PersonalBests.isNewBest', () {
    test('needs strictly more reps than every other verified set', () {
      expect(
        PersonalBests.isNewBest(
          session('x', DateTime(2026, 2, 1), 16),
          history,
        ),
        isTrue,
      );
      expect(
        PersonalBests.isNewBest(
          session('x', DateTime(2026, 2, 1), 15),
          history,
        ),
        isFalse,
      );
      expect(
        PersonalBests.isNewBest(
          session('x', DateTime(2026, 2, 1), 14),
          history,
        ),
        isFalse,
      );
    });

    test('ignores the session itself when it is already in the history', () {
      final x = session('x', DateTime(2026, 2, 1), 16);
      expect(PersonalBests.isNewBest(x, [...history, x]), isTrue);
      // b ties with c, so b is not a best even though it is in the history.
      expect(PersonalBests.isNewBest(b, history), isFalse);
      // a is the only push-up set in its own history.
      expect(PersonalBests.isNewBest(a, [a, squat]), isTrue);
    });

    test('ignores unverified and skipped sets in the history', () {
      expect(
        PersonalBests.isNewBest(session('x', DateTime(2026, 2, 1), 16), [
          unverified,
          skipped,
        ]),
        isTrue,
      );
    });

    test('only compares the same exercise', () {
      final squat13 = session(
        'x',
        DateTime(2026, 2, 1),
        13,
        exercise: ExerciseType.squat,
        target: 15,
      );
      expect(PersonalBests.isNewBest(squat13, history), isTrue);
    });

    test('an unverified, skipped or empty set is never a best', () {
      expect(
        PersonalBests.isNewBest(
          session('x', DateTime(2026, 2, 1), 99, verified: false),
          history,
        ),
        isFalse,
      );
      expect(PersonalBests.isNewBest(skipped, const []), isFalse);
      expect(
        PersonalBests.isNewBest(
          session('x', DateTime(2026, 2, 1), 0),
          const [],
        ),
        isFalse,
      );
    });

    test('the first set of an exercise is a best', () {
      expect(
        PersonalBests.isNewBest(
          session('x', DateTime(2026, 2, 1), 1),
          const [],
        ),
        isTrue,
      );
    });
  });
}
