import '../../../core/utils/geometry.dart';
import '../../../models/pose_result.dart';

/// Outcome of checking one frame for continuity and plausibility.
enum TrackQuality {
  /// No usable body.
  missing,

  /// A body, but its proportions are not those of a person (e.g. ML Kit
  /// locked onto a hand or a fragment).
  implausible,

  /// The skeleton moved too far since the previous frame: a different
  /// person, a glitch, or the detector re-attaching to something else.
  jumped,

  /// Continuous with the previous frames.
  stable,
}

/// Guards every counter against skeletons that appear, jump or distort.
/// Counting only proceeds while the same body is tracked continuously.
class BodyTracker {
  BodyTracker({
    this.presenceConfidence = 0.3,
    this.maxJumpRatio = 0.8,
    this.maxGap = const Duration(milliseconds: 700),
    this.minTorsoLength = 0.06,
    this.stableFramesRequired = 3,
  });

  /// Likelihood below which a landmark is treated as absent.
  final double presenceConfidence;

  /// Centre displacement between consecutive frames, as a fraction of the
  /// torso length, above which the track is considered broken.
  final double maxJumpRatio;

  /// Longer gaps between frames restart continuity without penalty.
  final Duration maxGap;

  /// Body size (2D, fraction of the frame) below which the body is noise.
  final double minTorsoLength;

  /// Frames of continuity required before counting resumes after a break.
  final int stableFramesRequired;

  Point2? _lastCenter;
  DateTime? _lastAt;
  double? _scale;
  int _stableFrames = 0;
  int _breaks = 0;

  int get stableFrames => _stableFrames;
  int get breaks => _breaks;
  bool get isStable => _stableFrames >= stableFramesRequired;

  void reset() {
    _lastCenter = null;
    _lastAt = null;
    _scale = null;
    _stableFrames = 0;
  }

  TrackQuality update(PoseResult pose) {
    final torso = _torso(pose);
    if (torso == null) {
      _stableFrames = 0;
      _lastCenter = null;
      return TrackQuality.missing;
    }
    final (center, torsoLength, shoulderWidth, extent) = torso;
    // Body size reference: the largest visible extent (a foreshortened torso
    // seen from the front is short, but the shoulders or the body length are
    // not). A crumpled fragment such as a hand is small on every axis.
    final size = [
      torsoLength,
      shoulderWidth,
      extent * 0.5,
    ].reduce((a, b) => a > b ? a : b);
    if (size < minTorsoLength) {
      _stableFrames = 0;
      _lastCenter = null;
      return TrackQuality.implausible;
    }
    // Smoothed over time so normal movement never looks like a jump.
    final scale = _scale;
    _scale = scale == null ? size : scale * 0.9 + size * 0.1;

    final last = _lastCenter;
    final lastAt = _lastAt;
    _lastCenter = center;
    _lastAt = pose.timestamp;
    if (last != null &&
        lastAt != null &&
        pose.timestamp.difference(lastAt) <= maxGap) {
      final jump = Geometry.distance(center, last);
      if (jump > maxJumpRatio * _scale!) {
        _stableFrames = 0;
        _breaks++;
        return TrackQuality.jumped;
      }
    } else if (last != null) {
      // Long gap: start counting stability again, silently.
      _stableFrames = 0;
    }
    _stableFrames++;
    return TrackQuality.stable;
  }

  (Point2, double, double, double)? _torso(PoseResult pose) {
    Point2? mid(LandmarkType a, LandmarkType b) {
      final la = pose[a];
      final lb = pose[b];
      final okA = la != null && la.likelihood >= presenceConfidence;
      final okB = lb != null && lb.likelihood >= presenceConfidence;
      if (okA && okB) {
        return Point2((la.x + lb.x) / 2, (la.y + lb.y) / 2);
      }
      if (okA) return la.point;
      if (okB) return lb.point;
      return null;
    }

    final shoulders = mid(
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    );
    final hips = mid(LandmarkType.leftHip, LandmarkType.rightHip);
    if (shoulders == null || hips == null) return null;
    final torsoLength = Geometry.distance(shoulders, hips);
    final ls = pose[LandmarkType.leftShoulder];
    final rs = pose[LandmarkType.rightShoulder];
    final shoulderWidth = ls != null && rs != null
        ? Geometry.distance(ls.point, rs.point)
        : 0.0;
    final center = Point2(
      (shoulders.x + hips.x) / 2,
      (shoulders.y + hips.y) / 2,
    );
    final ankles =
        mid(LandmarkType.leftAnkle, LandmarkType.rightAnkle) ??
        mid(LandmarkType.leftKnee, LandmarkType.rightKnee);
    final extent = ankles == null
        ? torsoLength
        : Geometry.distance(shoulders, ankles);
    return (center, torsoLength, shoulderWidth, extent);
  }
}
