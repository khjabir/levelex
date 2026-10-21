import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';
import 'package:levelex/core/utils/geometry.dart';
import 'package:levelex/features/pt/mannequin/rig.dart';

/// Dumps every clip's keyframes as joint positions so the Blender figure
/// script (tool/figure/build_figure.py) can animate the real body from the
/// same verified poses. Run with
/// `FIGURE_POSES=tool/figure/poses.json flutter test test/preview`.
void main() {
  final out = Platform.environment['FIGURE_POSES'];
  test('exports rig poses for the Blender figure', () {
    final clips = <String, dynamic>{};
    for (final id in MannequinClips.ids) {
      final clip = MannequinClips.clip(id);
      clips[id] = {
        'durations': clip.durations,
        'pingPong': clip.pingPong,
        'highlight': clip.highlight.toList(),
        'frames': [
          for (final pose in clip.frames)
            {
              for (final e in Rig.solve(pose).entries)
                e.key: [e.value.x, e.value.y, e.value.z],
              ..._pelvisAxes(pose),
            },
        ],
      };
    }
    final rest = {
      for (final e in Rig.solve(const RigPose.sym()).entries)
        e.key: [e.value.x, e.value.y, e.value.z],
      ..._pelvisAxes(const RigPose.sym()),
    };
    final doc = {
      'headRadius': Rig.headRadius,
      'rest': rest,
      'bones': [
        for (final b in Rig.bones) [b.a, b.b, b.thickness, b.part],
      ],
      'clips': clips,
    };
    if (out != null) {
      File(out)
          .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(doc));
    }
    expect(clips, isNotEmpty);
  }, skip: out == null ? 'Set FIGURE_POSES to export' : false);
}

/// The pelvis's own up and forward axes (world), so the body can bend its
/// spine between the hips and the chest instead of hinging at one joint.
Map<String, List<double>> _pelvisAxes(RigPose p) {
  final r0 =
      Mat3.rotY(p.bodyYaw) * Mat3.rotX(p.bodyPitch) * Mat3.rotZ(p.bodyRoll);
  final up = r0.apply(const Vec3(0, 1, 0));
  final fwd = r0.apply(const Vec3(0, 0, 1));
  return {
    'pelvisUp': [up.x, up.y, up.z],
    'pelvisFwd': [fwd.x, fwd.y, fwd.z],
  };
}
