import 'dart:math' as math;

import 'package:levelex/core/utils/geometry.dart';
import 'package:levelex/features/workout/analysis/exercise_analyzer.dart';
import 'package:levelex/models/pose_result.dart';

/// World frame (metres): x along the floor (head/front at 0, feet at +x for
/// a plank), y up, z lateral. The floor is y = 0.
class Body {
  Body(this.joints);

  final Map<LandmarkType, Vec3> joints;

  static Map<LandmarkType, Vec3> _bilateral(
    Map<LandmarkType, Vec3> Function(BodySide s, double sign) build,
  ) {
    final joints = <LandmarkType, Vec3>{};
    joints.addAll(build(BodySide.left, 1));
    joints.addAll(build(BodySide.right, -1));
    return joints;
  }

  /// Push-up body with elbow angle [elbowAngle] (degrees), with real
  /// mechanics: hands planted a little wider than the shoulders, shoulder
  /// width constant, the shoulders lowering (and drifting slightly towards
  /// the head) while the elbows bend back and out, placed by two-bone IK.
  /// [hipOffset] moves the hips up (+) or down (−) in metres.
  factory Body.pushUp(double elbowAngle, {double hipOffset = 0}) {
    const upper = 0.30, fore = 0.28;
    final theta = elbowAngle * math.pi / 180;
    // Shoulder–wrist distance for this elbow angle (law of cosines).
    final reach = math.sqrt(
      upper * upper + fore * fore - 2 * upper * fore * math.cos(theta),
    );
    final bend = ((180 - elbowAngle) / 90).clamp(0.0, 1.0);
    final forward = 0.06 * bend; // shoulders drift towards the head
    const lateral = 0.06; // hands wider than the shoulders
    final height = math.sqrt(
      math.max(0, reach * reach - forward * forward - lateral * lateral),
    );
    const ankleY = 0.05;
    final joints = _bilateral((s, sign) {
      final wrist = Vec3(0, 0, 0.25 * sign);
      final shoulder = Vec3(-forward, height, 0.19 * sign);
      // Elbow on the circle around the shoulder–wrist line, pushed back
      // (+x, towards the feet) and out.
      final axis = wrist - shoulder;
      final dist = axis.length;
      final along = (upper * upper - fore * fore + dist * dist) / (2 * dist);
      final radius = math.sqrt(math.max(0, upper * upper - along * along));
      final unit = axis * (1 / dist);
      final pole = Vec3(1, 0, 0.6 * sign);
      final perp = pole - unit * pole.dot(unit);
      final perpUnit = perp * (1 / perp.length);
      final elbow = shoulder + unit * along + perpUnit * radius;
      final hipY = (shoulder.y + ankleY) / 2 + hipOffset;
      return {
        s.shoulder: shoulder,
        s.elbow: elbow,
        s.wrist: wrist,
        s.hip: Vec3(shoulder.x + 0.5, hipY, 0.15 * sign),
        s.knee: Vec3(
          shoulder.x + 0.75,
          (hipY + ankleY) / 2 + hipOffset / 2,
          0.1 * sign,
        ),
        s.ankle: Vec3(shoulder.x + 1.0, ankleY, 0.1 * sign),
      };
    });
    final sh = joints[LandmarkType.leftShoulder]!;
    joints[LandmarkType.nose] = Vec3(sh.x - 0.15, sh.y - 0.05, 0);
    return Body(joints);
  }

  /// Standing body swinging its forearms (elbow angle [elbowAngle]).
  factory Body.standing(double elbowAngle) {
    final theta = (180 - elbowAngle) * math.pi / 180;
    final joints = _bilateral(
      (s, sign) => {
        s.shoulder: Vec3(0, 1.4, 0.2 * sign),
        s.elbow: Vec3(0, 1.1, 0.22 * sign),
        s.wrist: Vec3(
          0.3 * math.sin(theta),
          1.1 - 0.3 * math.cos(theta),
          0.22 * sign,
        ),
        s.hip: Vec3(0, 0.9, 0.15 * sign),
        s.knee: Vec3(0, 0.5, 0.1 * sign),
        s.ankle: Vec3(0, 0.05, 0.1 * sign),
      },
    );
    joints[LandmarkType.nose] = const Vec3(0.05, 1.6, 0);
    return Body(joints);
  }

  /// Push-up with bent elbows but the body left at the top: an arm twitch.
  factory Body.elbowTwitch(double elbowAngle) {
    final up = Body.pushUp(170);
    final bent = Body.pushUp(elbowAngle);
    final joints = Map<LandmarkType, Vec3>.from(up.joints);
    for (final s in BodySide.values) {
      joints[s.elbow] = bent.joints[s.elbow]!;
      joints[s.wrist] = Vec3(0.25, 0.3, bent.joints[s.wrist]!.z);
    }
    return Body(joints);
  }

  /// Squat with knee angle [kneeAngle]: feet planted, hips drop as the knees
  /// bend, torso upright, arms hanging.
  factory Body.squat(double kneeAngle) {
    const leg = 0.45;
    final phi = kneeAngle * math.pi / 180;
    final hipY = 0.05 + 2 * leg * math.sin(phi / 2);
    final kneeX = leg * math.cos(phi / 2);
    final kneeY = 0.05 + leg * math.sin(phi / 2);
    final joints = _bilateral(
      (s, sign) => {
        s.ankle: Vec3(0, 0.05, 0.12 * sign),
        s.knee: Vec3(kneeX, kneeY, 0.12 * sign),
        s.hip: Vec3(0, hipY, 0.15 * sign),
        s.shoulder: Vec3(0.02, hipY + 0.5, 0.2 * sign),
        s.elbow: Vec3(0.08, hipY + 0.2, 0.22 * sign),
        s.wrist: Vec3(0.12, hipY - 0.1, 0.22 * sign),
      },
    );
    joints[LandmarkType.nose] = Vec3(0.05, hipY + 0.7, 0);
    return Body(joints);
  }

  /// Lunge: left leg forward with knee angle [frontKneeAngle], right leg
  /// trailing; hips drop with the front knee.
  factory Body.lunge(double frontKneeAngle) {
    const leg = 0.45;
    final phi = frontKneeAngle * math.pi / 180;
    final hipY = 0.05 + 2 * leg * math.sin(phi / 2);
    final joints = <LandmarkType, Vec3>{
      LandmarkType.leftAnkle: const Vec3(0.3, 0.05, 0.12),
      LandmarkType.leftKnee: Vec3(
        0.3 + leg * math.cos(phi / 2),
        0.05 + leg * math.sin(phi / 2),
        0.12,
      ),
      LandmarkType.leftHip: Vec3(0.3, hipY, 0.15),
      LandmarkType.rightAnkle: const Vec3(-0.4, 0.05, -0.12),
      LandmarkType.rightKnee: Vec3(-0.15, hipY * 0.45, -0.12),
      LandmarkType.rightHip: Vec3(0.3, hipY, -0.15),
    };
    for (final (s, sign) in [(BodySide.left, 1.0), (BodySide.right, -1.0)]) {
      joints[s.shoulder] = Vec3(0.32, hipY + 0.5, 0.2 * sign);
      joints[s.elbow] = Vec3(0.36, hipY + 0.2, 0.22 * sign);
      joints[s.wrist] = Vec3(0.38, hipY - 0.1, 0.22 * sign);
    }
    joints[LandmarkType.nose] = Vec3(0.35, hipY + 0.7, 0);
    return Body(joints);
  }

  /// Jumping jack with openness [open] in `[0, 1]`: 0 = feet together, arms
  /// down; 1 = feet apart, arms overhead.
  factory Body.jumpingJack(double open) {
    final spread = 0.1 + 0.35 * open;
    final joints = _bilateral(
      (s, sign) => {
        s.ankle: Vec3(0, 0.05, spread * sign),
        s.knee: Vec3(0, 0.5, (0.1 + 0.2 * open) * sign),
        s.hip: Vec3(0, 0.9, 0.15 * sign),
        s.shoulder: Vec3(0, 1.4, 0.2 * sign),
        s.elbow: Vec3(0, 1.4 - 0.3 + 0.55 * open, (0.25 + 0.2 * open) * sign),
        s.wrist: Vec3(0, 0.9 + 1.05 * open, (0.25 + 0.1 * open) * sign),
      },
    );
    joints[LandmarkType.nose] = const Vec3(0.05, 1.6, 0);
    return Body(joints);
  }

  /// Sit-up with torso angle [torsoAngle] (shoulder→hip→knee): ~160 lying
  /// back, ~80 sitting up. Knees bent, feet planted.
  factory Body.sitUp(double torsoAngle) {
    final psi = torsoAngle * math.pi / 180;
    final joints = _bilateral((s, sign) {
      final hip = Vec3(0.5, 0.12, 0.15 * sign);
      final knee = Vec3(0.78, 0.38, 0.12 * sign);
      final ankle = Vec3(0.98, 0.05, 0.12 * sign);
      // Rotate the hip→knee direction by psi (towards the head) to place
      // the shoulder 0.5 m from the hip.
      final u = (knee - hip).normalized;
      final c = math.cos(psi);
      final sn = math.sin(psi);
      final dir = Vec3(u.x * c - u.y * sn, u.x * sn + u.y * c, 0);
      final shoulder = hip + dir * 0.5;
      return {
        s.hip: hip,
        s.knee: knee,
        s.ankle: ankle,
        s.shoulder: Vec3(shoulder.x, shoulder.y, 0.2 * sign),
        s.elbow: Vec3(shoulder.x + 0.1, shoulder.y + 0.1, 0.22 * sign),
        s.wrist: Vec3(shoulder.x + 0.2, shoulder.y + 0.2, 0.22 * sign),
      };
    });
    return Body(joints);
  }

  /// Linear blend between two bodies (for burpee transitions).
  factory Body.blend(Body a, Body b, double t) {
    final joints = <LandmarkType, Vec3>{};
    for (final entry in a.joints.entries) {
      final other = b.joints[entry.key];
      if (other == null) continue;
      joints[entry.key] = entry.value * (1 - t) + other * t;
    }
    return Body(joints);
  }

  /// A hand-sized fragment: what ML Kit produces when it latches onto a hand
  /// waved in front of the camera. All joints inside a 10 cm box.
  factory Body.handFragment(Vec3 at) {
    final r = math.Random(7);
    final joints = <LandmarkType, Vec3>{};
    for (final type in LandmarkType.values) {
      joints[type] = at + Vec3(r.nextDouble() * 0.1, r.nextDouble() * 0.1, 0);
    }
    return Body(joints);
  }
}

/// Orthographic camera: image axes expressed in world coordinates.
class View {
  const View(this.right, this.down, this.forward, {this.scale = 0.35});

  final Vec3 right;
  final Vec3 down;
  final Vec3 forward;
  final double scale;

  /// Phone beside the user, looking across the body.
  static const side = View(Vec3(1, 0, 0), Vec3(0, -1, 0), Vec3(0, 0, -1));

  /// Phone on the floor in front, looking along the body (x axis).
  static const front = View(Vec3(0, 0, 1), Vec3(0, -1, 0), Vec3(1, 0, 0));

  /// Phone propped up in front, looking down at 45°.
  static const elevated = View(
    Vec3(0, 0, 1),
    Vec3(-0.7071067811865476, -0.7071067811865476, 0),
    Vec3(0.7071067811865476, -0.7071067811865476, 0),
  );

  Vec3 gravityInImage() {
    const g = Vec3(0, -1, 0);
    return Vec3(g.dot(right), g.dot(down), g.dot(forward));
  }

  PoseResult project(
    Body body, {
    required DateTime at,
    bool withGravity = true,
    double confidence = 0.9,
    Map<LandmarkType, double> confidenceOverrides = const {},
    double offsetX = 0.5,
    double offsetY = 0.55,
    int orientationTag = 0,
    double depthNoise = 0,
    int noiseSeed = 1,
  }) {
    final lh = body.joints[LandmarkType.leftHip];
    final rh = body.joints[LandmarkType.rightHip];
    final hipMid = lh != null && rh != null
        ? lh.midpoint(rh)
        : body.joints.values.isEmpty
        ? Vec3.zero
        : body.joints.values.first;
    final hipDepth = hipMid.dot(forward);
    final r = math.Random(noiseSeed);
    final landmarks = <LandmarkType, PoseLandmark>{};
    body.joints.forEach((type, world) {
      final x = world.dot(right) * scale + offsetX;
      final y = world.dot(down) * scale + offsetY;
      final noise = depthNoise == 0 ? 0.0 : (r.nextDouble() - 0.5) * depthNoise;
      final z = (world.dot(forward) - hipDepth) * scale + noise;
      landmarks[type] = PoseLandmark(
        type: type,
        x: x,
        y: y,
        position: Vec3(x, y, z),
        likelihood: confidenceOverrides[type] ?? confidence,
      );
    });
    return PoseResult(
      landmarks: landmarks,
      timestamp: at,
      gravity: withGravity ? gravityInImage() : null,
      orientationTag: orientationTag,
    );
  }
}

/// Drives an analyzer through phases of synthetic bodies.
class Driver {
  Driver(
    this.analyzer, {
    this.view = View.side,
    this.framesPerPhase = 4,
    this.frameGap = 80,
    this.withGravity = true,
    this.depthNoise = 0,
  });

  final ExerciseAnalyzer analyzer;
  final View view;
  final int framesPerPhase;
  final int frameGap;
  final bool withGravity;
  final double depthNoise;
  DateTime now = DateTime(2026, 1, 1, 9);
  int orientationTag = 0;
  int _seed = 1;
  ExerciseAnalysis? last;

  ExerciseAnalysis feed(
    Body body, {
    Map<LandmarkType, double> conf = const {},
    double? offsetX,
  }) {
    now = now.add(Duration(milliseconds: frameGap));
    last = analyzer.processPose(
      view.project(
        body,
        at: now,
        withGravity: withGravity,
        confidenceOverrides: conf,
        orientationTag: orientationTag,
        depthNoise: depthNoise,
        noiseSeed: _seed++,
        offsetX: offsetX ?? 0.5,
      ),
    );
    return last!;
  }

  ExerciseAnalysis feedEmpty() {
    now = now.add(Duration(milliseconds: frameGap));
    last = analyzer.processPose(PoseResult.empty(now));
    return last!;
  }

  void phase(Body body, {int? frames}) {
    for (var i = 0; i < (frames ?? framesPerPhase); i++) {
      feed(body);
    }
  }

  /// Settles the tracker and the counter on [rest] before a test starts.
  void settle(Body rest) => phase(rest, frames: framesPerPhase + 3);

  /// Moves gradually from [from] to [to] over [steps] frames (the final
  /// frame is [to] itself), like a real movement filmed at ~12 FPS.
  void transition(Body from, Body to, {int steps = 3}) {
    for (var i = 1; i <= steps; i++) {
      feed(Body.blend(from, to, i / steps));
    }
  }
}
