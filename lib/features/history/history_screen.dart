import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils/date_utils.dart';
import '../../models/daily_stats.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';
import '../home/home_screen.dart';
import '../pt/screens/pt_home_screen.dart';

/// Per-day history with a 7-day chart and tappable day details.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final now = ref.watch(clockProvider);
    final byDay = {for (final d in history) d.date: d};

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: SafeArea(
        child: history.isEmpty
            ? const _EmptyHistory()
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  const SectionHeader('Last 7 days'),
                  AppCard(
                    glow: true,
                    padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                    child: SizedBox(
                      height: 180,
                      child: _WeekChart(byDay: byDay, today: now),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader('All days'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < history.length; i++) ...[
                          if (i > 0) const Divider(indent: 20, endIndent: 20),
                          _DayTile(
                            stats: history[i],
                            today: now,
                            onTap: () => _showDay(context, history[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showDay(BuildContext context, DailyStats stats) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DayDetailSheet(stats: stats),
    );
  }
}

/// Human label for a day: Today, Yesterday, weekday (this week) or a date.
String dayLabel(DateTime day, DateTime today) {
  final diff = AppDateUtils.daysBetween(day, today);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.EEEE().format(day);
  if (day.year == today.year) return DateFormat.MMMMd().format(day);
  return DateFormat.yMMMd().format(day);
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.history_rounded,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text('No history yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Finish your first set and it will show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.byDay, required this.today});

  final Map<DateTime, DailyStats> byDay;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = [
      for (var i = 6; i >= 0; i--)
        AppDateUtils.addDays(AppDateUtils.dateOnly(today), -i),
    ];
    final values = [for (final d in days) byDay[d]?.totalPushUps ?? 0];
    final maxValue = values.fold<int>(0, (m, v) => v > m ? v : m);
    final maxY = (maxValue == 0 ? 10 : maxValue * 1.25).toDouble();

    return Semantics(
      label:
          'Reps over the last 7 days: '
          '${[for (var i = 0; i < 7; i++) '${DateFormat.E().format(days[i])} ${values[i]}'].join(', ')}',
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.divider, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  final isToday = index == days.length - 1;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat.E().format(days[index]).substring(0, 1),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isToday
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.cardElevated,
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    '${rod.toY.round()}',
                    const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i].toDouble(),
                    width: 18,
                    borderRadius: BorderRadius.circular(6),
                    gradient: i == days.length - 1
                        ? const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [AppColors.primary, AppColors.lime],
                          )
                        : LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.secondary.withValues(alpha: 0.7),
                              AppColors.secondary,
                            ],
                          ),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.stats,
    required this.today,
    required this.onTap,
  });

  final DailyStats stats;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = stats.attemptedSessions + stats.ptSessions;
    final subtitle = [
      '$total ${total == 1 ? 'session' : 'sessions'}',
      if (stats.ptSessions > 0) '${stats.ptSessions} MY PT',
      if (stats.skippedSessions > 0) '${stats.skippedSessions} skipped',
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      onTap: onTap,
      title: Text(
        dayLabel(stats.date, today),
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${stats.totalPushUps}',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: stats.isCompletedDay
                  ? AppColors.primary
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text('reps', style: theme.textTheme.bodySmall),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _DayDetailSheet extends ConsumerWidget {
  const _DayDetailSheet({required this.stats});

  final DailyStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsForDayProvider(stats.date));
    final ptRecords = ref.watch(ptRecordsForDayProvider(stats.date));
    final today = ref.watch(clockProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(dayLabel(stats.date, today), style: theme.textTheme.titleLarge),
          Text(
            DateFormat.yMMMMEEEEd().format(stats.date),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.9,
            children: [
              _DetailStat(
                label: 'Total reps',
                value: '${stats.totalPushUps}',
                color: AppColors.primary,
              ),
              _DetailStat(
                label: 'Sessions',
                value: '${stats.attemptedSessions + stats.ptSessions}',
              ),
              _DetailStat(
                label: 'Completed',
                value: '${stats.completedSessions + stats.ptCompletedSessions}',
              ),
              _DetailStat(
                label: 'Skipped',
                value: '${stats.skippedSessions}',
                color: stats.skippedSessions > 0 ? AppColors.warning : null,
              ),
            ],
          ),
          if (ptRecords.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeader('MY PT'),
            AppCard(
              color: AppColors.card,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < ptRecords.length; i++) ...[
                    if (i > 0) const Divider(indent: 20, endIndent: 20),
                    PtRecordTile(record: ptRecords[i]),
                  ],
                ],
              ),
            ),
          ],
          if (sessions.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeader('Sessions'),
            AppCard(
              color: AppColors.card,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < sessions.length; i++) ...[
                    if (i > 0) const Divider(indent: 20, endIndent: 20),
                    SessionTile(session: sessions[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color ?? AppColors.textPrimary,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
