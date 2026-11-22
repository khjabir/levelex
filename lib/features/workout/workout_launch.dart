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
  DateTime? _setAt;

  /// A launch the user walked away from (closed the intro, went back) must
  /// not hijack a later, ordinary set.
  static const maxAge = Duration(minutes: 10);

  @override
  WorkoutLaunch? build() => null;

  void set(WorkoutLaunch? launch) {
    _setAt = launch == null ? null : DateTime.now();
    state = launch;
  }

  void clear() => set(null);

  /// Returns the pending launch and clears it (nothing when it is stale).
  WorkoutLaunch? consume() {
    final l = state;
    final at = _setAt;
    set(null);
    if (l == null || at == null) return null;
    return DateTime.now().difference(at) > maxAge ? null : l;
  }
}

/// Pending launch options, consumed by the workout controller on start.
final workoutLaunchProvider =
    NotifierProvider<WorkoutLaunchNotifier, WorkoutLaunch?>(
      WorkoutLaunchNotifier.new,
    );
