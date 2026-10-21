import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/levels/level_system.dart';
import '../../models/exercise.dart';
import '../../models/workout_session.dart';
import '../../widgets/animated_progress_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/level_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/section_header.dart';
import '../notifications/reminder_controller.dart';
import '../pt/models/workout_plan.dart';
import '../pt/pt_providers.dart';
import '../strength/logic/routine_launcher.dart';
import '../strength/logic/routine_schedule.dart';
import '../strength/models/routine.dart';
import '../strength/strength_providers.dart';
import '../workout/exercise_icons.dart';
import '../pt/mannequin/mannequin_3d.dart';

/// Dashboard: level and XP, today's goal ring, exercise picker, the START
/// call-to-action, reminder status and today's sessions.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayStatsProvider);
    final goal = ref.watch(dailyGoalProvider);
    final streak = ref.watch(currentStreakProvider);
    final sessions = ref.watch(todaySessionsProvider);
    final settings = ref.watch(settingsProvider);
    final reminderStatus = ref.watch(reminderControllerProvider);
    final level = ref.watch(levelProvider);
    final goalExercise = settings.reminderExercise;
    final goalTotal = ref.watch(todayTotalForExerciseProvider(goalExercise));
    final selected = settings.selectedExercise;
    final selectedTotal = ref.watch(todayTotalForExerciseProvider(selected));
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children:
              [
                    Row(
                      children: [
                        const Expanded(child: BrandWordmark(size: 17)),
                        _HeaderButton(
                          icon: Icons.insights_rounded,
                          tooltip: 'History',
                          onPressed: () => context.push(Routes.history),
                        ),
                        const SizedBox(width: 8),
                        _HeaderButton(
                          icon: Icons.settings_outlined,
                          tooltip: 'Settings',
                          onPressed: () => context.push(Routes.settings),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _LevelCard(level: level, streak: streak),
                    const SizedBox(height: 14),
                    _MyPtCard(onTap: () => context.push(Routes.pt)),
                    if (ref.watch(activeRoutineProvider) != null) ...[
                      const SizedBox(height: 10),
                      _TodayCard(
                        routine: ref.watch(activeRoutineProvider)!,
                        day: ref.watch(todayRoutineDayProvider),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.bolt_rounded,
                            title: 'Quick workout',
                            subtitle: '10 min, no setup',
                            color: AppColors.lime,
                            onTap: () {
                              final profile = ref.read(gymProfileProvider);
                              ref
                                  .read(ptPlanProvider.notifier)
                                  .generate(
                                    PtRequest(
                                      duration: const Duration(minutes: 10),
                                      mode: WorkoutMode.fullBody,
                                      level: ref.read(ptRequestProvider).level,
                                      equipment: profile.available,
                                      seed: DateTime.now().millisecond,
                                      quick: true,
                                    ),
                                  );
                              context.push(Routes.ptSession);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.emoji_events_rounded,
                            title: 'Challenge',
                            subtitle: 'Friends, one cup',
                            color: AppColors.warning,
                            onTap: () => context.push(Routes.challenge),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniTile(
                            icon: Icons.menu_book_rounded,
                            title: 'Library',
                            color: AppColors.cyan,
                            onTap: () => context.push(Routes.library),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniTile(
                            icon: Icons.insights_rounded,
                            title: 'Progress',
                            color: AppColors.primary,
                            onTap: () => context.push(Routes.progress),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniTile(
                            icon: Icons.monitor_weight_outlined,
                            title: 'Body',
                            color: AppColors.secondary,
                            onTap: () => context.push(Routes.body),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _GoalCard(
                      exercise: goalExercise,
                      total: goalTotal,
                      goal: goal,
                      completed: today.completedSessions,
                      skipped: settings.trackSkippedSessions
                          ? today.skippedSessions
                          : null,
                      remindersEnabled: settings.remindersEnabled,
                      permissionGranted: reminderStatus.permissionGranted,
                    ),
                    const SizedBox(height: 26),
                    const SectionHeader('Choose your exercise'),
                    _ExercisePicker(
                      selected: selected,
                      onSelected: (type) => ref
                          .read(settingsProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWith(selectedExercise: type),
                          ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          Icons.flag_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Target ${selected.describeTarget(settings.targetFor(selected))}'
                            ' · $selectedTotal ${selected.countLabel(selectedTotal)} today',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push(Routes.workout),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text('How to'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: selected.startLabel,
                      icon: Icons.play_arrow_rounded,
                      semanticLabel: 'Start ${selected.singular} set',
                      onPressed: () => context.push(Routes.workout),
                    ),
                    const SizedBox(height: 28),
                    const SectionHeader("Today's sessions"),
                    if (sessions.isEmpty)
                      AppCard(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No sets yet today. Your first one is one tap '
                                'away.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < sessions.length; i++) ...[
                              if (i > 0)
                                const Divider(indent: 20, endIndent: 20),
                              SessionTile(session: sessions[i]),
                            ],
                          ],
                        ),
                      ),
                  ]
                  .animate(interval: 45.ms)
                  .fadeIn(duration: 320.ms)
                  .slideY(begin: 0.06, end: 0, curve: AppTokens.curve),
        ),
      ),
    );
  }
}

/// Compact entry tile: icon over a one-word title.
class _MiniTile extends StatelessWidget {
  const _MiniTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the active routine asks for today.
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.routine, required this.day});

  final Routine routine;
  final RoutineDay? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final next = day == null
        ? RoutineScheduler.nextTrainingDate(
            routine,
            DateTime.now().add(const Duration(days: 1)),
          )
        : null;
    return AppCard(
      onTap: () => day == null
          ? context.push(Routes.routines)
          : startRoutineDay(context, ref, routine, day!),
      padding: const EdgeInsets.all(16),
      borderColor: day == null
          ? null
          : AppColors.primary.withValues(alpha: 0.4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (day == null ? AppColors.textMuted : AppColors.primary)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              day == null ? Icons.bedtime_outlined : Icons.today_rounded,
              color: day == null ? AppColors.textSecondary : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day == null ? 'Rest day' : 'Today: ${day!.name}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  day == null
                      ? '${routine.name}'
                            '${next == null ? '' : ' · next ${DateFormat.EEEE().format(next)}'}'
                      : '${routine.name} · ${day!.exercises.length} exercises · ${day!.minutes} min',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            day == null
                ? Icons.chevron_right_rounded
                : Icons.play_arrow_rounded,
            color: day == null ? AppColors.textMuted : AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// Entry to the guided personal-trainer module.
class _MyPtCard extends StatelessWidget {
  const _MyPtCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      glow: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.onPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY PT',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your AI personal trainer: pick a time and a focus, get a '
                  'guided warm-up, workout and cool-down with 3D form guides.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.primary),
        ],
      ),
    );
  }
}

/// Compact entry tile for one-tap flows.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        fixedSize: const Size(44, 44),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

/// Level, title, XP progress and the streak.
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level, required this.streak});

  final LevelInfo level;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: LevelBadge(info: level)),
              _StreakChip(streak: streak),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedProgressBar(
            value: level.progress,
            height: 8,
            semanticLabel: 'Level progress',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${level.xpIntoLevel} / ${level.xpForLevel} XP',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                '${level.xpToNext} XP to level ${level.level + 1}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final label = streak == 1 ? '1 day' : '$streak days';
    final hot = streak > 0;
    return Semantics(
      label: 'Current streak: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: hot ? 0.14 : 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: hot ? 0.4 : 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 18,
              color: hot ? AppColors.warning : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: hot ? AppColors.warning : AppColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's goal ring plus sessions and the next reminder.
class _GoalCard extends ConsumerWidget {
  const _GoalCard({
    required this.exercise,
    required this.total,
    required this.goal,
    required this.completed,
    required this.skipped,
    required this.remindersEnabled,
    required this.permissionGranted,
  });

  final ExerciseType exercise;
  final int total;
  final int goal;
  final int completed;
  final int? skipped;
  final bool remindersEnabled;
  final bool? permissionGranted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final next = ref.watch(nextReminderProvider);
    final progress = goal == 0 ? 0.0 : total / goal;
    final (reminderText, reminderColor) = !remindersEnabled
        ? ('Reminders off', AppColors.textMuted)
        : permissionGranted == false
        ? ('Notifications blocked', AppColors.danger)
        : next == null
        ? ('No reminder today', AppColors.textMuted)
        : ('Next at ${DateFormat.jm().format(next)}', AppColors.textPrimary);

    return AppCard(
      glow: progress >= 1,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          ProgressRing(
            value: progress,
            size: 124,
            thickness: 12,
            semanticLabel: 'Daily goal progress',
            child: Semantics(
              label: '${exercise.label} today',
              value: '$total of $goal',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: total),
                    duration: const Duration(milliseconds: 700),
                    curve: AppTokens.curve,
                    builder: (context, value, _) => Text(
                      '$value',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 34,
                        height: 1,
                        color: progress >= 1
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    'of $goal',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${exercise.label.toUpperCase()} TODAY',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress >= 1
                      ? 'Goal smashed!'
                      : '${goal - total} ${exercise.countLabel(goal - total)} to go',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: progress >= 1 ? AppColors.primary : null,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.check_circle_outline_rounded,
                  text: skipped == null
                      ? '$completed completed'
                      : '$completed completed · $skipped skipped',
                  color: skipped != null && skipped! > 0
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => context.push(Routes.settings),
                  child: _InfoRow(
                    icon: Icons.notifications_none_rounded,
                    text: reminderText,
                    color: reminderColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Horizontal cards, one per exercise, with a live demo on the selected one.
class _ExercisePicker extends StatelessWidget {
  const _ExercisePicker({required this.selected, required this.onSelected});

  final ExerciseType selected;
  final ValueChanged<ExerciseType> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: ExerciseType.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final type = ExerciseType.values[i];
          final isSelected = type == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: type.label,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onSelected(type),
              child: AnimatedContainer(
                duration: AppTokens.normal,
                curve: AppTokens.curve,
                width: 128,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.06),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.18),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Center(
                        child: Mannequin3D(
                          clipId: type.clipId,
                          size: 84,
                          playing: isSelected,
                          interactive: false,
                          autoRotate: false,
                          showFloor: false,
                          compact: true,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          type.icon,
                          size: 14,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            type.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One row describing a session (used on Home and in History details).
class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.jm().format(session.startTime);
    final (icon, color, status) = switch (session.status) {
      SessionStatus.completed => (
        Icons.check_rounded,
        AppColors.primary,
        'Completed',
      ),
      SessionStatus.incomplete => (
        Icons.remove_rounded,
        AppColors.warning,
        'Partial',
      ),
      SessionStatus.skipped => (
        Icons.close_rounded,
        AppColors.danger,
        'Skipped',
      ),
    };
    final exercise = session.exercise;
    final reps = session.skipped
        ? 'Reminder missed'
        : exercise.isTimed
        ? '${session.completedReps} s ${exercise.singular}'
        : '${session.completedReps} ${exercise.countLabel(session.completedReps)}';
    final xp = LevelSystem.xpForSession(session);
    return Semantics(
      label: '$time, $reps, $status',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                session.skipped ? Icons.alarm_off_rounded : exercise.icon,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reps,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: session.skipped
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '$time · $status'
                    '${session.verified ? '' : ' · unverified'}'
                    '${session.totalMistakes > 0 ? ' · ${session.totalMistakes} coach note${session.totalMistakes == 1 ? '' : 's'}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: session.verified ? null : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            if (xp > 0)
              Text(
                '+$xp XP',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
