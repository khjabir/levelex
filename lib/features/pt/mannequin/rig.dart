import 'dart:math' as math;

import '../../../core/utils/geometry.dart';

/// 3×3 rotation matrix.
class Mat3 {
  const Mat3(this.m);

  final List<double> m;

  static const identity = Mat3([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  static Mat3 rotX(double deg) {
    final r = deg * math.pi / 180;
    final c = math.cos(r);
    final s = math.sin(r);
    return Mat3([1, 0, 0, 0, c, -s, 0, s, c]);
  }

  static Mat3 rotY(double deg) {
    final r = deg * math.pi / 180;
    final c = math.cos(r);
    final s = math.sin(r);
    return Mat3([c, 0, s, 0, 1, 0, -s, 0, c]);
  }

  static Mat3 rotZ(double deg) {
    final r = deg * math.pi / 180;
    final c = math.cos(r);
    final s = math.sin(r);
    return Mat3([c, -s, 0, s, c, 0, 0, 0, 1]);
  }

  Mat3 operator *(Mat3 o) {
    final a = m;
    final b = o.m;
    return Mat3([
      a[0] * b[0] + a[1] * b[3] + a[2] * b[6],
      a[0] * b[1] + a[1] * b[4] + a[2] * b[7],
      a[0] * b[2] + a[1] * b[5] + a[2] * b[8],
      a[3] * b[0] + a[4] * b[3] + a[5] * b[6],
      a[3] * b[1] + a[4] * b[4] + a[5] * b[7],
      a[3] * b[2] + a[4] * b[5] + a[5] * b[8],
      a[6] * b[0] + a[7] * b[3] + a[8] * b[6],
      a[6] * b[1] + a[7] * b[4] + a[8] * b[7],
      a[6] * b[2] + a[7] * b[5] + a[8] * b[8],
    ]);
  }

  Vec3 apply(Vec3 v) => Vec3(
    m[0] * v.x + m[1] * v.y + m[2] * v.z,
    m[3] * v.x + m[4] * v.y + m[5] * v.z,
    m[6] * v.x + m[7] * v.y + m[8] * v.z,
  );
}

/// Joint angles (degrees) that describe one body position. The figure faces
/// +Z, Y is up, +X is the figure's left. Zero everywhere is standing tall.
class RigPose {
  const RigPose({
    this.bodyPitch = 0,
    this.bodyYaw = 0,
    this.bodyRoll = 0,
    this.spinePitch = 0,
    this.spineRoll = 0,
    this.spineYaw = 0,
    this.neckPitch = 0,
    this.shoulderFlexL = 0,
    this.shoulderFlexR = 0,
    this.shoulderAbdL = 6,
    this.shoulderAbdR = 6,
    this.armRotL = 0,
    this.armRotR = 0,
    this.elbowL = 8,
    this.elbowR = 8,
    this.hipFlexL = 0,
    this.hipFlexR = 0,
    this.hipAbdL = 4,
    this.hipAbdR = 4,
    this.kneeL = 4,
    this.kneeR = 4,
    this.lift = 0,
  });

  /// Symmetric pose: the same angles on both sides.
  const RigPose.sym({
    double bodyPitch = 0,
    double bodyYaw = 0,
    double bodyRoll = 0,
    double spinePitch = 0,
    double spineRoll = 0,
    double spineYaw = 0,
    double neckPitch = 0,
    double shoulderFlex = 0,
    double shoulderAbd = 6,
    double armRot = 0,
    double elbow = 8,
    double hipFlex = 0,
    double hipAbd = 4,
    double knee = 4,
    double lift = 0,
  }) : this(
         bodyPitch: bodyPitch,
         bodyYaw: bodyYaw,
         bodyRoll: bodyRoll,
         spinePitch: spinePitch,
         spineRoll: spineRoll,
         spineYaw: spineYaw,
         neckPitch: neckPitch,
         shoulderFlexL: shoulderFlex,
         shoulderFlexR: shoulderFlex,
         shoulderAbdL: shoulderAbd,
         shoulderAbdR: shoulderAbd,
         armRotL: armRot,
         armRotR: armRot,
         elbowL: elbow,
         elbowR: elbow,
         hipFlexL: hipFlex,
         hipFlexR: hipFlex,
         hipAbdL: hipAbd,
         hipAbdR: hipAbd,
         kneeL: knee,
         kneeR: knee,
         lift: lift,
       );

  /// Whole-body tilt about X: positive leans the head forward/down (a plank
  /// is ≈ 80, lying on the back is ≈ −90).
  final double bodyPitch;
  final double bodyYaw;

  /// Whole-body tilt sideways (side plank).
  final double bodyRoll;

  /// Bend at the waist: positive folds forward.
  final double spinePitch;
  final double spineRoll;
  final double spineYaw;
  final double neckPitch;

  /// Arm forward (+) / backward (−) from hanging.
  final double shoulderFlexL;
  final double shoulderFlexR;

  /// Arm out to the side (0 hanging, 90 horizontal, 170 overhead).
  final double shoulderAbdL;
  final double shoulderAbdR;

  /// Rotation about the upper arm; 90 turns elbow bending "forward" into
  /// bending "up" (pressing).
  final double armRotL;
  final double armRotR;
  final double elbowL;
  final double elbowR;

  /// Thigh forward (+) / back (−).
  final double hipFlexL;
  final double hipFlexR;
  final double hipAbdL;
  final double hipAbdR;
  final double kneeL;
  final double kneeR;

  /// Extra height above the floor (jumps, hanging).
  final double lift;

  RigPose copyWith({
    double? bodyPitch,
    double? bodyYaw,
    double? bodyRoll,
    double? spinePitch,
    double? spineRoll,
    double? spineYaw,
    double? neckPitch,
    double? shoulderFlexL,
    double? shoulderFlexR,
    double? shoulderAbdL,
    double? shoulderAbdR,
    double? armRotL,
    double? armRotR,
    double? elbowL,
    double? elbowR,
    double? hipFlexL,
    double? hipFlexR,
    double? hipAbdL,
    double? hipAbdR,
    double? kneeL,
    double? kneeR,
    double? lift,
  }) => RigPose(
    bodyPitch: bodyPitch ?? this.bodyPitch,
    bodyYaw: bodyYaw ?? this.bodyYaw,
    bodyRoll: bodyRoll ?? this.bodyRoll,
    spinePitch: spinePitch ?? this.spinePitch,
    spineRoll: spineRoll ?? this.spineRoll,
    spineYaw: spineYaw ?? this.spineYaw,
    neckPitch: neckPitch ?? this.neckPitch,
    shoulderFlexL: shoulderFlexL ?? this.shoulderFlexL,
    shoulderFlexR: shoulderFlexR ?? this.shoulderFlexR,
    shoulderAbdL: shoulderAbdL ?? this.shoulderAbdL,
    shoulderAbdR: shoulderAbdR ?? this.shoulderAbdR,
    armRotL: armRotL ?? this.armRotL,
    armRotR: armRotR ?? this.armRotR,
    elbowL: elbowL ?? this.elbowL,
    elbowR: elbowR ?? this.elbowR,
    hipFlexL: hipFlexL ?? this.hipFlexL,
    hipFlexR: hipFlexR ?? this.hipFlexR,
    hipAbdL: hipAbdL ?? this.hipAbdL,
    hipAbdR: hipAbdR ?? this.hipAbdR,
    kneeL: kneeL ?? this.kneeL,
    kneeR: kneeR ?? this.kneeR,
    lift: lift ?? this.lift,
  );

  /// The same pose with left and right swapped (alternating movements).
  RigPose get mirrored => RigPose(
    bodyPitch: bodyPitch,
    bodyYaw: bodyYaw,
    bodyRoll: -bodyRoll,
    spinePitch: spinePitch,
    spineRoll: -spineRoll,
    spineYaw: -spineYaw,
    neckPitch: neckPitch,
    shoulderFlexL: shoulderFlexR,
    shoulderFlexR: shoulderFlexL,
    shoulderAbdL: shoulderAbdR,
    shoulderAbdR: shoulderAbdL,
    armRotL: armRotR,
    armRotR: armRotL,
    elbowL: elbowR,
    elbowR: elbowL,
    hipFlexL: hipFlexR,
    hipFlexR: hipFlexL,
    hipAbdL: hipAbdR,
    hipAbdR: hipAbdL,
    kneeL: kneeR,
    kneeR: kneeL,
    lift: lift,
  );

  static double _l(double a, double b, double t) => a + (b - a) * t;

  static RigPose lerp(RigPose a, RigPose b, double t) => RigPose(
    bodyPitch: _l(a.bodyPitch, b.bodyPitch, t),
    bodyYaw: _l(a.bodyYaw, b.bodyYaw, t),
    bodyRoll: _l(a.bodyRoll, b.bodyRoll, t),
    spinePitch: _l(a.spinePitch, b.spinePitch, t),
    spineRoll: _l(a.spineRoll, b.spineRoll, t),
    spineYaw: _l(a.spineYaw, b.spineYaw, t),
    neckPitch: _l(a.neckPitch, b.neckPitch, t),
    shoulderFlexL: _l(a.shoulderFlexL, b.shoulderFlexL, t),
    shoulderFlexR: _l(a.shoulderFlexR, b.shoulderFlexR, t),
    shoulderAbdL: _l(a.shoulderAbdL, b.shoulderAbdL, t),
    shoulderAbdR: _l(a.shoulderAbdR, b.shoulderAbdR, t),
    armRotL: _l(a.armRotL, b.armRotL, t),
    armRotR: _l(a.armRotR, b.armRotR, t),
    elbowL: _l(a.elbowL, b.elbowL, t),
    elbowR: _l(a.elbowR, b.elbowR, t),
    hipFlexL: _l(a.hipFlexL, b.hipFlexL, t),
    hipFlexR: _l(a.hipFlexR, b.hipFlexR, t),
    hipAbdL: _l(a.hipAbdL, b.hipAbdL, t),
    hipAbdR: _l(a.hipAbdR, b.hipAbdR, t),
    kneeL: _l(a.kneeL, b.kneeL, t),
    kneeR: _l(a.kneeR, b.kneeR, t),
    lift: _l(a.lift, b.lift, t),
  );
}

/// A bone of the mannequin: two joint names and a thickness in metres.
class Bone {
  const Bone(this.a, this.b, this.thickness, {this.part = 'body'});

  final String a;
  final String b;
  final double thickness;

  /// Group used for highlighting ("arms", "legs", "torso", "hips").
  final String part;
}

/// Forward kinematics for the mannequin. Produces joint positions in metres
/// with the floor at y = 0 and the figure centred on the origin.
abstract final class Rig {
  static const torso = 0.50;
  static const neck = 0.07;
  static const headOffset = 0.16;
  static const headRadius = 0.105;
  static const shoulderHalf = 0.19;
  static const upperArm = 0.30;
  static const forearm = 0.26;
  static const hand = 0.08;
  static const hipHalf = 0.10;
  static const thigh = 0.45;
  static const shin = 0.43;
  static const foot = 0.14;

  static const bones = <Bone>[
    Bone('pelvis', 'chest', 0.19, part: 'torso'),
    Bone('chest', 'neck', 0.085, part: 'torso'),
    Bone('shoulderL', 'shoulderR', 0.12, part: 'torso'),
    Bone('hipL', 'hipR', 0.15, part: 'hips'),
    Bone('shoulderL', 'elbowL', 0.095, part: 'arms'),
    Bone('elbowL', 'wristL', 0.075, part: 'arms'),
    Bone('wristL', 'handL', 0.07, part: 'arms'),
    Bone('shoulderR', 'elbowR', 0.095, part: 'arms'),
    Bone('elbowR', 'wristR', 0.075, part: 'arms'),
    Bone('wristR', 'handR', 0.07, part: 'arms'),
    Bone('hipL', 'kneeL', 0.14, part: 'legs'),
    Bone('kneeL', 'ankleL', 0.10, part: 'legs'),
    Bone('ankleL', 'toeL', 0.075, part: 'legs'),
    Bone('hipR', 'kneeR', 0.14, part: 'legs'),
    Bone('kneeR', 'ankleR', 0.10, part: 'legs'),
    Bone('ankleR', 'toeR', 0.075, part: 'legs'),
  ];

  /// Floor-to-crown height of the standing rig, the scale every clip's
  /// extents are expressed in.
  static final double standingHeight = () {
    final j = solve(const RigPose.sym());
    return j['head']!.y + headRadius;
  }();

  static Map<String, Vec3> solve(RigPose p) {
    final r0 =
        Mat3.rotY(p.bodyYaw) * Mat3.rotX(p.bodyPitch) * Mat3.rotZ(p.bodyRoll);
    const pelvis = Vec3.zero;
    final rs =
        r0 *
        Mat3.rotX(p.spinePitch) *
        Mat3.rotZ(p.spineRoll) *
        Mat3.rotY(p.spineYaw);
    final chest = pelvis + rs.apply(const Vec3(0, torso, 0));
    final neckTop = chest + rs.apply(const Vec3(0, neck, 0));
    final rh = rs * Mat3.rotX(p.neckPitch);
    final head = neckTop + rh.apply(const Vec3(0, headOffset, 0));
    final shL = chest + rs.apply(const Vec3(shoulderHalf, -0.02, 0));
    final shR = chest + rs.apply(const Vec3(-shoulderHalf, -0.02, 0));

    Vec3 limb(Mat3 r, Vec3 from, double len) =>
        from + r.apply(Vec3(0, -len, 0));

    final raL =
        rs *
        Mat3.rotZ(p.shoulderAbdL) *
        Mat3.rotX(-p.shoulderFlexL) *
        Mat3.rotY(p.armRotL);
    final elL = limb(raL, shL, upperArm);
    final rfL = raL * Mat3.rotX(-p.elbowL);
    final wrL = limb(rfL, elL, forearm);
    final haL = limb(rfL, wrL, hand);
    final raR =
        rs *
        Mat3.rotZ(-p.shoulderAbdR) *
        Mat3.rotX(-p.shoulderFlexR) *
        Mat3.rotY(-p.armRotR);
    final elR = limb(raR, shR, upperArm);
    final rfR = raR * Mat3.rotX(-p.elbowR);
    final wrR = limb(rfR, elR, forearm);
    final haR = limb(rfR, wrR, hand);

    final hipL = pelvis + r0.apply(const Vec3(hipHalf, 0, 0));
    final hipR = pelvis + r0.apply(const Vec3(-hipHalf, 0, 0));
    final rtL = r0 * Mat3.rotZ(p.hipAbdL) * Mat3.rotX(-p.hipFlexL);
    final knL = limb(rtL, hipL, thigh);
    final rsL = rtL * Mat3.rotX(p.kneeL);
    final anL = limb(rsL, knL, shin);
    final toL =
        anL +
        rsL.apply(const Vec3(0, -0.04, 0)) +
        r0.apply(const Vec3(0, 0, foot));
    final rtR = r0 * Mat3.rotZ(-p.hipAbdR) * Mat3.rotX(-p.hipFlexR);
    final knR = limb(rtR, hipR, thigh);
    final rsR = rtR * Mat3.rotX(p.kneeR);
    final anR = limb(rsR, knR, shin);
    final toR =
        anR +
        rsR.apply(const Vec3(0, -0.04, 0)) +
        r0.apply(const Vec3(0, 0, foot));

    final joints = <String, Vec3>{
      'pelvis': pelvis,
      'chest': chest,
      'neck': neckTop,
      'head': head,
      'shoulderL': shL,
      'shoulderR': shR,
      'elbowL': elL,
      'elbowR': elR,
      'wristL': wrL,
      'wristR': wrR,
      'handL': haL,
      'handR': haR,
      'hipL': hipL,
      'hipR': hipR,
      'kneeL': knL,
      'kneeR': knR,
      'ankleL': anL,
      'ankleR': anR,
      'toeL': toL,
      'toeR': toR,
    };

    // Floor at the lowest point (the head counts with its radius), centred.
    var minY = double.infinity;
    var minX = double.infinity, maxX = -double.infinity;
    var minZ = double.infinity, maxZ = -double.infinity;
    joints.forEach((name, v) {
      final y = name == 'head' ? v.y - headRadius : v.y;
      if (y < minY) minY = y;
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.z < minZ) minZ = v.z;
      if (v.z > maxZ) maxZ = v.z;
    });
    final shift = Vec3(-(minX + maxX) / 2, -minY + p.lift, -(minZ + maxZ) / 2);
    final out = {for (final e in joints.entries) e.key: e.value + shift};
    // A foot whose ankle is on the floor lies flat, pointing away from the
    // hips. The foot is attached to the body's facing, which points at the
    // sky when lying on the back, so knees-bent floor work (sit-ups,
    // bridges) had its toes sticking up and the feet hovering.
    for (final (ankle, toe) in const [('ankleL', 'toeL'), ('ankleR', 'toeR')]) {
      final a = out[ankle]!, t = out[toe]!;
      if (a.y - p.lift > 0.12 || t.y - a.y < 0.03) continue;
      var dir = Vec3(t.x - a.x, 0, t.z - a.z);
      if (dir.length < 0.05) {
        final pelvis = out['pelvis']!;
        dir = Vec3(a.x - pelvis.x, 0, a.z - pelvis.z);
      }
      if (dir.length < 1e-6) continue;
      final flat = dir.normalized * foot;
      out[toe] = Vec3(a.x + flat.x, math.max(p.lift, a.y - 0.02), a.z + flat.z);
    }
    return out;
  }
}

/// A looping animation of [RigPose] keyframes.
class MannequinClip {
  const MannequinClip({
    required this.id,
    required this.frames,
    required this.durations,
    this.pingPong = true,
    this.highlight = const {},
    this.continuous = false,
  });

  final String id;
  final List<RigPose> frames;

  /// Constant-speed looping (circles) instead of easing into every key.
  final bool continuous;

  /// Milliseconds between frame i and i+1 (and, when not ping-pong, from
  /// the last frame back to the first).
  final List<int> durations;

  /// Play forwards then backwards (most reps) instead of wrapping around.
  final bool pingPong;

  /// Bone parts drawn in the warning colour.
  final Set<String> highlight;

  /// Reps lower slower than they rise: the way out (eccentric) takes this
  /// share more time, the way back (concentric) this share less.
  static const eccentricFactor = 1.15;
  static const concentricFactor = 0.85;

  int _forwardMs(int d) =>
      pingPong && !continuous ? (d * eccentricFactor).round() : d;
  int _backMs(int d) => continuous ? d : (d * concentricFactor).round();

  List<(RigPose, RigPose, int)> get _segments {
    final segs = <(RigPose, RigPose, int)>[];
    if (frames.length == 1) return [(frames[0], frames[0], durations[0])];
    for (var i = 0; i < frames.length - 1; i++) {
      segs.add((frames[i], frames[i + 1], _forwardMs(durations[i])));
    }
    if (pingPong) {
      for (var i = frames.length - 1; i > 0; i--) {
        segs.add((frames[i], frames[i - 1], _backMs(durations[i - 1])));
      }
    } else {
      segs.add((frames.last, frames.first, durations.last));
    }
    return segs;
  }

  int get totalMs => _segments.fold(0, (a, s) => a + s.$3);

  // ---------------------------------------------------------------------------
  // Ground contacts
  // ---------------------------------------------------------------------------

  /// Joints that can carry weight on the floor.
  static const _contactJoints = [
    'toeL',
    'toeR',
    'ankleL',
    'ankleR',
    'handL',
    'handR',
    'wristL',
    'wristR',
    'kneeL',
    'kneeR',
    'pelvis',
    'chest',
    'head',
  ];

  /// A joint this close to the floor is planted.
  static const _contactHeight = 0.09;

  /// Solved keyframes, their planted joints and offsets, computed once per
  /// clip (the class is const, so they live beside it).
  static final _cache = Expando<_ClipContacts>();

  _ClipContacts get _c => _cache[this] ??= _ClipContacts(this);

  List<Map<String, Vec3>> get _solved => _c.solved;
  List<Set<String>> get _contacts => _c.contacts;

  /// Horizontal translation of each keyframe that keeps the joints planted
  /// in both neighbouring keyframes (feet, hands, hips, back) in the same
  /// place, instead of re-centring every pose, which made hands and feet
  /// slide across the floor. Airborne transitions keep the pelvis over the
  /// same spot. Loops that would drift spread the drift over the loop.
  List<Vec3> get keyOffsets => _c.offsets ??= _computeOffsets();

  /// Priority of a planted joint when hands and feet disagree (the hands
  /// stay while the feet jump back in a burpee).
  static int _priority(String joint) => switch (joint) {
    'wristL' || 'wristR' || 'handL' || 'handR' => 3,
    'toeL' || 'toeR' || 'ankleL' || 'ankleR' => 2,
    'kneeL' || 'kneeR' => 1,
    _ => 0,
  };

  /// The planted joints that stay put between keyframes [a] and [b]: the
  /// largest set that agrees on one translation (hands first, then feet),
  /// so a foot that steps or jumps is not averaged with the one that stays.
  Set<String> _anchors(int a, int b) {
    final key = a < b ? (a, b) : (b, a);
    return _c.anchors[key] ??= () {
      final common = _contacts[a].intersection(_contacts[b]);
      if (common.isEmpty) return const {'pelvis'};
      final ja = _solved[a], jb = _solved[b];
      Vec3 implied(String n) {
        final d = ja[n]! - jb[n]!;
        return Vec3(d.x, 0, d.z);
      }

      Set<String>? best;
      (int, int, double)? bestScore;
      for (final n in common) {
        final c = implied(n);
        final inliers = {
          for (final m in common)
            if ((implied(m) - c).length < 0.03) m,
        };
        final score = (
          inliers.length,
          inliers.map(_priority).reduce(math.max),
          -c.length,
        );
        final s = bestScore;
        if (s == null ||
            score.$1 > s.$1 ||
            (score.$1 == s.$1 && score.$2 > s.$2) ||
            (score.$1 == s.$1 && score.$2 == s.$2 && score.$3 > s.$3)) {
          best = inliers;
          bestScore = score;
        }
      }
      return best!;
    }();
  }

  Vec3 _step(int a, int b, Vec3 offA) {
    final ja = _solved[a], jb = _solved[b];
    final names = _anchors(a, b);
    var sum = Vec3.zero;
    for (final n in names) {
      final d = ja[n]! + offA - jb[n]!;
      sum = sum + Vec3(d.x, 0, d.z);
    }
    return sum * (1 / names.length);
  }

  List<Vec3> _computeOffsets() {
    final n = frames.length;
    final offs = List<Vec3>.filled(n, Vec3.zero);
    for (var i = 1; i < n; i++) {
      offs[i] = _step(i - 1, i, offs[i - 1]);
    }
    if (!pingPong && n > 1) {
      final drift = _step(n - 1, 0, offs[n - 1]) - offs[0];
      for (var i = 1; i < n; i++) {
        offs[i] = offs[i] - drift * (i / n);
      }
    }
    var mean = Vec3.zero;
    for (final o in offs) {
      mean = mean + o;
    }
    mean = mean * (1 / n);
    return [for (final o in offs) o - mean];
  }

  /// Keyframe [i]'s joints, planted (see [keyOffsets]).
  Map<String, Vec3> keyJoints(int i) => {
    for (final e in _solved[i].entries) e.key: e.value + keyOffsets[i],
  };

  /// Translation to add to `Rig.solve(at(ms))` so the joints planted at
  /// both ends of the current segment stay exactly where they are.
  Vec3 offsetAt(int ms) {
    if (frames.length < 2) return keyOffsets.first;
    var t = ms % totalMs;
    for (final (a, b, d) in _segmentIndices) {
      if (t < d) {
        final u = _ease(d == 0 ? 1.0 : t / d);
        final joints = Rig.solve(RigPose.lerp(frames[a], frames[b], u));
        final names = _anchors(a, b);
        var sum = Vec3.zero;
        for (final n in names) {
          final wa = _solved[a][n]! + keyOffsets[a];
          final wb = _solved[b][n]! + keyOffsets[b];
          final world = wa + (wb - wa) * u;
          final dv = world - joints[n]!;
          sum = sum + Vec3(dv.x, 0, dv.z);
        }
        return sum * (1 / names.length);
      }
      t -= d;
    }
    return keyOffsets.first;
  }

  RigPose at(int ms) {
    final segs = _segments;
    var t = ms % totalMs;
    for (final (a, b, d) in segs) {
      if (t < d) {
        final u = d == 0 ? 1.0 : t / d;
        return RigPose.lerp(a, b, _ease(u));
      }
      t -= d;
    }
    return frames.first;
  }

  /// Ease in and out of every keyframe (reps pause at the top and bottom),
  /// or run at constant speed for continuous loops such as circles.
  double _ease(double u) {
    if (continuous) return u;
    // Smootherstep: zero velocity and zero acceleration at both keys, so
    // the body settles into the top and bottom instead of bouncing off.
    return u * u * u * (u * (u * 6 - 15) + 10);
  }

  /// Keyframe indices of each segment, in the same order as [_segments].
  List<(int, int, int)> get _segmentIndices {
    final segs = <(int, int, int)>[];
    if (frames.length == 1) return [(0, 0, durations[0])];
    for (var i = 0; i < frames.length - 1; i++) {
      segs.add((i, i + 1, _forwardMs(durations[i])));
    }
    if (pingPong) {
      for (var i = frames.length - 1; i > 0; i--) {
        segs.add((i, i - 1, _backMs(durations[i - 1])));
      }
    } else {
      segs.add((frames.length - 1, 0, durations.last));
    }
    return segs;
  }

  /// Fractional keyframe position at [ms] (e.g. 1.5 = half way from
  /// keyframe 1 to keyframe 2), with the same easing as [at], so a skinned
  /// body animated from the same keyframes stays in step with the rig.
  ///
  /// A loop that does not ping-pong closes from its last keyframe to a copy
  /// of the first at position [frames.length] (see [hasClosingKey]); going
  /// from the last position back down to 0 swept the body through every
  /// keyframe in between (a burpee flashed back through the plank).
  double framePosition(int ms) {
    var t = ms % totalMs;
    for (final (a, b, d) in _segmentIndices) {
      if (t < d) {
        final u = d == 0 ? 1.0 : t / d;
        if (hasClosingKey && a == frames.length - 1 && b == 0) {
          return a + _ease(u);
        }
        return a + (b - a) * _ease(u);
      }
      t -= d;
    }
    return 0;
  }

  /// Whether the skinned body's animation carries an extra keyframe, a copy
  /// of the first, after the last one (loops that do not ping-pong).
  bool get hasClosingKey => !pingPong && frames.length > 1;
}

/// World-space extents of a clip, used to frame the camera so every pose of
/// the clip fills the canvas without the view zooming in and out mid-rep.
class MannequinFrame {
  const MannequinFrame({required this.height, required this.halfWidth});

  /// Highest joint above the floor across the poses.
  final double height;

  /// Largest horizontal distance of any joint from the figure's centre line,
  /// so the fit holds for any camera yaw.
  final double halfWidth;

  factory MannequinFrame.ofPoses(Iterable<RigPose> poses) {
    var maxY = 0.0, maxR = 0.0;
    for (final pose in poses) {
      for (final v in Rig.solve(pose).values) {
        if (v.y > maxY) maxY = v.y;
        final r = math.sqrt(v.x * v.x + v.z * v.z);
        if (r > maxR) maxR = r;
      }
    }
    return MannequinFrame(
      height: math.max(maxY, 0.5),
      halfWidth: math.max(maxR, 0.3),
    );
  }

  /// Extents of a clip's keyframes, including how far its planted
  /// contacts move the body around (see [MannequinClip.keyOffsets]).
  factory MannequinFrame.ofClip(MannequinClip clip) {
    var maxY = 0.0, maxR = 0.0;
    for (var i = 0; i < clip.frames.length; i++) {
      for (final v in clip.keyJoints(i).values) {
        if (v.y > maxY) maxY = v.y;
        final r = math.sqrt(v.x * v.x + v.z * v.z);
        if (r > maxR) maxR = r;
      }
    }
    return MannequinFrame(
      height: math.max(maxY, 0.5),
      halfWidth: math.max(maxR, 0.3),
    );
  }
}

class _ClipContacts {
  _ClipContacts(MannequinClip clip)
    : solved = [for (final f in clip.frames) Rig.solve(f)] {
    contacts = [
      for (final j in solved)
        {
          for (final n in MannequinClip._contactJoints)
            if (j[n]!.y - (n == 'head' ? Rig.headRadius : 0) <
                MannequinClip._contactHeight)
              n,
        },
    ];
  }

  final List<Map<String, Vec3>> solved;
  late final List<Set<String>> contacts;
  final Map<(int, int), Set<String>> anchors = {};
  List<Vec3>? offsets;
}
