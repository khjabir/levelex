import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'progress_ring.dart';

/// An achievement badge for a grid: a tier-coloured ring around a gradient
/// disc when earned, or a grey progress ring with a faded icon when locked.
class BadgeTile extends StatelessWidget {
  const BadgeTile({
    super.key,
    required this.title,
    required this.icon,
    this.tier = 'bronze',
    this.earned = false,
    this.progress = 0,
    this.subtitle,
    this.onTap,
    this.large = false,
  });

  final String title;

  /// One of the keys in [icons]; unknown keys fall back to a trophy.
  final String icon;

  /// 'bronze', 'silver' or 'gold'.
  final String tier;
  final bool earned;

  /// Progress toward earning the badge, 0..1 (only shown while locked).
  final double progress;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool large;

  static const bronze = Color(0xFFCD7F32);
  static const silver = Color(0xFFB8C2CC);
  static const gold = Color(0xFFFFC53D);

  static const icons = <String, IconData>{
    'flame': Icons.local_fire_department_rounded,
    'bolt': Icons.bolt_rounded,
    'trophy': Icons.emoji_events_rounded,
    'medal': Icons.military_tech_rounded,
    'sunrise': Icons.wb_twilight_rounded,
    'moon': Icons.nightlight_round,
    'star': Icons.star_rounded,
    'heart': Icons.favorite_rounded,
    'timer': Icons.timer_rounded,
    'dumbbell': Icons.fitness_center_rounded,
    'target': Icons.track_changes_rounded,
    'camera': Icons.photo_camera_rounded,
    'calendar': Icons.calendar_month_rounded,
    'crown': Icons.workspace_premium_rounded,
    'scale': Icons.monitor_weight_rounded,
    'group': Icons.groups_rounded,
    'sparkle': Icons.auto_awesome_rounded,
  };

  static IconData iconFor(String key) =>
      icons[key] ?? Icons.emoji_events_rounded;

  static Color tierColor(String tier) => switch (tier) {
    'gold' => gold,
    'silver' => silver,
    _ => bronze,
  };

  @override
  Widget build(BuildContext context) {
    final size = large ? 96.0 : 64.0;
    final clamped = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final iconData = iconFor(icon);

    final badge = earned
        ? _EarnedBadge(icon: iconData, size: size, ring: tierColor(tier))
        : _LockedBadge(icon: iconData, size: size, progress: clamped);
    // Without a title or subtitle the tile is just the badge: the empty
    // title line and its gap made icon-only uses overflow their box.
    final iconOnly = title.isEmpty && subtitle == null;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        if (!iconOnly) SizedBox(height: large ? 12 : 8),
        if (!iconOnly)
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: large ? 14 : 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: earned ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: large ? 12 : 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );

    Widget body = Padding(
      padding: iconOnly
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              horizontal: large ? 12 : 6,
              vertical: large ? 12 : 8,
            ),
      child: column,
    );
    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
          onTap: onTap,
          child: body,
        ),
      );
    }

    final label = earned
        ? '$title, $tier badge earned'
        : '$title, locked, ${(clamped * 100).round()} percent';
    return Semantics(
      label: label,
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      child: body,
    );
  }
}

class _EarnedBadge extends StatelessWidget {
  const _EarnedBadge({
    required this.icon,
    required this.size,
    required this.ring,
  });

  final IconData icon;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final ringWidth = size >= 90 ? 4.0 : 3.0;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size >= 90 ? 5 : 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.cardElevated,
        border: Border.all(color: ring, width: ringWidth),
        boxShadow: [
          BoxShadow(
            color: ring.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.brandGradient,
        ),
        child: Center(
          child: Icon(icon, size: size * 0.42, color: AppColors.onPrimary),
        ),
      ),
    );
  }
}

class _LockedBadge extends StatelessWidget {
  const _LockedBadge({
    required this.icon,
    required this.size,
    required this.progress,
  });

  final IconData icon;
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final thickness = size >= 90 ? 5.0 : 4.0;
    final inner = size - thickness * 2 - 8;
    return ProgressRing(
      value: progress,
      size: size,
      thickness: thickness,
      trackColor: AppColors.outline,
      child: Container(
        width: inner,
        height: inner,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardElevated,
        ),
        child: Center(
          child: Opacity(
            opacity: 0.45,
            child: Icon(
              icon,
              size: size * 0.38,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
