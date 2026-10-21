import '../../../core/constants/app_constants.dart';
import '../../../models/exercise.dart';
import '../push_up_analyzer.dart';
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
    ExerciseType.gluteBridge => GenericAngleAnalyzer(
      spec: const AngleTracking(
        joint: JointKind.hip,
        restAngle: 120,
        workAngle: 165,
      ),
      label: type.label,
      exerciseType: type,
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
    ExerciseType.highKnees => GenericAngleAnalyzer(
      spec: const AngleTracking(
        joint: JointKind.hip,
        restAngle: 160,
        workAngle: 105,
        requireUpright: true,
        aggregate: SideAggregate.min,
      ),
      label: type.label,
      exerciseType: type,
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.mountainClimber => GenericAngleAnalyzer(
      spec: const AngleTracking(
        joint: JointKind.hip,
        restAngle: 155,
        workAngle: 100,
        aggregate: SideAggregate.min,
      ),
      label: type.label,
      exerciseType: type,
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.tricepDip => GenericAngleAnalyzer(
      spec: const AngleTracking(
        joint: JointKind.elbow,
        restAngle: 160,
        workAngle: 95,
      ),
      label: type.label,
      exerciseType: type,
      thresholds: thresholds,
      targetReps: target,
    ),
    ExerciseType.squatJump => SquatJumpAnalyzer(
      thresholds: thresholds,
      targetReps: target,
    ),
  };
}
