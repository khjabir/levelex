import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/figure/figure_model.dart';
import 'package:levelex/features/pt/figure/figure_painter.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';
import 'package:levelex/features/pt/mannequin/rig.dart';

/// Prints the CPU cost of one frame of the detailed body (skinning,
/// lighting, sorting, canvas commands). `FIGURE_BENCH=1 flutter test
/// test/preview/figure_benchmark_test.dart`.
void main() {
  test(
    'figure frame cost',
    () {
      final bytes = File('assets/figure/athlete.glb').readAsBytesSync();
      final model = FigureModel.fromGlb(ByteData.sublistView(bytes));
      final clip = MannequinClips.clip('squat');
      final frame = MannequinFrame.ofClip(clip);
      for (final (label, size, compact) in [
        ('full 360x360', const Size(360, 360), false),
        ('pip 120x150', const Size(120, 150), true),
      ]) {
        // Warm up.
        for (var i = 0; i < 10; i++) {
          final r = ui.PictureRecorder();
          FigurePainter(
            model: model,
            animation: model.animations['squat'],
            time: i / 10,
            yaw: -38,
            pitch: 14,
            showFloor: true,
            compact: compact,
            frame: frame,
          ).paint(Canvas(r), size);
          r.endRecording().dispose();
        }
        final sw = Stopwatch()..start();
        const n = 60;
        for (var i = 0; i < n; i++) {
          final r = ui.PictureRecorder();
          FigurePainter(
            model: model,
            animation: model.animations['squat'],
            time: (i % 20) / 10,
            yaw: -38.0 + i,
            pitch: 14,
            showFloor: true,
            compact: compact,
            frame: frame,
          ).paint(Canvas(r), size);
          r.endRecording().dispose();
        }
        sw.stop();
        // ignore: avoid_print
        print(
          '[figure bench] $label: ${(sw.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms/frame '
          '(${model.vertexCount} verts, ${model.triangleCount} tris)',
        );
      }
    },
    skip: Platform.environment['FIGURE_BENCH'] == null
        ? 'Set FIGURE_BENCH'
        : false,
  );
}
