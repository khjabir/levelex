import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';
import 'package:levelex/features/pt/mannequin/mannequin_painter.dart';
import 'package:levelex/features/pt/mannequin/rig.dart';

/// Renders every mannequin clip (two keyframes × two camera angles) into a
/// contact sheet so poses can be eyeballed without a device. Run with
/// `MANNEQUIN_PREVIEW=/path/to/dir flutter test test/preview`.
void main() {
  final outDir = Platform.environment['MANNEQUIN_PREVIEW'];
  test('renders mannequin contact sheets', () async {
    const cell = 220.0;
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
        final frames = [
          clip.frames.first,
          clip.frames.length > 1 ? clip.frames[1] : clip.frames.first,
        ];
        var x = 0.0;
        for (final frame in frames) {
          for (final yaw in [-38.0, 90.0]) {
            canvas.save();
            canvas.translate(x, y + 30);
            MannequinPainter(
              pose: frame,
              yaw: yaw,
              pitch: 14,
              highlight: const {},
              showFloor: true,
              compact: false,
              frame: MannequinFrame.ofClip(clip),
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
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (outDir != null) {
        final file = File('$outDir/mannequin_${start ~/ perSheet}.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      }
    }
  }, skip: outDir == null ? 'Set MANNEQUIN_PREVIEW to render sheets' : false);
}
