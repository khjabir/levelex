import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/stats_calculator.dart';
import '../../../models/workout_session.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/section_header.dart';
import '../../pt/models/movement_library.dart';
import '../../pt/models/muscle_group.dart';
import '../../pt/models/pt_record.dart';
import '../../pt/pt_providers.dart';
import '../logic/body_weight_stats.dart';
import '../logic/records.dart';
import '../logic/recovery.dart';
import '../models/lift_log.dart';
import '../strength_providers.dart';
import '../widgets/activity_heatmap.dart';
import '../widgets/muscle_map.dart';

/// Workouts per calendar day for the activity heatmap: camera sets with reps,
/// MY PT sessions in which some work was done, and lifts logged by hand
/// (MY PT's own lift-log copies are already counted through the session).
/// Unverified work counts here; the streak below it does not.
@visibleForTesting
Map<DateTime, int> activityByDay({
  required Iterable<WorkoutSession> sessions,
  required Iterable<PtRecord> ptRecords,
  required Iterable<LiftEntry> lifts,
}) {
  final activity = <DateTime, int>{};
  void bump(DateTime t) {
    final d = AppDateUtils.dateOnly(t);
    activity[d] = (activity[d] ?? 0) + 1;
  }

  for (final s in sessions) {
    if (s.completedReps > 0 && !s.skipped) bump(s.startTime);
  }
  for (final r in ptRecords) {
    if (r.hasWork) bump(r.startTime);
  }
  for (final e in lifts) {
    if (e.source != LiftSource.pt) bump(e.startTime);
  }
  return activity;
}

/// The long view: a year of activity, which muscles are fresh, your
/// records, weekly volume and body weight.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  MuscleGroup? _picked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsProvider);
    final ptRecords = ref.watch(ptRecordsProvider);
    final lifts = ref.watch(liftLogProvider);
    final unit = ref.watch(weightUnitProvider);
    final bodyWeights = ref.watch(bodyWeightProvider);
    final now = DateTime.now();

    final activity = activityByDay(
      sessions: sessions,
      ptRecords: ptRecords,
      lifts: lifts,
    );
    final activeDays = activity.length;
    final restWeekdays = ref.watch(
      settingsProvider.select((s) => s.restWeekdays),
    );
    // Same rest days as the home screen's streak.
    final streak = StatsCalculator.currentStreak(
      sessions,
      now,
      ptRecords: ptRecords,
      restWeekdays: restWeekdays,
    );
    final longest = StatsCalculator.longestStreak(
      sessions,
      ptRecords: ptRecords,
      restWeekdays: restWeekdays,
    );

    final recovery = MuscleRecovery.compute(
      lifts: lifts,
      ptRecords: ptRecords,
      sessions: sessions,
      now: now,
    );
    final fresh = MuscleRecovery.suggestNext(recovery);
    final picked = _picked == null ? null : recovery[_picked!];
    final records = RecordBook.recent(lifts, limit: 8);
    final weekly = _weeklyVolume(lifts, now);
    final latestWeight = BodyWeightStats.latest(bodyWeights);
    final change30 = BodyWeightStats.change(bodyWeights, days: 30);

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          AppCard(
            glow: true,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Last 26 weeks',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '$activeDays active days',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ActivityHeatmap(values: activity, today: now),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    // The heatmap shows all activity; the streak, like the
                    // home screen's, counts verified workouts only.
                    'Verified streak $streak day${streak == 1 ? '' : 's'} · '
                    'longest $longest',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Muscle recovery'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              children: [
                MuscleMap(
                  statuses: recovery,
                  highlighted: _picked,
                  height: 250,
                  onTap: (g) =>
                      setState(() => _picked = _picked == g ? null : g),
                ),
                const SizedBox(height: 8),
                if (picked != null)
                  Text(
                    '${_picked!.label}: ${picked.state.label.toLowerCase()}'
                    '${picked.lastTrained == null ? ', never trained' : ', last ${_ago(picked.lastTrained!, now)}'}'
                    ' · ${picked.hardSets7d.toStringAsFixed(0)} hard sets this week',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  )
                else
                  Text(
                    fresh.isEmpty
                        ? 'Everything is still recovering: an easy '
                              'mobility session fits today.'
                        : 'Fresh and ready: '
                              '${fresh.take(4).map((g) => g.label).join(', ')}. '
                              'Tap a muscle for details.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            'Personal records',
            trailing: TextButton(
              onPressed: () => context.push(Routes.library),
              child: const Text('Library'),
            ),
          ),
          if (records.isEmpty)
            AppCard(
              child: Text(
                'Records appear once you log the same exercise '
                'twice: heaviest set, most reps at a weight, '
                'best estimated 1RM and most volume.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < records.length; i++) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.emoji_events_rounded,
                        color: AppColors.warning,
                      ),
                      title: Text(
                        MovementLibrary.byId(records[i].movementId)?.name ??
                            _customName(lifts, records[i].movementId),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${records[i].kind.label} · '
                        '${DateFormat.MMMd().format(records[i].date)}',
                      ),
                      trailing: Text(
                        _prLabel(records[i], unit),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: () =>
                          context.push(Routes.movement(records[i].movementId)),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          const SectionHeader('Weekly volume'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: SizedBox(
              height: 170,
              child: weekly.every((w) => w.$2 == 0 && w.$3 == 0)
                  ? Center(
                      child: Text(
                        'Volume (sets × reps × load) shows here once '
                        'you log loaded sets.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : _VolumeChart(weeks: weekly, unit: unit),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Body'),
          AppCard(
            onTap: () => context.push(Routes.body),
            child: Row(
              children: [
                const Icon(
                  Icons.monitor_weight_outlined,
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latestWeight == null
                            ? 'No weigh-ins yet'
                            : unit.format(latestWeight.kg),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        latestWeight == null
                            ? 'Track weight, a goal line and progress photos'
                            : change30 == null
                            ? 'Log a few more weigh-ins for a trend'
                            : '${change30 >= 0 ? '+' : '−'}${unit.format(change30.abs())} in 30 days',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ].animate(interval: 40.ms).fadeIn(duration: 260.ms).slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
      ),
    );
  }

  static String _customName(List<LiftEntry> lifts, String id) {
    for (final e in lifts.reversed) {
      if (e.movementId == id) return e.name;
    }
    return id;
  }

  static String _prLabel(PersonalRecord r, dynamic unit) {
    return switch (r.kind) {
      PrKind.weight => unit.format(r.value),
      PrKind.oneRm => unit.format(r.value),
      PrKind.volume => unit.format(r.value),
      PrKind.reps =>
        '${r.value.toStringAsFixed(0)} × ${r.weightKg == null || r.weightKg == 0 ? 'bw' : unit.format(r.weightKg!)}',
    };
  }

  static String _ago(DateTime t, DateTime now) {
    final h = now.difference(t).inHours;
    if (h < 24) return '${h}h ago';
    final d = (h / 24).floor();
    return d == 1 ? 'yesterday' : '$d days ago';
  }

  /// (weekStart, volumeKg, sets) for the last 8 weeks, oldest first.
  static List<(DateTime, double, int)> _weeklyVolume(
    List<LiftEntry> lifts,
    DateTime now,
  ) {
    final today = AppDateUtils.dateOnly(now);
    final thisWeek = today.subtract(Duration(days: today.weekday - 1));
    final out = <(DateTime, double, int)>[];
    for (var i = 7; i >= 0; i--) {
      final start = thisWeek.subtract(Duration(days: 7 * i));
      final end = start.add(const Duration(days: 7));
      var vol = 0.0;
      var sets = 0;
      for (final e in lifts) {
        if (e.startTime.isBefore(start) || !e.startTime.isBefore(end)) {
          continue;
        }
        vol += e.volume;
        sets += e.workSets.length;
      }
      out.add((start, vol, sets));
    }
    return out;
  }
}

class _VolumeChart extends StatelessWidget {
  const _VolumeChart({required this.weeks, required this.unit});

  final List<(DateTime, double, int)> weeks;
  final dynamic unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [for (final w in weeks) unit.fromKg(w.$2) as double];
    final maxY = values.fold<double>(0, (m, v) => v > m ? v : m);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY == 0 ? 10 : maxY * 1.25,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
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
              reservedSize: 26,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= weeks.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat.Md().format(weeks[i].$1),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.cardElevated,
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '${unit.format(weeks[gi].$2)}\n${weeks[gi].$3} sets',
              const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < weeks.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: 16,
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: i == weeks.length - 1
                        ? const [AppColors.primary, AppColors.lime]
                        : [
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
    );
  }
}
