import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Confetti burst drawn on a canvas: no assets, no extra packages.
class Celebration extends StatefulWidget {
  const Celebration({
    super.key,
    this.duration = const Duration(milliseconds: 2600),
    this.particles = 90,
  });

  final Duration duration;
  final int particles;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final r = math.Random(7);
    const colors = [
      AppColors.primary,
      AppColors.lime,
      AppColors.cyan,
      AppColors.secondary,
      AppColors.warning,
      Colors.white,
    ];
    _particles = [
      for (var i = 0; i < widget.particles; i++)
        _Particle(
          x: 0.2 + r.nextDouble() * 0.6,
          vx: (r.nextDouble() - 0.5) * 1.6,
          vy: -(0.9 + r.nextDouble() * 1.4),
          size: 5 + r.nextDouble() * 7,
          spin: (r.nextDouble() - 0.5) * 12,
          color: colors[r.nextInt(colors.length)],
          delay: r.nextDouble() * 0.15,
          round: r.nextBool(),
        ),
    ];
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(_particles, _controller.value),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.x,
    required this.vx,
    required this.vy,
    required this.size,
    required this.spin,
    required this.color,
    required this.delay,
    required this.round,
  });

  final double x, vx, vy, size, spin, delay;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final u = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (u <= 0) continue;
      final x = (p.x + p.vx * u * 0.6) * size.width;
      final y = (0.55 + p.vy * u + 1.6 * u * u) * size.height;
      final alpha = (1 - u).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * u);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.6,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
