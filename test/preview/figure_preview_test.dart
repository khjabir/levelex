import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/figure/figure_model.dart';
import 'package:levelex/features/pt/figure/figure_painter.dart';
import 'package:levelex/features/pt/figure/guide_3d.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';
import 'package:levelex/features/pt/mannequin/rig.dart';

/// Renders the detailed body for every clip (two keyframes × two angles)
/// into contact sheets. `FIGURE_PREVIEW=/path flutter test test/preview`.
void main() {
  final outDir = Platform.environment['FIGURE_PREVIEW'];
  test('renders figure contact sheets', () async {
    final bytes = File('assets/figure/athlete.glb').readAsBytesSync();
    final model = FigureModel.fromGlb(ByteData.sublistView(bytes));
    const cell = 240.0;
    final ids = MannequinClips.ids.toList()..sort();
    const perSheet = 8;
    for (var start = 0; start < ids.length; start += perSheet) {
      final batch = ids.sublist(start, (start + perSheet).clamp(0, ids.length));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final width = cell * 4;
      final height = cell * batch.length + 30 * batch.length;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = const Color(0xFF07090E),
      );
      var y = 0.0;
      for (final id in batch) {
        final clip = MannequinClips.clip(id);
        final frame = MannequinFrame.ofClip(clip);
        final muscles = Guide3D.musclesFor(id);
        final emphasis = Guide3D.emphasisFor(
          muscles.primary,
          muscles.secondary,
        );
        final times = [0.0, clip.frames.length > 1 ? 1.0 : 0.0];
        var x = 0.0;
        for (final t in times) {
          for (final yaw in [-38.0, 90.0]) {
            canvas.save();
            canvas.translate(x, y + 30);
            canvas.clipRect(const Rect.fromLTWH(0, 0, cell, cell));
            FigurePainter(
              model: model,
              animation: model.animations[id],
              time: t,
              yaw: yaw,
              pitch: 14,
              showFloor: true,
              compact: false,
              frame: frame,
              emphasis: emphasis,
              // Mid-breath, as the app shows it.
              lifeTime: 1.7,
            ).paint(canvas, const Size(cell, cell));
            canvas.restore();
            x += cell;
          }
        }
        final tp = TextPainter(
          text: TextSpan(
            text: id,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(8, y + 6));
        y += cell + 30;
      }
      final image = await recorder.endRecording().toImage(
        width.toInt(),
        height.toInt(),
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (outDir != null) {
        File('$outDir/figure_${start ~/ perSheet}.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
      }
    }
  }, skip: outDir == null ? 'Set FIGURE_PREVIEW to render sheets' : false);
}
