import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/figure/figure_model.dart';
import 'package:levelex/features/pt/figure/figure_painter.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';
import 'package:levelex/features/pt/mannequin/rig.dart';
import 'package:levelex/features/workout/exercise_icons.dart';
import 'package:levelex/models/exercise.dart';

/// Renders camera-like frame sequences of the 3D athlete doing every
/// camera-tracked exercise, from the places people put their phone, so the
/// real pose detector can be run on them (see `tool/pose_probe/`).
///
/// `POSE_FRAMES=<dir> flutter test test/preview/pose_frames_test.dart`
/// writes `<dir>/<exercise>__<view>/f_0000.png …` plus a `meta.json` per
/// sequence (frame interval, rep count, gravity in image coordinates).
void main() {
  final outDir = Platform.environment['POSE_FRAMES'];
  final only = Platform.environment['POSE_FRAMES_ONLY']?.split(',');

  test(
    'render pose frames',
    () async {
      final bytes = File('assets/figure/athlete.glb').readAsBytesSync();
      final model = FigureModel.fromGlb(ByteData.sublistView(bytes));
      const frameMs = 83; // ~12 fps, what the app analyses on a phone
      const reps = 4;
      for (final type in ExerciseType.values) {
        if (only != null && !only.contains(type.name)) continue;
        final clipId = type.clipId;
        final clip = MannequinClips.clip(clipId);
        final fit = MannequinFrame.ofClip(clip);
        final animation = model.animations[clipId];
        final timed = type.isTimed;
        final activeMs = timed ? 7000 : clip.totalMs * reps;
        const leadMs = 1200, tailMs = 900;
        final total = leadMs + activeMs + tailMs;
        for (final view in _views) {
          final dir = Directory('$outDir/${type.name}__${view.name}')
            ..createSync(recursive: true);
          var i = 0;
          for (var t = 0; t < total; t += frameMs) {
            final active = t - leadMs;
            final ms = active < 0 || active >= activeMs
                ? 0
                : (timed ? active : active % clip.totalMs);
            final image = await _render(
              model: model,
              animation: animation,
              time: timed && clip.frames.length > 1
                  ? clip.framePosition(ms)
                  : (timed ? 0.0 : clip.framePosition(ms)),
              fit: fit,
              view: view,
            );
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('${dir.path}/f_${i.toString().padLeft(4, '0')}.png')
                .writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
            i++;
          }
          final p = view.pitch * math.pi / 180;
          // Gravity (down) in image coordinates: x right, y down, z away.
          final g = view.rotated
              ? [-math.cos(p), 0.0, math.sin(p)]
              : [0.0, math.cos(p), math.sin(p)];
          File('${dir.path}/meta.json').writeAsStringSync(
            jsonEncode({
              'exercise': type.name,
              'clip': clipId,
              'view': view.name,
              'frames': i,
              'frameMs': frameMs,
              'leadMs': leadMs,
              'activeMs': activeMs,
              'reps': timed ? 0 : reps,
              'holdSeconds': timed ? activeMs ~/ 1000 : 0,
              'width': view.outWidth,
              'height': view.outHeight,
              'gravity': g,
            }),
          );
          // ignore: avoid_print
          print('[frames] ${type.name}__${view.name}: $i');
        }
      }
    },
    skip: outDir == null ? 'Set POSE_FRAMES to render' : false,
    timeout: const Timeout(Duration(hours: 1)),
  );
}

class _View {
  const _View(
    this.name, {
    required this.yaw,
    required this.pitch,
    required this.width,
    required this.height,
    this.rotated = false,
    this.zoom = 1.0,
  });

  final String name;
  final double yaw;
  final double pitch;
  final double width;
  final double height;

  /// The phone lies on its side while the app stays in portrait: the scene
  /// reaches the detector turned a quarter turn.
  final bool rotated;

  /// Below 1 the person is smaller in the frame (phone further away).
  final double zoom;

  double get outWidth => rotated ? height : width;
  double get outHeight => rotated ? width : height;
}

const _views = [
  _View('side_land', yaw: 90, pitch: 3, width: 720, height: 480),
  _View(
    'side_land_rot',
    yaw: 90,
    pitch: 3,
    width: 720,
    height: 480,
    rotated: true,
  ),
  _View('side_port', yaw: 90, pitch: 6, width: 480, height: 720),
  _View('front_port', yaw: 0, pitch: 8, width: 480, height: 720),
  _View('diag_port', yaw: 45, pitch: 10, width: 480, height: 720),
  _View('far_port', yaw: 25, pitch: 10, width: 480, height: 720, zoom: 0.6),
];

Future<ui.Image> _render({
  required FigureModel model,
  required FigureAnimation? animation,
  required double time,
  required MannequinFrame fit,
  required _View view,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (view.rotated) {
    canvas.translate(view.height, 0);
    canvas.rotate(math.pi / 2);
  }
  final w = view.width, h = view.height;
  // A plain room: a light wall fading into a darker floor.
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, h),
        const [Color(0xFFD9D4CC), Color(0xFFC9C1B5), Color(0xFF8D8478)],
        const [0.0, 0.62, 1.0],
      ),
  );
  canvas.save();
  canvas.translate(w * (1 - view.zoom) / 2, h * (1 - view.zoom) / 2);
  canvas.scale(view.zoom);
  FigurePainter(
    model: model,
    animation: animation,
    time: time,
    yaw: view.yaw,
    pitch: view.pitch,
    showFloor: true,
    compact: false,
    frame: fit,
    emphasis: const {},
  ).paint(canvas, Size(w, h));
  canvas.restore();
  return recorder.endRecording().toImage(
    view.outWidth.toInt(),
    view.outHeight.toInt(),
  );
}
