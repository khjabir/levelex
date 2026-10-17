import '../core/utils/geometry.dart';

/// The subset of body landmarks the app cares about.
///
/// This enum deliberately mirrors ML Kit's naming but is independent of it so
/// the analyzer and its tests never depend on a camera or ML package.
enum LandmarkType {
  nose,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

/// Which side of the body a measurement refers to.
enum BodySide {
  left,
  right;

  LandmarkType get shoulder =>
      this == left ? LandmarkType.leftShoulder : LandmarkType.rightShoulder;
  LandmarkType get elbow =>
      this == left ? LandmarkType.leftElbow : LandmarkType.rightElbow;
  LandmarkType get wrist =>
      this == left ? LandmarkType.leftWrist : LandmarkType.rightWrist;
  LandmarkType get hip =>
      this == left ? LandmarkType.leftHip : LandmarkType.rightHip;
  LandmarkType get knee =>
      this == left ? LandmarkType.leftKnee : LandmarkType.rightKnee;
  LandmarkType get ankle =>
      this == left ? LandmarkType.leftAnkle : LandmarkType.rightAnkle;
}

/// A single detected landmark.
///
/// [x] and [y] are normalised to `[0, 1]` relative to the *upright* camera
/// frame (0,0 is top-left) and are used for drawing and edge checks only.
/// [position] holds the same point in *uniform* units (pixels divided by the
/// longer frame side, so angles and distances are undistorted) including the
/// estimated depth [Vec3.z] (negative = closer to the camera, relative to the
/// hips).
class PoseLandmark {
  const PoseLandmark({
    required this.type,
    required this.x,
    required this.y,
    required this.position,
    required this.likelihood,
  });

  final LandmarkType type;
  final double x;
  final double y;
  final Vec3 position;

  /// ML Kit "in-frame likelihood" in `[0, 1]`.
  final double likelihood;

  Point2 get point => Point2(x, y);
}

/// The result of running pose detection on one camera frame, plus the frame
/// context needed to interpret it (gravity direction, orientation).
class PoseResult {
  const PoseResult({
    required this.landmarks,
    required this.timestamp,
    this.gravity,
    this.orientationTag = 0,
  });

  /// An empty result for frames where no body was detected.
  const PoseResult.empty(
    this.timestamp, {
    this.gravity,
    this.orientationTag = 0,
  }) : landmarks = const {};

  final Map<LandmarkType, PoseLandmark> landmarks;
  final DateTime timestamp;

  /// Unit vector pointing *down* in image coordinates, when the device's
  /// motion sensor is available. Null means "assume image +y is down".
  final Vec3? gravity;

  /// Changes whenever the frame orientation/rotation changes, so consumers
  /// can drop in-flight comparisons across the change.
  final int orientationTag;

  bool get hasPose => landmarks.isNotEmpty;

  PoseLandmark? operator [](LandmarkType type) => landmarks[type];

  /// Likelihood of [type], or `0` if the landmark is missing.
  double confidenceOf(LandmarkType type) => landmarks[type]?.likelihood ?? 0;

  /// Direction that is "up" for the body: opposite of gravity when known,
  /// otherwise the image's negative y axis.
  Vec3 get up => gravity == null ? const Vec3(0, -1, 0) : -gravity!;

  /// True when gravity came from a real sensor rather than the image axis.
  bool get hasGravity => gravity != null;

  /// Mean likelihood over the six key joints of [side].
  double sideConfidence(BodySide side) {
    final types = [
      side.shoulder,
      side.elbow,
      side.wrist,
      side.hip,
      side.knee,
      side.ankle,
    ];
    var sum = 0.0;
    for (final t in types) {
      sum += confidenceOf(t);
    }
    return sum / types.length;
  }

  /// Overall confidence: mean likelihood of all tracked body joints.
  double get confidence {
    if (landmarks.isEmpty) return 0;
    return (sideConfidence(BodySide.left) + sideConfidence(BodySide.right)) / 2;
  }

  /// The side whose joints are detected with higher confidence.
  BodySide get preferredSide =>
      sideConfidence(BodySide.left) >= sideConfidence(BodySide.right)
      ? BodySide.left
      : BodySide.right;

  Vec3? _pos(LandmarkType type) => landmarks[type]?.position;

  /// Position of [type] in uniform units with depth dropped (image plane).
  Vec3? position2D(LandmarkType type) {
    final p = _pos(type);
    return p == null ? null : Vec3(p.x, p.y, 0);
  }

  /// Mean image-plane position of the given landmarks (those present).
  Vec3? mean2D(Iterable<LandmarkType> types) {
    var sum = Vec3.zero;
    var n = 0;
    for (final t in types) {
      final p = position2D(t);
      if (p == null) continue;
      sum = sum + p;
      n++;
    }
    return n == 0 ? null : sum * (1 / n);
  }

  /// Distance between two landmarks in the image plane, or `null`.
  double? distance2D(LandmarkType a, LandmarkType b) {
    final pa = position2D(a);
    final pb = position2D(b);
    if (pa == null || pb == null) return null;
    return Geometry.distance3(pa, pb);
  }

  /// Fraction of the limb's depth-inclusive length that is visible in the
  /// image plane: 1 when the limb lies in the image plane, small when it
  /// points at the camera.
  static const _foreshortenedBelow = 0.6;

  /// A depth-inclusive angle this much smaller than the planar one means
  /// the bend happens towards the camera and the planar angle is blind to it.
  static const _depthBendMargin = 25.0;

  /// Angle at [b] formed by [a]→[b]→[c]. Uses the reliable image-plane angle
  /// unless the limb is strongly foreshortened or bends mostly in depth, in
  /// which case the depth-inclusive angle is used. `null` if a joint is
  /// missing.
  double? jointAngle(LandmarkType a, LandmarkType b, LandmarkType c) {
    final pa = _pos(a);
    final pb = _pos(b);
    final pc = _pos(c);
    if (pa == null || pb == null || pc == null) return null;
    final a2 = Vec3(pa.x, pa.y, 0);
    final b2 = Vec3(pb.x, pb.y, 0);
    final c2 = Vec3(pc.x, pc.y, 0);
    final planar = Geometry.angleAt3(a2, b2, c2);
    final spatial = Geometry.angleAt3(pa, pb, pc);
    final len3 = Geometry.distance3(pa, pb) + Geometry.distance3(pb, pc);
    final len2 = Geometry.distance3(a2, b2) + Geometry.distance3(b2, c2);
    if (len3 > 0 && len2 / len3 < _foreshortenedBelow) return spatial;
    if (spatial < planar - _depthBendMargin) return spatial;
    return planar;
  }

  /// Elbow angle (shoulder→elbow→wrist) in degrees for [side].
  double? elbowAngle(BodySide side) =>
      jointAngle(side.shoulder, side.elbow, side.wrist);

  /// Knee angle (hip→knee→ankle) in degrees for [side].
  double? kneeAngle(BodySide side) =>
      jointAngle(side.hip, side.knee, side.ankle);

  /// Torso angle (shoulder→hip→knee) in degrees for [side]: ~180 lying flat
  /// or standing straight, small when sitting up or folded.
  double? torsoAngle(BodySide side) =>
      jointAngle(side.shoulder, side.hip, side.knee);

  /// Body alignment angle (shoulder→hip→ankle) in degrees for [side].
  /// Falls back to the knee when the ankle is missing. `null` if unavailable.
  double? bodyAlignmentAngle(BodySide side) {
    final ankle = landmarks[side.ankle] != null ? side.ankle : side.knee;
    return jointAngle(side.shoulder, side.hip, ankle);
  }

  /// Signed height of [a] above [b] along [up], as a fraction of [scale].
  double? heightAbove(LandmarkType a, LandmarkType b, double scale) {
    final pa = _pos(a);
    final pb = _pos(b);
    if (pa == null || pb == null || scale == 0) return null;
    return (pa - pb).dot(up) / scale;
  }

  /// Angle in degrees between the body line (shoulder→ankle or knee) and the
  /// horizontal plane, in `[0, 90]`: a plank is small, standing is near 90.
  /// Uses gravity when known; otherwise the image horizontal.
  double? bodyTiltDegrees(BodySide side) {
    final s = _pos(side.shoulder);
    final a = _pos(side.ankle) ?? _pos(side.knee);
    if (s == null || a == null) return null;
    final raw = a - s;
    // Depth is the noisiest axis: halve its influence on the tilt.
    final body = Vec3(raw.x, raw.y, raw.z * 0.5);
    if (body.length == 0) return null;
    final angleToUp = Geometry.angleBetween(body, up);
    // 0° or 180° to "up" means vertical; 90° means horizontal.
    return (90 - angleToUp).abs();
  }

  /// How far the wrist sits *below* the shoulder along the body's up
  /// direction, as a fraction of the upper-arm length. Positive when the
  /// hands are lower than the shoulders (the push-up case). `null` if
  /// unavailable.
  double? wristBelowShoulderRatio(BodySide side) {
    final s = _pos(side.shoulder);
    final e = _pos(side.elbow);
    final w = _pos(side.wrist);
    if (s == null || e == null || w == null) return null;
    final upperArm = Geometry.distance3(s, e);
    if (upperArm == 0) return null;
    return (s - w).dot(up) / upperArm;
  }

  /// Length of the upper arm (shoulder→elbow) in uniform units, or `null`.
  double? upperArmLength(BodySide side) {
    final s = _pos(side.shoulder);
    final e = _pos(side.elbow);
    if (s == null || e == null) return null;
    return Geometry.distance3(s, e);
  }

  /// Signed hip deviation from the shoulder–ankle line along [up], as a
  /// fraction of the shoulder–ankle distance. Positive means hips are raised
  /// (pike), negative means sagging. `null` if unavailable.
  double? hipDeviationRatio(BodySide side) {
    final s = _pos(side.shoulder);
    final h = _pos(side.hip);
    final a = _pos(side.ankle) ?? _pos(side.knee);
    if (s == null || h == null || a == null) return null;
    final length = Geometry.distance3(s, a);
    if (length == 0) return null;
    return Geometry.deviationAlong(h, s, a, up) / length;
  }
}
