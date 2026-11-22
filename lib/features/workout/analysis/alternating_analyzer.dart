import 'dart:math' as math;

import '../../../core/constants/app_constants.dart';
import '../../../models/exercise.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import 'body_tracker.dart';
import 'exercise_analyzer.dart';
import 'rep_cycle_counter.dart';
import 'signals.dart';
import 'tracking_diagnostics.dart';

/// Body position an alternating-knee exercise is done in.
enum AlternatingStance {
  /// Upright (high knees, marching).
  standing,

  /// Hands on the floor, body roughly horizontal (mountain climbers).
  plank,
}

/// Counts alternating knee drives (high knees, mountain climbers): every
/// time the other knee becomes the leading one, that is a rep.
///
/// Signal: how far each knee is driven along the body axis (hip → shoulder),
/// in torso lengths, left minus right. It swings positive and negative as
/// the legs alternate, so a rep is counted on arrival at either side; the
/// moment the legs cross, which is often between two camera frames, does
/// not need to be seen. Taking the most-flexed leg instead (the old method)
/// never returns to "rest" while the legs alternate, so nothing counted.
class AlternatingKneeAnalyzer implements ExerciseAnalyzer {
  AlternatingKneeAnalyzer({
    required this.exerciseType,
    required this.stance,
    this.thresholds = const PushUpThresholds(),
    this.targetReps,
    this.label,
  }) : tracker = BodyTracker(presenceConfidence: thresholds.presenceConfidence);

  final ExerciseType? exerciseType;
  final AlternatingStance stance;
  final PushUpThresholds thresholds;
  final int? targetReps;

  /// Name in the tracking report (defaults to the exercise's label).
  final String? label;
  final BodyTracker tracker;

  /// Smallest knee lead (torso lengths) that counts as a drive.
  static const minLead = 0.22;

  /// Fraction of the user's usual lead that counts as a drive.
  static const leadFraction = 0.45;

  /// Shortest time between two counted drives.
  static const cooldown = Duration(milliseconds: 140);

  /// Tracking gaps up to this long keep the current side.
  static const maxDropout = Duration(milliseconds: 900);

  late final TrackingDiagnostics _diagnostics = TrackingDiagnostics(
    diagnosticsLabel,
  );
  final DecayingMax _torso = DecayingMax(decayPerSecond: 0.03);
  final DecayingMax _amplitude = DecayingMax(decayPerSecond: 0.05);

  /// Recent raw samples. Seen end-on (a plank filmed from the head) one leg
  /// reads as leading more than the other; the signal is centred on the
  /// middle of its recent extremes, which removes that bias after a single
  /// swing.
  final List<(DateTime, double)> _window = [];

  /// Length of [_window].
  static const _windowSpan = Duration(milliseconds: 2000);
  FormStatus _formStatus = FormStatus.bodyNotVisible;
  int _orientationTag = 0;
  int _reps = 0;
  int _side = 0; // +1 left knee leading, -1 right, 0 unknown
  double? _lastSignal;
  DateTime? _lastCountAt;
  DateTime? _lastValidAt;
  int _trackedFrames = 0;
  int _goodFrames = 0;

  @override
  ExerciseType? get type => exerciseType;

  @override
  String get diagnosticsLabel => label ?? exerciseType?.label ?? 'Movement';

  @override
  int get repCount => _reps;

  @override
  FormStatus get formStatus => _formStatus;

  @override
  double? get formScore =>
      _trackedFrames == 0 ? null : _goodFrames / _trackedFrames;

  @override
  TrackingDiagnostics get diagnostics => _diagnostics;

  bool get _completed => targetReps != null && _reps >= targetReps!;

  @override
  void resetCounting() {
    _reps = 0;
    _side = 0;
    _lastSignal = null;
    _lastCountAt = null;
    _trackedFrames = 0;
    _goodFrames = 0;
  }

  @override
  void reset() {
    resetCounting();
    tracker.reset();
    _torso.reset();
    _amplitude.reset();
    _window.clear();
    _lastValidAt = null;
    _formStatus = FormStatus.bodyNotVisible;
  }

  bool _ok(PoseResult pose, LandmarkType t) =>
      pose.confidenceOf(t) >= thresholds.minLandmarkConfidence;

  bool _countable(PoseResult pose) {
    final shoulder =
        _ok(pose, LandmarkType.leftShoulder) ||
        _ok(pose, LandmarkType.rightShoulder);
    return shoulder &&
        BodySide.values.every((s) => _ok(pose, s.hip) && _ok(pose, s.knee));
  }

  bool _inPosition(PoseResult pose) {
    final side = pose.preferredSide;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return false;
    switch (stance) {
      case AlternatingStance.standing:
        final up = pose.heightAbove(side.shoulder, side.hip, torso);
        return up != null && up > 0.5;
      case AlternatingStance.plank:
        final hands = pose.wristBelowShoulderRatio(side);
        if (hands == null || hands < thresholds.maxHandsRaisedRatio) {
          return false;
        }
        if (pose.hasGravity) {
          final tilt = pose.bodyTiltDegrees(side);
          if (tilt != null && tilt > 60) return false;
        }
        return true;
    }
  }

  /// Left knee lead minus right knee lead, in torso lengths.
  double? _signal(PoseResult pose) {
    final shoulders = pose.mean2D([
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    ]);
    final hips = pose.mean2D([LandmarkType.leftHip, LandmarkType.rightHip]);
    if (shoulders == null || hips == null) return null;
    final axis = shoulders - hips;
    final torso = _torso.update(axis.length, pose.timestamp);
    if (torso <= 1e-6 || axis.length <= 1e-6) return null;
    final unit = axis.normalized;
    double? lead(BodySide s) {
      final knee = pose.position2D(s.knee);
      final hip = pose.position2D(s.hip);
      if (knee == null || hip == null) return null;
      return (knee - hip).dot(unit) / torso;
    }

    final l = lead(BodySide.left);
    final r = lead(BodySide.right);
    if (l == null || r == null) return null;
    return l - r;
  }

  @override
  ExerciseAnalysis processPose(PoseResult pose) {
    final d = _diagnostics;
    d.frames++;
    if (pose.orientationTag != _orientationTag) {
      _orientationTag = pose.orientationTag;
      d.orientationChanges++;
      tracker.reset();
      _side = 0;
      _lastSignal = null;
    }
    final now = pose.timestamp;
    final lastValid = _lastValidAt;
    if (lastValid != null && now.difference(lastValid) > maxDropout) {
      // Too long without seeing the legs: forget which one was leading.
      _side = 0;
      _lastSignal = null;
      _lastValidAt = null;
    }

    final quality = tracker.update(pose);
    if (quality != TrackQuality.stable || !pose.hasPose) {
      if (quality == TrackQuality.jumped) d.trackBreaks++;
      _formStatus = quality == TrackQuality.jumped
          ? FormStatus.lowConfidence
          : FormStatus.bodyNotVisible;
      d.countForm(_formStatus.name);
      return _analysis(quality, repCounted: false);
    }
    d.framesWithBody++;
    final countable = _countable(pose);
    final position = countable && _inPosition(pose);
    _formStatus = !countable
        ? FormStatus.bodyNotVisible
        : position
        ? FormStatus.goodForm
        : FormStatus.notInPosition;
    d.countForm(_formStatus.name);
    if (_formStatus.isTracking) {
      _trackedFrames++;
      if (_formStatus.isGood) _goodFrames++;
    }
    if (countable) d.framesCountable++;
    if (position) d.framesInPosition++;
    if (!position || !tracker.isStable || _completed) {
      return _analysis(quality, repCounted: false, inPosition: position);
    }

    final raw = _signal(pose);
    if (raw == null) return _analysis(quality, repCounted: false);
    _window.add((now, raw));
    while (_window.isNotEmpty &&
        now.difference(_window.first.$1) > _windowSpan) {
      _window.removeAt(0);
    }
    // Second-highest and second-lowest: one glitch frame (the detector
    // swapping the legs for a frame) must not drag the centre.
    final values = [for (final (_, v) in _window) v]..sort();
    final hi = values.length >= 4 ? values[values.length - 2] : values.last;
    final lo = values.length >= 4 ? values[1] : values.first;
    final s = raw - (hi + lo) / 2;
    d.observeSignal(s);
    _lastValidAt = now;
    final amplitude = _amplitude.update((hi - lo) / 2, now);
    final threshold = math.max(minLead, leadFraction * amplitude);
    d.lastHigh = threshold;
    d.lastLow = -threshold;

    final previous = _lastSignal;
    _lastSignal = s;
    final candidate = s >= threshold
        ? 1
        : s <= -threshold
        ? -1
        : 0;
    var counted = false;
    if (candidate != 0 && candidate != _side) {
      // A flip from one side to the other in a single frame is the detector
      // swapping the legs' identities, not a knee drive.
      final swapped =
          previous != null &&
          previous.sign == -candidate &&
          previous.abs() >= threshold &&
          (s - previous).abs() > 1.4 * amplitude;
      final last = _lastCountAt;
      if (swapped) {
        d.reject('legsSwapped');
      } else if (last != null && now.difference(last) < cooldown) {
        d.reject('cooldown');
      } else {
        _side = candidate;
        _reps++;
        _lastCountAt = now;
        counted = true;
        d.repsCounted = _reps;
      }
    }
    d.lastState = _side == 0 ? 'ready' : (_side > 0 ? 'left' : 'right');
    return _analysis(
      quality,
      repCounted: counted,
      inPosition: true,
      signal: s,
      depth: (s.abs() / threshold).clamp(0.0, 1.0),
      threshold: threshold,
    );
  }

  ExerciseAnalysis _analysis(
    TrackQuality quality, {
    required bool repCounted,
    bool inPosition = false,
    double? signal,
    double depth = 0,
    double? threshold,
  }) => ExerciseAnalysis(
    repCount: _reps,
    phase: _completed
        ? CyclePhase.completed
        : _side == 0
        ? CyclePhase.ready
        : CyclePhase.work,
    formStatus: _formStatus,
    repCounted: repCounted,
    depth: depth,
    inPosition: inPosition,
    signal: signal,
    restThreshold: threshold == null ? null : -threshold,
    workThreshold: threshold,
    limbsUsed: 2,
    trackQuality: quality,
  );
}
