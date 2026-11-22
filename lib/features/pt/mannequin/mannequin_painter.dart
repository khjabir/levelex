import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/geometry.dart';
import 'rig.dart';

/// Software-rendered mannequin: perspective projection, painter's-algorithm
/// depth sorting, shaded capsules for limbs, a filled torso and pelvis, a
/// shaded head, hands and feet. No model files.
class MannequinPainter extends CustomPainter {
  MannequinPainter({
    required this.pose,
    required this.yaw,
    required this.pitch,
    required this.highlight,
    required this.showFloor,
    required this.compact,
    this.tint = AppColors.primary,
    this.emphasis = const {},
    this.frame,
    this.offset = Vec3.zero,
  });

  final RigPose pose;

  /// Horizontal translation keeping planted hands and feet in place
  /// (see [MannequinClip.offsetAt]).
  final Vec3 offset;
  final double yaw;
  final double pitch;
  final Set<String> highlight;
  final bool showFloor;
  final bool compact;
  final Color tint;

  /// Parts that do the work; when set, every other part is drawn neutral.
  final Set<String> emphasis;
  static const _muted = Color(0xFF8E98A8);

  /// Extents to fit; defaults to this pose alone (steady only for stills).
  final MannequinFrame? frame;

  static const _distance = 3.6;

  // Light from the upper left, slightly in front of the camera.
  static final Vec3 _light = const Vec3(-0.55, 0.75, 0.6).normalized;

  @override
  void paint(Canvas canvas, Size size) {
    final joints = {
      for (final e in Rig.solve(pose).entries) e.key: e.value + offset,
    };
    final fit = frame ?? MannequinFrame.ofPoses([pose]);
    final target = Vec3(0, fit.height * 0.5, 0);
    final view = Mat3.rotX(pitch) * Mat3.rotY(-yaw);
    // Fit the clip's extents (plus limb thickness) into the canvas so a
    // push-up fills a card as well as a standing figure does.
    const pad = Rig.headRadius + 0.10;
    final usable = compact ? 0.92 : 0.86;
    final scale = math.min(
      size.width * usable / 2 / (fit.halfWidth + pad),
      size.height * usable / 2 / (fit.height / 2 + pad),
    );
    final focal = scale * _distance;
    final centre = Offset(size.width / 2, size.height * 0.5);

    (Offset, double) project(Vec3 p) {
      final c = view.apply(p - target);
      // The camera sits on +z, so nearer points have larger z.
      final depth = _distance - c.z;
      final s = focal / depth;
      return (Offset(centre.dx + c.x * s, centre.dy - c.y * s), depth);
    }

    if (showFloor) _paintFloor(canvas, size, project, joints);

    // Every drawable primitive with its camera depth, far to near.
    final items = <_Prim>[];
    for (final bone in Rig.bones) {
      final a = joints[bone.a];
      final b = joints[bone.b];
      if (a == null || b == null) continue;
      final (pa, da) = project(a);
      final (pb, db) = project(b);
      // Lighting from the limb direction: limbs facing the light are
      // brighter. Cylinders are lit by the component of light orthogonal
      // to their axis, approximated here with the view-space direction.
      final axis = (view.apply(b - a)).normalized;
      final facing =
          1 - (axis.dot(_light)).abs() * 0.35; // along-axis limbs are flatter
      items.add(
        _Prim.capsule(
          pa,
          pb,
          (da + db) / 2,
          bone.thickness * focal / ((da + db) / 2),
          flagged: highlight.contains(bone.part),
          dim: emphasis.isNotEmpty && !emphasis.contains(bone.part),
          light: facing,
        ),
      );
    }
    // Torso plate between shoulders and hips, drawn as a soft filled quad.
    final sl = joints['shoulderL'], sr = joints['shoulderR'];
    final hl = joints['hipL'], hr = joints['hipR'];
    if (sl != null && sr != null && hl != null && hr != null) {
      final pts = [sl, sr, hr, hl].map(project).toList();
      final depth = pts.fold(0.0, (s, p) => s + p.$2) / 4;
      items.add(
        _Prim.quad(
          [for (final p in pts) p.$1],
          depth,
          flagged: highlight.contains('torso'),
          dim: emphasis.isNotEmpty && !emphasis.contains('torso'),
        ),
      );
    }
    final head = joints['head'];
    if (head != null) {
      final (hp, hd) = project(head);
      items.add(
        _Prim.head(
          hp,
          hd,
          Rig.headRadius * focal / hd,
          dim: emphasis.isNotEmpty,
        ),
      );
      // Face hint: nose direction is body +Z through the neck pitch.
    }
    items.sort((x, y) => y.depth.compareTo(x.depth));

    for (final item in items) {
      final shade = ((item.depth - (_distance - 1.0)) / 2.0).clamp(0.0, 1.0);
      final base = item.flagged
          ? AppColors.warning
          : item.dim
          ? _muted
          : tint;
      switch (item.kind) {
        case _Kind.capsule:
          _capsule(canvas, item, base, shade);
        case _Kind.quad:
          _quad(canvas, item, base, shade);
        case _Kind.head:
          _head(canvas, item, base, shade);
      }
    }
  }

  void _capsule(Canvas canvas, _Prim p, Color base, double shade) {
    final a = p.a!, b = p.b!;
    final w = p.width;
    final lit = Color.lerp(base, Colors.white, 0.18 * p.light)!;
    final body = Color.lerp(lit, AppColors.background, 0.10 + shade * 0.45)!;
    final dark = Color.lerp(body, Colors.black, 0.45)!;
    // Outline for separation between overlapping limbs.
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..strokeWidth = w + 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = body
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
    final dir = b - a;
    final len = dir.distance;
    if (len <= 0) return;
    final n = Offset(-dir.dy / len, dir.dx / len);
    // Underside shadow and top highlight give the capsule its roundness.
    canvas.drawLine(
      a + n * (w * 0.26),
      b + n * (w * 0.26),
      Paint()
        ..color = dark.withValues(alpha: 0.55)
        ..strokeWidth = math.max(1, w * 0.26)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      a - n * (w * 0.22),
      b - n * (w * 0.22),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30 * p.light)
        ..strokeWidth = math.max(1, w * 0.20)
        ..strokeCap = StrokeCap.round,
    );
  }

  void _quad(Canvas canvas, _Prim p, Color base, double shade) {
    final pts = p.points!;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    path.close();
    final top = Color.lerp(base, Colors.white, 0.12)!;
    final bottom = Color.lerp(base, AppColors.background, 0.35 + shade * 0.3)!;
    final bounds = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(bounds),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  void _head(Canvas canvas, _Prim p, Color base, double shade) {
    final c = p.a!;
    final r = p.width;
    canvas.drawCircle(
      c,
      r + 1.5,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.45),
          colors: [
            Color.lerp(base, Colors.white, 0.45)!,
            Color.lerp(base, Colors.white, 0.05)!,
            Color.lerp(base, AppColors.background, 0.55 + shade * 0.2)!,
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
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
  bool shouldRepaint(covariant MannequinPainter old) =>
      old.pose != pose ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.highlight != highlight ||
      old.tint != tint ||
      old.emphasis != emphasis ||
      old.offset != offset ||
      old.showFloor != showFloor ||
      old.compact != compact ||
      old.frame != frame;
}

enum _Kind { capsule, quad, head }

class _Prim {
  _Prim._(
    this.kind,
    this.depth, {
    this.a,
    this.b,
    this.points,
    this.width = 0,
    this.flagged = false,
    this.dim = false,
    this.light = 1,
  });

  factory _Prim.capsule(
    Offset a,
    Offset b,
    double depth,
    double width, {
    required bool flagged,
    required double light,
    bool dim = false,
  }) => _Prim._(
    _Kind.capsule,
    depth,
    a: a,
    b: b,
    width: width,
    flagged: flagged,
    dim: dim,
    light: light,
  );

  factory _Prim.quad(
    List<Offset> points,
    double depth, {
    required bool flagged,
    bool dim = false,
  }) => _Prim._(_Kind.quad, depth, points: points, flagged: flagged, dim: dim);

  factory _Prim.head(
    Offset c,
    double depth,
    double radius, {
    bool dim = false,
  }) => _Prim._(_Kind.head, depth, a: c, width: radius, dim: dim);

  final _Kind kind;
  final double depth;
  final Offset? a;
  final Offset? b;
  final List<Offset>? points;
  final double width;
  final bool flagged;
  final bool dim;
  final double light;
}
