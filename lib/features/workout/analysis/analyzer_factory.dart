import '../../../core/constants/app_constants.dart';
import '../../../models/exercise.dart';
import '../push_up_analyzer.dart';
import 'alternating_analyzer.dart';
import 'floor_analyzers.dart';
import 'generic_analyzers.dart';
import 'leg_analyzers.dart';
import 'plank_analyzer.dart';
import 'tracking_spec.dart';

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
    ExerciseType.gluteBridge => GluteBridgeAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.wallSit => GenericHoldAnalyzer(
      spec: const HoldTracking(
        joint: JointKind.knee,
        minAngle: 60,
        maxAngle: 125,
      ),
      label: type.label,
      exerciseType: type,
      thresholds: thresholds,
      targetSeconds: target,
    ),
    ExerciseType.highKnees => AlternatingKneeAnalyzer(
      exerciseType: type,
      stance: AlternatingStance.standing,
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.mountainClimber => AlternatingKneeAnalyzer(
      exerciseType: type,
      stance: AlternatingStance.plank,
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.tricepDip => TricepDipAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.squatJump => SquatJumpAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
  };
}
