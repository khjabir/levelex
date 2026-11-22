import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/levels/level_system.dart';
import '../../models/coaching.dart';
import '../../widgets/animated_progress_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/celebration.dart';
import '../../widgets/level_badge.dart';
import '../../widgets/primary_button.dart';
import '../../core/engagement/daily_challenge.dart';
import '../../core/engagement/personal_best.dart';
import '../../widgets/badge_tile.dart';
import '../../widgets/section_header.dart';
import '../../widgets/share_card.dart';
import '../../widgets/share_sheet.dart';
import '../engagement/engagement_providers.dart';
import 'workout_controller.dart';
import 'workout_launch.dart';

/// After a set: celebration, count, XP and level progress, coach's notes.
class WorkoutCompleteScreen extends ConsumerWidget {
  const WorkoutCompleteScreen({super.key, required this.outcome});

  final WorkoutOutcome? outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = outcome?.session;
    if (session == null) {
      // Reached without a session (e.g. deep link): nothing to show.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.home);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final exercise = session.exercise;
    final todayForExercise = ref.watch(todayTotalForExerciseProvider(exercise));
    final streak = ref.watch(currentStreakProvider);
    final level = ref.watch(levelProvider);
    final xp = LevelSystem.xpForSession(session);
    final before = LevelSystem.levelFor(level.totalXp - xp);
    final leveledUp = level.level > before.level;
    final completed = session.isCompleted;
    final formScore = session.formScore;
    final notes = CoachingLibrary.notes(
      outcome?.mistakes.isNotEmpty == true
          ? outcome!.mistakes
          : session.mistakes,
      exercise,
    );
    final report = outcome?.report ?? '';
    final allSessions = ref.watch(sessionsProvider);
    final newBest =
        session.verified && PersonalBests.isNewBest(session, allSessions);
    final priorBest = allSessions
        .where(
          (s) =>
              s.id != session.id &&
              s.exercise == exercise &&
              s.verified &&
              !s.skipped &&
              s.completedReps > 0,
        )
        .fold<int>(0, (m, s) => s.completedReps > m ? s.completedReps : m);
    final challenge = ref.watch(dailyChallengeProgressProvider);
    final partIndex = challenge.challenge.parts.indexWhere(
      (p) => p.exercise == exercise,
    );
    final newBadges = ref.watch(newBadgesShownProvider(session.id));
    if (newBadges.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(markAchievementsSeenProvider)();
      });
    }
    final today = ref.watch(clockProvider);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    children:
                        [
                              Center(
                                child:
                                    Container(
                                      width: 88,
                                      height: 88,
                                      decoration: BoxDecoration(
                                        gradient: completed
                                            ? AppColors.brandGradient
                                            : null,
                                        color: completed
                                            ? null
                                            : AppColors.cardElevated,
                                        shape: BoxShape.circle,
                                        boxShadow: completed
                                            ? [
                                                BoxShadow(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.45),
                                                  blurRadius: 36,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Icon(
                                        completed
                                            ? Icons.emoji_events_rounded
                                            : Icons.fitness_center_rounded,
                                        size: 44,
                                        color: completed
                                            ? AppColors.onPrimary
                                            : AppColors.textSecondary,
                                      ),
                                    ).animate().scale(
                                      begin: const Offset(0.5, 0.5),
                                      end: const Offset(1, 1),
                                      duration: 600.ms,
                                      curve: Curves.elasticOut,
                                    ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                completed ? 'SET COMPLETE' : 'SET ENDED',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  letterSpacing: 2,
                                  color: completed
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                leveledUp
                                    ? 'Level up! You are now ${level.title}.'
                                    : completed
                                    ? 'Nice work. Keep the streak alive.'
                                    : 'Every rep counts.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: leveledUp
                                      ? AppColors.lime
                                      : AppColors.textSecondary,
                                  fontWeight: leveledUp
                                      ? FontWeight.w700
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Semantics(
                                label:
                                    '${session.completedReps} '
                                    '${exercise.countLabel(session.completedReps)}',
                                excludeSemantics: true,
                                child: Column(
                                  children: [
                                    TweenAnimationBuilder<int>(
                                      tween: IntTween(
                                        begin: 0,
                                        end: session.completedReps,
                                      ),
                                      duration: const Duration(
                                        milliseconds: 900,
                                      ),
                                      curve: AppTokens.curve,
                                      builder: (context, v, _) => Text(
                                        '$v',
                                        style: theme.textTheme.displayLarge
                                            ?.copyWith(fontSize: 96, height: 1),
                                      ),
                                    ),
                                    Text(
                                      exercise.isTimed
                                          ? 'seconds of ${exercise.singular}'
                                          : exercise.countLabel(
                                              session.completedReps,
                                            ),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (!session.verified) ...[
                                AppCard(
                                  borderColor: AppColors.warning.withValues(
                                    alpha: 0.5,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.no_accounts_outlined,
                                        color: AppColors.warning,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Unverified set: saved and counted '
                                          'in today\'s total, but it does not '
                                          'extend your streak or earn XP '
                                          'because the face check was skipped.',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: AppColors.textPrimary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              _XpCard(
                                xp: xp,
                                level: level,
                                leveledUp: leveledUp,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _Stat(
                                      value: '$todayForExercise',
                                      label: exercise.isTimed
                                          ? 'seconds today'
                                          : '${exercise.label.toLowerCase()} today',
                                      icon: Icons.today_rounded,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _Stat(
                                      value: streak == 1
                                          ? '1 day'
                                          : '$streak days',
                                      label: 'streak',
                                      icon: Icons.local_fire_department_rounded,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  if (formScore != null) ...[
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _Stat(
                                        value: '${(formScore * 100).round()}%',
                                        label: 'good form',
                                        icon: Icons.straighten_rounded,
                                        color: formScore >= 0.8
                                            ? AppColors.cyan
                                            : AppColors.warning,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (newBest && priorBest > 0) ...[
                                const SizedBox(height: 12),
                                AppCard(
                                  borderColor: AppColors.lime.withValues(
                                    alpha: 0.6,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.emoji_events_rounded,
                                        color: AppColors.lime,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'New personal best: '
                                          '${exercise.describeTarget(session.completedReps)} '
                                          '(was $priorBest).',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (partIndex >= 0) ...[
                                const SizedBox(height: 12),
                                _ChallengeLine(
                                  progress: challenge,
                                  partIndex: partIndex,
                                ),
                              ],
                              if (newBadges.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                SectionHeader(
                                  newBadges.length == 1
                                      ? 'New badge'
                                      : 'New badges',
                                ),
                                AppCard(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      for (final b in newBadges.take(3))
                                        Expanded(
                                          child: BadgeTile(
                                            title: b.achievement.title,
                                            icon: b.achievement.icon,
                                            tier: b.achievement.tier.name,
                                            earned: true,
                                            progress: 1,
                                            onTap: () => context.push(
                                              Routes.achievements,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              const SectionHeader("Coach's notes"),
                              if (notes.isEmpty)
                                AppCard(
                                  borderColor: AppColors.primary.withValues(
                                    alpha: 0.35,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.verified_rounded,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Clean set: no corrections needed. '
                                          'Keep that form as the reps climb.',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: AppColors.textPrimary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                for (final note in notes) _NoteCard(note: note),
                              if (report.isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: report),
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Tracking report copied to '
                                                'clipboard.',
                                              ),
                                            ),
                                          );
                                    },
                                    icon: const Icon(
                                      Icons.bug_report_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Copy tracking report'),
                                  ),
                                ),
                            ]
                            .animate(interval: 55.ms)
                            .fadeIn(duration: 320.ms)
                            .slideY(
                              begin: 0.06,
                              end: 0,
                              curve: AppTokens.curve,
                            ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrimaryButton(
                        label: 'DONE',
                        icon: Icons.check_rounded,
                        onPressed: () => context.go(Routes.home),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                // Same exercise and target as this set (a
                                // daily-challenge squat set stays squats).
                                ref
                                    .read(workoutLaunchProvider.notifier)
                                    .set(
                                      WorkoutLaunch(
                                        exercise: exercise,
                                        target: session.targetReps,
                                      ),
                                    );
                                context.pushReplacement(Routes.workoutCamera);
                              },
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text('ANOTHER SET'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => showShareSheet(
                                context,
                                ShareCardData(
                                  headline: newBest && priorBest > 0
                                      ? 'NEW PERSONAL BEST'
                                      : completed
                                      ? 'SET COMPLETE'
                                      : 'SET LOGGED',
                                  title: exercise.describeTarget(
                                    session.completedReps,
                                  ),
                                  subtitle: exercise.isTimed
                                      ? '${exercise.label} hold'
                                      : '${exercise.label} in one set',
                                  date: today,
                                  stats: [
                                    ShareStat(
                                      label: 'Today',
                                      value: '$todayForExercise',
                                    ),
                                    ShareStat(
                                      label: 'Streak',
                                      value: '$streak d',
                                    ),
                                    if (formScore != null)
                                      ShareStat(
                                        label: 'Good form',
                                        value: '${(formScore * 100).round()}%',
                                      ),
                                    ShareStat(
                                      label: 'Level',
                                      value: '${level.level}',
                                    ),
                                  ],
                                  accent: newBest && priorBest > 0
                                      ? 'warning'
                                      : 'primary',
                                ),
                              ),
                              icon: const Icon(Icons.ios_share_rounded),
                              label: const Text('SHARE'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (completed) const Positioned.fill(child: Celebration()),
        ],
      ),
    );
  }
}

class _XpCard extends StatelessWidget {
  const _XpCard({
    required this.xp,
    required this.level,
    required this.leveledUp,
  });

  final int xp;
  final LevelInfo level;
  final bool leveledUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      glow: leveledUp,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: LevelBadge(info: level, compact: true)),
              Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+$xp XP',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                  .animate(delay: 400.ms)
                  .scale(
                    begin: const Offset(0.6, 0.6),
                    end: const Offset(1, 1),
                    duration: 500.ms,
                    curve: Curves.elasticOut,
                  ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedProgressBar(
            value: level.progress,
            height: 8,
            semanticLabel: 'Level progress',
          ),
          const SizedBox(height: 6),
          Text(
            '${level.xpToNext} XP to level ${level.level + 1}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final CoachingNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        borderColor: AppColors.warning.withValues(alpha: 0.3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '×${note.count}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    note.tip,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
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

class _ChallengeLine extends StatelessWidget {
  const _ChallengeLine({required this.progress, required this.partIndex});

  final DailyChallengeProgress progress;
  final int partIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final part = progress.challenge.parts[partIndex];
    final done = progress.done[partIndex];
    final partDone = done >= part.target;
    final all = progress.completed;
    return AppCard(
      borderColor: (all ? AppColors.primary : AppColors.warning).withValues(
        alpha: 0.5,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            all ? Icons.check_circle_rounded : Icons.bolt_rounded,
            color: all ? AppColors.primary : AppColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              all
                  ? 'Daily challenge complete: +${DailyChallenge.bonusXp} XP.'
                  : partDone
                  ? 'Daily challenge: ${part.exercise.label.toLowerCase()} '
                        'done. ${progress.remainingParts} part'
                        '${progress.remainingParts == 1 ? '' : 's'} to go.'
                  : 'Daily challenge: ${done.clamp(0, part.target)}/'
                        '${part.target} ${part.exercise.countLabel(part.target)} '
                        'today. ${part.target - done} to go.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
