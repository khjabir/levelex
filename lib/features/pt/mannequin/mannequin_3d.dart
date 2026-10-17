import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/geometry.dart';
import 'mannequin_clips.dart';
import 'rig.dart';

/// Animated 3D figure demonstrating a movement. Rendered with a software
/// perspective projection and depth-sorted shaded capsules, so it needs no
/// model files. Drag to orbit, double-tap to reset.
class Mannequin3D extends StatefulWidget {
  const Mannequin3D({
    super.key,
    required this.clipId,
    this.size,
    this.playing = true,
    this.interactive = true,
    this.autoRotate = true,
    this.initialYaw = -38,
    this.initialPitch = 14,
    this.highlight = const {},
    this.showFloor = true,
    this.compact = false,
  });

  final String clipId;
  final double? size;
  final bool playing;
  final bool interactive;
  final bool autoRotate;
  final double initialYaw;
  final double initialPitch;

  /// Bone parts drawn in the warning colour (e.g. {'hips'}).
  final Set<String> highlight;
  final bool showFloor;

  /// Smaller figure for picture-in-picture use.
  final bool compact;

  @override
  State<Mannequin3D> createState() => _Mannequin3DState();
}

class _Mannequin3DState extends State<Mannequin3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late MannequinClip _clip;
  late double _yaw = widget.initialYaw;
  late double _pitch = widget.initialPitch;
  DateTime? _lastDrag;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _clip = MannequinClips.clip(widget.clipId);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant Mannequin3D old) {
    super.didUpdateWidget(old);
    if (old.clipId != widget.clipId) {
      _clip = MannequinClips.clip(widget.clipId);
      _epoch = _controller.lastElapsedDuration?.inMilliseconds ?? 0;
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

  int get _elapsedMs => (_controller.lastElapsedDuration?.inMilliseconds ?? 0);

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ms = _elapsedMs - _epoch;
        final idleFor = _lastDrag == null
            ? 1e9
            : DateTime.now().difference(_lastDrag!).inMilliseconds.toDouble();
        final yaw = widget.autoRotate && idleFor > 2500
            ? _yaw + math.sin(ms / 4200) * 22
            : _yaw;
        return CustomPaint(
          painter: _MannequinPainter(
            pose: _clip.at(ms < 0 ? 0 : ms),
            yaw: yaw,
            pitch: _pitch,
            highlight: {...widget.highlight, ..._clip.highlight},
            showFloor: widget.showFloor,
            compact: widget.compact,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
    final sized = widget.size == null
        ? body
        : SizedBox(width: widget.size, height: widget.size, child: body);
    if (!widget.interactive) return sized;
    return Semantics(
      label: '3D guide for the movement. Drag to rotate.',
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _yaw -= d.delta.dx * 0.6;
          _pitch = (_pitch + d.delta.dy * 0.4).clamp(-10.0, 60.0);
          _lastDrag = DateTime.now();
        }),
        onDoubleTap: () => setState(() {
          _yaw = widget.initialYaw;
          _pitch = widget.initialPitch;
          _lastDrag = null;
        }),
        child: sized,
      ),
    );
  }
}

class _MannequinPainter extends CustomPainter {
  _MannequinPainter({
    required this.pose,
    required this.yaw,
    required this.pitch,
    required this.highlight,
    required this.showFloor,
    required this.compact,
  });

  final RigPose pose;
  final double yaw;
  final double pitch;
  final Set<String> highlight;
  final bool showFloor;
  final bool compact;

  static const _distance = 3.6;

  @override
  void paint(Canvas canvas, Size size) {
    final joints = Rig.solve(pose);
    // Orbit target: the figure's vertical centre.
    var maxY = 0.0;
    for (final v in joints.values) {
      if (v.y > maxY) maxY = v.y;
    }
    final target = Vec3(0, maxY * 0.5, 0);
    final view = Mat3.rotX(pitch) * Mat3.rotY(-yaw);
    final focal = size.shortestSide * (compact ? 1.25 : 1.05);
    final centre = Offset(size.width / 2, size.height * 0.55);

    (Offset, double) project(Vec3 p) {
      final c = view.apply(p - target);
      final depth = c.z + _distance;
      final s = focal / depth;
      return (Offset(centre.dx + c.x * s, centre.dy - c.y * s), depth);
    }

    if (showFloor) _paintFloor(canvas, size, project, joints);

    // Depth sort the bones, far to near.
    final items = <(Bone, Offset, Offset, double)>[];
    for (final bone in Rig.bones) {
      final a = joints[bone.a];
      final b = joints[bone.b];
      if (a == null || b == null) continue;
      final (pa, da) = project(a);
      final (pb, db) = project(b);
      items.add((bone, pa, pb, (da + db) / 2));
    }
    final head = joints['head'];
    final (headPos, headDepth) = head == null
        ? (Offset.zero, _distance)
        : project(head);
    items.sort((x, y) => y.$4.compareTo(x.$4));

    var headDrawn = false;
    for (final (bone, pa, pb, depth) in items) {
      if (!headDrawn && head != null && depth <= headDepth) {
        _paintHead(canvas, headPos, headDepth, focal);
        headDrawn = true;
      }
      final flagged = highlight.contains(bone.part);
      final base = flagged ? AppColors.warning : AppColors.primary;
      final shade = ((depth - (_distance - 1.0)) / 2.0).clamp(0.0, 1.0);
      final color = Color.lerp(
        base,
        AppColors.background,
        0.12 + shade * 0.45,
      )!;
      final width = bone.thickness * focal / depth;
      canvas.drawLine(
        pa,
        pb,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.5)
          ..strokeWidth = width + 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        pa,
        pb,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
      // Specular edge for the capsule look.
      final dir = (pb - pa);
      final len = dir.distance;
      if (len > 0) {
        final n = Offset(-dir.dy / len, dir.dx / len) * (width * 0.22);
        canvas.drawLine(
          pa - n,
          pb - n,
          Paint()
            ..color = Colors.white.withValues(alpha: flagged ? 0.35 : 0.28)
            ..strokeWidth = math.max(1, width * 0.22)
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (!headDrawn && head != null) {
      _paintHead(canvas, headPos, headDepth, focal);
    }
  }

  void _paintHead(Canvas canvas, Offset p, double depth, double focal) {
    final r = Rig.headRadius * focal / depth;
    canvas.drawCircle(
      p,
      r + 1.5,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Color.lerp(AppColors.primary, Colors.white, 0.35)!,
            AppColors.primary,
            Color.lerp(AppColors.primary, AppColors.background, 0.55)!,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: p, radius: r)),
    );
  }

  void _paintFloor(
    Canvas canvas,
    Size size,
    (Offset, double) Function(Vec3) project,
    Map<String, Vec3> joints,
  ) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    const extent = 1.4;
    const step = 0.35;
    for (var i = -extent; i <= extent + 1e-6; i += step) {
      final (a, _) = project(Vec3(i, 0, -extent));
      final (b, _) = project(Vec3(i, 0, extent));
      canvas.drawLine(a, b, grid);
      final (c, _) = project(Vec3(-extent, 0, i));
      final (d, _) = project(Vec3(extent, 0, i));
      canvas.drawLine(c, d, grid);
    }
    // Soft shadow under the figure's footprint.
    var minX = double.infinity, maxX = -double.infinity;
    var minZ = double.infinity, maxZ = -double.infinity;
    for (final v in joints.values) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.z < minZ) minZ = v.z;
      if (v.z > maxZ) maxZ = v.z;
    }
    final path = Path();
    const n = 24;
    final cx = (minX + maxX) / 2;
    final cz = (minZ + maxZ) / 2;
    final rx = math.max(0.25, (maxX - minX) / 2 + 0.12);
    final rz = math.max(0.25, (maxZ - minZ) / 2 + 0.12);
    for (var i = 0; i <= n; i++) {
      final t = i / n * math.pi * 2;
      final (p, _) = project(
        Vec3(cx + rx * math.cos(t), 0.001, cz + rz * math.sin(t)),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  @override
  bool shouldRepaint(covariant _MannequinPainter old) =>
      old.pose != pose ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.highlight != highlight;
}
