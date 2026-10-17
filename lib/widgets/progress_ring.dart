import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Circular progress with the brand gradient and a glowing head.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 180,
    this.thickness = 14,
    this.child,
    this.trackColor = AppColors.divider,
    this.gradient = AppColors.brandGradient,
    this.semanticLabel,
    this.animate = true,
  });

  final double value;
  final double size;
  final double thickness;
  final Widget? child;
  final Color trackColor;
  final Gradient gradient;
  final String? semanticLabel;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(clamped * 100).round()} percent',
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: clamped),
          duration: animate ? const Duration(milliseconds: 900) : Duration.zero,
          curve: AppTokens.curve,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(
              value: v,
              thickness: thickness,
              trackColor: trackColor,
              gradient: gradient,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.thickness,
    required this.trackColor,
    required this.gradient,
  });

  final double value;
  final double thickness;
  final Color trackColor;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(thickness / 2);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inset, 0, math.pi * 2, false, track);
    if (value <= 0) return;

    const start = -math.pi / 2;
    final sweep = math.pi * 2 * value;
    final glow = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: gradient.colors,
        stops: gradient.stops,
        transform: const GradientRotation(start),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawArc(inset, start, sweep, false, glow..color = Colors.white24);

    final arc = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: gradient.colors,
        stops: gradient.stops,
        transform: const GradientRotation(start),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inset, start, sweep, false, arc);

    // Bright head dot.
    final angle = start + sweep;
    final r = inset.width / 2;
    final head = Offset(
      inset.center.dx + r * math.cos(angle),
      inset.center.dy + r * math.sin(angle),
    );
    canvas.drawCircle(
      head,
      thickness * 0.32,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value ||
      old.thickness != thickness ||
      old.trackColor != trackColor;
}
