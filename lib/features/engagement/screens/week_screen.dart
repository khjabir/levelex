import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/engagement/weekly_report.dart';
import '../../../widgets/animated_progress_bar.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/share_card.dart';
import '../../../widgets/share_sheet.dart';
import '../engagement_providers.dart';

/// This week against the goal and against last week, with a share card.
class WeekScreen extends ConsumerWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final week = ref.watch(thisWeekReportProvider);
    final last = ref.watch(lastWeekReportProvider);
    final weeks = ref.watch(weeksMetProvider);
    final today = ref.watch(clockProvider);
    final end = week.weekStart.add(const Duration(days: 6));
    final range =
        '${DateFormat.MMMd().format(week.weekStart)} – '
        '${DateFormat.MMMd().format(end)}';
    final daysLeft = 7 - today.weekday;

    return Scaffold(
      appBar: AppBar(
        title: const Text('This week'),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: () => showShareSheet(
              context,
              ShareCardData(
                headline: week.goalMet ? 'WEEKLY GOAL HIT' : 'THIS WEEK',
                title:
                    '${week.activeDays} active day${week.activeDays == 1 ? '' : 's'}',
                subtitle: range,
                date: today,
                stats: [
                  ShareStat(label: 'Workouts', value: '${week.workouts}'),
                  ShareStat(label: 'Reps', value: '${week.reps}'),
                  ShareStat(label: 'Minutes', value: '${week.activeMinutes}'),
                  ShareStat(label: 'XP', value: '${week.xp}'),
                ],
                footnote: weeks > 1 ? '$weeks weeks in a row on goal' : null,
                accent: week.goalMet ? 'primary' : 'cyan',
              ),
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Change goal',
            onPressed: () => context.push(Routes.settings),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children:
            [
                  AppCard(
                    glow: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(range, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          week.goalMet
                              ? 'Goal hit: ${week.activeDays} of ${week.goal} days'
                              : '${week.activeDays} of ${week.goal} active days',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: week.goalMet ? AppColors.primary : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedProgressBar(
                          value: week.goalProgress,
                          height: 10,
                          semanticLabel: 'Weekly goal progress',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          week.goalMet
                              ? weeks > 1
                                    ? '$weeks weeks in a row. Keep the chain.'
                                    : 'First week on goal. Make it two.'
                              : daysLeft == 0
                              ? '${week.goal - week.activeDays} more today to hit it.'
                              : '${week.goal - week.activeDays} more in the next '
                                    '$daysLeft day${daysLeft == 1 ? '' : 's'}.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('This week vs last week'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        _CompareRow(
                          label: 'Workouts',
                          now: week.workouts,
                          before: last.workouts,
                        ),
                        _CompareRow(
                          label: 'Active days',
                          now: week.activeDays,
                          before: last.activeDays,
                        ),
                        _CompareRow(
                          label: 'Reps',
                          now: week.reps,
                          before: last.reps,
                        ),
                        _CompareRow(
                          label: 'Active minutes',
                          now: week.activeMinutes,
                          before: last.activeMinutes,
                        ),
                        _CompareRow(
                          label: 'XP earned',
                          now: week.xp,
                          before: last.xp,
                        ),
                        _CompareRow(
                          label: 'Personal records',
                          now: week.prs,
                          before: last.prs,
                        ),
                        _CompareRow(
                          label: 'Daily challenges',
                          now: week.dailyChallenges,
                          before: last.dailyChallenges,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('Days'),
                  AppCard(
                    child: Row(
                      children: [
                        for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    gradient: week.activeWeekdays.contains(d)
                                        ? AppColors.brandGradient
                                        : null,
                                    color: week.activeWeekdays.contains(d)
                                        ? null
                                        : AppColors.cardElevated,
                                    shape: BoxShape.circle,
                                    border: today.weekday == d
                                        ? Border.all(
                                            color: AppColors.primary,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: week.activeWeekdays.contains(d)
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: AppColors.onPrimary,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  DateFormat.E()
                                      .format(DateTime(2024, 1, d))
                                      .substring(0, 2),
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ]
                .animate(interval: 40.ms)
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.now,
    required this.before,
    this.last = false,
  });

  final String label;
  final int now;
  final int before;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = now - before;
    final color = delta > 0
        ? AppColors.primary
        : delta < 0
        ? AppColors.warning
        : AppColors.textMuted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '$now',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text(
                  delta == 0 ? '= $before' : '${delta > 0 ? '+' : ''}$delta',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!last) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// Convenience for other screens.
String weekRangeLabel(WeeklyReport week) =>
    '${DateFormat.MMMd().format(week.weekStart)} – '
    '${DateFormat.MMMd().format(week.weekStart.add(const Duration(days: 6)))}';
