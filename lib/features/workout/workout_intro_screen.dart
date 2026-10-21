import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/constants/app_constants.dart';
import '../../models/coaching.dart';
import '../../models/exercise.dart';
import '../../models/form_status.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../face/face_providers.dart';
import '../pt/mannequin/mannequin_3d.dart';
import 'exercise_icons.dart';

/// Training guide for the selected exercise: animated demo, how-to cues,
/// common mistakes with their fixes, camera placement, then the start button.
class WorkoutIntroScreen extends ConsumerWidget {
  const WorkoutIntroScreen({super.key});

  /// Generic camera setup steps shared by every exercise.
  static const steps = [
    (
      Icons.phone_android,
      'Prop the phone so your whole body is visible. Portrait or landscape '
          'both work, and you can switch cameras from the workout screen.',
    ),
    (
      Icons.face_retouching_natural,
      'Look at the camera first so we can confirm it is you.',
    ),
    (
      Icons.timer_outlined,
      'Get into the start position; counting begins after a 3-second '
          'countdown.',
    ),
  ];

  /// The mistakes worth showing before each exercise.
  static List<FormStatus> mistakesFor(ExerciseType type) => switch (type) {
    ExerciseType.pushUp => [FormStatus.hipsTooLow, FormStatus.goDeeper],
    ExerciseType.squat => [FormStatus.torsoLeaning, FormStatus.goDeeper],
    ExerciseType.lunge => [FormStatus.torsoLeaning, FormStatus.goDeeper],
    ExerciseType.jumpingJack => [
      FormStatus.armsNotOverhead,
      FormStatus.goDeeper,
    ],
    ExerciseType.burpee => [FormStatus.goDeeper, FormStatus.slowDown],
    ExerciseType.plank => [FormStatus.hipsTooLow, FormStatus.hipsTooHigh],
    ExerciseType.sitUp => [FormStatus.goDeeper, FormStatus.slowDown],
    ExerciseType.gluteBridge => [FormStatus.goDeeper, FormStatus.slowDown],
    ExerciseType.wallSit => [FormStatus.goDeeper],
    ExerciseType.highKnees => [FormStatus.goDeeper, FormStatus.slowDown],
    ExerciseType.mountainClimber => [
      FormStatus.hipsTooHigh,
      FormStatus.goDeeper,
    ],
    ExerciseType.tricepDip => [FormStatus.goDeeper, FormStatus.slowDown],
    ExerciseType.squatJump => [FormStatus.goDeeper, FormStatus.torsoLeaning],
  };

  /// Mannequin parts to flag for a mistake.
  static Set<String> highlightFor(FormStatus status) => switch (status) {
    FormStatus.hipsTooHigh || FormStatus.hipsTooLow => {'hips', 'torso'},
    FormStatus.torsoLeaning => {'torso'},
    FormStatus.armsNotOverhead => {'arms'},
    FormStatus.goDeeper => {'legs', 'arms'},
    _ => <String>{},
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final exercise = settings.selectedExercise;
    final target = settings.targetFor(exercise);
    final faceRegistered = ref.watch(faceRegisteredProvider);
    final mistakes = mistakesFor(exercise);

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.label),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children:
                    [
                          AppCard(
                            glow: true,
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 230,
                                  child: Mannequin3D(
                                    key: ValueKey(exercise.clipId),
                                    clipId: exercise.clipId,
                                  ),
                                ),
                                Text(
                                  'Drag to rotate the guide',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  exercise.tagline,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.flag_rounded,
                                        size: 16,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Target: ${exercise.describeTarget(target)}',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          const SectionHeader('How to do it'),
                          AppCard(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                            child: Column(
                              children: [
                                for (var i = 0; i < exercise.cues.length; i++)
                                  _NumberedStep(
                                    index: i + 1,
                                    text: exercise.cues[i],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          const SectionHeader(
                            'Common mistakes the coach fixes',
                          ),
                          SizedBox(
                            height: 236,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              itemCount: mistakes.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) => _MistakeCard(
                                exercise: exercise,
                                status: mistakes[i],
                                showDemo: i == 0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const SectionHeader('Camera setup'),
                          AppCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _Step(
                                  icon: Icons.videocam_outlined,
                                  text: exercise.placement,
                                ),
                                for (final (icon, text) in steps)
                                  _Step(icon: icon, text: text),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${AppStrings.privacyStatement} Camera '
                                  'permission is requested only when you open '
                                  'the camera.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ]
                        .animate(interval: 50.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05, end: 0, curve: AppTokens.curve),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: faceRegistered
                  ? PrimaryButton(
                      label: exercise.isTimed
                          ? 'START ${exercise.label.toUpperCase()}'
                          : 'START SET',
                      icon: Icons.videocam_rounded,
                      onPressed: () => context.push(Routes.workoutCamera),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'One-time setup: register your face so only you '
                          'can score workouts.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: 'REGISTER FACE',
                          icon: Icons.face_retouching_natural,
                          onPressed: () =>
                              context.push(Routes.faceRegistration),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                '$index',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: theme.textTheme.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}

class _MistakeCard extends StatelessWidget {
  const _MistakeCard({
    required this.exercise,
    required this.status,
    required this.showDemo,
  });

  final ExerciseType exercise;
  final FormStatus status;
  final bool showDemo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cue = CoachingLibrary.cue(status, exercise);
    if (cue == null) return const SizedBox.shrink();
    return SizedBox(
      width: 230,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        borderColor: AppColors.warning.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 96,
              child: Mannequin3D(
                clipId: exercise.clipId,
                interactive: false,
                autoRotate: showDemo,
                compact: true,
                showFloor: false,
                highlight: WorkoutIntroScreen.highlightFor(status),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    cue.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    cue.instruction,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
