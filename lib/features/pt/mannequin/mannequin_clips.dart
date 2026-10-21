import 'rig.dart';

/// Keyframe library for every movement in the catalogue.
///
/// Poses are built with [hinge], which keeps the back flat and lets the body
/// fold at the hips the way a coach would want: [lean] is how far the torso
/// tips forward from vertical, [thigh] the thigh's forward angle from
/// vertical in the world, [knee] the knee flexion, [arms] the arm's forward
/// angle from hanging in the world. Positive angles are forward.
abstract final class MannequinClips {
  static const stand = RigPose.sym();

  /// Flat-back pose composed in world angles (see class docs).
  static RigPose hinge({
    double lean = 0,
    double thigh = 0,
    double knee = 6,
    double arms = 0,
    double elbow = 6,
    double abd = 6,
    double armRot = 0,
    double neck = 0,
    double lift = 0,
    double hipAbd = 4,
  }) => RigPose.sym(
    bodyPitch: lean,
    hipFlex: thigh + lean,
    knee: knee,
    shoulderFlex: arms + lean,
    elbow: elbow,
    shoulderAbd: abd,
    armRot: armRot,
    neckPitch: neck,
    lift: lift,
    hipAbd: hipAbd,
  );

  /// Lying on the back with the knees bent and feet flat.
  static RigPose lying({
    double arms = 40,
    double elbow = 110,
    double abd = 6,
    double armRot = 0,
    double torso = -90,
  }) => RigPose.sym(
    bodyPitch: torso,
    hipFlex: 135 + torso,
    knee: 85,
    shoulderFlex: arms,
    elbow: elbow,
    shoulderAbd: abd,
    armRot: armRot,
  );

  // Shared poses -------------------------------------------------------------

  /// Top of a push-up: straight line from heels to head, hands under the
  /// shoulders.
  static final plankTop = hinge(
    lean: 70,
    thigh: -70,
    knee: 2,
    arms: 0,
    elbow: 4,
    neck: -32,
    hipAbd: 2,
  );

  /// Bottom of a push-up: elbows tucked about 45°, forearms vertical, body
  /// still one straight line.
  static final pushBottom = hinge(
    lean: 76,
    thigh: -76,
    knee: 2,
    arms: -72,
    elbow: 76,
    abd: 30,
    neck: -32,
    hipAbd: 2,
  );

  /// Parallel squat: hips back, chest up, knees over the toes.
  static final squatBottom = hinge(
    lean: 25,
    thigh: 80,
    knee: 112,
    arms: 85,
    elbow: 6,
    hipAbd: 8,
  );

  /// Deep crouch with the hands on the floor (burpee, inchworm).
  static final crouch = hinge(
    lean: 45,
    thigh: 85,
    knee: 135,
    arms: 70,
    elbow: 10,
    neck: -30,
    hipAbd: 10,
  );

  /// Hip hinge with a flat back and soft knees (deadlift, RDL, rows).
  static RigPose hingeBottom({
    double lean = 70,
    double arms = 0,
    double elbow = 4,
  }) => hinge(
    lean: lean,
    thigh: 12,
    knee: 14,
    arms: arms,
    elbow: elbow,
    neck: -25,
  );

  /// Hands and knees, back flat.
  static final quadruped = hinge(
    lean: 75,
    thigh: 0,
    knee: 90,
    arms: 0,
    elbow: 4,
    neck: -40,
  );

  static const hang = RigPose.sym(
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
    MannequinClip(
      id: 'push_up',
      frames: [plankTop, pushBottom],
      durations: const [950],
    ),
    MannequinClip(
      id: 'pike_push_up',
      frames: [
        hinge(lean: 70, thigh: 25, knee: 8, arms: 15, elbow: 4, neck: 20),
        hinge(
          lean: 72,
          thigh: 25,
          knee: 8,
          arms: 12,
          elbow: 95,
          abd: 25,
          neck: 20,
        ),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'squat',
      frames: [stand, squatBottom],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'squat_jump',
      frames: [
        stand,
        squatBottom,
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
          bodyPitch: 4,
          hipFlexL: 94,
          kneeL: 92,
          hipFlexR: -16,
          kneeR: 70,
          shoulderFlexL: 4,
          shoulderFlexR: 4,
        ),
        stand,
        const RigPose(
          bodyPitch: 4,
          hipFlexR: 94,
          kneeR: 92,
          hipFlexL: -16,
          kneeL: 70,
          shoulderFlexL: 4,
          shoulderFlexR: 4,
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
          bodyPitch: 4,
          hipFlexL: 94,
          kneeL: 92,
          hipFlexR: -16,
          kneeR: 70,
          elbowL: 4,
          elbowR: 4,
          shoulderAbdL: 8,
          shoulderAbdR: 8,
          shoulderFlexL: 4,
          shoulderFlexR: 4,
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
    MannequinClip(
      id: 'burpee',
      frames: [
        stand,
        crouch,
        plankTop,
        crouch,
        const RigPose.sym(lift: 0.3, shoulderFlex: 165, elbow: 4),
      ],
      durations: const [450, 500, 500, 450, 500],
      pingPong: false,
    ),
    MannequinClip(
      id: 'plank',
      frames: [
        hinge(
          lean: 83,
          thigh: -83,
          knee: 2,
          arms: 0,
          elbow: 92,
          neck: -30,
          hipAbd: 2,
        ),
        hinge(
          lean: 84,
          thigh: -84,
          knee: 2,
          arms: 0,
          elbow: 92,
          neck: -30,
          hipAbd: 2,
        ),
      ],
      durations: const [1500],
    ),
    const MannequinClip(
      id: 'side_plank',
      frames: [
        RigPose(
          bodyRoll: 78,
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
      frames: [lying(), lying(torso: -12).copyWith(neckPitch: 8)],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'glute_bridge',
      frames: [
        lying(arms: 0, elbow: 4, abd: 18),
        lying(arms: 0, elbow: 4, abd: 18, torso: -118),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'mountain_climbers',
      frames: [
        plankTop.copyWith(hipFlexL: 100, kneeL: 115),
        plankTop.copyWith(hipFlexR: 100, kneeR: 115),
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
      frames: [RigPose.sym(hipFlex: 90, knee: 90, elbow: 4)],
      durations: [1500],
    ),
    MannequinClip(
      id: 'superman',
      frames: [
        hinge(lean: 90, thigh: -90, knee: 2, arms: 160, elbow: 4, neck: -20),
        hinge(
          lean: 90,
          thigh: -105,
          knee: 2,
          arms: 178,
          elbow: 4,
          neck: -30,
        ).copyWith(spinePitch: -14),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'bird_dog',
      frames: [
        quadruped,
        quadruped.copyWith(shoulderFlexL: 170, hipFlexR: -10, kneeR: 4),
        quadruped,
        quadruped.copyWith(shoulderFlexR: 170, hipFlexL: -10, kneeL: 4),
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
          bodyPitch: 5,
          shoulderFlex: -40,
          elbow: 8,
          hipFlex: 85,
          knee: 75,
        ),
        const RigPose.sym(
          bodyPitch: 5,
          shoulderFlex: -55,
          elbow: 95,
          hipFlex: 90,
          knee: 75,
        ),
      ],
      durations: const [900],
    ),
    MannequinClip(
      id: 'pull_up',
      frames: [
        hang,
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
        hang.copyWith(kneeL: 10, kneeR: 10, hipFlexL: 5, hipFlexR: 5),
        hang.copyWith(kneeL: 110, kneeR: 110, hipFlexL: 105, hipFlexR: 105),
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
        hingeBottom(lean: 55, arms: 0),
        hingeBottom(lean: 55, arms: -35, elbow: 115),
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
    MannequinClip(
      id: 'hinge',
      frames: [const RigPose.sym(elbow: 4, shoulderFlex: 6), hingeBottom()],
      durations: const [1100],
    ),
    MannequinClip(
      id: 'swing',
      frames: [
        hinge(lean: 60, thigh: 20, knee: 25, arms: -15, elbow: 4, neck: -20),
        const RigPose.sym(shoulderFlex: 92, elbow: 4),
      ],
      durations: const [550],
    ),
    MannequinClip(
      id: 'goblet_squat',
      frames: [
        const RigPose.sym(shoulderFlex: 28, elbow: 128),
        squatBottom.copyWith(
          shoulderFlexL: 28 + 25,
          shoulderFlexR: 28 + 25,
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
        squatBottom.copyWith(
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
        lying(arms: 0, elbow: 95, abd: 72, armRot: 90),
        lying(arms: 92, elbow: 4),
      ],
      durations: const [950],
    ),
    MannequinClip(
      id: 'bench_press',
      frames: [
        lying(arms: 0, elbow: 95, abd: 72, armRot: 90).copyWith(lift: 0.4),
        lying(arms: 92, elbow: 4).copyWith(lift: 0.4),
      ],
      durations: const [1000],
    ),
    MannequinClip(
      id: 'kickback',
      frames: [
        hinge(lean: 70, thigh: 12, knee: 14, arms: -70, elbow: 70, neck: -25),
        hinge(lean: 70, thigh: 12, knee: 14, arms: -70, elbow: 5, neck: -25),
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
          bodyPitch: 25,
          hipFlexL: 95,
          kneeL: 115,
          hipFlexR: 60,
          kneeR: 55,
          shoulderFlexL: 85,
          shoulderFlexR: 85,
          elbowL: 18,
          elbowR: 18,
          lift: 0.35,
        ),
        const RigPose(
          bodyPitch: 25,
          hipFlexR: 95,
          kneeR: 115,
          hipFlexL: 60,
          kneeL: 55,
          shoulderFlexL: 85,
          shoulderFlexR: 85,
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
        hinge(lean: 15, thigh: 100, knee: 125, arms: 75, elbow: 8),
        hinge(lean: -15, thigh: 85, knee: 10, arms: 20, elbow: 110),
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
      continuous: true,
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
        hinge(lean: 85, thigh: 5, knee: 12, arms: 10, elbow: 4, neck: -20),
        plankTop,
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
      continuous: true,
    ),
    // --- Stretches ------------------------------------------------------
    MannequinClip(
      id: 'hamstring_stretch',
      frames: [
        hinge(
          lean: 40,
          thigh: 0,
          knee: 6,
          arms: 15,
          elbow: 8,
          neck: -20,
        ).copyWith(hipFlexL: 75, kneeL: 4),
      ],
      durations: const [1500],
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
    MannequinClip(
      id: 'childs_pose',
      frames: [
        hinge(lean: 80, thigh: 70, knee: 160, arms: 100, elbow: 4, neck: 10),
      ],
      durations: const [1500],
    ),
    MannequinClip(
      id: 'cat_cow',
      frames: [
        quadruped.copyWith(spinePitch: -16, neckPitch: -55),
        quadruped.copyWith(spinePitch: 16, neckPitch: -15),
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
    MannequinClip(
      id: 'calf_stretch',
      frames: [
        hinge(
          lean: 12,
          thigh: 0,
          knee: 4,
          arms: 85,
          elbow: 10,
        ).copyWith(hipFlexL: 52, kneeL: 42, hipFlexR: -4),
      ],
      durations: const [1500],
    ),
    MannequinClip(
      id: 'figure_four',
      frames: [
        lying(arms: 70, elbow: 60, abd: 10).copyWith(
          hipFlexL: 50,
          kneeL: 95,
          hipFlexR: 55,
          kneeR: 90,
          hipAbdR: 60,
        ),
      ],
      durations: const [1500],
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
