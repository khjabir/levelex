import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme.dart';
import '../../../models/coaching.dart';
import '../../../models/form_status.dart';

/// Live coaching banner on the workout screen: a correction with a concrete
/// instruction, or a quiet "good form" pill when everything is fine.
class CoachCard extends StatelessWidget {
  const CoachCard({
    super.key,
    required this.cue,
    required this.status,
    required this.positionHint,
    this.goodLabel = 'Good form',
  });

  /// Active correction (null when nothing needs fixing).
  final CoachingCue? cue;

  /// Current posture/visibility status, used when there is no cue.
  final FormStatus status;
  final String positionHint;

  /// Text of the quiet pill when nothing needs fixing.
  final String goodLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = cue;
    if (c != null) {
      final color = c.severity == CueSeverity.warning
          ? AppColors.warning
          : AppColors.cyan;
      return Semantics(
        liveRegion: true,
        label: '${c.title}. ${c.instruction}',
        excludeSemantics: true,
        child:
            Container(
                  key: ValueKey(c.status),
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
                    border: Border.all(color: color.withValues(alpha: 0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_iconFor(c.status), color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.title.toUpperCase(),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: color,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.instruction,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
                .animate(key: ValueKey(c.status))
                .fadeIn(duration: 220.ms)
                .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic)
                .then()
                .shimmer(
                  duration: 900.ms,
                  color: color.withValues(alpha: 0.25),
                ),
      );
    }

    final (icon, color, text) = status.isGood
        ? (Icons.check_circle_rounded, AppColors.primary, goodLabel)
        : status.isTracking
        ? (Icons.info_outline_rounded, AppColors.warning, status.message)
        : status == FormStatus.notInPosition
        ? (Icons.accessibility_new_rounded, AppColors.cyan, positionHint)
        : (Icons.visibility_off_outlined, AppColors.danger, status.message);
    return Semantics(
      liveRegion: true,
      label: 'Form: $text',
      excludeSemantics: true,
      child: Align(
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: AppTokens.normal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(FormStatus status) => switch (status) {
    FormStatus.goDeeper => Icons.south_rounded,
    FormStatus.slowDown => Icons.speed_rounded,
    FormStatus.hipsTooHigh => Icons.arrow_downward_rounded,
    FormStatus.hipsTooLow => Icons.arrow_upward_rounded,
    FormStatus.torsoLeaning => Icons.straighten_rounded,
    FormStatus.armsNotOverhead => Icons.north_rounded,
    _ => Icons.sports_rounded,
  };
}
