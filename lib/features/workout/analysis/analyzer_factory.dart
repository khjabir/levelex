import '../../../core/constants/app_constants.dart';
import '../../../models/exercise.dart';
import '../push_up_analyzer.dart';
import 'floor_analyzers.dart';
import 'leg_analyzers.dart';
import 'plank_analyzer.dart';

/// Builds the analyzer for an exercise.
abstract final class ExerciseAnalyzerFactory {
  static ExerciseAnalyzer create(
    ExerciseType type, {
    required PushUpThresholds thresholds,
    required int target,
  }) => switch (type) {
    ExerciseType.pushUp => PushUpAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.squat => SquatAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.lunge => LungeAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.sitUp => SitUpAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.burpee => BurpeeAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.jumpingJack => JumpingJackAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.plank => PlankAnalyzer(
      thresholds: thresholds,
      targetSeconds: target,
    ),
  };
}
