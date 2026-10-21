import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/figure/figure_model.dart';
import 'package:levelex/features/pt/figure/figure_painter.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';
import 'package:levelex/features/pt/mannequin/rig.dart';

/// Renders the head and shoulders large from three angles, for checking
/// hair, eyes and the top. `FIGURE_HEAD=/path flutter test test/preview`.
void main() {
  final outDir = Platform.environment['FIGURE_HEAD'];
  test('head close-ups', () async {
    final bytes = File('assets/figure/athlete.glb').readAsBytesSync();
    final model = FigureModel.fromGlb(ByteData.sublistView(bytes));
    const big = 2400.0;
    const crop = 640.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, crop * 3, crop),
      Paint()..color = const Color(0xFF151A24),
    );
    final clip = MannequinClips.clip('stand');
    final frame = MannequinFrame.ofClip(clip);
    var x = 0.0;
    for (final yaw in [0.0, -38.0, 90.0]) {
      canvas.save();
      canvas.translate(x, 0);
      canvas.clipRect(const Rect.fromLTWH(0, 0, crop, crop));
      // Head sits in the top ~22% of the big frame, centred.
      canvas.translate(-(big - crop) / 2, -big * 0.04);
      FigurePainter(
        model: model,
        animation: model.animations['stand'],
        time: 0,
        yaw: yaw,
        pitch: 4,
        showFloor: false,
        compact: false,
        frame: frame,
        emphasis: const {},
        lifeTime: 1.7,
      ).paint(canvas, const Size(big, big));
      canvas.restore();
      x += crop;
    }
    final image = await recorder.endRecording().toImage(
      (crop * 3).toInt(),
      crop.toInt(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/head.png').writeAsBytesSync(png!.buffer.asUint8List());
  }, skip: outDir == null ? 'Set FIGURE_HEAD to render' : false);
}
