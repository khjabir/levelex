import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The Levelex mark: three rising chevrons in the brand gradient. Drawn, not
/// an image, so it scales anywhere.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(glow: glow)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.glow});

  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final dx = (size.width - s) / 2;
    final dy = (size.height - s) / 2;
    Offset p(double x, double y) => Offset(dx + x * s, dy + (1 - y) * s);
    // Same geometry as the app icon: head, torso, V arms, driving legs.
    final body = Path()
      ..moveTo(p(0.5, 0.66).dx, p(0.5, 0.66).dy)
      ..lineTo(p(0.5, 0.37).dx, p(0.5, 0.37).dy)
      ..moveTo(p(0.22, 0.93).dx, p(0.22, 0.93).dy)
      ..lineTo(p(0.5, 0.60).dx, p(0.5, 0.60).dy)
      ..lineTo(p(0.78, 0.93).dx, p(0.78, 0.93).dy)
      ..moveTo(p(0.27, 0.07).dx, p(0.27, 0.07).dy)
      ..lineTo(p(0.5, 0.37).dx, p(0.5, 0.37).dy)
      ..lineTo(p(0.73, 0.07).dx, p(0.73, 0.07).dy);
    final head = Rect.fromCircle(center: p(0.5, 0.83), radius: 0.10 * s);
    final shader = AppColors.brandGradient.createShader(Offset.zero & size);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.135
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = shader;
    final fill = Paint()..shader = shader;
    if (glow) {
      final glowStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.135
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(2, s * 0.08));
      canvas.drawPath(body, glowStroke);
      canvas.drawOval(
        head,
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(2, s * 0.08),
          ),
      );
    }
    canvas.drawPath(body, stroke);
    canvas.drawOval(head, fill);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.glow != glow;
}

/// Wordmark: mark + "LEVELEX".
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size * 1.35, glow: false),
        SizedBox(width: size * 0.4),
        Text(
          'LEVELEX',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: size * 0.18,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
