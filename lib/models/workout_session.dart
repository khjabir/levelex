import 'exercise.dart';
import 'form_status.dart';

/// Outcome of a workout session.
enum SessionStatus {
  /// The user reached the target rep count.
  completed,

  /// The user finished early with fewer reps than the target.
  incomplete,

  /// A reminder passed without any workout.
  skipped;

  static SessionStatus fromName(String? name) =>
      SessionStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => SessionStatus.incomplete,
      );
}

/// One set of an exercise (or a recorded skipped reminder).
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.targetReps,
    required this.completedReps,
    required this.status,
    this.formScore,
    this.exercise = ExerciseType.pushUp,
    this.mistakes = const {},
    this.verified = true,
  });

  final String id;

  /// Which exercise; reps are seconds for timed exercises.
  final ExerciseType exercise;
  final DateTime startTime;
  final DateTime? endTime;
  final int targetReps;
  final int completedReps;
  final SessionStatus status;

  /// Fraction of analysed frames with good form, `0..1`. Optional.
  final double? formScore;

  /// Coaching mistakes during the set (status → episodes).
  final Map<FormStatus, int> mistakes;

  /// The registered user was recognised before the set. Unverified sets are
  /// saved and shown, but never count towards the streak or XP.
  final bool verified;

  int get totalMistakes => mistakes.values.fold(0, (a, b) => a + b);

  bool get skipped => status == SessionStatus.skipped;
  bool get isCompleted => status == SessionStatus.completed;

  /// A session the user actually attempted (any reps performed).
  bool get isAttempted => !skipped && completedReps > 0;

  Duration? get duration => endTime?.difference(startTime);

  WorkoutSession copyWith({
    DateTime? endTime,
    int? completedReps,
    SessionStatus? status,
    double? formScore,
    Map<FormStatus, int>? mistakes,
  }) {
    return WorkoutSession(
      id: id,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      targetReps: targetReps,
      completedReps: completedReps ?? this.completedReps,
      status: status ?? this.status,
      formScore: formScore ?? this.formScore,
      exercise: exercise,
      mistakes: mistakes ?? this.mistakes,
      verified: verified,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'startTime': startTime.millisecondsSinceEpoch,
    'endTime': endTime?.millisecondsSinceEpoch,
    'targetReps': targetReps,
    'completedReps': completedReps,
    'status': status.name,
    'formScore': formScore,
    'exercise': exercise.id,
    'mistakes': {for (final e in mistakes.entries) e.key.name: e.value},
    'verified': verified,
  };

  factory WorkoutSession.fromMap(Map<dynamic, dynamic> map) {
    return WorkoutSession(
      id: map['id'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
      endTime: switch (map['endTime']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
      targetReps: map['targetReps'] as int,
      completedReps: map['completedReps'] as int,
      status: SessionStatus.fromName(map['status'] as String?),
      formScore: (map['formScore'] as num?)?.toDouble(),
      exercise: ExerciseType.fromId(map['exercise'] as String?),
      mistakes: switch (map['mistakes']) {
        final Map raw => {
          for (final e in raw.entries)
            for (final status in FormStatus.values)
              if (status.name == e.key && e.value is int)
                status: e.value as int,
        },
        _ => const {},
      },
      verified: (map['verified'] as bool?) ?? true,
    );
  }

  @override
  String toString() =>
      'WorkoutSession($id, $startTime, $completedReps/$targetReps, $status)';
}
