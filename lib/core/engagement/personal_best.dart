import '../../models/exercise.dart';
import '../../models/workout_session.dart';

/// The most reps (or seconds) ever done in one verified set of an exercise.
class PersonalBest {
  const PersonalBest({
    required this.exercise,
    required this.best,
    required this.date,
    required this.sessionId,
  });

  final ExerciseType exercise;

  /// Reps, or seconds for timed exercises.
  final int best;

  /// When the best set started.
  final DateTime date;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is PersonalBest &&
      other.exercise == exercise &&
      other.best == best &&
      other.date == date &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(exercise, best, date, sessionId);

  @override
  String toString() => 'PersonalBest(${exercise.id} $best on $date)';
}

/// Personal bests read from the session history. Only verified, non-skipped
/// sets with at least one rep count; unverified sets never set a best.
abstract final class PersonalBests {
  /// The best set of every exercise that has one. Ties go to the earliest
  /// set.
  static Map<ExerciseType, PersonalBest> all(
    Iterable<WorkoutSession> sessions,
  ) {
    final bests = <ExerciseType, PersonalBest>{};
    for (final s in sessions) {
      if (!_counts(s)) continue;
      final current = bests[s.exercise];
      if (current == null ||
          s.completedReps > current.best ||
          (s.completedReps == current.best &&
              s.startTime.isBefore(current.date))) {
        bests[s.exercise] = PersonalBest(
          exercise: s.exercise,
          best: s.completedReps,
          date: s.startTime,
          sessionId: s.id,
        );
      }
    }
    return bests;
  }

  /// The best set of [exercise], or null when none counts.
  static PersonalBest? forExercise(
    Iterable<WorkoutSession> sessions,
    ExerciseType exercise,
  ) => all(sessions.where((s) => s.exercise == exercise))[exercise];

  /// Whether [session] beats every other verified set of its exercise in
  /// [history] (a copy of the session itself, by id, is ignored). A tie is
  /// not a new best; the first-ever set of an exercise is.
  static bool isNewBest(
    WorkoutSession session,
    Iterable<WorkoutSession> history,
  ) {
    if (!_counts(session)) return false;
    for (final other in history) {
      if (other.id == session.id || other.exercise != session.exercise) {
        continue;
      }
      if (_counts(other) && other.completedReps >= session.completedReps) {
        return false;
      }
    }
    return true;
  }

  static bool _counts(WorkoutSession s) =>
      s.verified && !s.skipped && s.completedReps > 0;
}
