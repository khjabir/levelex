import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Rounded, animated progress bar. Uses the brand gradient unless [color]
/// is given.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.height = 10,
    this.color,
    this.backgroundColor = AppColors.divider,
    this.semanticLabel,
  });

  /// Progress in `[0, 1]`. Values outside the range are clamped.
  final double value;
  final double height;
  final Color? color;
  final Color backgroundColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(clamped * 100).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              ColoredBox(
                color: backgroundColor,
                child: const SizedBox.expand(),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: clamped),
                duration: const Duration(milliseconds: 700),
                curve: AppTokens.curve,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      gradient: color == null ? AppColors.brandGradient : null,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
