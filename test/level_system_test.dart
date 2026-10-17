import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/levels/level_system.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/workout_session.dart';

WorkoutSession session(
  int reps, {
  ExerciseType exercise = ExerciseType.pushUp,
  int target = 10,
  SessionStatus? status,
}) => WorkoutSession(
  id: '$exercise-$reps',
  startTime: DateTime(2026, 1, 1, 9),
  targetReps: target,
  completedReps: reps,
  status:
      status ??
      (reps >= target ? SessionStatus.completed : SessionStatus.incomplete),
  exercise: exercise,
);

void main() {
  group('LevelSystem', () {
    test('XP rewards reps, effort and finishing the set', () {
      expect(LevelSystem.xpForSession(session(10)), 10 * 10 + 25);
      expect(LevelSystem.xpForSession(session(4)), 40);
      expect(
        LevelSystem.xpForSession(
          session(30, exercise: ExerciseType.plank, target: 30),
        ),
        30 * 2 + 25,
      );
      expect(
        LevelSystem.xpForSession(session(0, status: SessionStatus.skipped)),
        0,
      );
    });

    test('levels start at Rookie and advance with XP', () {
      final rookie = LevelSystem.levelFor(0);
      expect(rookie.level, 1);
      expect(rookie.title, 'Rookie');
      expect(rookie.progress, 0);
      expect(rookie.xpToNext, 200);

      final almost = LevelSystem.levelFor(199);
      expect(almost.level, 1);
      expect(almost.xpToNext, 1);

      final two = LevelSystem.levelFor(200);
      expect(two.level, 2);
      expect(two.xpIntoLevel, 0);
      expect(two.xpForLevel, 350);

      final high = LevelSystem.levelFor(100000);
      expect(high.level, greaterThan(10));
      expect(high.title, 'Legend');
    });

    test('total XP sums every session', () {
      final total = LevelSystem.totalXp([
        session(10),
        session(15, exercise: ExerciseType.squat, target: 15),
      ]);
      expect(total, 125 + (15 * 6 + 25));
    });
  });
}
