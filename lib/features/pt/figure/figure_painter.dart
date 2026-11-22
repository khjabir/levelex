import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../../app/theme.dart';
import '../mannequin/mannequin_painter.dart' show guideGridPaint;
import '../mannequin/rig.dart';
import 'figure_model.dart';

/// Which muscle groups to light up and how strongly (0..1), keyed by the
/// glTF material name (chest, back, shoulders, biceps, triceps, core,
/// glutes, quads, hamstrings, calves).
typedef MuscleEmphasis = Map<String, double>;

/// Draws a skinned body with `Canvas.drawVertices`: CPU skinning, a
/// perspective projection, per-vertex lighting and a depth-sorted index
/// buffer (no depth buffer is needed for a closed body). Around 14k
/// triangles render in a few milliseconds on a phone.
class FigurePainter extends CustomPainter {
  FigurePainter({
    required this.model,
    required this.animation,
    required this.time,
    required this.yaw,
    required this.pitch,
    required this.showFloor,
    required this.compact,
    this.frame,
    this.emphasis = const {},
    this.warn = const {},
    this.skinColor = const Color(0xFFDCC2AE),
    this.fromAnimation,
    this.fromTime = 0,
    this.blend = 1,
    this.lifeTime,
    this.lifeAmount = 1,
  });

  final FigureModel model;
  final FigureAnimation? animation;

  /// Animation time in seconds (keyframe i lives at i seconds).
  final double time;
  final double yaw;
  final double pitch;
  final bool showFloor;
  final bool compact;

  /// Extents used to frame the camera (from the rig clip, so it matches
  /// the lite mannequin); falls back to the rest pose.
  final MannequinFrame? frame;
  final MuscleEmphasis emphasis;

  /// Material names drawn in the warning colour (form corrections).
  final Set<String> warn;
  final Color skinColor;

  /// Cross-fade: the previous movement at [fromTime], blended toward
  /// [animation] by [blend] (1 = fully the current movement).
  final FigureAnimation? fromAnimation;
  final double fromTime;
  final double blend;

  /// Seconds for the idle micro-motion (breathing, sway, head turn); null
  /// draws the pose exactly as keyed (stills, tests).
  final double? lifeTime;
  final double lifeAmount;

  static const _distance = 3.6;
  static final vm.Vector3 _light = vm.Vector3(-0.55, 0.75, 0.6).normalized();

  // Reused across frames to avoid allocation churn.
  static Float32List? _screen;
  static Float32List? _depth;
  static Int32List? _colors;
  static Uint16List? _sorted;
  static Float32List? _triDepth;
  static Int32List? _triOrder;
  static Uint8List? _keep;
  static Int32List? _bucketOf;
  static Int32List? _counts;
  static Float32List? _shadow;
  static const _buckets = 2048;

  @override
  void paint(Canvas canvas, Size size) {
    // The floor reaches past the body; keep it inside the guide's own box
    // instead of drawing over the card below.
    canvas.clipRect(Offset.zero & size);
    final m = model;
    if (blend < 1 && fromAnimation != null) {
      m.sampleBlend(fromAnimation, fromTime, animation, time, blend);
    } else {
      m.resetPose();
      final anim = animation;
      if (anim != null) m.sample(anim, time);
    }
    final life = lifeTime;
    if (life != null) {
      m.applyLife(life, towardCamera: yaw, amount: lifeAmount);
    }
    m.pose();
    m.skin();

    final n = m.vertexCount;
    final pos = m.skinnedPositions;
    // Keep the lowest point of the body on the floor: the body's segment
    // lengths differ from the rig's, so the keyed root height alone can
    // leave the feet floating or sunk.
    var minY = double.infinity;
    for (var v = 0; v < n; v++) {
      final y = pos[v * 3 + 1];
      if (y < minY) minY = y;
    }
    final lift = minY.isFinite ? 0.004 - minY : 0.0;
    if (lift != 0) {
      for (var v = 0; v < n; v++) {
        pos[v * 3 + 1] += lift;
      }
    }
    final screen = _screen = (_screen?.length == n * 2
        ? _screen
        : Float32List(n * 2))!;
    final depth = _depth = (_depth?.length == n ? _depth : Float32List(n))!;
    final colors = _colors = (_colors?.length == n ? _colors : Int32List(n))!;

    // Camera: fit like the mannequin, plus padding for flesh.
    final fit = frame;
    final bounds = m.restBounds;
    final restHeight = bounds.max.y - bounds.min.y;
    // The body may be taller than the rig it is animated from (its hips sit
    // at the rig's hip height); scale the rig's extents to match.
    final ratio = fit == null
        ? 1.0
        : (restHeight / Rig.standingHeight).clamp(0.8, 1.4);
    final height = fit == null ? restHeight : fit.height * ratio;
    final halfWidth = fit == null
        ? math.max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z) / 2
        : fit.halfWidth * ratio;
    const pad = 0.14;
    final usable = compact ? 0.94 : 0.88;
    final scale = math.min(
      size.width * usable / 2 / (halfWidth + pad),
      size.height * usable / 2 / (height / 2 + pad),
    );
    final focal = scale * _distance;
    final cx = size.width / 2, cy = size.height * 0.5;
    final targetY = height * 0.5;

    final yawR = yaw * math.pi / 180, pitchR = pitch * math.pi / 180;
    final cyw = math.cos(yawR), syw = math.sin(yawR);
    final cp = math.cos(pitchR), sp = math.sin(pitchR);
    // view = rotX(pitch) * rotY(-yaw)
    // rotY(-yaw): x' = x*cos - z*sin ; z' = x*sin + z*cos   (for angle -yaw)
    double vx(double x, double y, double z) => x * cyw - z * syw;
    double vzA(double x, double y, double z) => x * syw + z * cyw;

    final nrm = m.skinnedNormals;
    final occlusion = m.occlusion;
    final warmth = m.warmth;
    final lx = _light.x, ly = _light.y, lz = _light.z;

    // Per-primitive base colours.
    final primColors = <int, List<double>>{};
    for (var p = 0; p < m.primitives.length; p++) {
      primColors[p] = _baseColor(m.primitives[p].materialName);
    }
    final vertexPrim = m.vertexPrimitive;

    for (var v = 0; v < n; v++) {
      final x = pos[v * 3], y = pos[v * 3 + 1] - targetY, z = pos[v * 3 + 2];
      final x1 = vx(x, y, z);
      final z1 = vzA(x, y, z);
      // rotX(pitch): y' = y cos - z sin ; z' = y sin + z cos
      final y2 = y * cp - z1 * sp;
      final z2 = y * sp + z1 * cp;
      // The camera sits on +z looking at the origin: nearer = larger z.
      final d = _distance - z2;
      depth[v] = d;
      final s = focal / d;
      screen[v * 2] = cx + x1 * s;
      screen[v * 2 + 1] = cy - y2 * s;

      // Normal in view space.
      final nx0 = nrm[v * 3], ny0 = nrm[v * 3 + 1], nz0 = nrm[v * 3 + 2];
      final nx1 = vx(nx0, ny0, nz0);
      final nz1 = vzA(nx0, ny0, nz0);
      final ny2 = ny0 * cp - nz1 * sp;
      final nz2 = ny0 * sp + nz1 * cp;
      var lambert = nx1 * lx + ny2 * ly + nz2 * lz;
      if (lambert < 0) {
        lambert = 0;
      }
      // Soft fill from the opposite side so shadowed limbs keep their form.
      var fill = -nx1 * 0.6 + ny2 * 0.2 - nz2 * 0.3;
      if (fill < 0) {
        fill = 0;
      }
      final facing = nz2 < 0 ? 0.0 : nz2;
      final rim = (1 - facing) * (1 - facing) * 0.26;
      // Baked occlusion, floored so sockets and armpits never go black.
      final ao = 0.4 + 0.6 * occlusion[v];
      // Hemisphere ambient: surfaces facing up catch more sky light.
      final sky = 0.5 + 0.5 * ny2;
      final ambient = (0.17 + 0.13 * sky) * (0.5 + 0.5 * ao);
      final shade =
          ambient + 0.74 * lambert * (0.35 + 0.65 * ao) + 0.14 * fill * ao;
      // Warm wrap at the light terminator stands in for skin scattering.
      final wrap = (1 - lambert) * lambert * 0.6;
      // Broad specular from the key light.
      final hx = lx, hy = ly, hz = lz + 1;
      final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
      var spec = (nx1 * hx + ny2 * hy + nz2 * hz) / hl;
      spec = spec <= 0
          ? 0
          : spec * spec * spec * spec * spec * spec * spec * spec * 0.18 * ao;
      final c = primColors[vertexPrim[v]]!;
      final skin = c[3] > 0.5;
      // Baked warmth: face, hands and joints run redder and a touch darker.
      final warm = skin ? warmth[v] : 0.0;
      final cr = c[0] * (1 + 0.05 * warm), cg = c[1] * (1 - 0.05 * warm);
      final cb = c[2] * (1 - 0.12 * warm);
      var r = cr * shade + rim * 0.9 * ao + spec + (skin ? wrap * 0.16 : 0);
      var g = cg * shade + rim * 0.95 * ao + spec + (skin ? wrap * 0.04 : 0);
      var b = cb * shade + rim * 1.0 * ao + spec + (skin ? wrap * 0.015 : 0);
      // Depth fog toward the background keeps far limbs behind.
      final fog = ((d - (_distance - 1.0)) / 2.4).clamp(0.0, 1.0) * 0.35;
      r = r * (1 - fog) + 0.03 * fog;
      g = g * (1 - fog) + 0.035 * fog;
      b = b * (1 - fog) + 0.055 * fog;
      colors[v] =
          0xFF000000 |
          ((r.clamp(0.0, 1.0) * 255).round() << 16) |
          ((g.clamp(0.0, 1.0) * 255).round() << 8) |
          (b.clamp(0.0, 1.0) * 255).round();
    }

    if (showFloor) {
      _paintFloor(
        canvas,
        size,
        focal,
        cx,
        cy,
        targetY,
        cyw,
        syw,
        cp,
        sp,
        bounds,
        m,
      );
      _paintCastShadow(
        canvas,
        size,
        m,
        focal,
        cx,
        cy,
        targetY,
        cyw,
        syw,
        cp,
        sp,
      );
    }

    // Depth sort triangles (far first) with a bucket sort; cull back faces.
    var triCount = 0;
    for (final p in m.primitives) {
      triCount += p.indices.length ~/ 3;
    }
    final triDepth = _triDepth = (_triDepth?.length == triCount
        ? _triDepth
        : Float32List(triCount))!;
    final triOrder = _triOrder = (_triOrder?.length == triCount
        ? _triOrder
        : Int32List(triCount))!;
    final sorted = _sorted = (_sorted?.length == triCount * 3
        ? _sorted
        : Uint16List(triCount * 3))!;
    var t = 0;
    var minD = double.infinity, maxD = -double.infinity;
    final flat = m.flatIndices;
    final keep = _keep = (_keep?.length == triCount
        ? _keep
        : Uint8List(triCount))!;
    final bucketOf = _bucketOf = (_bucketOf?.length == triCount
        ? _bucketOf
        : Int32List(triCount))!;
    final counts = _counts ??= Int32List(_buckets + 1);
    counts.fillRange(0, counts.length, 0);
    for (var i = 0; i < triCount; i++) {
      final a = flat[i * 3], b = flat[i * 3 + 1], c = flat[i * 3 + 2];
      // Screen-space winding (y down): front faces are counter-clockwise
      // in glTF, which is clockwise once y is flipped.
      final ax = screen[a * 2], ay = screen[a * 2 + 1];
      final cross =
          (screen[b * 2] - ax) * (screen[c * 2 + 1] - ay) -
          (screen[b * 2 + 1] - ay) * (screen[c * 2] - ax);
      if (cross >= 0) {
        keep[i] = 0;
        continue;
      }
      keep[i] = 1;
      final d = (depth[a] + depth[b] + depth[c]) / 3;
      triDepth[i] = d;
      if (d < minD) minD = d;
      if (d > maxD) maxD = d;
      t++;
    }
    const buckets = _buckets;
    final range = maxD - minD;
    final inv = range <= 0 ? 0.0 : (buckets - 1) / range;
    for (var i = 0; i < triCount; i++) {
      if (keep[i] == 0) continue;
      // Far triangles first: invert the bucket index.
      final bkt = (buckets - 1 - ((triDepth[i] - minD) * inv).floor()).clamp(
        0,
        buckets - 1,
      );
      bucketOf[i] = bkt;
      counts[bkt + 1]++;
    }
    for (var b = 0; b < buckets; b++) {
      counts[b + 1] += counts[b];
    }
    for (var i = 0; i < triCount; i++) {
      if (keep[i] == 0) continue;
      triOrder[counts[bucketOf[i]]++] = i;
    }
    for (var k = 0; k < t; k++) {
      final i = triOrder[k];
      sorted[k * 3] = flat[i * 3];
      sorted[k * 3 + 1] = flat[i * 3 + 1];
      sorted[k * 3 + 2] = flat[i * 3 + 2];
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      screen,
      colors: colors,
      indices: Uint16List.sublistView(sorted, 0, t * 3),
    );
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()..isAntiAlias = true,
    );
    vertices.dispose();
  }

  /// RGB plus a flag (1 = bare skin, which gets the warm scattering wrap).
  /// Material names are `<muscle>`, `<garment>` or `<garment>.<muscle>` for
  /// a muscle under the clothes, which lights up through the cloth.
  List<double> _baseColor(String material) {
    switch (material) {
      case 'eye' || 'iris':
        return const [0.2, 0.13, 0.08, 0];
      case 'sclera':
        return const [0.9, 0.9, 0.88, 0];
      case 'hair':
        return const [0.17, 0.12, 0.09, 0];
    }
    // Black trunks and a slate T-shirt.
    const shorts = [0.11, 0.12, 0.15, 0.0];
    const shirt = [0.26, 0.31, 0.40, 0.0];
    final dot = material.indexOf('.');
    final garment = dot < 0 ? material : material.substring(0, dot);
    final part = dot < 0 ? material : material.substring(dot + 1);
    final base = switch (garment) {
      'shorts' => shorts,
      'shirt' => shirt,
      _ => [skinColor.r, skinColor.g, skinColor.b, 1.0],
    };
    if (warn.contains(part)) {
      final w = AppColors.warning;
      return [w.r, w.g, w.b, 0];
    }
    final e = emphasis[part] ?? 0;
    if (e <= 0) return base;
    final p = AppColors.primary;
    final k = 0.35 + 0.65 * e.clamp(0.0, 1.0);
    return [
      base[0] + (p.r - base[0]) * k,
      base[1] + (p.g - base[1]) * k,
      base[2] + (p.b - base[2]) * k,
      0,
    ];
  }

  /// The body's shadow projected along the key light onto the floor: the
  /// mesh itself flattened to y = 0, drawn as one soft dark shape.
  void _paintCastShadow(
    Canvas canvas,
    Size size,
    FigureModel m,
    double focal,
    double cx,
    double cy,
    double targetY,
    double cyw,
    double syw,
    double cp,
    double sp,
  ) {
    final n = m.vertexCount;
    final pos = m.skinnedPositions;
    final out = _shadow = (_shadow?.length == n * 2
        ? _shadow
        : Float32List(n * 2))!;
    // Shadow direction: away from the light, flattened so it stays short.
    final dx = -_light.x / _light.y * 0.55, dz = -_light.z / _light.y * 0.55;
    for (var v = 0; v < n; v++) {
      final y = pos[v * 3 + 1];
      final x = pos[v * 3] + dx * y;
      final z = pos[v * 3 + 2] + dz * y;
      final yy = -targetY;
      final x1 = x * cyw - z * syw;
      final z1 = x * syw + z * cyw;
      final y2 = yy * cp - z1 * sp;
      final z2 = yy * sp + z1 * cp;
      final s = focal / (_distance - z2);
      out[v * 2] = cx + x1 * s;
      out[v * 2 + 1] = cy - y2 * s;
    }
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: compact ? 0.38 : 0.45);
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    // One layer so overlapping triangles do not darken each other, blurred
    // for a soft edge on the big cards.
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = compact
            ? null
            : ui.ImageFilter.blur(
                sigmaX: 5,
                sigmaY: 5,
                tileMode: TileMode.decal,
              ),
    );
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      out,
      indices: m.flatIndices,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
    canvas.restore();
  }

  void _paintFloor(
    Canvas canvas,
    Size size,
    double focal,
    double cx,
    double cy,
    double targetY,
    double cyw,
    double syw,
    double cp,
    double sp,
    ({vm.Vector3 min, vm.Vector3 max}) bounds,
    FigureModel m,
  ) {
    Offset project(double x, double y, double z) {
      final yy = y - targetY;
      final x1 = x * cyw - z * syw;
      final z1 = x * syw + z * cyw;
      final y2 = yy * cp - z1 * sp;
      final z2 = yy * sp + z1 * cp;
      final s = focal / (_distance - z2);
      return Offset(cx + x1 * s, cy - y2 * s);
    }

    // A soft pool of light under the body: gives the cast shadow something
    // to fall on, and grounds the figure on a dark card.
    final centre = project(0, 0, 0);
    final rx = (project(1.1, 0, 0) - centre).distance;
    final ry = (project(0, 0, -1.1) - centre).distance.clamp(rx * 0.15, rx);
    canvas.drawOval(
      Rect.fromCenter(center: centre, width: rx * 2, height: ry * 2),
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          rx,
          [
            Colors.white.withValues(alpha: compact ? 0.10 : 0.13),
            Colors.white.withValues(alpha: 0.0),
          ],
          const [0.0, 1.0],
          TileMode.clamp,
          (Matrix4.identity()
                ..translateByDouble(0, centre.dy, 0, 1)
                ..scaleByDouble(1, ry / rx, 1, 1)
                ..translateByDouble(0, -centre.dy, 0, 1))
              .storage,
        ),
    );
    const extent = 1.4;
    const step = 0.35;
    final grid = guideGridPaint(
      centre,
      (project(extent, 0, 0) - centre).distance,
      size,
    );
    for (var i = -extent; i <= extent + 1e-6; i += step) {
      canvas.drawLine(project(i, 0, -extent), project(i, 0, extent), grid);
      canvas.drawLine(project(-extent, 0, i), project(extent, 0, i), grid);
    }
  }

  @override
  bool shouldRepaint(covariant FigurePainter old) =>
      old.model != model ||
      old.animation != animation ||
      old.time != time ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.showFloor != showFloor ||
      old.compact != compact ||
      old.frame != frame ||
      old.emphasis != emphasis ||
      old.warn != warn ||
      old.skinColor != skinColor ||
      old.fromAnimation != fromAnimation ||
      old.fromTime != fromTime ||
      old.blend != blend ||
      old.lifeTime != lifeTime ||
      old.lifeAmount != lifeAmount;
}
