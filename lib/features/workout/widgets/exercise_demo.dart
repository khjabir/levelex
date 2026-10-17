import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/exercise.dart';

/// Which version of the movement to show.
enum DemoVariant { correct, mistake }

/// One keyframe: joint name → position in a unit box (y down).
typedef DemoPose = Map<String, Offset>;

/// A looping sequence of keyframes with per-segment durations (ms).
class DemoClip {
  const DemoClip({
    required this.frames,
    required this.durations,
    required this.bones,
    this.head = 'head',
    this.headRadius = 0.065,
    this.highlight = const {},
    this.label,
  }) : assert(frames.length == durations.length);

  final List<DemoPose> frames;

  /// Time to move from frame i to frame i+1 (the last wraps to the first).
  final List<int> durations;
  final List<(String, String)> bones;
  final String head;
  final double headRadius;

  /// Joints drawn in the warning colour (for mistake demos).
  final Set<String> highlight;

  /// Caption for the mistake demo ("Hips sagging").
  final String? label;

  int get totalMs => durations.fold(0, (a, b) => a + b);

  /// Interpolated pose at [t] milliseconds into the loop.
  DemoPose at(int t) {
    var ms = t % totalMs;
    for (var i = 0; i < frames.length; i++) {
      final d = durations[i];
      if (ms < d) {
        final a = frames[i];
        final b = frames[(i + 1) % frames.length];
        final u = Curves.easeInOut.transform(d == 0 ? 1 : ms / d);
        return {
          for (final k in a.keys)
            k: Offset.lerp(a[k], b[k] ?? a[k], u) ?? a[k]!,
        };
      }
      ms -= d;
    }
    return frames.first;
  }
}

/// Animated stick-figure demonstration of an exercise, correct or with a
/// typical mistake highlighted. Vector-drawn so it is crisp at any size.
class ExerciseDemo extends StatefulWidget {
  const ExerciseDemo({
    super.key,
    required this.exercise,
    this.variant = DemoVariant.correct,
    this.size = 180,
    this.showFloor = true,
    this.playing = true,
  });

  final ExerciseType exercise;
  final DemoVariant variant;
  final double size;
  final bool showFloor;
  final bool playing;

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late DemoClip _clip;

  @override
  void initState() {
    super.initState();
    _clip = DemoClips.clip(widget.exercise, widget.variant);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _clip.totalMs),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ExerciseDemo old) {
    super.didUpdateWidget(old);
    if (old.exercise != widget.exercise || old.variant != widget.variant) {
      _clip = DemoClips.clip(widget.exercise, widget.variant);
      _controller.duration = Duration(milliseconds: _clip.totalMs);
      if (widget.playing) _controller.repeat();
    }
    if (old.playing != widget.playing) {
      widget.playing ? _controller.repeat() : _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mistake = widget.variant == DemoVariant.mistake;
    return Semantics(
      label: mistake
          ? 'Animation showing a common mistake: ${_clip.label}'
          : 'Animation showing a correct ${widget.exercise.singular}',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _FigurePainter(
              pose: _clip.at((_controller.value * _clip.totalMs).round()),
              clip: _clip,
              color: mistake ? AppColors.warning : AppColors.primary,
              showFloor: widget.showFloor,
            ),
          ),
        ),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  _FigurePainter({
    required this.pose,
    required this.clip,
    required this.color,
    required this.showFloor,
  });

  final DemoPose pose;
  final DemoClip clip;
  final Color color;
  final bool showFloor;

  Offset _p(String k, Size s) {
    final o = pose[k] ?? Offset.zero;
    return Offset(o.dx * s.width, o.dy * s.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    if (showFloor) {
      final floorY = size.height * 0.905;
      canvas.drawLine(
        Offset(size.width * 0.04, floorY),
        Offset(size.width * 0.96, floorY),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..strokeWidth = math.max(1.5, w * 0.012)
          ..strokeCap = StrokeCap.round,
      );
    }
    final bone = Paint()
      ..color = color
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final bad = Paint()
      ..color = AppColors.danger
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03);

    for (final (a, b) in clip.bones) {
      if (!pose.containsKey(a) || !pose.containsKey(b)) continue;
      final p1 = _p(a, size);
      final p2 = _p(b, size);
      final flagged = clip.highlight.contains(a) && clip.highlight.contains(b);
      canvas.drawLine(p1, p2, glow);
      canvas.drawLine(p1, p2, flagged ? bad : bone);
    }
    // Joints
    final joint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final entry in pose.entries) {
      if (entry.key == clip.head) continue;
      final flagged = clip.highlight.contains(entry.key);
      canvas.drawCircle(
        _p(entry.key, size),
        flagged ? w * 0.03 : w * 0.02,
        flagged ? (Paint()..color = AppColors.danger) : joint,
      );
    }
    // Head
    if (pose.containsKey(clip.head)) {
      final c = _p(clip.head, size);
      canvas.drawCircle(c, clip.headRadius * w, glow);
      canvas.drawCircle(
        c,
        clip.headRadius * w,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.045,
      );
      canvas.drawCircle(
        c,
        clip.headRadius * w,
        Paint()..color = AppColors.background.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FigurePainter old) =>
      old.pose != pose || old.color != color || old.clip != clip;
}

/// Keyframe library. Figures face right in side views; the floor is y≈0.9.
abstract final class DemoClips {
  static const _side = <(String, String)>[
    ('head', 'neck'),
    ('neck', 'shoulder'),
    ('shoulder', 'elbow'),
    ('elbow', 'wrist'),
    ('shoulder', 'hip'),
    ('hip', 'knee'),
    ('knee', 'ankle'),
    ('ankle', 'toe'),
  ];

  static const _sideTwoLegs = <(String, String)>[
    ('head', 'neck'),
    ('neck', 'shoulder'),
    ('shoulder', 'elbow'),
    ('elbow', 'wrist'),
    ('shoulder', 'hip'),
    ('hip', 'kneeF'),
    ('kneeF', 'ankleF'),
    ('hip', 'kneeB'),
    ('kneeB', 'ankleB'),
  ];

  static const _front = <(String, String)>[
    ('head', 'neck'),
    ('neck', 'lShoulder'),
    ('neck', 'rShoulder'),
    ('lShoulder', 'lElbow'),
    ('lElbow', 'lWrist'),
    ('rShoulder', 'rElbow'),
    ('rElbow', 'rWrist'),
    ('lShoulder', 'lHip'),
    ('rShoulder', 'rHip'),
    ('lHip', 'rHip'),
    ('lHip', 'lKnee'),
    ('lKnee', 'lAnkle'),
    ('rHip', 'rKnee'),
    ('rKnee', 'rAnkle'),
  ];

  static DemoPose _with(DemoPose base, DemoPose overrides) => {
    ...base,
    ...overrides,
  };

  static DemoClip clip(ExerciseType type, DemoVariant variant) {
    final mistake = variant == DemoVariant.mistake;
    return switch (type) {
      ExerciseType.pushUp => mistake ? _pushUpSag : _pushUp,
      ExerciseType.squat => mistake ? _squatLean : _squat,
      ExerciseType.lunge => mistake ? _lungeLean : _lunge,
      ExerciseType.jumpingJack => mistake ? _jackLowArms : _jack,
      ExerciseType.burpee => mistake ? _burpeeShallow : _burpee,
      ExerciseType.plank => mistake ? _plankSag : _plank,
      ExerciseType.sitUp => mistake ? _sitUpHalf : _sitUp,
    };
  }

  // --- Push-up -------------------------------------------------------------

  static const _pushTop = <String, Offset>{
    'head': Offset(0.86, 0.43),
    'neck': Offset(0.79, 0.49),
    'shoulder': Offset(0.73, 0.52),
    'elbow': Offset(0.76, 0.69),
    'wrist': Offset(0.78, 0.88),
    'hip': Offset(0.44, 0.66),
    'knee': Offset(0.28, 0.76),
    'ankle': Offset(0.12, 0.86),
    'toe': Offset(0.07, 0.90),
  };
  static const _pushBottom = <String, Offset>{
    'head': Offset(0.86, 0.66),
    'neck': Offset(0.79, 0.71),
    'shoulder': Offset(0.73, 0.73),
    'elbow': Offset(0.60, 0.80),
    'wrist': Offset(0.78, 0.88),
    'hip': Offset(0.44, 0.80),
    'knee': Offset(0.28, 0.84),
    'ankle': Offset(0.12, 0.87),
    'toe': Offset(0.07, 0.90),
  };
  static final _pushUp = DemoClip(
    frames: [_pushTop, _pushBottom],
    durations: [900, 900],
    bones: _side,
  );
  static final _pushTopSag = _with(_pushTop, {
    'hip': const Offset(0.44, 0.78),
    'knee': const Offset(0.28, 0.83),
  });
  static final _pushBottomSag = _with(_pushBottom, {
    'hip': const Offset(0.44, 0.87),
    'knee': const Offset(0.28, 0.88),
  });
  static final _pushUpSag = DemoClip(
    frames: [_pushTopSag, _pushBottomSag],
    durations: [900, 900],
    bones: _side,
    highlight: {'shoulder', 'hip', 'knee'},
    label: 'Hips sagging',
  );

  // --- Squat ---------------------------------------------------------------

  static const _stand = <String, Offset>{
    'head': Offset(0.52, 0.13),
    'neck': Offset(0.52, 0.22),
    'shoulder': Offset(0.52, 0.26),
    'elbow': Offset(0.535, 0.41),
    'wrist': Offset(0.55, 0.54),
    'hip': Offset(0.52, 0.53),
    'knee': Offset(0.525, 0.72),
    'ankle': Offset(0.52, 0.89),
    'toe': Offset(0.60, 0.90),
  };
  static const _squatBottom = <String, Offset>{
    'head': Offset(0.55, 0.30),
    'neck': Offset(0.52, 0.39),
    'shoulder': Offset(0.50, 0.42),
    'elbow': Offset(0.64, 0.45),
    'wrist': Offset(0.77, 0.44),
    'hip': Offset(0.38, 0.66),
    'knee': Offset(0.62, 0.72),
    'ankle': Offset(0.52, 0.89),
    'toe': Offset(0.60, 0.90),
  };
  static final _squat = DemoClip(
    frames: [_stand, _squatBottom],
    durations: [1000, 1000],
    bones: _side,
  );
  static final _squatLeanBottom = _with(_squatBottom, {
    'head': const Offset(0.74, 0.44),
    'neck': const Offset(0.68, 0.50),
    'shoulder': const Offset(0.64, 0.53),
    'elbow': const Offset(0.70, 0.66),
    'wrist': const Offset(0.74, 0.78),
  });
  static final _squatLean = DemoClip(
    frames: [_stand, _squatLeanBottom],
    durations: [1000, 1000],
    bones: _side,
    highlight: {'shoulder', 'hip', 'neck'},
    label: 'Chest falls forward',
  );

  // --- Lunge ---------------------------------------------------------------

  static const _lungeStand = <String, Offset>{
    'head': Offset(0.50, 0.13),
    'neck': Offset(0.50, 0.22),
    'shoulder': Offset(0.50, 0.26),
    'elbow': Offset(0.515, 0.41),
    'wrist': Offset(0.53, 0.54),
    'hip': Offset(0.50, 0.53),
    'kneeF': Offset(0.51, 0.72),
    'ankleF': Offset(0.51, 0.89),
    'kneeB': Offset(0.49, 0.72),
    'ankleB': Offset(0.49, 0.89),
  };
  static const _lungeBottom = <String, Offset>{
    'head': Offset(0.50, 0.26),
    'neck': Offset(0.50, 0.35),
    'shoulder': Offset(0.50, 0.39),
    'elbow': Offset(0.515, 0.53),
    'wrist': Offset(0.53, 0.65),
    'hip': Offset(0.50, 0.64),
    'kneeF': Offset(0.68, 0.70),
    'ankleF': Offset(0.68, 0.89),
    'kneeB': Offset(0.38, 0.86),
    'ankleB': Offset(0.26, 0.89),
  };
  static final _lunge = DemoClip(
    frames: [_lungeStand, _lungeBottom],
    durations: [1000, 1000],
    bones: _sideTwoLegs,
  );
  static final _lungeLeanBottom = _with(_lungeBottom, {
    'head': const Offset(0.70, 0.36),
    'neck': const Offset(0.64, 0.44),
    'shoulder': const Offset(0.61, 0.47),
    'elbow': const Offset(0.66, 0.60),
    'wrist': const Offset(0.70, 0.70),
  });
  static final _lungeLean = DemoClip(
    frames: [_lungeStand, _lungeLeanBottom],
    durations: [1000, 1000],
    bones: _sideTwoLegs,
    highlight: {'shoulder', 'hip', 'neck'},
    label: 'Leaning over the front knee',
  );

  // --- Jumping jack --------------------------------------------------------

  static const _jackClosed = <String, Offset>{
    'head': Offset(0.50, 0.12),
    'neck': Offset(0.50, 0.21),
    'lShoulder': Offset(0.40, 0.26),
    'rShoulder': Offset(0.60, 0.26),
    'lElbow': Offset(0.37, 0.42),
    'rElbow': Offset(0.63, 0.42),
    'lWrist': Offset(0.36, 0.56),
    'rWrist': Offset(0.64, 0.56),
    'lHip': Offset(0.44, 0.53),
    'rHip': Offset(0.56, 0.53),
    'lKnee': Offset(0.44, 0.72),
    'rKnee': Offset(0.56, 0.72),
    'lAnkle': Offset(0.44, 0.89),
    'rAnkle': Offset(0.56, 0.89),
  };
  static const _jackOpen = <String, Offset>{
    'head': Offset(0.50, 0.12),
    'neck': Offset(0.50, 0.21),
    'lShoulder': Offset(0.40, 0.26),
    'rShoulder': Offset(0.60, 0.26),
    'lElbow': Offset(0.30, 0.15),
    'rElbow': Offset(0.70, 0.15),
    'lWrist': Offset(0.44, 0.04),
    'rWrist': Offset(0.56, 0.04),
    'lHip': Offset(0.44, 0.53),
    'rHip': Offset(0.56, 0.53),
    'lKnee': Offset(0.36, 0.72),
    'rKnee': Offset(0.64, 0.72),
    'lAnkle': Offset(0.28, 0.89),
    'rAnkle': Offset(0.72, 0.89),
  };
  static final _jack = DemoClip(
    frames: [_jackClosed, _jackOpen],
    durations: [450, 450],
    bones: _front,
    headRadius: 0.06,
  );
  static final _jackOpenLow = _with(_jackOpen, {
    'lElbow': const Offset(0.29, 0.30),
    'rElbow': const Offset(0.71, 0.30),
    'lWrist': const Offset(0.19, 0.27),
    'rWrist': const Offset(0.81, 0.27),
  });
  static final _jackLowArms = DemoClip(
    frames: [_jackClosed, _jackOpenLow],
    durations: [450, 450],
    bones: _front,
    headRadius: 0.06,
    highlight: {
      'lShoulder',
      'lElbow',
      'lWrist',
      'rShoulder',
      'rElbow',
      'rWrist',
    },
    label: 'Arms stop at shoulder height',
  );

  // --- Burpee --------------------------------------------------------------

  static const _crouch = <String, Offset>{
    'head': Offset(0.60, 0.42),
    'neck': Offset(0.55, 0.49),
    'shoulder': Offset(0.52, 0.52),
    'elbow': Offset(0.58, 0.70),
    'wrist': Offset(0.64, 0.88),
    'hip': Offset(0.40, 0.68),
    'knee': Offset(0.58, 0.74),
    'ankle': Offset(0.50, 0.89),
    'toe': Offset(0.58, 0.90),
  };
  static const _plankHands = <String, Offset>{
    'head': Offset(0.82, 0.43),
    'neck': Offset(0.75, 0.49),
    'shoulder': Offset(0.69, 0.52),
    'elbow': Offset(0.71, 0.70),
    'wrist': Offset(0.72, 0.88),
    'hip': Offset(0.42, 0.66),
    'knee': Offset(0.27, 0.76),
    'ankle': Offset(0.12, 0.86),
    'toe': Offset(0.07, 0.90),
  };
  static const _jump = <String, Offset>{
    'head': Offset(0.52, 0.05),
    'neck': Offset(0.52, 0.14),
    'shoulder': Offset(0.52, 0.18),
    'elbow': Offset(0.56, 0.06),
    'wrist': Offset(0.58, -0.04),
    'hip': Offset(0.52, 0.45),
    'knee': Offset(0.53, 0.63),
    'ankle': Offset(0.52, 0.80),
    'toe': Offset(0.58, 0.84),
  };
  static final _burpee = DemoClip(
    frames: [_stand, _crouch, _plankHands, _crouch, _jump],
    durations: [500, 450, 650, 450, 600],
    bones: _side,
  );
  static const _halfPlank = <String, Offset>{
    'head': Offset(0.74, 0.40),
    'neck': Offset(0.67, 0.46),
    'shoulder': Offset(0.62, 0.50),
    'elbow': Offset(0.66, 0.68),
    'wrist': Offset(0.68, 0.88),
    'hip': Offset(0.42, 0.58),
    'knee': Offset(0.40, 0.76),
    'ankle': Offset(0.30, 0.88),
    'toe': Offset(0.36, 0.90),
  };
  static final _burpeeShallow = DemoClip(
    frames: [_stand, _crouch, _halfPlank, _crouch, _stand],
    durations: [500, 450, 650, 450, 600],
    bones: _side,
    highlight: {'hip', 'knee', 'shoulder'},
    label: 'Never reaches a flat plank',
  );

  // --- Plank ---------------------------------------------------------------

  static const _plankA = <String, Offset>{
    'head': Offset(0.80, 0.45),
    'neck': Offset(0.73, 0.50),
    'shoulder': Offset(0.67, 0.53),
    'elbow': Offset(0.68, 0.88),
    'wrist': Offset(0.84, 0.88),
    'hip': Offset(0.42, 0.66),
    'knee': Offset(0.27, 0.76),
    'ankle': Offset(0.12, 0.86),
    'toe': Offset(0.07, 0.90),
  };
  static final _plankB = _with(_plankA, {
    'shoulder': const Offset(0.67, 0.545),
    'neck': const Offset(0.73, 0.515),
  });
  static final _plank = DemoClip(
    frames: [_plankA, _plankB],
    durations: [1400, 1400],
    bones: _side,
  );
  static final _plankSagA = _with(_plankA, {
    'hip': const Offset(0.42, 0.78),
    'knee': const Offset(0.27, 0.83),
  });
  static final _plankSag = DemoClip(
    frames: [_plankSagA, _plankSagA],
    durations: [1400, 1400],
    bones: _side,
    highlight: {'shoulder', 'hip', 'knee'},
    label: 'Hips sagging',
  );

  // --- Sit-up --------------------------------------------------------------

  static const _lying = <String, Offset>{
    'head': Offset(0.14, 0.78),
    'neck': Offset(0.23, 0.80),
    'shoulder': Offset(0.27, 0.81),
    'elbow': Offset(0.36, 0.72),
    'wrist': Offset(0.42, 0.78),
    'hip': Offset(0.52, 0.83),
    'knee': Offset(0.66, 0.60),
    'ankle': Offset(0.78, 0.88),
    'toe': Offset(0.86, 0.90),
  };
  static const _sitting = <String, Offset>{
    'head': Offset(0.52, 0.38),
    'neck': Offset(0.50, 0.48),
    'shoulder': Offset(0.49, 0.52),
    'elbow': Offset(0.58, 0.60),
    'wrist': Offset(0.64, 0.66),
    'hip': Offset(0.52, 0.83),
    'knee': Offset(0.66, 0.60),
    'ankle': Offset(0.78, 0.88),
    'toe': Offset(0.86, 0.90),
  };
  static final _sitUp = DemoClip(
    frames: [_lying, _sitting],
    durations: [1000, 1000],
    bones: _side,
  );
  static final _halfSitting = _with(_lying, {
    'head': const Offset(0.26, 0.60),
    'neck': const Offset(0.32, 0.67),
    'shoulder': const Offset(0.35, 0.70),
    'elbow': const Offset(0.44, 0.66),
    'wrist': const Offset(0.50, 0.72),
  });
  static final _sitUpHalf = DemoClip(
    frames: [_lying, _halfSitting],
    durations: [700, 700],
    bones: _side,
    highlight: {'shoulder', 'neck', 'head'},
    label: 'Only half way up',
  );
}
