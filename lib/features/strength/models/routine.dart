import '../../pt/models/workout_plan.dart';
import 'progression_rule.dart';

/// How a routine's days are scheduled.
enum RoutineSchedule {
  weekdays('Fixed weekdays', 'Each day of the plan has its own weekday.'),
  rotation('Rotation', 'Days follow each other (A, B, C…) whenever you train.');

  const RoutineSchedule(this.label, this.description);

  final String label;
  final String description;

  static RoutineSchedule fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => weekdays);
}

/// One exercise slot on a routine day.
class RoutineExercise {
  const RoutineExercise({
    required this.movementId,
    this.sets = 3,
    this.repsMin = 8,
    this.repsMax = 12,
    this.seconds,
    this.policy,
  });

  final String movementId;
  final int sets;
  final int repsMin;
  final int repsMax;

  /// Timed movements: seconds per set.
  final int? seconds;

  /// Overrides the movement's default progression policy when set.
  final ProgressionPolicy? policy;

  String get prescription => seconds != null
      ? '$sets × ${seconds}s'
      : repsMin == repsMax
      ? '$sets × $repsMax'
      : '$sets × $repsMin–$repsMax';

  RoutineExercise copyWith({
    String? movementId,
    int? sets,
    int? repsMin,
    int? repsMax,
    int? seconds,
    ProgressionPolicy? policy,
    bool clearPolicy = false,
  }) => RoutineExercise(
    movementId: movementId ?? this.movementId,
    sets: sets ?? this.sets,
    repsMin: repsMin ?? this.repsMin,
    repsMax: repsMax ?? this.repsMax,
    seconds: seconds ?? this.seconds,
    policy: clearPolicy ? null : (policy ?? this.policy),
  );

  Map<String, dynamic> toMap() => {
    'movementId': movementId,
    'sets': sets,
    'repsMin': repsMin,
    'repsMax': repsMax,
    if (seconds != null) 'seconds': seconds,
    if (policy != null) 'policy': policy!.name,
  };

  factory RoutineExercise.fromMap(Map<dynamic, dynamic> map) => RoutineExercise(
    movementId: map['movementId'] as String,
    sets: (map['sets'] as num?)?.toInt() ?? 3,
    repsMin: (map['repsMin'] as num?)?.toInt() ?? 8,
    repsMax: (map['repsMax'] as num?)?.toInt() ?? 12,
    seconds: (map['seconds'] as num?)?.toInt(),
    policy: map['policy'] == null
        ? null
        : ProgressionPolicy.fromName(map['policy'] as String?),
  );
}

/// A training day: a mode (drives warm-up and cool-down) and its exercises.
class RoutineDay {
  const RoutineDay({
    required this.id,
    required this.name,
    this.mode = WorkoutMode.fullBody,
    this.minutes = 45,
    this.exercises = const [],
  });

  final String id;
  final String name;
  final WorkoutMode mode;
  final int minutes;
  final List<RoutineExercise> exercises;

  RoutineDay copyWith({
    String? name,
    WorkoutMode? mode,
    int? minutes,
    List<RoutineExercise>? exercises,
  }) => RoutineDay(
    id: id,
    name: name ?? this.name,
    mode: mode ?? this.mode,
    minutes: minutes ?? this.minutes,
    exercises: exercises ?? this.exercises,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'mode': mode.name,
    'minutes': minutes,
    'exercises': [for (final e in exercises) e.toMap()],
  };

  factory RoutineDay.fromMap(Map<dynamic, dynamic> map) => RoutineDay(
    id: map['id'] as String,
    name: map['name'] as String? ?? 'Day',
    mode: WorkoutMode.fromName(map['mode'] as String?),
    minutes: (map['minutes'] as num?)?.toInt() ?? 45,
    exercises: [
      for (final raw in (map['exercises'] as List? ?? const []))
        if (raw is Map) RoutineExercise.fromMap(raw),
    ],
  );
}

/// A weekly programme: days plus how they are scheduled.
class Routine {
  const Routine({
    required this.id,
    required this.name,
    this.description = '',
    this.days = const [],
    this.schedule = RoutineSchedule.weekdays,
    this.weekdays = const {},
    this.starterId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final List<RoutineDay> days;
  final RoutineSchedule schedule;

  /// Weekday (DateTime.monday == 1 … sunday == 7) → day id.
  final Map<int, String> weekdays;

  /// The starter template this came from, if any.
  final String? starterId;
  final DateTime createdAt;

  RoutineDay? day(String? id) {
    for (final d in days) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Weekdays that have a training day, sorted.
  List<int> get trainingWeekdays => weekdays.keys.toList()..sort();

  Routine copyWith({
    String? name,
    String? description,
    List<RoutineDay>? days,
    RoutineSchedule? schedule,
    Map<int, String>? weekdays,
  }) => Routine(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    days: days ?? this.days,
    schedule: schedule ?? this.schedule,
    weekdays: weekdays ?? this.weekdays,
    starterId: starterId,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'days': [for (final d in days) d.toMap()],
    'schedule': schedule.name,
    'weekdays': {for (final e in weekdays.entries) '${e.key}': e.value},
    if (starterId != null) 'starterId': starterId,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Routine.fromMap(Map<dynamic, dynamic> map) => Routine(
    id: map['id'] as String,
    name: map['name'] as String? ?? 'Routine',
    description: map['description'] as String? ?? '',
    days: [
      for (final raw in (map['days'] as List? ?? const []))
        if (raw is Map) RoutineDay.fromMap(raw),
    ],
    schedule: RoutineSchedule.fromName(map['schedule'] as String?),
    weekdays: switch (map['weekdays']) {
      final Map raw => {
        for (final e in raw.entries)
          if (int.tryParse('${e.key}') != null && e.value is String)
            int.parse('${e.key}'): e.value as String,
      },
      _ => const {},
    },
    starterId: map['starterId'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num?)?.toInt() ?? 0,
    ),
  );
}
