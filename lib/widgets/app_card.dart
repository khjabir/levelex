import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Surface card with a faint sheen and hairline border. [glow] adds a brand
/// tint for hero content.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.borderColor,
    this.onTap,
    this.glow = false,
    this.radius = AppTokens.radiusLarge,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool glow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    final decoration = BoxDecoration(
      color: color ?? AppColors.surface,
      gradient: color == null ? AppColors.cardGradient : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color:
            borderColor ??
            (glow
                ? AppColors.primary.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.06)),
      ),
      boxShadow: glow
          ? [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: body);
    }
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: body,
        ),
      ),
    );
  }
}
