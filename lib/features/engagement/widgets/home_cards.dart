import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/engagement/daily_challenge.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/exercise.dart';
import '../../../widgets/animated_progress_bar.dart';
import '../../../widgets/app_card.dart';
import '../../pt/models/muscle_group.dart';
import '../../pt/models/workout_plan.dart';
import '../../pt/pt_providers.dart';
import '../../strength/logic/recovery.dart';
import '../../strength/strength_providers.dart';
import '../../workout/exercise_icons.dart';
import '../../workout/workout_launch.dart';
import '../engagement_providers.dart';

/// Today's seeded challenge with progress and a one-tap start.
class DailyChallengeCard extends ConsumerWidget {
  const DailyChallengeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(dailyChallengeProgressProvider);
    final streak = ref.watch(dailyChallengeStreakProvider);
    final c = progress.challenge;
    final done = progress.completed;
    return AppCard(
      glow: !done,
      borderColor: done ? AppColors.primary.withValues(alpha: 0.5) : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: done ? AppColors.brandGradient : null,
                  color: done
                      ? null
                      : AppColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  done ? Icons.check_rounded : Icons.bolt_rounded,
                  color: done ? AppColors.onPrimary : AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DAILY CHALLENGE'
                      '${streak > 0 ? ' · $streak-DAY STREAK' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: done ? AppColors.primary : AppColors.warning,
                        letterSpacing: 1.4,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      c.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '+${DailyChallenge.bonusXp} XP',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: done ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < c.parts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PartRow(
              part: c.parts[i],
              done: progress.done[i],
              onStart: done || progress.done[i] >= c.parts[i].target
                  ? null
                  : () => _start(context, ref, c.parts[i], progress.done[i]),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            done
                ? 'Done. Bonus XP banked; tomorrow brings a new one.'
                : c.tagline,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  void _start(
    BuildContext context,
    WidgetRef ref,
    DailyChallengePart part,
    int done,
  ) {
    final remaining = (part.target - done).clamp(1, 9999);
    ref
        .read(workoutLaunchProvider.notifier)
        .set(
          WorkoutLaunch(
            exercise: part.exercise,
            target: remaining,
            reason: 'Daily challenge',
          ),
        );
    context.push(Routes.workout);
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.part, required this.done, this.onStart});

  final DailyChallengePart part;
  final int done;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = done >= part.target;
    return Row(
      children: [
        Icon(part.exercise.icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${part.exercise.describeTarget(part.target)} · '
                '${done.clamp(0, part.target)}/${part.target}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedProgressBar(
                value: part.target == 0 ? 1 : done / part.target,
                height: 6,
                color: finished ? null : AppColors.warning,
                semanticLabel: '${part.exercise.label} progress',
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (finished)
          const Icon(Icons.check_circle_rounded, color: AppColors.primary)
        else
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cardElevated,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('GO'),
          ),
      ],
    );
  }
}

/// Mon–Sun dots for the weekly goal.
class WeekGoalCard extends ConsumerWidget {
  const WeekGoalCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ref.watch(thisWeekReportProvider);
    final today = ref.watch(clockProvider);
    final rest = ref.watch(settingsProvider.select((s) => s.restWeekdays));
    final weeks = ref.watch(weeksMetProvider);
    final met = report.goalMet;
    return AppCard(
      onTap: () => context.push(Routes.week),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  met
                      ? 'Weekly goal hit'
                      : '${report.activeDays} of ${report.goal} days this week',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: met ? AppColors.primary : null,
                  ),
                ),
              ),
              if (weeks > 0)
                Text(
                  '$weeks wk${weeks == 1 ? '' : 's'} in a row',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.cyan,
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                Expanded(
                  child: _DayDot(
                    weekday: d,
                    active: report.activeWeekdays.contains(d),
                    today: today.weekday == d,
                    rest: rest.contains(d),
                    future: d > today.weekday,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.weekday,
    required this.active,
    required this.today,
    required this.rest,
    required this.future,
  });

  final int weekday;
  final bool active;
  final bool today;
  final bool rest;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = DateFormat.E().format(DateTime(2024, 1, weekday));
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: active ? AppColors.brandGradient : null,
            color: active
                ? null
                : rest
                ? AppColors.secondary.withValues(alpha: 0.18)
                : AppColors.cardElevated,
            shape: BoxShape.circle,
            border: today
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: Icon(
            active
                ? Icons.check_rounded
                : rest
                ? Icons.bedtime_outlined
                : null,
            size: 16,
            color: active ? AppColors.onPrimary : AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.substring(0, 1),
          style: theme.textTheme.labelSmall?.copyWith(
            color: future ? AppColors.textMuted : AppColors.textSecondary,
            fontWeight: today ? FontWeight.w800 : null,
          ),
        ),
      ],
    );
  }
}

/// A MY PT suggestion built from the muscle recovery map, shown when no
/// programme is being followed.
class TodayPickCard extends ConsumerWidget {
  const TodayPickCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider);
    final recovery = MuscleRecovery.compute(
      lifts: ref.watch(liftLogProvider),
      ptRecords: ref.watch(ptRecordsProvider),
      sessions: ref.watch(sessionsProvider),
      now: now,
    );
    final fresh = MuscleRecovery.suggestNext(recovery).toSet();
    final pick = _pick(fresh, now);
    final minutes = ref.watch(ptRequestProvider).duration.inMinutes;
    return AppCard(
      onTap: () {
        final profile = ref.read(gymProfileProvider);
        ref
            .read(ptPlanProvider.notifier)
            .generate(
              PtRequest(
                duration: Duration(minutes: minutes),
                mode: pick.mode,
                level: ref.read(ptRequestProvider).level,
                equipment: profile.available,
                seed: now.millisecondsSinceEpoch % 100000,
              ),
            );
        context.push(Routes.ptPlan);
      },
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.cyan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's pick: ${pick.mode.label}",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${pick.reason} · $minutes min with MY PT',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.play_arrow_rounded, color: AppColors.cyan),
        ],
      ),
    );
  }

  static ({WorkoutMode mode, String reason}) _pick(
    Set<MuscleGroup> fresh,
    DateTime now,
  ) {
    bool all(Set<MuscleGroup> g) => g.every(fresh.contains);
    int count(Set<MuscleGroup> g) => g.where(fresh.contains).length;
    if (fresh.isEmpty) {
      return (
        mode: WorkoutMode.mobility,
        reason: 'Everything is still recovering, so open up and stretch',
      );
    }
    final candidates = [
      (WorkoutMode.legs, MuscleGroup.legs),
      (WorkoutMode.push, MuscleGroup.push),
      (WorkoutMode.pull, MuscleGroup.pull),
      (WorkoutMode.core, const {MuscleGroup.core, MuscleGroup.glutes}),
    ];
    for (final (mode, groups) in candidates) {
      if (all(groups)) {
        return (
          mode: mode,
          reason: '${groups.map((g) => g.label).join(', ')} are fresh',
        );
      }
    }
    candidates.sort((a, b) => count(b.$2).compareTo(count(a.$2)));
    final best = candidates.first;
    if (count(best.$2) >= 2) {
      final names = best.$2.where(fresh.contains).map((g) => g.label);
      return (mode: best.$1, reason: '${names.join(' and ')} are fresh');
    }
    return (
      mode: now.weekday == DateTime.sunday
          ? WorkoutMode.mobility
          : WorkoutMode.fullBody,
      reason: 'A balanced session fits today',
    );
  }
}

/// "Beat your best" for the exercise chosen on the home screen.
class BeatBestRow extends ConsumerWidget {
  const BeatBestRow({super.key, required this.exercise});

  final ExerciseType exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final best = ref.watch(personalBestsProvider)[exercise];
    if (best == null) return const SizedBox.shrink();
    final today = ref.watch(clockProvider);
    final ago = AppDateUtils.daysBetween(
      AppDateUtils.dateOnly(best.date),
      AppDateUtils.dateOnly(today),
    );
    return Row(
      children: [
        const Icon(
          Icons.emoji_events_outlined,
          size: 16,
          color: AppColors.warning,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Best: ${exercise.describeTarget(best.best)} · '
            '${ago == 0
                ? 'today'
                : ago == 1
                ? 'yesterday'
                : '$ago days ago'}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        TextButton(
          onPressed: () {
            ref
                .read(workoutLaunchProvider.notifier)
                .set(
                  WorkoutLaunch(
                    exercise: exercise,
                    target: best.best + 1,
                    reason: 'Beat your best',
                    bestToBeat: best.best,
                  ),
                );
            context.push(Routes.workout);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
          ),
          child: const Text('Beat it'),
        ),
      ],
    );
  }
}
