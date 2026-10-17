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
    final thick = s * 0.14;
    final path = Path();
    for (final (cx, cy) in [(0.50, 0.36), (0.50, 0.64)]) {
      const w = 0.56;
      const h = 0.26;
      path.moveTo((cx - w / 2) * s, (cy + h / 2) * s);
      path.lineTo(cx * s, (cy - h / 2) * s);
      path.lineTo((cx + w / 2) * s, (cy + h / 2) * s);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thick
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = AppColors.brandGradient.createShader(Offset.zero & size);
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.primary.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(2, s * 0.08),
          ),
      );
    }
    canvas.drawPath(path, stroke);
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
