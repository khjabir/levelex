import '../../../models/form_status.dart';
import 'movement.dart';
import 'movement_library.dart';
import 'workout_plan.dart';

/// What happened for one plan item.
class PtItemResult {
  const PtItemResult({
    required this.movementId,
    required this.phase,
    required this.setsPlanned,
    required this.setsDone,
    required this.reps,
    required this.seconds,
    required this.skipped,
    this.mistakes = const {},
  });

  final String movementId;
  final PlanPhase phase;
  final int setsPlanned;
  final int setsDone;

  /// Total reps across sets (tracked or logged).
  final int reps;

  /// Total seconds of timed work.
  final int seconds;
  final bool skipped;
  final Map<FormStatus, int> mistakes;

  Movement? get movement => MovementLibrary.byId(movementId);

  bool get completed => !skipped && setsDone >= setsPlanned;

  Map<String, dynamic> toMap() => {
    'movementId': movementId,
    'phase': phase.name,
    'setsPlanned': setsPlanned,
    'setsDone': setsDone,
    'reps': reps,
    'seconds': seconds,
    'skipped': skipped,
    'mistakes': {for (final e in mistakes.entries) e.key.name: e.value},
  };

  factory PtItemResult.fromMap(Map<dynamic, dynamic> map) => PtItemResult(
    movementId: map['movementId'] as String,
    phase: PlanPhase.values.firstWhere(
      (p) => p.name == map['phase'],
      orElse: () => PlanPhase.main,
    ),
    setsPlanned: (map['setsPlanned'] as int?) ?? 1,
    setsDone: (map['setsDone'] as int?) ?? 0,
    reps: (map['reps'] as int?) ?? 0,
    seconds: (map['seconds'] as int?) ?? 0,
    skipped: (map['skipped'] as bool?) ?? false,
    mistakes: switch (map['mistakes']) {
      final Map raw => {
        for (final e in raw.entries)
          for (final s in FormStatus.values)
            if (s.name == e.key && e.value is int) s: e.value as int,
      },
      _ => const {},
    },
  );
}

/// A finished (or abandoned) MY PT session.
class PtRecord {
  const PtRecord({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.mode,
    required this.plannedMinutes,
    required this.items,
    required this.verified,
    this.plannedItems = 0,
    this.activeSeconds,
  });

  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final WorkoutMode mode;
  final int plannedMinutes;
  final List<PtItemResult> items;

  /// The registered user was recognised when the camera first opened. XP
  /// is only awarded for verified sessions.
  final bool verified;

  /// How many items the plan had. Items the user never reached have no
  /// result, so completion is measured against this. 0 on older records.
  final int plannedItems;

  /// Time spent exercising, excluding pauses. Null on older records.
  final int? activeSeconds;

  Duration get duration => activeSeconds != null
      ? Duration(seconds: activeSeconds!)
      : endTime.difference(startTime);
  int get itemCount =>
      plannedItems > items.length ? plannedItems : items.length;
  int get itemsDone => items.where((i) => i.completed).length;
  int get totalReps => items.fold(0, (s, i) => s + i.reps);
  int get totalMistakes =>
      items.fold(0, (s, i) => s + i.mistakes.values.fold(0, (a, b) => a + b));
  double get completion => itemCount == 0 ? 0 : itemsDone / itemCount;

  /// Verified and some work was done: covers any reminder whose window the
  /// session overlaps, like an attempted push-up set.
  bool get isAttempted =>
      verified && items.any((i) => i.reps > 0 || i.seconds > 0);

  /// Verified and most of the plan finished: keeps the streak alive, like
  /// a completed push-up set.
  bool get isCompleted => verified && completion >= 0.8;

  Map<String, dynamic> toMap() => {
    'id': id,
    'startTime': startTime.millisecondsSinceEpoch,
    'endTime': endTime.millisecondsSinceEpoch,
    'mode': mode.name,
    'plannedMinutes': plannedMinutes,
    'items': [for (final i in items) i.toMap()],
    'verified': verified,
    'plannedItems': plannedItems,
    if (activeSeconds != null) 'activeSeconds': activeSeconds,
  };

  factory PtRecord.fromMap(Map<dynamic, dynamic> map) => PtRecord(
    id: map['id'] as String,
    startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
    endTime: DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int),
    mode: WorkoutMode.fromName(map['mode'] as String?),
    plannedMinutes: (map['plannedMinutes'] as int?) ?? 0,
    items: [
      for (final raw in (map['items'] as List? ?? const []))
        if (raw is Map) PtItemResult.fromMap(raw),
    ],
    verified: (map['verified'] as bool?) ?? false,
    plannedItems: (map['plannedItems'] as int?) ?? 0,
    activeSeconds: map['activeSeconds'] as int?,
  );
}
