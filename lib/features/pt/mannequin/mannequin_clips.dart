import 'rig.dart';

/// Keyframe library for every movement in the catalogue.
abstract final class MannequinClips {
  static const stand = RigPose.sym();

  static const _plankTop = RigPose.sym(
    bodyPitch: 70,
    shoulderFlex: 70,
    elbow: 4,
    neckPitch: -30,
    hipAbd: 2,
    knee: 2,
  );
  static const _pushBottom = RigPose.sym(
    bodyPitch: 74,
    shoulderFlex: 30,
    shoulderAbd: 22,
    elbow: 100,
    neckPitch: -30,
    hipAbd: 2,
    knee: 2,
  );
  static const _squatBottom = RigPose.sym(
    hipFlex: 98,
    knee: 108,
    spinePitch: 26,
    shoulderFlex: 82,
    elbow: 6,
    hipAbd: 8,
  );
  static const _crouch = RigPose.sym(
    hipFlex: 118,
    knee: 128,
    spinePitch: 45,
    shoulderFlex: 108,
    elbow: 12,
    hipAbd: 10,
  );
  static const _lying = RigPose.sym(
    bodyPitch: -90,
    hipFlex: 55,
    knee: 100,
    shoulderFlex: 40,
    elbow: 110,
  );
  static const _hinge = RigPose.sym(
    spinePitch: 18,
    hipFlex: 78,
    knee: 22,
    shoulderFlex: 72,
    elbow: 4,
  );
  static const _quadruped = RigPose.sym(
    bodyPitch: 72,
    hipFlex: 95,
    knee: 95,
    shoulderFlex: 95,
    elbow: 4,
    neckPitch: -40,
  );
  static const _hang = RigPose.sym(
    shoulderAbd: 168,
    elbow: 4,
    knee: 30,
    hipFlex: 15,
    lift: 0.25,
  );

  static final Map<String, MannequinClip> _clips = {
    for (final c in _all) c.id: c,
  };

  static bool has(String id) => _clips.containsKey(id);

  static MannequinClip clip(String id) => _clips[id] ?? _clips['stand']!;

  static Iterable<String> get ids => _clips.keys;

  static final List<MannequinClip> _all = [
    const MannequinClip(id: 'stand', frames: [stand], durations: [1000]),
    // --- Bodyweight ---------------------------------------------------
    const MannequinClip(
      id: 'push_up',
      frames: [_plankTop, _pushBottom],
      durations: [950],
    ),
    MannequinClip(
      id: 'pike_push_up',
      frames: [
        const RigPose.sym(
          bodyPitch: 30,
          hipFlex: 95,
          spinePitch: 20,
          shoulderFlex: 165,
          elbow: 4,
          neckPitch: 30,
        ),
        const RigPose.sym(
          bodyPitch: 30,
          hipFlex: 95,
          spinePitch: 20,
          shoulderFlex: 165,
          shoulderAbd: 30,
          elbow: 95,
          neckPitch: 30,
        ),
      ],
      durations: const [900],
    ),
    const MannequinClip(
      id: 'squat',
      frames: [stand, _squatBottom],
      durations: [1000],
    ),
    MannequinClip(
      id: 'squat_jump',
      frames: [
        stand,
        _squatBottom,
        const RigPose.sym(lift: 0.28, shoulderFlex: 160, elbow: 4),
        stand,
      ],
      durations: const [600, 350, 450],
      pingPong: false,
    ),
    MannequinClip(
      id: 'lunge',
      frames: [
        stand,
        const RigPose(
          hipFlexL: 82,
          kneeL: 86,
          hipFlexR: -18,
          kneeR: 78,
          spinePitch: 4,
          shoulderAbdL: 6,
          shoulderAbdR: 6,
        ),
        stand,
        const RigPose(
          hipFlexR: 82,
          kneeR: 86,
          hipFlexL: -18,
          kneeL: 78,
          spinePitch: 4,
          shoulderAbdL: 6,
          shoulderAbdR: 6,
        ),
      ],
      durations: const [900, 900, 900, 900],
      pingPong: false,
    ),
    MannequinClip(
      id: 'db_lunge',
      frames: [
        const RigPose.sym(elbow: 4, shoulderAbd: 8),
        const RigPose(
          hipFlexL: 82,
          kneeL: 86,
          hipFlexR: -18,
          kneeR: 78,
          elbowL: 4,
          elbowR: 4,
          shoulderAbdL: 8,
          shoulderAbdR: 8,
        ),
      ],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'jumping_jack',
      frames: [
        const RigPose.sym(shoulderAbd: 8, hipAbd: 3, elbow: 4),
        const RigPose.sym(shoulderAbd: 165, hipAbd: 22, elbow: 4, lift: 0.04),
      ],
      durations: const [420],
    ),
    const MannequinClip(
      id: 'burpee',
      frames: [
        stand,
        _crouch,
        _plankTop,
        _crouch,
        RigPose.sym(lift: 0.3, shoulderFlex: 165, elbow: 4),
      ],
      durations: [450, 500, 500, 450, 500],
      pingPong: false,
    ),
    const MannequinClip(
      id: 'plank',
      frames: [
        RigPose.sym(
          bodyPitch: 83,
          shoulderFlex: 83,
          elbow: 90,
          neckPitch: -30,
          hipAbd: 2,
          knee: 2,
        ),
        RigPose.sym(
          bodyPitch: 84,
          shoulderFlex: 83,
          elbow: 90,
          neckPitch: -30,
          hipAbd: 2,
          knee: 2,
        ),
      ],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'side_plank',
      frames: [
        RigPose(
          bodyRoll: 78,
          bodyPitch: 0,
          shoulderAbdR: 95,
          elbowR: 95,
          armRotR: 90,
          shoulderAbdL: 160,
          elbowL: 4,
          hipAbdL: 4,
          hipAbdR: 4,
          kneeL: 2,
          kneeR: 2,
        ),
      ],
      durations: [1500],
    ),
    MannequinClip(
      id: 'sit_up',
      frames: [
        _lying,
        const RigPose.sym(
          bodyPitch: -90,
          spinePitch: 85,
          hipFlex: 55,
          knee: 100,
          shoulderFlex: 40,
          elbow: 110,
          neckPitch: 10,
        ),
      ],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'glute_bridge',
      frames: [
        const RigPose.sym(
          bodyPitch: -90,
          hipFlex: 60,
          knee: 110,
          shoulderAbd: 20,
          elbow: 4,
        ),
        const RigPose.sym(
          bodyPitch: -65,
          hipFlex: 25,
          knee: 110,
          shoulderAbd: 20,
          elbow: 4,
        ),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'mountain_climbers',
      frames: [
        _plankTop.copyWith(hipFlexL: 95, kneeL: 110),
        _plankTop.copyWith(hipFlexR: 95, kneeR: 110),
      ],
      durations: const [340],
    ),
    MannequinClip(
      id: 'high_knees',
      frames: [
        const RigPose(
          hipFlexL: 90,
          kneeL: 110,
          elbowL: 90,
          elbowR: 90,
          shoulderFlexL: -25,
          shoulderFlexR: 35,
          lift: 0.04,
        ),
        const RigPose(
          hipFlexR: 90,
          kneeR: 110,
          elbowL: 90,
          elbowR: 90,
          shoulderFlexL: 35,
          shoulderFlexR: -25,
          lift: 0.04,
        ),
      ],
      durations: const [300],
    ),
    MannequinClip(
      id: 'jog',
      frames: [
        const RigPose(
          hipFlexL: 45,
          kneeL: 70,
          hipFlexR: -10,
          kneeR: 25,
          elbowL: 90,
          elbowR: 90,
          shoulderFlexL: -20,
          shoulderFlexR: 25,
          lift: 0.03,
        ),
        const RigPose(
          hipFlexR: 45,
          kneeR: 70,
          hipFlexL: -10,
          kneeL: 25,
          elbowL: 90,
          elbowR: 90,
          shoulderFlexL: 25,
          shoulderFlexR: -20,
          lift: 0.03,
        ),
      ],
      durations: const [320],
    ),
    const MannequinClip(
      id: 'wall_sit',
      frames: [RigPose.sym(hipFlex: 90, knee: 90, spinePitch: -4, elbow: 4)],
      durations: [1500],
    ),
    MannequinClip(
      id: 'superman',
      frames: [
        const RigPose.sym(
          bodyPitch: 90,
          shoulderFlex: 160,
          elbow: 4,
          neckPitch: -20,
        ),
        const RigPose.sym(
          bodyPitch: 90,
          shoulderFlex: 175,
          elbow: 4,
          hipFlex: -22,
          spinePitch: -18,
          neckPitch: -30,
        ),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'bird_dog',
      frames: [
        _quadruped,
        _quadruped.copyWith(shoulderFlexL: 175, hipFlexR: -5, kneeR: 4),
        _quadruped,
        _quadruped.copyWith(shoulderFlexR: 175, hipFlexL: -5, kneeL: 4),
      ],
      durations: const [800, 800, 800, 800],
      pingPong: false,
    ),
    MannequinClip(
      id: 'calf_raise',
      frames: [
        const RigPose.sym(elbow: 4),
        const RigPose.sym(elbow: 4, lift: 0.07),
      ],
      durations: const [700],
    ),
    MannequinClip(
      id: 'dip',
      frames: [
        const RigPose.sym(
          shoulderFlex: -35,
          elbow: 8,
          hipFlex: 75,
          knee: 70,
          spinePitch: 5,
        ),
        const RigPose.sym(
          shoulderFlex: -45,
          elbow: 95,
          hipFlex: 80,
          knee: 70,
          spinePitch: 5,
        ),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'pull_up',
      frames: [
        _hang,
        const RigPose.sym(
          shoulderAbd: 110,
          elbow: 130,
          armRot: 90,
          knee: 30,
          hipFlex: 15,
          lift: 0.55,
        ),
      ],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'knee_raise',
      frames: [
        _hang.copyWith(kneeL: 10, kneeR: 10, hipFlexL: 5, hipFlexR: 5),
        _hang.copyWith(kneeL: 110, kneeR: 110, hipFlexL: 105, hipFlexR: 105),
      ],
      durations: const [900],
    ),
    // --- Dumbbells / barbell -------------------------------------------
    MannequinClip(
      id: 'curl',
      frames: [
        const RigPose.sym(elbow: 18, shoulderAbd: 8),
        const RigPose.sym(elbow: 140, shoulderAbd: 8),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'shoulder_press',
      frames: [
        const RigPose.sym(shoulderAbd: 85, armRot: 90, elbow: 100),
        const RigPose.sym(shoulderAbd: 168, armRot: 90, elbow: 6),
      ],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'lateral_raise',
      frames: [
        const RigPose.sym(shoulderAbd: 10, elbow: 15),
        const RigPose.sym(shoulderAbd: 88, elbow: 15),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'front_raise',
      frames: [
        const RigPose.sym(shoulderFlex: 10, elbow: 8),
        const RigPose.sym(shoulderFlex: 92, elbow: 8),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'bent_row',
      frames: [
        const RigPose.sym(
          spinePitch: 48,
          hipFlex: 38,
          knee: 22,
          shoulderFlex: 52,
          elbow: 6,
        ),
        const RigPose.sym(
          spinePitch: 48,
          hipFlex: 38,
          knee: 22,
          shoulderFlex: 0,
          elbow: 115,
        ),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'band_row',
      frames: [
        const RigPose.sym(shoulderFlex: 88, elbow: 6),
        const RigPose.sym(shoulderFlex: 18, elbow: 115),
      ],
      durations: const [800],
    ),
    const MannequinClip(
      id: 'hinge',
      frames: [RigPose.sym(elbow: 4, shoulderFlex: 6), _hinge],
      durations: [1100],
    ),
    MannequinClip(
      id: 'swing',
      frames: [
        const RigPose.sym(
          spinePitch: 22,
          hipFlex: 80,
          knee: 28,
          shoulderFlex: 48,
          elbow: 4,
        ),
        const RigPose.sym(shoulderFlex: 92, elbow: 4),
      ],
      durations: const [550],
    ),
    MannequinClip(
      id: 'goblet_squat',
      frames: [
        const RigPose.sym(shoulderFlex: 28, elbow: 128),
        _squatBottom.copyWith(
          shoulderFlexL: 28,
          shoulderFlexR: 28,
          elbowL: 128,
          elbowR: 128,
        ),
      ],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'back_squat',
      frames: [
        const RigPose.sym(shoulderAbd: 80, armRot: 90, elbow: 125),
        _squatBottom.copyWith(
          shoulderFlexL: 0,
          shoulderFlexR: 0,
          shoulderAbdL: 80,
          shoulderAbdR: 80,
          armRotL: 90,
          armRotR: 90,
          elbowL: 125,
          elbowR: 125,
        ),
      ],
      durations: const [1100],
    ),
    MannequinClip(
      id: 'floor_press',
      frames: [
        const RigPose.sym(
          bodyPitch: -90,
          hipFlex: 55,
          knee: 100,
          shoulderAbd: 72,
          armRot: 90,
          elbow: 95,
        ),
        const RigPose.sym(
          bodyPitch: -90,
          hipFlex: 55,
          knee: 100,
          shoulderFlex: 92,
          elbow: 4,
        ),
      ],
      durations: const [950],
    ),
    MannequinClip(
      id: 'bench_press',
      frames: [
        const RigPose.sym(
          bodyPitch: -90,
          hipFlex: 70,
          knee: 95,
          shoulderAbd: 72,
          armRot: 90,
          elbow: 95,
          lift: 0.4,
        ),
        const RigPose.sym(
          bodyPitch: -90,
          hipFlex: 70,
          knee: 95,
          shoulderFlex: 92,
          elbow: 4,
          lift: 0.4,
        ),
      ],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'kickback',
      frames: [
        _hinge.copyWith(
          shoulderFlexL: -35,
          shoulderFlexR: -35,
          elbowL: 95,
          elbowR: 95,
        ),
        _hinge.copyWith(
          shoulderFlexL: -35,
          shoulderFlexR: -35,
          elbowL: 6,
          elbowR: 6,
        ),
      ],
      durations: const [800],
    ),
    MannequinClip(
      id: 'overhead_ext',
      frames: [
        const RigPose.sym(shoulderAbd: 165, armRot: 90, elbow: 120),
        const RigPose.sym(shoulderAbd: 168, armRot: 90, elbow: 8),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'pushdown',
      frames: [
        const RigPose.sym(shoulderFlex: 12, elbow: 105),
        const RigPose.sym(shoulderFlex: 12, elbow: 8),
      ],
      durations: const [800],
    ),
    MannequinClip(
      id: 'pull_apart',
      frames: [
        const RigPose.sym(shoulderFlex: 90, elbow: 6),
        const RigPose.sym(shoulderFlex: 30, shoulderAbd: 85, elbow: 6),
      ],
      durations: const [900],
    ),
    // --- Cardio machines ------------------------------------------------
    MannequinClip(
      id: 'bike',
      frames: [
        const RigPose(
          spinePitch: 28,
          hipFlexL: 95,
          kneeL: 115,
          hipFlexR: 45,
          kneeR: 55,
          shoulderFlexL: 62,
          shoulderFlexR: 62,
          elbowL: 18,
          elbowR: 18,
          lift: 0.35,
        ),
        const RigPose(
          spinePitch: 28,
          hipFlexR: 95,
          kneeR: 115,
          hipFlexL: 45,
          kneeL: 55,
          shoulderFlexL: 62,
          shoulderFlexR: 62,
          elbowL: 18,
          elbowR: 18,
          lift: 0.35,
        ),
      ],
      durations: const [450],
    ),
    MannequinClip(
      id: 'rower',
      frames: [
        const RigPose.sym(
          hipFlex: 100,
          knee: 125,
          spinePitch: 18,
          shoulderFlex: 75,
          elbow: 8,
        ),
        const RigPose.sym(
          hipFlex: 85,
          knee: 8,
          spinePitch: -12,
          shoulderFlex: 22,
          elbow: 110,
        ),
      ],
      durations: const [800],
    ),
    MannequinClip(
      id: 'jump_rope',
      frames: [
        const RigPose.sym(shoulderAbd: 22, elbow: 95, armRot: 20),
        const RigPose.sym(shoulderAbd: 22, elbow: 95, armRot: 20, lift: 0.09),
      ],
      durations: const [260],
    ),
    // --- Warm-up --------------------------------------------------------
    MannequinClip(
      id: 'arm_circles',
      frames: [
        const RigPose.sym(shoulderAbd: 90, shoulderFlex: 35, elbow: 4),
        const RigPose.sym(shoulderAbd: 110, shoulderFlex: 0, elbow: 4),
        const RigPose.sym(shoulderAbd: 90, shoulderFlex: -35, elbow: 4),
        const RigPose.sym(shoulderAbd: 70, shoulderFlex: 0, elbow: 4),
      ],
      durations: const [350, 350, 350, 350],
      pingPong: false,
    ),
    MannequinClip(
      id: 'leg_swings',
      frames: [
        const RigPose(
          hipFlexL: -30,
          kneeL: 8,
          shoulderAbdR: 70,
          elbowR: 8,
          shoulderAbdL: 6,
          elbowL: 8,
        ),
        const RigPose(
          hipFlexL: 65,
          kneeL: 8,
          shoulderAbdR: 70,
          elbowR: 8,
          shoulderAbdL: 6,
          elbowL: 8,
        ),
      ],
      durations: const [550],
    ),
    MannequinClip(
      id: 'torso_twists',
      frames: [
        const RigPose.sym(
          spineYaw: -45,
          shoulderAbd: 75,
          elbow: 95,
          armRot: 90,
        ),
        const RigPose.sym(spineYaw: 45, shoulderAbd: 75, elbow: 95, armRot: 90),
      ],
      durations: const [700],
    ),
    MannequinClip(
      id: 'inchworm',
      frames: [
        stand,
        const RigPose.sym(
          hipFlex: 90,
          knee: 12,
          spinePitch: 25,
          shoulderFlex: 120,
          elbow: 4,
        ),
        _plankTop,
      ],
      durations: const [800, 900],
    ),
    MannequinClip(
      id: 'hip_circles',
      frames: [
        const RigPose.sym(
          bodyRoll: -8,
          shoulderAbd: 28,
          elbow: 100,
          armRot: 90,
        ),
        const RigPose.sym(
          bodyPitch: -7,
          shoulderAbd: 28,
          elbow: 100,
          armRot: 90,
        ),
        const RigPose.sym(bodyRoll: 8, shoulderAbd: 28, elbow: 100, armRot: 90),
        const RigPose.sym(
          bodyPitch: 7,
          shoulderAbd: 28,
          elbow: 100,
          armRot: 90,
        ),
      ],
      durations: const [450, 450, 450, 450],
      pingPong: false,
    ),
    // --- Stretches ------------------------------------------------------
    const MannequinClip(
      id: 'hamstring_stretch',
      frames: [
        RigPose(
          hipFlexL: 32,
          kneeL: 4,
          hipFlexR: 0,
          kneeR: 6,
          spinePitch: 48,
          shoulderFlexL: 60,
          shoulderFlexR: 60,
          elbowL: 8,
          elbowR: 8,
          shoulderAbdL: 6,
          shoulderAbdR: 6,
        ),
      ],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'quad_stretch',
      frames: [
        RigPose(
          kneeR: 135,
          hipFlexR: -12,
          shoulderFlexR: -35,
          elbowR: 95,
          shoulderAbdR: 4,
          shoulderAbdL: 85,
          elbowL: 8,
          kneeL: 4,
        ),
      ],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'chest_stretch',
      frames: [RigPose.sym(shoulderAbd: 92, shoulderFlex: -35, elbow: 90)],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'childs_pose',
      frames: [
        RigPose.sym(
          bodyPitch: 25,
          hipFlex: 135,
          knee: 150,
          spinePitch: 60,
          shoulderFlex: 170,
          elbow: 4,
          neckPitch: 20,
        ),
      ],
      durations: [1500],
    ),
    MannequinClip(
      id: 'cat_cow',
      frames: [
        _quadruped.copyWith(spinePitch: -16, neckPitch: -55),
        _quadruped.copyWith(spinePitch: 16, neckPitch: -15),
      ],
      durations: const [1300],
    ),
    const MannequinClip(
      id: 'hip_flexor_stretch',
      frames: [
        RigPose(
          hipFlexL: 88,
          kneeL: 90,
          hipFlexR: -28,
          kneeR: 92,
          spinePitch: -4,
          shoulderAbdL: 6,
          shoulderAbdR: 6,
          elbowL: 8,
          elbowR: 8,
        ),
      ],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'cross_body_stretch',
      frames: [
        RigPose(
          shoulderFlexL: 88,
          shoulderAbdL: -32,
          elbowL: 8,
          shoulderFlexR: 50,
          elbowR: 115,
          shoulderAbdR: 6,
        ),
      ],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'tricep_stretch',
      frames: [
        RigPose(
          shoulderAbdL: 170,
          armRotL: 90,
          elbowL: 140,
          shoulderAbdR: 120,
          armRotR: 90,
          elbowR: 120,
        ),
      ],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'calf_stretch',
      frames: [
        RigPose(
          bodyPitch: 12,
          hipFlexL: 40,
          kneeL: 42,
          hipFlexR: -16,
          kneeR: 2,
          shoulderFlexL: 85,
          shoulderFlexR: 85,
          elbowL: 10,
          elbowR: 10,
          shoulderAbdL: 6,
          shoulderAbdR: 6,
        ),
      ],
      durations: [1500],
    ),
    const MannequinClip(
      id: 'figure_four',
      frames: [
        RigPose(
          bodyPitch: -90,
          hipFlexL: 95,
          kneeL: 95,
          hipFlexR: 100,
          kneeR: 90,
          hipAbdR: 60,
          hipAbdL: 4,
          shoulderFlexL: 70,
          shoulderFlexR: 70,
          elbowL: 60,
          elbowR: 60,
          shoulderAbdL: 10,
          shoulderAbdR: 10,
        ),
      ],
      durations: [1500],
    ),
    MannequinClip(
      id: 'breathing',
      frames: [
        const RigPose.sym(shoulderAbd: 15, elbow: 4),
        const RigPose.sym(shoulderAbd: 165, elbow: 4),
      ],
      durations: const [2800],
    ),
  ];
}
