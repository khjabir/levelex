import 'dart:math' as math;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/geometry.dart';
import '../../../models/exercise.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import 'exercise_analyzer.dart';
import 'rep_cycle_counter.dart';
import 'signals.dart';

/// Sit-ups: how high the shoulders are above the hips, in torso lengths
/// (≈0.1 lying back, ≈0.95 sitting up). The torso length is the longest
/// seen, which is when sitting upright. Unlike the shoulder→hip→knee angle
/// it reads the same with the phone at the side or at the feet, where the
/// torso lying back points at the camera. The hips stay planted while the
/// shoulders travel.
class SitUpAnalyzer extends CycleExerciseAnalyzer {
  SitUpAnalyzer({super.thresholds = const PushUpThresholds(), int? targetReps})
    : super(
        target: targetReps,
        cycle: CycleConfig(
          restDefault: 0.45,
          workDefault: 0.75,
          restIsHigh: false,
          minRange: 0.3,
          margin: 0.3,
          minGap: 0.15,
          decayPerFrame: 0.002,
          maxAdaptiveLoosening: 0.1,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: const Duration(milliseconds: 250),
          cooldown: const Duration(milliseconds: 400),
          shallowFraction: thresholds.shallowFraction,
        ),
      );

  final DecayingMax _torso = DecayingMax(decayPerSecond: 0.01);

  Vec3? _hipAtRest;
  double? _riseAtRest;
  double? _torsoAtRest;

  @override
  ExerciseType get type => ExerciseType.sitUp;

  List<BodySide> _sides(PoseResult pose) => [
    for (final side in BodySide.values)
      if (jointsOk(pose, [side.shoulder, side.hip, side.knee])) side,
  ];

  @override
  int limbsUsed(PoseResult pose) => _sides(pose).length;

  @override
  bool countable(PoseResult pose) => _sides(pose).isNotEmpty;

  /// Knees bent (hip→knee→ankle well under 160°) and hips lower than the
  /// shoulders are not required: any lying/sitting body with bent knees.
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final knee = pose.kneeAngle(side);
    if (knee != null && knee > 165) return false; // legs straight: not set up
    if (pose.hasGravity) {
      final tilt = pose.bodyTiltDegrees(side);
      // Standing bodies are excluded; lying/sitting bodies pass.
      if (tilt != null && tilt > 75) return false;
    }
    return true;
  }

  @override
  double? signal(PoseResult pose) {
    final s = _sides(pose);
    if (s.isEmpty) return null;
    final rise = pose.heightBetween(
      s.map((x) => x.shoulder),
      s.map((x) => x.hip),
    );
    final length = meanSegment(pose, (x) => x.shoulder, (x) => x.hip);
    if (rise == null || length == 0) return null;
    final torso = _torso.update(length, pose.timestamp);
    // The shoulders cannot rise more than a torso length above the hips;
    // until the user first sits up the torso looks short (it points at the
    // camera when filmed from the feet), so early ratios overshoot.
    return torso <= 0 ? null : (rise / torso).clamp(-0.3, 1.05);
  }

  @override
  void reset() {
    super.reset();
    _torso.reset();
  }

  /// Remembers the lowest the shoulders were while lying back (the last
  /// rest frame is already part way up and would hide the rise).
  @override
  void onRestFrame(PoseResult pose) {
    final s = _sides(pose);
    final rise = pose.heightBetween(
      s.map((x) => x.shoulder),
      s.map((x) => x.hip),
    );
    final lowest = _riseAtRest;
    if (rise != null && (lowest == null || rise <= lowest)) {
      _riseAtRest = rise;
      _hipAtRest = pose.mean2D(s.map((x) => x.hip));
      _torsoAtRest = meanSegment(pose, (x) => x.shoulder, (x) => x.hip);
    }
  }

  /// The shoulders must rise above the hips (sitting up, not just a neck
  /// curl) and the hips must stay planted. The rise is measured along "up",
  /// so it reads the same with the phone at the side or at the head or feet
  /// (where the shoulders barely move across the picture).
  @override
  bool vetoWork(PoseResult pose) {
    final s = _sides(pose);
    final torso = meanSegment(pose, (x) => x.shoulder, (x) => x.hip);
    final rise = pose.heightBetween(
      s.map((x) => x.shoulder),
      s.map((x) => x.hip),
    );
    final refRise = _riseAtRest;
    final refTorso = _torsoAtRest;
    if (rise == null || refRise == null || torso == 0) return false;
    final scale = math.max(torso, refTorso ?? 0);
    if (rise - refRise < 0.3 * scale) {
      diagnostics.reject('shouldersDidNotRise');
      return true;
    }
    final hip = pose.mean2D(s.map((x) => x.hip));
    final refH = _hipAtRest;
    if (hip != null &&
        refH != null &&
        Geometry.distance3(hip, refH) > 1.0 * scale) {
      diagnostics.reject('hipsMoved');
      return true;
    }
    // Accepted: the next lying-back phase learns its own lowest point.
    _riseAtRest = null;
    return false;
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      FormStatus.goodForm;
}

/// Glute bridges: how high the hips rise above the shoulders, in torso
/// lengths (≈0 lying, ≈0.45 at the top). Clearer than the hip angle from a
/// diagonal; filmed from the feet the hips hide behind the knees, so the
/// side is the place for the phone.
class GluteBridgeAnalyzer extends CycleExerciseAnalyzer {
  GluteBridgeAnalyzer({
    super.thresholds = const PushUpThresholds(),
    int? targetReps,
  }) : super(
         target: targetReps,
         cycle: CycleConfig(
           restDefault: 0.12,
           workDefault: 0.3,
           restIsHigh: false,
           minRange: 0.25,
           margin: 0.3,
           minGap: 0.1,
           decayPerFrame: 0.002,
           maxAdaptiveLoosening: 0.06,
           minFrames: thresholds.minFramesForTransition,
           minWorkDuration: const Duration(milliseconds: 200),
           cooldown: const Duration(milliseconds: 400),
           shallowFraction: thresholds.shallowFraction,
         ),
       );

  final DecayingMax _torso = DecayingMax(decayPerSecond: 0.01);

  @override
  ExerciseType get type => ExerciseType.gluteBridge;

  List<BodySide> _sides(PoseResult pose) => [
    for (final side in BodySide.values)
      if (jointsOk(pose, [side.shoulder, side.hip, side.knee])) side,
  ];

  @override
  int limbsUsed(PoseResult pose) => _sides(pose).length;

  @override
  bool countable(PoseResult pose) => _sides(pose).isNotEmpty;

  /// Lying down: not standing (the shoulders are not well above the hips).
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    if (pose.hasGravity) {
      final tilt = pose.bodyTiltDegrees(side);
      if (tilt != null && tilt > 70) return false;
    }
    return true;
  }

  @override
  double? signal(PoseResult pose) {
    final s = _sides(pose);
    if (s.isEmpty) return null;
    final rise = pose.heightBetween(
      s.map((x) => x.hip),
      s.map((x) => x.shoulder),
    );
    final length = meanSegment(pose, (x) => x.shoulder, (x) => x.hip);
    if (rise == null || length == 0) return null;
    final torso = _torso.update(length, pose.timestamp);
    return torso <= 0 ? null : (rise / torso).clamp(-1.0, 1.0);
  }

  @override
  void reset() {
    super.reset();
    _torso.reset();
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      FormStatus.goodForm;
}

/// Burpees: standing is rest, the floor (crouch or plank, hands down) is
/// work.
///
/// Signal: the shoulders' height above the ankles as a fraction of the
/// standing height (≈0.95 standing, 0.25-0.55 on the floor). The body's
/// tilt, used before, is unreliable when the plank points at the camera (it
/// read 40-55° there instead of ~10°), so filmed from the front burpees
/// were missed. Entering the floor position needs the hands down near the
/// floor, which a squat does not have.
class BurpeeAnalyzer extends CycleExerciseAnalyzer {
  BurpeeAnalyzer({super.thresholds = const PushUpThresholds(), int? targetReps})
    : super(
        target: targetReps,
        cycle: CycleConfig(
          restDefault: 0.8,
          workDefault: 0.62,
          minRange: 0.3,
          margin: 0.25,
          minGap: 0.12,
          decayPerFrame: 0.002,
          maxAdaptiveLoosening: 0.05,
          minFrames: thresholds.minFramesForTransition,
          minWorkDuration: const Duration(milliseconds: 250),
          cooldown: const Duration(milliseconds: 600),
        ),
      );

  final DropRatio _drop = DropRatio(decayPerSecond: 0.01);

  static const _ankles = [LandmarkType.leftAnkle, LandmarkType.rightAnkle];
  static const _shoulders = [
    LandmarkType.leftShoulder,
    LandmarkType.rightShoulder,
  ];
  static const _wrists = [LandmarkType.leftWrist, LandmarkType.rightWrist];

  @override
  ExerciseType get type => ExerciseType.burpee;

  @override
  bool countable(PoseResult pose) =>
      bodyPresent(pose, BodySide.left) || bodyPresent(pose, BodySide.right);

  /// Any visible body qualifies; the signal itself decides.
  @override
  bool inPosition(PoseResult pose) => true;

  @override
  double? signal(PoseResult pose) {
    final h = pose.heightBetween(
      _shoulders,
      _ankles,
      minConfidence: thresholds.presenceConfidence,
    );
    return _drop.update(h, pose.timestamp);
  }

  @override
  void reset() {
    super.reset();
    _drop.reset();
  }

  /// On the floor the hands must be down near the floor (within 30% of the
  /// standing shoulder height above the feet): a squat does not count.
  @override
  bool vetoWork(PoseResult pose) {
    final top = _drop.top;
    final hands = pose.heightBetween(
      _wrists,
      _ankles,
      minConfidence: thresholds.presenceConfidence,
    );
    if (top == null || top <= 0 || hands == null) return false;
    if (hands / top > 0.3) {
      diagnostics.reject('handsNotDown');
      return true;
    }
    return false;
  }

  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) =>
      FormStatus.goodForm;
}

/// Jumping jacks: openness = arms raised + feet spread. Closed is rest.
///
/// From the side the feet spreading is invisible, so the thresholds adapt
/// to the range the camera can see (arms alone then carry the signal);
/// when the camera faces the user, an "open" position must also show the
/// feet apart, so raising the arms alone never counts.
class JumpingJackAnalyzer extends CycleExerciseAnalyzer {
  JumpingJackAnalyzer({
    super.thresholds = const PushUpThresholds(),
    int? targetReps,
  }) : super(
         target: targetReps,
         cycle: CycleConfig(
           restDefault: 0.3,
           workDefault: 1.3,
           restIsHigh: false,
           minRange: 0.9,
           margin: 0.3,
           minGap: 0.4,
           decayPerFrame: 0.005,
           maxAdaptiveLoosening: 0.75,
           minFrames: thresholds.minFramesForTransition,
           minWorkDuration: const Duration(milliseconds: 120),
           cooldown: const Duration(milliseconds: 250),
         ),
       );

  /// Shoulder width over torso length above which the user faces the
  /// camera (the feet spreading is then visible).
  static const _frontalRatio = 0.45;

  static const _needed = [
    LandmarkType.leftShoulder,
    LandmarkType.rightShoulder,
    LandmarkType.leftWrist,
    LandmarkType.rightWrist,
    LandmarkType.leftHip,
    LandmarkType.rightHip,
    LandmarkType.leftAnkle,
    LandmarkType.rightAnkle,
  ];

  @override
  ExerciseType get type => ExerciseType.jumpingJack;

  @override
  int limbsUsed(PoseResult pose) => 2;

  @override
  bool countable(PoseResult pose) => jointsOk(pose, _needed);

  /// Standing upright, facing roughly towards the camera.
  @override
  bool inPosition(PoseResult pose) {
    final side = chooseSide(pose);
    if (side == null) return false;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return false;
    final up = pose.heightAbove(side.shoulder, side.hip, torso);
    return up != null && up > 0.5;
  }

  /// 0 ≈ closed (hands down, feet together); ~2 ≈ fully open.
  @override
  double? signal(PoseResult pose) {
    final shoulders = pose.mean2D([
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    ]);
    final hips = pose.mean2D([LandmarkType.leftHip, LandmarkType.rightHip]);
    final wrists = pose.mean2D([
      LandmarkType.leftWrist,
      LandmarkType.rightWrist,
    ]);
    if (shoulders == null || hips == null || wrists == null) return null;
    final torso = Geometry.distance3(shoulders, hips);
    if (torso == 0) return null;
    final handsUp = ((wrists - shoulders).dot(pose.up2D) / torso).clamp(
      -0.6,
      1.2,
    );
    return handsUp + (_spread(pose) ?? 0);
  }

  /// Feet apart relative to the hips: 0 together, 1 wide. Zero when the
  /// user is side-on: the hips overlap there, and dividing by their tiny
  /// apparent width read "feet wide apart" with the feet together.
  double? _spread(PoseResult pose) {
    final la = pose.position2D(LandmarkType.leftAnkle);
    final ra = pose.position2D(LandmarkType.rightAnkle);
    final lh = pose.position2D(LandmarkType.leftHip);
    final rh = pose.position2D(LandmarkType.rightHip);
    if (la == null || ra == null || lh == null || rh == null) return null;
    if (!_facingCamera(pose)) return 0;
    final side = pose.preferredSide;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    final hipWidth = math.max(Geometry.distance3(lh, rh), 0.4 * torso);
    if (hipWidth == 0) return 0;
    return ((Geometry.distance3(la, ra) / hipWidth - 1.0) / 1.5).clamp(
      0.0,
      1.0,
    );
  }

  bool _facingCamera(PoseResult pose) {
    final width = pose.distance2D(
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    );
    final side = pose.preferredSide;
    final torso = pose.distance2D(side.shoulder, side.hip);
    if (width == null || torso == null || torso == 0) return true;
    return width / torso >= _frontalRatio;
  }

  /// Facing the camera, "open" must include the feet apart.
  @override
  bool vetoWork(PoseResult pose) {
    if (!_facingCamera(pose)) return false;
    final spread = _spread(pose);
    if (spread != null && spread < 0.2) {
      diagnostics.reject('feetTogether');
      return true;
    }
    return false;
  }

  /// At the open position the hands should be clearly above the shoulders.
  @override
  FormStatus evaluateForm(PoseResult pose, BodySide side) {
    if (counter.phase != CyclePhase.work) return FormStatus.goodForm;
    final torso = pose.distance2D(side.shoulder, side.hip) ?? 0;
    if (torso == 0) return FormStatus.goodForm;
    final wrists = pose.mean2D([
      LandmarkType.leftWrist,
      LandmarkType.rightWrist,
    ]);
    final shoulders = pose.mean2D([
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    ]);
    if (wrists == null || shoulders == null) return FormStatus.goodForm;
    final handsUp = (wrists - shoulders).dot(pose.up2D) / torso;
    return handsUp < 0.45 ? FormStatus.armsNotOverhead : FormStatus.goodForm;
  }
}
