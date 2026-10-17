import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/brand_mark.dart';
import '../models/equipment.dart';
import '../models/muscle_group.dart';

/// The trainer's avatar: brand mark in a glowing ring.
class TrainerAvatar extends StatelessWidget {
  const TrainerAvatar({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.brandGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size - 6,
          height: size - 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.background,
          ),
          child: Center(child: BrandMark(size: size * 0.55, glow: false)),
        ),
      ),
    );
  }
}

/// A speech bubble from the trainer.
class TrainerBubble extends StatelessWidget {
  const TrainerBubble({
    super.key,
    required this.text,
    this.compact = false,
    this.onCamera = false,
  });

  final String text;
  final bool compact;

  /// Dark translucent styling for overlaying the camera.
  final bool onCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: 'Trainer: $text',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrainerAvatar(size: compact ? 32 : 40),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 16,
                vertical: compact ? 10 : 14,
              ),
              decoration: BoxDecoration(
                color: onCamera
                    ? Colors.black.withValues(alpha: 0.65)
                    : AppColors.surface,
                gradient: onCamera ? null : AppColors.cardGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: AnimatedSwitcher(
                duration: AppTokens.normal,
                child: Text(
                  text,
                  key: ValueKey(text),
                  style:
                      (compact
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.bodyLarge)
                          ?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.35,
                          ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small chip naming a muscle group.
class MuscleChip extends StatelessWidget {
  const MuscleChip(this.muscle, {super.key, this.selected = false, this.onTap});

  final MuscleGroup muscle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = AnimatedContainer(
      duration: AppTokens.fast,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.cardElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? AppColors.primary : Colors.transparent,
        ),
      ),
      child: Text(
        muscle.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: selected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: selected,
      label: muscle.label,
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}

/// Equipment chip with the user's photo thumbnail when they attached one.
class EquipmentChip extends StatelessWidget {
  const EquipmentChip({
    super.key,
    required this.type,
    this.item,
    this.large = false,
  });

  final Equipment type;
  final EquipmentItem? item;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = item?.photoPath;
    final size = large ? 40.0 : 22.0;
    return Container(
      padding: EdgeInsets.fromLTRB(large ? 6 : 6, 4, large ? 14 : 10, 4),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: photo != null && File(photo).existsSync()
                ? Image.file(
                    File(photo),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: size,
                    height: size,
                    color: AppColors.secondary.withValues(alpha: 0.25),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      size: size * 0.55,
                      color: AppColors.secondary,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            type.label,
            style:
                (large
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
          ),
        ],
      ),
    );
  }
}

/// Icon for a piece of equipment.
IconData equipmentIcon(Equipment type) => switch (type) {
  Equipment.dumbbells => Icons.fitness_center_rounded,
  Equipment.barbell => Icons.straighten_rounded,
  Equipment.kettlebell => Icons.sports_handball_rounded,
  Equipment.bench => Icons.weekend_rounded,
  Equipment.pullUpBar => Icons.horizontal_rule_rounded,
  Equipment.resistanceBands => Icons.all_inclusive_rounded,
  Equipment.cableMachine => Icons.cable_rounded,
  Equipment.box => Icons.square_rounded,
  Equipment.mat => Icons.crop_landscape_rounded,
  Equipment.jumpRope => Icons.gesture_rounded,
  Equipment.medicineBall => Icons.sports_basketball_rounded,
  Equipment.treadmill => Icons.directions_run_rounded,
  Equipment.bike => Icons.directions_bike_rounded,
  Equipment.rower => Icons.rowing_rounded,
};

/// mm:ss for timers.
String formatClock(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
