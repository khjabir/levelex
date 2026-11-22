import 'dart:math' as math;

import '../../../core/constants/app_constants.dart';
import '../../../models/exercise.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import 'analyzer_factory.dart';
import 'body_tracker.dart';
import 'exercise_analyzer.dart';
import 'rep_cycle_counter.dart';
import 'signals.dart';
import 'tracking_diagnostics.dart';
import 'tracking_spec.dart';

/// Landmarks that define a [JointKind] angle on one side.
(LandmarkType, LandmarkType, LandmarkType) jointTriple(
  JointKind joint,
  BodySide side,
) => switch (joint) {
  JointKind.elbow => (side.shoulder, side.elbow, side.wrist),
  JointKind.knee => (side.hip, side.knee, side.ankle),
  JointKind.hip => (side.shoulder, side.hip, side.knee),
  JointKind.shoulderRaise => (side.hip, side.shoulder, side.wrist),
};

/// Counts reps of any movement that opens and closes one joint angle
/// (curls, presses, rows, raises, hinges…) using the shared rep engine.
class GenericAngleAnalyzer extends CycleExerciseAnalyzer {
  GenericAngleAnalyzer({
    required this.spec,
    required this.label,
    this.exerciseType,
    super.thresholds = const PushUpThresholds(),
    int? targetReps,
  }) : super(
         target: targetReps,
         cycle: CycleConfig(
           restDefault: spec.restAngle,
           workDefault: spec.workAngle,
           restIsHigh: spec.restIsHigh,
           adaptive: true,
           minRange: 60,
           margin: 0.3,
           minGap: spec.minGap,
           minFrames: thresholds.minFramesForTransition,
           minWorkDuration: const Duration(milliseconds: 150),
           cooldown: const Duration(milliseconds: 300),
           shallowFraction: thresholds.shallowFraction,
         ),
       );

  final AngleTracking spec;
  final String label;

  /// Set when this analyzer backs one of the built-in exercises.
  final ExerciseType? exerciseType;

  @override
  ExerciseType? get type => exerciseType;

  @override
  String get diagnosticsLabel => label;

  List<BodySide> _sides(PoseResult pose) => [
    for (final side in BodySide.values)
      if (jointsOk(pose, [
        for (final j in [
          jointTriple(spec.joint, side).$1,
          jointTriple(spec.joint, side).$2,
          jointTriple(spec.joint, side).$3,
        ])
          j,
      ]))
        side,
  ];

  @override
  double? signal(PoseResult pose) {
    final values = <double>[];
    for (final side in _sides(pose)) {
      final (a, b, c) = jointTriple(spec.joint, side);
      final angle = pose.jointAngle(a, b, c);
      if (angle != null) values.add(angle);
    }
    if (values.isEmpty) return null;
    return switch (spec.aggregate) {
      SideAggregate.mean => values.reduce((x, y) => x + y) / values.length,
      SideAggregate.min => values.reduce((x, y) => x < y ? x : y),
      SideAggregate.max => values.reduce((x, y) => x > y ? x : y),
    };
  }

  @override
  int limbsUsed(PoseResult pose) => _sides(pose).length;

  @override
  bool countable(PoseResult pose) => _sides(pose).isNotEmpty;

  @override
  bool inPosition(PoseResult pose) {
    if (!spec.requireUpright) return true;
    final side = chooseSide(pose);
    if (side == null) return false;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return false;
    final up = pose.heightAbove(side.shoulder, side.hip, torso);
    return up != null && up > 0.5;
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      FormStatus.goodForm;
}

/// Tricep dips (hands on a bench or chair behind, body upright): the
/// shoulders' height above the hands as a fraction of the top, like the
/// push-up. The elbow angle is blind when the camera faces the user.
class TricepDipAnalyzer extends CycleExerciseAnalyzer {
  TricepDipAnalyzer({
    super.thresholds = const PushUpThresholds(),
    int? targetReps,
  }) : super(
         target: targetReps,
         cycle: CycleConfig(
           // Bench dips drop the shoulders less than push-ups, and seen
           // from the front perspective hides part of the drop.
           restDefault: 0.92,
           workDefault: math.min(0.86, thresholds.pushUpDropRatio + 0.04),
           minRange: 0.15,
           margin: thresholds.adaptiveMargin,
           minGap: 0.08,
           decayPerFrame: 0.0015,
           maxAdaptiveLoosening: 0.05,
           minFrames: thresholds.minFramesForTransition,
           minWorkDuration: const Duration(milliseconds: 200),
           cooldown: const Duration(milliseconds: 350),
           shallowFraction: thresholds.shallowFraction,
         ),
       );

  final DropRatio _drop = DropRatio();

  @override
  ExerciseType get type => ExerciseType.tricepDip;

  List<BodySide> _arms(PoseResult pose) => [
    for (final side in BodySide.values)
      if (jointsOk(pose, [side.shoulder, side.elbow, side.wrist])) side,
  ];

  @override
  int limbsUsed(PoseResult pose) => _arms(pose).length;

  @override
  bool countable(PoseResult pose) => _arms(pose).isNotEmpty;

  /// Torso upright and hands below the shoulders.
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return false;
    final up = pose.heightAbove(side.shoulder, side.hip, torso);
    final hands = pose.wristBelowShoulderRatio(side);
    return up != null && up > 0.4 && hands != null && hands > 0;
  }

  @override
  double? signal(PoseResult pose) {
    final arms = _arms(pose);
    if (arms.isEmpty) return null;
    final h = pose.heightBetween(
      arms.map((s) => s.shoulder),
      arms.map((s) => s.wrist),
    );
    return _drop.update(h, pose.timestamp);
  }

  @override
  void reset() {
    super.reset();
    _drop.reset();
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      FormStatus.goodForm;
}

/// Timed hold: the clock runs while a joint angle stays inside a range
/// (wall sit). Modelled on the plank analyzer.
class GenericHoldAnalyzer implements ExerciseAnalyzer {
  GenericHoldAnalyzer({
    required this.spec,
    required this.label,
    this.exerciseType,
    this.thresholds = const PushUpThresholds(),
    this.targetSeconds,
  }) : tracker = BodyTracker(presenceConfidence: thresholds.presenceConfidence);

  final HoldTracking spec;
  final String label;
  final ExerciseType? exerciseType;
  final PushUpThresholds thresholds;
  final int? targetSeconds;
  final BodyTracker tracker;

  late final TrackingDiagnostics _diagnostics = TrackingDiagnostics(label);
  FormStatus _formStatus = FormStatus.bodyNotVisible;
  double _heldMs = 0;
  int _wholeSeconds = 0;
  DateTime? _lastFrameAt;
  int _orientationTag = 0;
  bool _completed = false;

  static const _maxCreditedGap = Duration(milliseconds: 400);

  @override
  ExerciseType? get type => exerciseType;

  @override
  String get diagnosticsLabel => label;

  @override
  int get repCount => _wholeSeconds;

  @override
  FormStatus get formStatus => _formStatus;

  @override
  double? get formScore => null;

  @override
  TrackingDiagnostics get diagnostics => _diagnostics;

  double get secondsHeld => _heldMs / 1000;

  @override
  void resetCounting() {
    _heldMs = 0;
    _wholeSeconds = 0;
    _lastFrameAt = null;
    _completed = false;
  }

  @override
  void reset() {
    resetCounting();
    tracker.reset();
    _formStatus = FormStatus.bodyNotVisible;
  }

  double? _angle(PoseResult pose) {
    for (final side in [pose.preferredSide, ...BodySide.values]) {
      final (a, b, c) = jointTriple(spec.joint, side);
      if (pose.confidenceOf(a) < thresholds.minLandmarkConfidence ||
          pose.confidenceOf(b) < thresholds.minLandmarkConfidence ||
          pose.confidenceOf(c) < thresholds.minLandmarkConfidence) {
        continue;
      }
      return pose.jointAngle(a, b, c);
    }
    return null;
  }

  /// Seen from the front, a bent knee points at the camera and its 2D
  /// angle reads almost straight. A seated knee hold is then recognised by
  /// its shape instead: thighs about level (hips near knee height) over
  /// upright shins.
  bool _kneeHoldShape(PoseResult pose) {
    if (spec.joint != JointKind.knee) return false;
    for (final side in BodySide.values) {
      final ok = [
        side.hip,
        side.knee,
        side.ankle,
      ].every((t) => pose.confidenceOf(t) >= thresholds.minLandmarkConfidence);
      if (!ok) continue;
      final shin = pose.distance2D(side.knee, side.ankle) ?? 0;
      if (shin == 0) continue;
      final thighRise = pose.heightAbove(side.hip, side.knee, shin);
      final shinRise = pose.heightAbove(side.knee, side.ankle, shin);
      if (thighRise != null &&
          shinRise != null &&
          thighRise.abs() < 0.45 &&
          shinRise > 0.75) {
        return true;
      }
    }
    return false;
  }

  @override
  ExerciseAnalysis processPose(PoseResult pose) {
    final d = _diagnostics;
    d.frames++;
    if (pose.orientationTag != _orientationTag) {
      _orientationTag = pose.orientationTag;
      d.orientationChanges++;
      tracker.reset();
      _lastFrameAt = null;
    }
    final quality = tracker.update(pose);
    final angle = quality == TrackQuality.stable && pose.hasPose
        ? _angle(pose)
        : null;
    var holding = false;
    if (angle == null) {
      if (quality == TrackQuality.jumped) d.trackBreaks++;
      _formStatus = FormStatus.bodyNotVisible;
      _lastFrameAt = null;
    } else {
      d.framesWithBody++;
      d.observeSignal(angle);
      if ((angle < spec.minAngle || angle > spec.maxAngle) &&
          !_kneeHoldShape(pose)) {
        _formStatus = FormStatus.notInPosition;
        _lastFrameAt = null;
      } else {
        d.framesInPosition++;
        _formStatus = FormStatus.goodForm;
        holding = tracker.isStable && !_completed;
      }
    }
    d.countForm(_formStatus.name);
    var tick = false;
    if (holding) {
      d.framesCountable++;
      final last = _lastFrameAt;
      if (last != null) {
        final gap = pose.timestamp.difference(last);
        if (gap > Duration.zero) {
          _heldMs +=
              (gap > _maxCreditedGap ? _maxCreditedGap : gap).inMilliseconds;
        }
      }
      _lastFrameAt = pose.timestamp;
      final whole = (_heldMs / 1000).floor();
      if (whole > _wholeSeconds) {
        _wholeSeconds = whole;
        tick = true;
        d.repsCounted = whole;
      }
      final t = targetSeconds;
      if (t != null && _wholeSeconds >= t) _completed = true;
    }
    final t = targetSeconds;
    return ExerciseAnalysis(
      repCount: _wholeSeconds,
      phase: _completed
          ? CyclePhase.completed
          : holding
          ? CyclePhase.work
          : CyclePhase.ready,
      formStatus: _formStatus,
      repCounted: tick,
      depth: t == null || t == 0 ? 0 : (secondsHeld / t).clamp(0.0, 1.0),
      inPosition: holding || _formStatus.isGood,
      signal: angle,
      secondsHeld: secondsHeld,
      limbsUsed: 1,
      trackQuality: quality,
    );
  }
}

/// Builds the analyzer for a movement's tracking spec (null for timers).
abstract final class PtAnalyzerFactory {
  static ExerciseAnalyzer? create(
    TrackingSpec spec, {
    required String label,
    PushUpThresholds thresholds = const PushUpThresholds(),
    int? target,
  }) => switch (spec) {
    ExerciseTracking(:final type) => ExerciseAnalyzerFactory.create(
      type,
      thresholds: thresholds,
      target: target ?? 9999,
    ),
    AngleTracking() => GenericAngleAnalyzer(
      spec: spec,
      label: label,
      thresholds: thresholds,
      targetReps: target,
    ),
    HoldTracking() => GenericHoldAnalyzer(
      spec: spec,
      label: label,
      thresholds: thresholds,
      targetSeconds: target,
    ),
    TimerTracking() => null,
  };
}
