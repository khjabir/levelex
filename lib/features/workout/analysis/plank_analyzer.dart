import '../../../core/constants/app_constants.dart';
import '../../../models/exercise.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import 'body_tracker.dart';
import 'exercise_analyzer.dart';
import 'rep_cycle_counter.dart';
import 'tracking_diagnostics.dart';

/// Plank: a timed hold. The clock runs while a continuously tracked body is
/// horizontal with the hands or forearms on the floor; [repCount] is the
/// number of whole seconds held.
class PlankAnalyzer implements ExerciseAnalyzer {
  PlankAnalyzer({
    this.thresholds = const PushUpThresholds(),
    this.targetSeconds,
  }) : tracker = BodyTracker(presenceConfidence: thresholds.presenceConfidence);

  final PushUpThresholds thresholds;
  final int? targetSeconds;
  final BodyTracker tracker;

  final TrackingDiagnostics _diagnostics = TrackingDiagnostics('Plank');
  FormStatus _formStatus = FormStatus.bodyNotVisible;
  double _heldMs = 0;
  int _wholeSeconds = 0;
  DateTime? _lastFrameAt;
  int _orientationTag = 0;
  int _trackedFrames = 0;
  int _goodFormFrames = 0;
  bool _completed = false;

  /// Longest frame-to-frame gap credited to the hold (drops hide pauses).
  static const _maxCreditedGap = Duration(milliseconds: 400);

  @override
  ExerciseType get type => ExerciseType.plank;

  @override
  String get diagnosticsLabel => type.label;

  @override
  int get repCount => _wholeSeconds;

  @override
  FormStatus get formStatus => _formStatus;

  @override
  double? get formScore =>
      _trackedFrames == 0 ? null : _goodFormFrames / _trackedFrames;

  @override
  TrackingDiagnostics get diagnostics => _diagnostics;

  double get secondsHeld => _heldMs / 1000;

  @override
  void resetCounting() {
    _heldMs = 0;
    _wholeSeconds = 0;
    _lastFrameAt = null;
    _trackedFrames = 0;
    _goodFormFrames = 0;
    _completed = false;
  }

  @override
  void reset() {
    resetCounting();
    tracker.reset();
    _formStatus = FormStatus.bodyNotVisible;
  }

  bool _above(PoseResult pose, LandmarkType t, double v) =>
      pose.confidenceOf(t) >= v;

  bool _bodyPresent(PoseResult pose, BodySide side) {
    final p = thresholds.presenceConfidence;
    return _above(pose, side.shoulder, p) &&
        _above(pose, side.hip, p) &&
        (_above(pose, side.ankle, p) || _above(pose, side.knee, p));
  }

  /// Horizontal body with the hands (or elbows) below the shoulders.
  bool _inPlank(PoseResult pose, BodySide side) {
    final tilt = pose.bodyTiltDegrees(side);
    if (tilt != null && tilt > 40) return false;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return false;
    final wrist = pose.heightAbove(side.wrist, side.shoulder, torso);
    final elbow = pose.heightAbove(side.elbow, side.shoulder, torso);
    final support = wrist ?? elbow;
    // Support point must be lower than the shoulder (negative height).
    return support != null && support < -0.15;
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
    final side = pose.hasPose ? pose.preferredSide : null;
    final present =
        side != null &&
        (_bodyPresent(pose, BodySide.left) ||
            _bodyPresent(pose, BodySide.right));

    var holding = false;
    if (quality != TrackQuality.stable || !present) {
      if (quality == TrackQuality.jumped) d.trackBreaks++;
      _formStatus = FormStatus.bodyNotVisible;
      _lastFrameAt = null;
    } else {
      d.framesWithBody++;
      final tilt = pose.bodyTiltDegrees(side);
      if (tilt != null) {
        d.lastTilt = tilt;
        d.observeSignal(tilt);
      }
      if (!_inPlank(pose, side)) {
        _formStatus = FormStatus.notInPosition;
        _lastFrameAt = null;
      } else {
        d.framesInPosition++;
        holding = tracker.isStable && !_completed;
        final bodyAngle = pose.bodyAlignmentAngle(side);
        final deviation = pose.hipDeviationRatio(side);
        if (bodyAngle != null &&
            deviation != null &&
            bodyAngle < thresholds.straightBodyMinAngle &&
            deviation.abs() > thresholds.hipDeviationRatio) {
          _formStatus = deviation > 0
              ? FormStatus.hipsTooHigh
              : FormStatus.hipsTooLow;
        } else {
          _formStatus = FormStatus.goodForm;
        }
        _trackedFrames++;
        if (_formStatus.isGood) _goodFormFrames++;
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
          final credited = gap > _maxCreditedGap ? _maxCreditedGap : gap;
          _heldMs += credited.inMilliseconds;
        }
      }
      _lastFrameAt = pose.timestamp;
      final whole = (_heldMs / 1000).floor();
      if (whole > _wholeSeconds) {
        _wholeSeconds = whole;
        tick = true;
        d.repsCounted = whole;
      }
      final target = targetSeconds;
      if (target != null && _wholeSeconds >= target) _completed = true;
    }
    d.lastState = _completed
        ? 'completed'
        : holding
        ? 'holding'
        : 'idle';

    final target = targetSeconds;
    return ExerciseAnalysis(
      repCount: _wholeSeconds,
      phase: _completed
          ? CyclePhase.completed
          : holding
          ? CyclePhase.work
          : CyclePhase.ready,
      formStatus: _formStatus,
      repCounted: tick,
      depth: target == null || target == 0
          ? 0
          : (secondsHeld / target).clamp(0.0, 1.0),
      inPosition: holding || _formStatus.isTracking,
      bodyTilt: d.lastTilt,
      secondsHeld: secondsHeld,
      limbsUsed: 1,
      trackQuality: quality,
    );
  }
}
