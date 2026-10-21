import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/exercise.dart';

/// One-shot options for the next camera set: a target that overrides the
/// saved one (daily challenge, "beat your best") and the reason to show.
class WorkoutLaunch {
  const WorkoutLaunch({
    required this.exercise,
    this.target,
    this.reason,
    this.bestToBeat,
  });

  final ExerciseType exercise;

  /// Target reps (or seconds) for this set only.
  final int? target;

  /// Short label shown on the intro and the camera, e.g. "Daily challenge".
  final String? reason;

  /// The personal best this set is trying to beat.
  final int? bestToBeat;
}

class WorkoutLaunchNotifier extends Notifier<WorkoutLaunch?> {
  @override
  WorkoutLaunch? build() => null;

  void set(WorkoutLaunch? launch) => state = launch;

  /// Returns the pending launch and clears it.
  WorkoutLaunch? consume() {
    final l = state;
    state = null;
    return l;
  }
}

/// Pending launch options, consumed by the workout controller on start.
final workoutLaunchProvider =
    NotifierProvider<WorkoutLaunchNotifier, WorkoutLaunch?>(
      WorkoutLaunchNotifier.new,
    );
