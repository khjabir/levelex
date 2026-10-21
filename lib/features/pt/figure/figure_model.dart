import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart' as vm;

import 'gltf.dart';

/// One draw batch: triangles sharing a material.
class FigurePrimitive {
  FigurePrimitive({
    required this.indices,
    required this.materialName,
    required this.baseColor,
    required this.vertexOffset,
  });

  final Uint16List indices;
  final String materialName;

  /// RGBA 0..1 from the glTF material.
  final List<double> baseColor;

  /// Offset of this primitive's vertices in the model's shared arrays.
  final int vertexOffset;
}

class _Node {
  _Node({
    required this.name,
    required this.children,
    required this.translation,
    required this.rotation,
    required this.scale,
    required this.mesh,
    required this.skin,
  });

  final String name;
  final List<int> children;
  final vm.Vector3 translation;
  final vm.Quaternion rotation;
  final vm.Vector3 scale;
  final int? mesh;
  final int? skin;
  int parent = -1;
}

class _Channel {
  _Channel({
    required this.node,
    required this.path,
    required this.times,
    required this.values,
    required this.step,
  });

  final int node;
  final String path; // translation | rotation | scale
  final Float32List times;
  final Float32List values;
  final bool step;
}

/// A named animation: channels plus its time span.
class FigureAnimation {
  FigureAnimation(this.name, this._channels) {
    var end = 0.0;
    for (final c in _channels) {
      if (c.times.isNotEmpty && c.times.last > end) end = c.times.last;
    }
    duration = end;
  }

  final String name;
  final List<_Channel> _channels;
  late final double duration;
}

/// A skinned body loaded from a GLB: shared vertex arrays, primitives by
/// material, a node hierarchy with one skin, and named animations. All the
/// per-frame work (sampling, skinning) writes into reusable buffers.
class FigureModel {
  FigureModel._({
    required this.positions,
    required this.normals,
    required this.joints,
    required this.weights,
    required this.occlusion,
    required this.warmth,
    required this.primitives,
    required List<_Node> nodes,
    required this.skinJoints,
    required this.inverseBind,
    required this.animations,
    required this.meshNode,
  }) : _nodes = nodes,
       vertexCount = positions.length ~/ 3,
       skinnedPositions = Float32List(positions.length),
       skinnedNormals = Float32List(normals.length),
       _local = List.generate(nodes.length, (_) => vm.Matrix4.identity()),
       _global = List.generate(nodes.length, (_) => vm.Matrix4.identity()),
       _skinMatrices = List.generate(
         skinJoints.length,
         (_) => vm.Matrix4.identity(),
       ),
       _t = List.generate(nodes.length, (i) => nodes[i].translation.clone()),
       _r = List.generate(nodes.length, (i) => nodes[i].rotation.clone()),
       _s = List.generate(nodes.length, (i) => nodes[i].scale.clone());

  /// Rest-pose vertex data (model space).
  final Float32List positions;
  final Float32List normals;
  final Int32List joints; // 4 per vertex
  final Float32List weights; // 4 per vertex

  /// Baked ambient occlusion per vertex (0 = fully occluded, 1 = open),
  /// from the glTF COLOR_0 attribute; all 1 when the asset has none.
  final Float32List occlusion;

  /// Skin warmth per vertex (0..1, COLOR_0 green): face, hands, knees and
  /// elbows run a little redder.
  final Float32List warmth;
  final List<FigurePrimitive> primitives;
  final int vertexCount;

  final List<_Node> _nodes;
  final List<int> skinJoints;
  final List<vm.Matrix4> inverseBind;
  final Map<String, FigureAnimation> animations;
  final int meshNode;

  /// Output of [skin]: current-pose vertex data.
  final Float32List skinnedPositions;
  final Float32List skinnedNormals;

  final List<vm.Matrix4> _local;
  final List<vm.Matrix4> _global;
  final List<vm.Matrix4> _skinMatrices;
  final List<vm.Vector3> _t;
  final List<vm.Quaternion> _r;
  final List<vm.Vector3> _s;

  int get triangleCount =>
      primitives.fold(0, (s, p) => s + p.indices.length ~/ 3);

  Uint16List? _flatIndices;
  Int32List? _vertexPrimitive;

  /// All triangle indices of every primitive, concatenated.
  Uint16List get flatIndices {
    if (_flatIndices != null) return _flatIndices!;
    final out = Uint16List(triangleCount * 3);
    var o = 0;
    for (final p in primitives) {
      out.setAll(o, p.indices);
      o += p.indices.length;
    }
    return _flatIndices = out;
  }

  /// Primitive index per vertex (for material colours).
  Int32List get vertexPrimitive {
    if (_vertexPrimitive != null) return _vertexPrimitive!;
    final out = Int32List(vertexCount);
    for (var p = 0; p < primitives.length; p++) {
      for (final i in primitives[p].indices) {
        out[i] = p;
      }
    }
    return _vertexPrimitive = out;
  }

  List<String> get nodeNames => [for (final n in _nodes) n.name];

  /// Node index by name, or -1.
  int nodeIndex(String name) {
    for (var i = 0; i < _nodes.length; i++) {
      if (_nodes[i].name == name) return i;
    }
    return -1;
  }

  /// World position of a node in the current pose (after [pose]).
  vm.Vector3 nodePosition(int node) => _global[node].getTranslation();

  static FigureModel fromGlb(ByteData data) {
    final g = Gltf.fromGlb(data);
    final nodes = <_Node>[];
    for (final raw in g.nodes) {
      final n = raw as Map;
      vm.Vector3 t;
      vm.Quaternion r;
      vm.Vector3 s;
      if (n['matrix'] != null) {
        final m = vm.Matrix4.fromList([
          for (final v in n['matrix'] as List) (v as num).toDouble(),
        ]);
        t = m.getTranslation();
        r = vm.Quaternion.fromRotation(m.getRotation());
        s = vm.Vector3(
          m.getColumn(0).xyz.length,
          m.getColumn(1).xyz.length,
          m.getColumn(2).xyz.length,
        );
      } else {
        final tl = n['translation'] as List?;
        final rl = n['rotation'] as List?;
        final sl = n['scale'] as List?;
        t = tl == null
            ? vm.Vector3.zero()
            : vm.Vector3(
                (tl[0] as num).toDouble(),
                (tl[1] as num).toDouble(),
                (tl[2] as num).toDouble(),
              );
        r = rl == null
            ? vm.Quaternion.identity()
            : vm.Quaternion(
                (rl[0] as num).toDouble(),
                (rl[1] as num).toDouble(),
                (rl[2] as num).toDouble(),
                (rl[3] as num).toDouble(),
              );
        s = sl == null
            ? vm.Vector3.all(1)
            : vm.Vector3(
                (sl[0] as num).toDouble(),
                (sl[1] as num).toDouble(),
                (sl[2] as num).toDouble(),
              );
      }
      nodes.add(
        _Node(
          name: (n['name'] as String?) ?? 'node${nodes.length}',
          children: [
            for (final c in (n['children'] as List? ?? const [])) c as int,
          ],
          translation: t,
          rotation: r,
          scale: s,
          mesh: n['mesh'] as int?,
          skin: n['skin'] as int?,
        ),
      );
    }
    for (var i = 0; i < nodes.length; i++) {
      for (final c in nodes[i].children) {
        nodes[c].parent = i;
      }
    }

    // The (single) skinned mesh.
    var meshNode = -1;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].mesh != null && nodes[i].skin != null) {
        meshNode = i;
        break;
      }
    }
    if (meshNode == -1) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].mesh != null) {
          meshNode = i;
          break;
        }
      }
    }
    if (meshNode == -1) throw const FormatException('GLB has no mesh');
    final mesh = g.meshes[nodes[meshNode].mesh!] as Map;

    final posChunks = <Float32List>[];
    final nrmChunks = <Float32List>[];
    final jntChunks = <Int32List>[];
    final wgtChunks = <Float32List>[];
    final aoChunks = <Float32List>[];
    final warmChunks = <Float32List>[];
    final prims = <FigurePrimitive>[];
    var vertexOffset = 0;
    for (final raw in mesh['primitives'] as List) {
      final p = raw as Map;
      final attrs = p['attributes'] as Map;
      final pos = g.readFloats(attrs['POSITION'] as int);
      final n = pos.length ~/ 3;
      final nrm = attrs['NORMAL'] != null
          ? g.readFloats(attrs['NORMAL'] as int)
          : Float32List(pos.length);
      final jnt = attrs['JOINTS_0'] != null
          ? g.readInts(attrs['JOINTS_0'] as int)
          : Int32List(n * 4);
      final wgt = attrs['WEIGHTS_0'] != null
          ? g.readFloats(attrs['WEIGHTS_0'] as int)
          : (Float32List(n * 4)..setAll(0, List.filled(n * 4, 0)));
      if (attrs['WEIGHTS_0'] == null) {
        for (var i = 0; i < n; i++) {
          wgt[i * 4] = 1;
        }
      }
      final ao = Float32List(n);
      final warm = Float32List(n);
      if (attrs['COLOR_0'] != null) {
        final acc = g.accessors[attrs['COLOR_0'] as int] as Map;
        final comps = acc['type'] == 'VEC4' ? 4 : 3;
        final col = g.readFloats(attrs['COLOR_0'] as int);
        for (var i = 0; i < n; i++) {
          ao[i] = col[i * comps];
          warm[i] = col[i * comps + 1];
        }
      } else {
        ao.fillRange(0, n, 1);
      }
      final rawIdx = p['indices'] != null
          ? g.readInts(p['indices'] as int)
          : Int32List.fromList([for (var i = 0; i < n; i++) i]);
      final idx = Uint16List(rawIdx.length);
      for (var i = 0; i < rawIdx.length; i++) {
        idx[i] = rawIdx[i] + vertexOffset;
      }
      var materialName = 'skin';
      var color = <double>[0.78, 0.66, 0.58, 1];
      final mi = p['material'] as int?;
      if (mi != null && mi < g.materials.length) {
        final m = g.materials[mi] as Map;
        materialName = (m['name'] as String?) ?? materialName;
        final pbr = m['pbrMetallicRoughness'] as Map?;
        final f = pbr?['baseColorFactor'] as List?;
        if (f != null && f.length == 4) {
          color = [for (final v in f) (v as num).toDouble()];
        }
      }
      posChunks.add(pos);
      nrmChunks.add(nrm);
      jntChunks.add(jnt);
      wgtChunks.add(wgt);
      aoChunks.add(ao);
      warmChunks.add(warm);
      prims.add(
        FigurePrimitive(
          indices: idx,
          materialName: materialName,
          baseColor: color,
          vertexOffset: vertexOffset,
        ),
      );
      vertexOffset += n;
    }
    if (vertexOffset > 65535) {
      throw FormatException(
        'Too many vertices for 16-bit indices: $vertexOffset',
      );
    }
    final positions = _concat(posChunks);
    final normals = _concat(nrmChunks);
    final joints = Int32List(vertexOffset * 4);
    var o = 0;
    for (final c in jntChunks) {
      joints.setAll(o, c);
      o += c.length;
    }
    final weights = _concat(wgtChunks);
    final occlusion = _concat(aoChunks);
    final warmth = _concat(warmChunks);

    // Skin.
    var skinJoints = <int>[];
    var inverseBind = <vm.Matrix4>[];
    final skinIndex = nodes[meshNode].skin;
    if (skinIndex != null) {
      final skin = g.skins[skinIndex] as Map;
      skinJoints = [for (final j in skin['joints'] as List) j as int];
      final ibm = skin['inverseBindMatrices'] as int?;
      if (ibm != null) {
        final m = g.readFloats(ibm);
        inverseBind = [
          for (var i = 0; i < skinJoints.length; i++)
            vm.Matrix4.fromList([for (var k = 0; k < 16; k++) m[i * 16 + k]]),
        ];
      } else {
        inverseBind = [for (final _ in skinJoints) vm.Matrix4.identity()];
      }
    }

    // Animations.
    final animations = <String, FigureAnimation>{};
    for (final raw in g.animations) {
      final a = raw as Map;
      final samplers = a['samplers'] as List;
      final channels = <_Channel>[];
      for (final cr in a['channels'] as List) {
        final c = cr as Map;
        final target = c['target'] as Map;
        final node = target['node'] as int?;
        if (node == null) continue;
        final s = samplers[c['sampler'] as int] as Map;
        channels.add(
          _Channel(
            node: node,
            path: target['path'] as String,
            times: g.readFloats(s['input'] as int),
            values: g.readFloats(s['output'] as int),
            step: s['interpolation'] == 'STEP',
          ),
        );
      }
      final name = (a['name'] as String?) ?? 'animation${animations.length}';
      animations[name] = FigureAnimation(name, channels);
    }

    return FigureModel._(
      positions: positions,
      normals: normals,
      joints: joints,
      weights: weights,
      occlusion: occlusion,
      warmth: warmth,
      primitives: prims,
      nodes: nodes,
      skinJoints: skinJoints,
      inverseBind: inverseBind,
      animations: animations,
      meshNode: meshNode,
    );
  }

  static Float32List _concat(List<Float32List> chunks) {
    var n = 0;
    for (final c in chunks) {
      n += c.length;
    }
    final out = Float32List(n);
    var o = 0;
    for (final c in chunks) {
      out.setAll(o, c);
      o += c.length;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Posing
  // ---------------------------------------------------------------------------

  /// Resets every node to its rest transform.
  void resetPose() {
    for (var i = 0; i < _nodes.length; i++) {
      _t[i].setFrom(_nodes[i].translation);
      _r[i].setFrom(_nodes[i].rotation);
      _s[i].setFrom(_nodes[i].scale);
    }
  }

  /// Samples [animation] at [time] seconds (clamped) into the node TRS.
  void sample(FigureAnimation animation, double time) {
    for (final c in animation._channels) {
      final times = c.times;
      if (times.isEmpty) continue;
      final t = time.clamp(times.first, times.last);
      var lo = 0;
      var hi = 0;
      var f = 0.0;
      if (times.length > 1) {
        hi = 1;
        while (hi < times.length - 1 && times[hi] < t) {
          hi++;
        }
        lo = hi - 1;
        final span = times[hi] - times[lo];
        f = span <= 0 ? 0.0 : (t - times[lo]) / span;
        if (c.step) f = 0;
      }
      switch (c.path) {
        case 'translation':
          _lerp3(c.values, lo, hi, f, _t[c.node]);
        case 'scale':
          _lerp3(c.values, lo, hi, f, _s[c.node]);
        case 'rotation':
          _slerp(c.values, lo, hi, f, _r[c.node]);
      }
    }
  }

  static void _lerp3(Float32List v, int a, int b, double f, vm.Vector3 out) {
    out.setValues(
      v[a * 3] + (v[b * 3] - v[a * 3]) * f,
      v[a * 3 + 1] + (v[b * 3 + 1] - v[a * 3 + 1]) * f,
      v[a * 3 + 2] + (v[b * 3 + 2] - v[a * 3 + 2]) * f,
    );
  }

  static void _slerp(Float32List v, int a, int b, double f, vm.Quaternion out) {
    var ax = v[a * 4], ay = v[a * 4 + 1], az = v[a * 4 + 2], aw = v[a * 4 + 3];
    var bx = v[b * 4], by = v[b * 4 + 1], bz = v[b * 4 + 2], bw = v[b * 4 + 3];
    var dot = ax * bx + ay * by + az * bz + aw * bw;
    if (dot < 0) {
      bx = -bx;
      by = -by;
      bz = -bz;
      bw = -bw;
      dot = -dot;
    }
    double wa, wb;
    if (dot > 0.9995) {
      wa = 1 - f;
      wb = f;
    } else {
      final theta = math.acos(dot.clamp(-1.0, 1.0));
      final sin = math.sin(theta);
      wa = math.sin((1 - f) * theta) / sin;
      wb = math.sin(f * theta) / sin;
    }
    final x = ax * wa + bx * wb;
    final y = ay * wa + by * wb;
    final z = az * wa + bz * wb;
    final w = aw * wa + bw * wb;
    final len = math.sqrt(x * x + y * y + z * z + w * w);
    out.setValues(x / len, y / len, z / len, w / len);
  }

  List<vm.Vector3>? _bt;
  List<vm.Quaternion>? _br;
  List<vm.Vector3>? _bs;

  /// Samples [a] at [ta] and [b] at [tb] and blends them with [weight]
  /// (0 = all [a], 1 = all [b]); a null animation means the rest pose.
  /// Used to cross-fade when the guide changes movement.
  void sampleBlend(
    FigureAnimation? a,
    double ta,
    FigureAnimation? b,
    double tb,
    double weight,
  ) {
    final n = _nodes.length;
    final bt = _bt ??= List.generate(n, (_) => vm.Vector3.zero());
    final br = _br ??= List.generate(n, (_) => vm.Quaternion.identity());
    final bs = _bs ??= List.generate(n, (_) => vm.Vector3.zero());
    resetPose();
    if (a != null) sample(a, ta);
    for (var i = 0; i < n; i++) {
      bt[i].setFrom(_t[i]);
      br[i].setFrom(_r[i]);
      bs[i].setFrom(_s[i]);
    }
    resetPose();
    if (b != null) sample(b, tb);
    final w = weight.clamp(0.0, 1.0);
    for (var i = 0; i < n; i++) {
      _t[i].setValues(
        bt[i].x + (_t[i].x - bt[i].x) * w,
        bt[i].y + (_t[i].y - bt[i].y) * w,
        bt[i].z + (_t[i].z - bt[i].z) * w,
      );
      _s[i].setValues(
        bs[i].x + (_s[i].x - bs[i].x) * w,
        bs[i].y + (_s[i].y - bs[i].y) * w,
        bs[i].z + (_s[i].z - bs[i].z) * w,
      );
      _slerpQ(br[i], _r[i], w, _r[i]);
    }
  }

  static void _slerpQ(
    vm.Quaternion a,
    vm.Quaternion b,
    double f,
    vm.Quaternion out,
  ) {
    var bx = b.x, by = b.y, bz = b.z, bw = b.w;
    var dot = a.x * bx + a.y * by + a.z * bz + a.w * bw;
    if (dot < 0) {
      bx = -bx;
      by = -by;
      bz = -bz;
      bw = -bw;
      dot = -dot;
    }
    double wa, wb;
    if (dot > 0.9995) {
      wa = 1 - f;
      wb = f;
    } else {
      final theta = math.acos(dot.clamp(-1.0, 1.0));
      final sin = math.sin(theta);
      wa = math.sin((1 - f) * theta) / sin;
      wb = math.sin(f * theta) / sin;
    }
    final x = a.x * wa + bx * wb;
    final y = a.y * wa + by * wb;
    final z = a.z * wa + bz * wb;
    final w = a.w * wa + bw * wb;
    final len = math.sqrt(x * x + y * y + z * z + w * w);
    out.setValues(x / len, y / len, z / len, w / len);
  }

  int? _headNode, _neckNode, _spineUpperNode, _spineLowerNode, _pelvisNode;
  int? _armLNode, _armRNode;

  int _node(String name) => nodeIndex(name);

  /// Adds the small motions a still body never has: breathing through the
  /// upper spine, a slow weight shift at the pelvis, a little drift in the
  /// arms, and the head turning a touch toward the viewer. [t] is seconds;
  /// [towardCamera] is the camera yaw relative to the body's facing, in
  /// degrees (0 = camera straight in front); [amount] scales everything.
  void applyLife(double t, {double towardCamera = 0, double amount = 1}) {
    _headNode ??= _node('head');
    _neckNode ??= _node('neck');
    _spineUpperNode ??= _node('spineUpper');
    _spineLowerNode ??= _node('spineLower');
    _pelvisNode ??= _node('pelvis');
    _armLNode ??= _node('upperArmL');
    _armRNode ??= _node('upperArmR');
    final a = amount.clamp(0.0, 1.0);
    if (a == 0) return;
    const deg = math.pi / 180;
    void rot(int? node, double ax, double ay, double az) {
      if (node == null || node < 0) return;
      final q = _r[node];
      final d = vm.Quaternion.euler(ay, ax, az);
      final out = q * d;
      q.setFrom(out.normalized());
    }

    // Breathing: ~14 breaths a minute through the upper spine, with the
    // neck counter-rotating so the head stays level.
    final breath = math.sin(t * 2 * math.pi / 4.3);
    rot(_spineUpperNode, breath * 1.1 * deg * a, 0, 0);
    rot(_neckNode, -breath * 0.6 * deg * a, 0, 0);
    // Slow sway: a weight shift at the pelvis plus a hint in the low back.
    final sway = math.sin(t * 2 * math.pi / 6.1 + 1.3);
    final sway2 = math.sin(t * 2 * math.pi / 8.7 + 0.4);
    rot(_pelvisNode, 0, 0, sway * 0.7 * deg * a);
    rot(_spineLowerNode, sway2 * 0.5 * deg * a, 0, -sway * 0.5 * deg * a);
    if (_pelvisNode != null && _pelvisNode! >= 0) {
      _t[_pelvisNode!].x += sway * 0.006 * a;
    }
    // Arms drift independently so the two sides never move as one.
    rot(
      _armLNode,
      math.sin(t * 1.7 + 0.9) * 0.8 * deg * a,
      0,
      math.sin(t * 1.1) * 0.5 * deg * a,
    );
    rot(
      _armRNode,
      math.sin(t * 1.9 + 2.1) * 0.8 * deg * a,
      0,
      -math.sin(t * 1.3 + 0.5) * 0.5 * deg * a,
    );
    // Head: turn part of the way toward the camera, within a natural range.
    final turn = (towardCamera.clamp(-70.0, 70.0)) * 0.35;
    rot(_headNode, 0, turn * deg * a, 0);
  }

  /// Computes global matrices from the node TRS and the skin matrices.
  void pose() {
    for (var i = 0; i < _nodes.length; i++) {
      _local[i]
        ..setIdentity()
        ..setTranslation(_t[i])
        ..multiply(vm.Matrix4.compose(vm.Vector3.zero(), _r[i], _s[i]));
    }
    void visit(int i, vm.Matrix4? parent) {
      if (parent == null) {
        _global[i].setFrom(_local[i]);
      } else {
        _global[i]
          ..setFrom(parent)
          ..multiply(_local[i]);
      }
      for (final c in _nodes[i].children) {
        visit(c, _global[i]);
      }
    }

    for (var i = 0; i < _nodes.length; i++) {
      if (_nodes[i].parent == -1) visit(i, null);
    }
    final meshInverse = vm.Matrix4.inverted(_global[meshNode]);
    for (var j = 0; j < skinJoints.length; j++) {
      _skinMatrices[j]
        ..setFrom(meshInverse)
        ..multiply(_global[skinJoints[j]])
        ..multiply(inverseBind[j]);
    }
  }

  /// Linear-blend skinning of every vertex into [skinnedPositions] and
  /// [skinnedNormals] (model space of the mesh node).
  void skin() {
    if (skinJoints.isEmpty) {
      skinnedPositions.setAll(0, positions);
      skinnedNormals.setAll(0, normals);
      return;
    }
    final m = _skinMatrices;
    final ms = List<Float64List>.generate(m.length, (i) => m[i].storage);
    for (var v = 0; v < vertexCount; v++) {
      final px = positions[v * 3],
          py = positions[v * 3 + 1],
          pz = positions[v * 3 + 2];
      final nx = normals[v * 3],
          ny = normals[v * 3 + 1],
          nz = normals[v * 3 + 2];
      var ox = 0.0, oy = 0.0, oz = 0.0;
      var qx = 0.0, qy = 0.0, qz = 0.0;
      for (var k = 0; k < 4; k++) {
        final w = weights[v * 4 + k];
        if (w == 0) continue;
        final s = ms[joints[v * 4 + k]];
        // Column-major 4x4.
        ox += w * (s[0] * px + s[4] * py + s[8] * pz + s[12]);
        oy += w * (s[1] * px + s[5] * py + s[9] * pz + s[13]);
        oz += w * (s[2] * px + s[6] * py + s[10] * pz + s[14]);
        qx += w * (s[0] * nx + s[4] * ny + s[8] * nz);
        qy += w * (s[1] * nx + s[5] * ny + s[9] * nz);
        qz += w * (s[2] * nx + s[6] * ny + s[10] * nz);
      }
      skinnedPositions[v * 3] = ox;
      skinnedPositions[v * 3 + 1] = oy;
      skinnedPositions[v * 3 + 2] = oz;
      final len = math.sqrt(qx * qx + qy * qy + qz * qz);
      if (len > 1e-9) {
        skinnedNormals[v * 3] = qx / len;
        skinnedNormals[v * 3 + 1] = qy / len;
        skinnedNormals[v * 3 + 2] = qz / len;
      } else {
        skinnedNormals[v * 3] = 0;
        skinnedNormals[v * 3 + 1] = 1;
        skinnedNormals[v * 3 + 2] = 0;
      }
    }
  }

  /// Bounding box of the rest pose (model space).
  ({vm.Vector3 min, vm.Vector3 max}) get restBounds {
    final min = vm.Vector3.all(double.infinity);
    final max = vm.Vector3.all(-double.infinity);
    for (var v = 0; v < vertexCount; v++) {
      final x = positions[v * 3],
          y = positions[v * 3 + 1],
          z = positions[v * 3 + 2];
      if (x < min.x) min.x = x;
      if (y < min.y) min.y = y;
      if (z < min.z) min.z = z;
      if (x > max.x) max.x = x;
      if (y > max.y) max.y = y;
      if (z > max.z) max.z = z;
    }
    return (min: min, max: max);
  }
}
