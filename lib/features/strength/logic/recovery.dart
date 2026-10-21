import 'dart:math' as math;

import '../../../models/exercise.dart';
import '../../../models/workout_session.dart';
import '../../pt/models/movement.dart';
import '../../pt/models/muscle_group.dart';
import '../../pt/models/pt_record.dart';
import '../models/lift_log.dart';

/// How recovered a muscle group is right now.
enum MuscleState {
  fresh('Fresh'),
  recovering('Recovering'),
  trained('Worked');

  const MuscleState(this.label);

  final String label;
}

/// Recovery snapshot for one muscle group.
class MuscleStatus {
  const MuscleStatus({
    required this.state,
    required this.fatigue,
    this.lastTrained,
    this.hardSets7d = 0,
  });

  /// Never trained (or cardio / mobility, which never accumulate fatigue).
  static const fresh = MuscleStatus(state: MuscleState.fresh, fatigue: 0);

  final MuscleState state;

  /// Decayed stimulus, 0 when fully recovered. One full session of 8 hard
  /// sets is 1.0 at the moment it ends; it can exceed 1 after back-to-back
  /// sessions.
  final double fatigue;

  /// Start of the most recent occasion that loaded this muscle; null when
  /// it never has been.
  final DateTime? lastTrained;

  /// Weighted hard sets over the last 7 days (primary 1.0, secondary 0.4).
  final double hardSets7d;

  @override
  String toString() =>
      'MuscleStatus(${state.name}, fatigue ${fatigue.toStringAsFixed(2)}, '
      'last $lastTrained, 7d ${hardSets7d.toStringAsFixed(1)})';
}

/// Recovery model over everything the app logs: lift entries, MY PT
/// sessions and camera sets. Each training occasion deposits hard sets on
/// the muscles it loads; the stimulus then decays with a per-muscle
/// half-life (big legs muscles recover more slowly than arms).
abstract final class MuscleRecovery {
  /// Occasions older than this are ignored for fatigue.
  static const window = Duration(days: 30);

  /// Window for [MuscleStatus.hardSets7d].
  static const recentWindow = Duration(days: 7);

  static const primaryWeight = 1.0;
  static const secondaryWeight = 0.4;

  /// Hard-set cap per muscle per occasion: a 30-set arm day does not mean
  /// a week of recovery.
  static const maxSetsPerOccasion = 12.0;

  /// Sets that equal one full stimulus (fatigue 1.0).
  static const setsPerFullStimulus = 8.0;

  /// Fatigue above this reads as "worked"; at or above
  /// [recoveringThreshold] as "recovering".
  static const trainedThreshold = 0.5;
  static const recoveringThreshold = 0.25;

  /// Camera sets: every 10 reps (or seconds) count as one hard set.
  static const repsPerSet = 10;

  /// Groups that never accumulate fatigue.
  static const neverTrained = {MuscleGroup.cardio, MuscleGroup.mobility};

  /// Which muscles the camera exercises load.
  static const Map<
    ExerciseType,
    ({Set<MuscleGroup> primary, Set<MuscleGroup> secondary})
  >
  exerciseMuscles = {
    ExerciseType.pushUp: (
      primary: {MuscleGroup.chest, MuscleGroup.triceps},
      secondary: {MuscleGroup.shoulders, MuscleGroup.core},
    ),
    ExerciseType.squat: (
      primary: {MuscleGroup.quads, MuscleGroup.glutes},
      secondary: {},
    ),
    ExerciseType.lunge: (
      primary: {MuscleGroup.quads, MuscleGroup.glutes},
      secondary: {MuscleGroup.hamstrings},
    ),
    ExerciseType.sitUp: (primary: {MuscleGroup.core}, secondary: {}),
    ExerciseType.burpee: (
      primary: {MuscleGroup.chest, MuscleGroup.quads, MuscleGroup.cardio},
      secondary: {MuscleGroup.core},
    ),
    ExerciseType.jumpingJack: (
      primary: {MuscleGroup.cardio},
      secondary: {MuscleGroup.calves, MuscleGroup.shoulders},
    ),
    ExerciseType.plank: (primary: {MuscleGroup.core}, secondary: {}),
    ExerciseType.gluteBridge: (
      primary: {MuscleGroup.glutes},
      secondary: {MuscleGroup.hamstrings},
    ),
    ExerciseType.wallSit: (primary: {MuscleGroup.quads}, secondary: {}),
    ExerciseType.highKnees: (
      primary: {MuscleGroup.cardio},
      secondary: {MuscleGroup.quads},
    ),
    ExerciseType.mountainClimber: (
      primary: {MuscleGroup.core},
      secondary: {MuscleGroup.cardio},
    ),
    ExerciseType.tricepDip: (
      primary: {MuscleGroup.triceps},
      secondary: {MuscleGroup.chest},
    ),
    ExerciseType.squatJump: (
      primary: {MuscleGroup.quads, MuscleGroup.glutes},
      secondary: {MuscleGroup.calves},
    ),
  };

  /// How long the stimulus takes to halve.
  static Duration halfLife(MuscleGroup muscle) => switch (muscle) {
    MuscleGroup.quads ||
    MuscleGroup.hamstrings ||
    MuscleGroup.glutes ||
    MuscleGroup.calves => const Duration(hours: 48),
    MuscleGroup.chest || MuscleGroup.back => const Duration(hours: 30),
    _ => const Duration(hours: 24),
  };

  /// Status of every muscle group at [now]. The map always holds all
  /// [MuscleGroup] values; cardio and mobility are always fresh.
  static Map<MuscleGroup, MuscleStatus> compute({
    required Iterable<LiftEntry> lifts,
    required Iterable<PtRecord> ptRecords,
    required Iterable<WorkoutSession> sessions,
    required DateTime now,
  }) {
    final occasions = <_Occasion>[
      for (final lift in lifts) ?_fromLift(lift),
      for (final record in ptRecords) ?_fromPtRecord(record),
      for (final session in sessions) ?_fromSession(session),
    ];

    final fatigue = <MuscleGroup, double>{};
    final hardSets7d = <MuscleGroup, double>{};
    final lastTrained = <MuscleGroup, DateTime>{};

    for (final occasion in occasions) {
      var age = now.difference(occasion.at);
      if (age.isNegative) age = Duration.zero;
      final inWindow = age <= window;
      final recent = age <= recentWindow;

      for (final entry in occasion.sets.entries) {
        final muscle = entry.key;
        if (neverTrained.contains(muscle)) continue;
        final sets = math.min(entry.value, maxSetsPerOccasion);
        if (sets <= 0) continue;

        final last = lastTrained[muscle];
        if (last == null || occasion.at.isAfter(last)) {
          lastTrained[muscle] = occasion.at;
        }
        if (!inWindow) continue;

        final halfLives = age.inMilliseconds / halfLife(muscle).inMilliseconds;
        final stimulus =
            sets / setsPerFullStimulus * math.pow(0.5, halfLives).toDouble();
        fatigue[muscle] = (fatigue[muscle] ?? 0) + stimulus;
        if (recent) hardSets7d[muscle] = (hardSets7d[muscle] ?? 0) + sets;
      }
    }

    return {
      for (final muscle in MuscleGroup.values)
        muscle: neverTrained.contains(muscle)
            ? MuscleStatus.fresh
            : MuscleStatus(
                state: stateFor(fatigue[muscle] ?? 0),
                fatigue: fatigue[muscle] ?? 0,
                lastTrained: lastTrained[muscle],
                hardSets7d: hardSets7d[muscle] ?? 0,
              ),
    };
  }

  static MuscleState stateFor(double fatigue) => fatigue > trainedThreshold
      ? MuscleState.trained
      : fatigue >= recoveringThreshold
      ? MuscleState.recovering
      : MuscleState.fresh;

  /// Fresh muscles worth training next, the longest-rested first (never
  /// trained before anything else). Cardio and mobility are left out.
  static List<MuscleGroup> suggestNext(
    Map<MuscleGroup, MuscleStatus> statuses,
  ) {
    final fresh = [
      for (final e in statuses.entries)
        if (!neverTrained.contains(e.key) && e.value.state == MuscleState.fresh)
          e.key,
    ];
    fresh.sort((a, b) {
      final la = statuses[a]!.lastTrained;
      final lb = statuses[b]!.lastTrained;
      if (la == null && lb == null) return a.index.compareTo(b.index);
      if (la == null) return -1;
      if (lb == null) return 1;
      final byDate = la.compareTo(lb);
      return byDate != 0 ? byDate : a.index.compareTo(b.index);
    });
    return fresh;
  }

  static _Occasion? _fromLift(LiftEntry lift) {
    final movement = lift.movement;
    if (movement == null) return null;
    final sets = lift.workSets.length.toDouble();
    if (sets <= 0) return null;
    return _Occasion(lift.startTime)
      ..add(movement.primary, movement.secondary, sets);
  }

  static _Occasion? _fromPtRecord(PtRecord record) {
    final occasion = _Occasion(record.startTime);
    for (final item in record.items) {
      if (item.skipped || item.phase != PlanPhase.main || item.setsDone <= 0) {
        continue;
      }
      final movement = item.movement;
      if (movement == null) continue;
      occasion.add(
        movement.primary,
        movement.secondary,
        item.setsDone.toDouble(),
      );
    }
    return occasion.sets.isEmpty ? null : occasion;
  }

  static _Occasion? _fromSession(WorkoutSession session) {
    if (session.completedReps <= 0) return null;
    final muscles = exerciseMuscles[session.exercise];
    if (muscles == null) return null;
    final sets = math.max(1.0, session.completedReps / repsPerSet);
    return _Occasion(session.startTime)
      ..add(muscles.primary, muscles.secondary, sets);
  }
}

/// One training occasion: when it happened and the weighted hard sets it
/// put on each muscle.
class _Occasion {
  _Occasion(this.at);

  final DateTime at;
  final Map<MuscleGroup, double> sets = {};

  void add(Set<MuscleGroup> primary, Set<MuscleGroup> secondary, double n) {
    for (final m in primary) {
      sets[m] = (sets[m] ?? 0) + n * MuscleRecovery.primaryWeight;
    }
    for (final m in secondary) {
      if (primary.contains(m)) continue;
      sets[m] = (sets[m] ?? 0) + n * MuscleRecovery.secondaryWeight;
    }
  }
}
