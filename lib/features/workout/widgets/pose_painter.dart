import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/pose_result.dart';

/// Draws a simple skeleton over the camera preview from normalised landmarks.
class PosePainter extends CustomPainter {
  PosePainter({
    required this.pose,
    required this.mirror,
    required this.good,
    this.minLikelihood = 0.3,
  });

  final PoseResult? pose;

  /// Flip x to match a mirrored (selfie) preview.
  final bool mirror;

  /// Colours the skeleton green when form is good, amber otherwise.
  final bool good;
  final double minLikelihood;

  static const _bones = <(LandmarkType, LandmarkType)>[
    (LandmarkType.leftShoulder, LandmarkType.rightShoulder),
    (LandmarkType.leftHip, LandmarkType.rightHip),
    (LandmarkType.leftShoulder, LandmarkType.leftElbow),
    (LandmarkType.leftElbow, LandmarkType.leftWrist),
    (LandmarkType.rightShoulder, LandmarkType.rightElbow),
    (LandmarkType.rightElbow, LandmarkType.rightWrist),
    (LandmarkType.leftShoulder, LandmarkType.leftHip),
    (LandmarkType.rightShoulder, LandmarkType.rightHip),
    (LandmarkType.leftHip, LandmarkType.leftKnee),
    (LandmarkType.leftKnee, LandmarkType.leftAnkle),
    (LandmarkType.rightHip, LandmarkType.rightKnee),
    (LandmarkType.rightKnee, LandmarkType.rightAnkle),
  ];

  Offset _toCanvas(PoseLandmark l, Size size) =>
      Offset((mirror ? 1 - l.x : l.x) * size.width, l.y * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final pose = this.pose;
    if (pose == null || !pose.hasPose) return;

    final color = good ? AppColors.primary : AppColors.warning;
    final bonePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final jointFill = Paint()..color = color;
    final jointOutline = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final (a, b) in _bones) {
      final la = pose[a];
      final lb = pose[b];
      if (la == null || lb == null) continue;
      if (la.likelihood < minLikelihood || lb.likelihood < minLikelihood) {
        continue;
      }
      final p1 = _toCanvas(la, size);
      final p2 = _toCanvas(lb, size);
      canvas.drawLine(p1, p2, outline);
      canvas.drawLine(p1, p2, bonePaint);
    }

    for (final landmark in pose.landmarks.values) {
      if (landmark.type == LandmarkType.nose) continue;
      if (landmark.likelihood < minLikelihood) continue;
      final p = _toCanvas(landmark, size);
      canvas.drawCircle(p, 6, jointFill);
      canvas.drawCircle(p, 6, jointOutline);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.mirror != mirror ||
      oldDelegate.good != good;
}
