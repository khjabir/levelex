import '../../../core/constants/app_constants.dart';
import '../../../models/exercise.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import 'body_tracker.dart';
import 'rep_cycle_counter.dart';
import 'tracking_diagnostics.dart';

/// Snapshot of an analyzer after processing one frame.
class ExerciseAnalysis {
  const ExerciseAnalysis({
    required this.repCount,
    required this.phase,
    required this.formStatus,
    required this.repCounted,
    this.depth = 0,
    this.inPosition = false,
    this.signal,
    this.restThreshold,
    this.workThreshold,
    this.limbsUsed = 0,
    this.bodyTilt,
    this.secondsHeld = 0,
    this.trackQuality = TrackQuality.missing,
    this.rejection,
    this.event,
  });

  /// Reps for rep-based exercises, whole seconds held for timed ones.
  final int repCount;
  final CyclePhase phase;
  final FormStatus formStatus;

  /// True on the frame a rep (or a new whole second) was counted.
  final bool repCounted;

  /// 0 at rest, 1 at the work position (drives the gauge).
  final double depth;

  /// The user is in the exercise's starting posture.
  final bool inPosition;

  /// The raw signal the counter looks at (e.g. elbow angle in degrees).
  final double? signal;
  final double? restThreshold;
  final double? workThreshold;

  /// Arms or legs contributing to the signal.
  final int limbsUsed;

  /// Angle of the body line from the horizontal (0 = plank, 90 = standing).
  final double? bodyTilt;

  /// For timed exercises: seconds held so far (fractional).
  final double secondsHeld;
  final TrackQuality trackQuality;
  final CycleRejection? rejection;

  /// A movement mistake that ended on this frame ([FormStatus.goDeeper] or
  /// [FormStatus.slowDown]), for the coach.
  final FormStatus? event;

  bool get isWorking => phase == CyclePhase.work;
  bool get isCompleted => phase == CyclePhase.completed;
}

/// Contract for exercise analyzers: pure Dart, one [PoseResult] per frame in,
/// an [ExerciseAnalysis] out.
abstract class ExerciseAnalyzer {
  /// One of the built-in exercises, or null for a generic movement.
  ExerciseType? get type;

  /// Name used in the tracking report.
  String get diagnosticsLabel => type?.label ?? 'Movement';
  int get repCount;
  FormStatus get formStatus;

  /// Fraction of tracked frames with good form, or null when nothing was
  /// tracked yet.
  double? get formScore;
  TrackingDiagnostics get diagnostics;
  ExerciseAnalysis processPose(PoseResult pose);

  /// Clears counted work and form statistics but keeps body tracking warm,
  /// so counting can start on the very next frame.
  void resetCounting();

  /// Full reset, including body tracking.
  void reset();
}

/// Shared machinery for rep-based exercises: continuity tracking, form
/// bookkeeping, the cycle counter and diagnostics. Subclasses describe the
/// movement through a handful of hooks.
abstract class CycleExerciseAnalyzer implements ExerciseAnalyzer {
  CycleExerciseAnalyzer({
    required this.thresholds,
    required CycleConfig cycle,
    this.target,
  }) : counter = RepCycleCounter(config: cycle, target: target),
       tracker = BodyTracker(presenceConfidence: thresholds.presenceConfidence);

  final PushUpThresholds thresholds;
  final int? target;
  final RepCycleCounter counter;
  final BodyTracker tracker;

  late final TrackingDiagnostics _diagnostics = TrackingDiagnostics(
    diagnosticsLabel,
  );

  FormStatus _formStatus = FormStatus.bodyNotVisible;
  int _orientationTag = 0;
  int _trackedFrames = 0;
  int _goodFormFrames = 0;

  @override
  String get diagnosticsLabel => type?.label ?? 'Movement';

  @override
  int get repCount => counter.repCount;

  @override
  FormStatus get formStatus => _formStatus;

  @override
  double? get formScore =>
      _trackedFrames == 0 ? null : _goodFormFrames / _trackedFrames;

  @override
  TrackingDiagnostics get diagnostics => _diagnostics;

  // ---------------------------------------------------------------------------
  // Hooks
  // ---------------------------------------------------------------------------

  /// The scalar the counter follows, or null when it cannot be measured.
  double? signal(PoseResult pose);

  /// Landmarks needed for counting are confidently tracked.
  bool countable(PoseResult pose);

  /// The user is in the starting posture for this exercise.
  bool inPosition(PoseResult pose);

  /// Number of limbs contributing to [signal].
  int limbsUsed(PoseResult pose) => 1;

  /// Called on every frame at rest; store references for the vetoes.
  void onRestFrame(PoseResult pose) {}

  /// Refuse entering the work position (e.g. body did not move).
  bool vetoWork(PoseResult pose) => false;

  /// Refuse the return to rest (rarely needed).
  bool vetoRest(PoseResult pose) => false;

  /// Form feedback once the body is tracked and in position.
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      evaluateAlignment(pose, side);

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  bool above(PoseResult pose, LandmarkType type, double threshold) =>
      pose.confidenceOf(type) >= threshold;

  bool jointsOk(PoseResult pose, List<LandmarkType> joints) {
    for (final j in joints) {
      if (!above(pose, j, thresholds.minLandmarkConfidence)) return false;
    }
    return true;
  }

  bool bodyPresent(PoseResult pose, BodySide side) {
    final p = thresholds.presenceConfidence;
    return above(pose, side.shoulder, p) &&
        above(pose, side.hip, p) &&
        (above(pose, side.ankle, p) || above(pose, side.knee, p));
  }

  /// Side with the better overall confidence (null without a pose).
  BodySide? chooseSide(PoseResult pose) =>
      pose.hasPose ? pose.preferredSide : null;

  bool nearEdge(PoseResult pose, BodySide side) {
    final m = thresholds.edgeMargin;
    for (final type in [side.shoulder, side.wrist, side.hip, side.ankle]) {
      final l = pose[type];
      if (l == null) continue;
      if (l.likelihood < thresholds.presenceConfidence) continue;
      if (l.x < m || l.x > 1 - m || l.y < m || l.y > 1 - m) return true;
    }
    return false;
  }

  /// Standard hips-high/low check along "up".
  FormStatus evaluateAlignment(PoseResult pose, BodySide side) {
    final bodyAngle = pose.bodyAlignmentAngle(side);
    final deviation = pose.hipDeviationRatio(side);
    if (bodyAngle == null || deviation == null) return FormStatus.goodForm;
    if (bodyAngle < thresholds.straightBodyMinAngle &&
        deviation.abs() > thresholds.hipDeviationRatio) {
      return deviation > 0 ? FormStatus.hipsTooHigh : FormStatus.hipsTooLow;
    }
    return FormStatus.goodForm;
  }

  /// Mean length of a limb segment over the sides where it is measurable.
  double meanSegment(
    PoseResult pose,
    LandmarkType Function(BodySide) a,
    LandmarkType Function(BodySide) b,
  ) {
    var sum = 0.0;
    var n = 0;
    for (final side in BodySide.values) {
      final d = pose.distance2D(a(side), b(side));
      if (d == null || d == 0) continue;
      sum += d;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  // ---------------------------------------------------------------------------
  // Frame processing
  // ---------------------------------------------------------------------------

  @override
  void resetCounting() {
    counter.reset();
    _trackedFrames = 0;
    _goodFormFrames = 0;
  }

  @override
  void reset() {
    resetCounting();
    tracker.reset();
    _formStatus = FormStatus.bodyNotVisible;
  }

  @override
  ExerciseAnalysis processPose(PoseResult pose) {
    final d = _diagnostics;
    d.frames++;
    if (pose.orientationTag != _orientationTag) {
      _orientationTag = pose.orientationTag;
      d.orientationChanges++;
      counter.invalidate();
      tracker.reset();
    }
    if (pose.hasGravity) {
      d.hadGravity = true;
      d.lastGravity = pose.gravity.toString();
    }

    final quality = tracker.update(pose);
    final side = chooseSide(pose);
    if (quality != TrackQuality.stable || side == null) {
      if (quality == TrackQuality.jumped) d.trackBreaks++;
      counter.invalidate();
      _formStatus = switch (quality) {
        TrackQuality.jumped => FormStatus.lowConfidence,
        _ => FormStatus.bodyNotVisible,
      };
      d.countForm(_formStatus.name);
      return ExerciseAnalysis(
        repCount: counter.repCount,
        phase: counter.phase,
        formStatus: _formStatus,
        repCounted: false,
        trackQuality: quality,
      );
    }
    d.framesWithBody++;

    final present =
        bodyPresent(pose, BodySide.left) || bodyPresent(pose, BodySide.right);
    final canCount = countable(pose);
    final position = present && inPosition(pose);
    final tilt = pose.bodyTiltDegrees(side);
    if (tilt != null) d.lastTilt = tilt;

    if (!present) {
      _formStatus = FormStatus.bodyNotVisible;
    } else if (!canCount) {
      _formStatus = FormStatus.armNotVisible;
    } else if (nearEdge(pose, side)) {
      _formStatus = FormStatus.moveBack;
    } else if (!position) {
      _formStatus = FormStatus.notInPosition;
    } else {
      _formStatus = evaluateForm(pose, side);
    }
    d.countForm(_formStatus.name);
    if (_formStatus.isTracking) {
      _trackedFrames++;
      if (_formStatus.isGood) _goodFormFrames++;
    }

    final valid = canCount && position && tracker.isStable;
    if (canCount) d.framesCountable++;
    if (position) d.framesInPosition++;
    final value = valid ? signal(pose) : null;
    if (value != null) d.observeSignal(value);

    final update = counter.update(
      signal: value,
      now: pose.timestamp,
      valid: valid,
      vetoWork: () => vetoWork(pose),
      vetoRest: () => vetoRest(pose),
    );
    // Refresh the rest reference only while the signal is genuinely at
    // rest, never during the unconfirmed first frames of a descent.
    if (valid &&
        value != null &&
        (update.phase == CyclePhase.rest || update.phase == CyclePhase.ready)) {
      final atRest = counter.config.restIsHigh
          ? value >= update.restThreshold
          : value <= update.restThreshold;
      if (atRest) onRestFrame(pose);
    }
    d.lastHigh = update.restThreshold;
    d.lastLow = update.workThreshold;
    d.lastState = update.phase.name;
    if (update.repCounted) d.repsCounted++;
    if (update.rejection != null &&
        update.rejection != CycleRejection.notValid) {
      d.reject(update.rejection!.name);
    }
    FormStatus? event;
    if (update.shallowAttempt) {
      event = FormStatus.goDeeper;
      d.shallowAttempts++;
    } else if (update.rejection == CycleRejection.tooSoon) {
      event = FormStatus.slowDown;
    }

    return ExerciseAnalysis(
      repCount: counter.repCount,
      phase: update.phase,
      formStatus: _formStatus,
      repCounted: update.repCounted,
      depth: update.depth,
      inPosition: position,
      signal: value,
      restThreshold: update.restThreshold,
      workThreshold: update.workThreshold,
      limbsUsed: limbsUsed(pose),
      bodyTilt: tilt,
      trackQuality: quality,
      rejection: update.rejection,
      event: event,
    );
  }
}
