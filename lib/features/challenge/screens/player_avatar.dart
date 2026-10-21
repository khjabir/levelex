import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/challenge.dart';

/// Round avatar: the player's photo, or their initial on a gradient.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.player,
    this.size = 48,
    this.crowned = false,
  });

  final ChallengePlayer player;
  final double size;
  final bool crowned;

  @override
  Widget build(BuildContext context) {
    final photo = player.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();
    final initial = player.name.isEmpty ? '?' : player.name[0].toUpperCase();
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : AppColors.brandGradient,
        border: Border.all(
          color: crowned
              ? AppColors.warning
              : Colors.white.withValues(alpha: 0.12),
          width: crowned ? 2.5 : 1,
        ),
        image: hasPhoto
            ? DecorationImage(image: FileImage(File(photo)), fit: BoxFit.cover)
            : null,
      ),
      child: hasPhoto
          ? null
          : Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w900,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
    );
    if (!crowned) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          top: -size * 0.28,
          left: 0,
          right: 0,
          child: Icon(
            Icons.workspace_premium_rounded,
            size: size * 0.5,
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }
}
