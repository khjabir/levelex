import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../models/user_settings.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../../pt/mannequin/mannequin_3d.dart';
import '../../pt/models/equipment.dart';
import '../../pt/models/movement.dart';
import '../../pt/models/movement_library.dart';
import '../../pt/pt_providers.dart';
import '../../pt/screens/pt_widgets.dart';
import '../models/lift_log.dart';
import '../models/progression_rule.dart';
import '../strength_providers.dart';
import '../widgets/progression_rule_sheet.dart';
import '../widgets/set_logger_sheet.dart';
import 'movement_insights.dart';

/// One movement: 3D guide, cues, your history, records and progression.
class MovementDetailScreen extends ConsumerWidget {
  const MovementDetailScreen({super.key, required this.movementId});

  final String movementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final movement = MovementLibrary.byId(movementId);
    final history = ref.watch(movementHistoryProvider(movementId));
    final unit = ref.watch(weightUnitProvider);
    final available = ref.watch(gymProfileProvider).available;
    final rules = ref.watch(progressionRulesProvider);
    final name =
        movement?.name ?? (history.isEmpty ? movementId : history.last.name);
    final equipment =
        movement?.equipmentFor(available) ??
        (movement?.equipmentOptions.isEmpty ?? true
            ? const <Equipment>{}
            : movement!.equipmentOptions.first);
    final rule =
        rules[movementId] ??
        (movement == null
            ? const ProgressionRule()
            : ProgressionRule.defaultsFor(movement, equipment: equipment));

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (movement != null)
            IconButton(
              tooltip: 'Progression rule',
              onPressed: () => showProgressionRuleSheet(
                context,
                movement: movement,
                rule: rule,
                custom: rules.containsKey(movementId),
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children:
            [
                  if (movement != null)
                    AppCard(
                      glow: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 230,
                            child: Mannequin3D(clipId: movement.clip),
                          ),
                          Text(
                            'Drag to rotate the guide',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final g in movement.primary) MuscleChip(g),
                              for (final g in movement.secondary)
                                Opacity(opacity: 0.6, child: MuscleChip(g)),
                            ],
                          ),
                          if (movement.equipmentOptions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              movement.equipmentOptions
                                  .map((o) => o.map((e) => e.label).join(' + '))
                                  .join('  or  '),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    AppCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'An exercise from an import. The coach has no '
                              'guide for it, but your history and records '
                              'still count.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  MovementInsights(
                    movementId: movementId,
                    movement: movement,
                    history: history,
                    rule: rule,
                    unit: unit,
                  ),
                  const SizedBox(height: 14),
                  if (history.isNotEmpty) ...[
                    const SectionHeader('Progress'),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                      child: SizedBox(
                        height: 180,
                        child: _HistoryChart(
                          history: history,
                          movement: movement,
                          unit: unit,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (movement != null) ...[
                    const SectionHeader('How to do it'),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Column(
                        children: [
                          for (var i = 0; i < movement.cues.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.brandGradient,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${i + 1}',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: AppColors.onPrimary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        movement.cues[i],
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: AppColors.textPrimary,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  SectionHeader(
                    history.isEmpty ? 'History' : 'History · ${history.length}',
                  ),
                  if (history.isEmpty)
                    AppCard(
                      child: Text(
                        'Nothing logged yet. Sets you do in MY PT land here '
                        'by themselves; tap Log sets to add one by hand.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (
                            var i = history.length - 1;
                            i >= 0 && i >= history.length - 30;
                            i--
                          ) ...[
                            if (i != history.length - 1)
                              const Divider(indent: 16, endIndent: 16),
                            _EntryTile(
                              entry: history[i],
                              unit: unit,
                              timed: movement?.isTimed ?? false,
                              onDelete: () =>
                                  _confirmDelete(context, ref, history[i]),
                              onEdit: movement == null
                                  ? null
                                  : () =>
                                        showSetLoggerSheet(
                                          context,
                                          movement: movement,
                                          template: history[i],
                                          date: history[i].startTime,
                                        ).then((saved) {
                                          if (saved != null) {
                                            ref
                                                .read(liftLogProvider.notifier)
                                                .remove(history[i].id);
                                          }
                                        }),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'LOG SETS',
                    icon: Icons.add_rounded,
                    onPressed: () => showSetLoggerSheet(
                      context,
                      movement:
                          movement ??
                          MovementLibrary.all.first.copyAsCustom(name),
                      template: history.isEmpty ? null : history.last,
                      customName: movement == null ? name : null,
                    ),
                  ),
                ]
                .animate(interval: 40.ms)
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LiftEntry entry,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          '${DateFormat.yMMMd().format(entry.startTime)} · '
          '${entry.sets.length} sets. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(liftLogProvider.notifier).remove(entry.id);
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.unit,
    required this.timed,
    required this.onDelete,
    this.onEdit,
  });

  final LiftEntry entry;
  final WeightUnit unit;
  final bool timed;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sets = entry.sets
        .map((s) {
          final count = timed ? '${s.seconds ?? 0}s' : '${s.reps}';
          final w = s.weightKg > 0
              ? '${unit.format(s.weightKg, withUnit: false)}×'
              : '';
          return '${s.warmUp ? 'w ' : ''}$w$count';
        })
        .join('  ');
    return ListTile(
      dense: true,
      title: Text(
        DateFormat.MMMEd().format(entry.startTime),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '$sets${entry.note != null ? '\n${entry.note}' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.source == LiftSource.pt)
            const Tooltip(
              message: 'Logged by MY PT',
              child: Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
          if (entry.source == LiftSource.import)
            const Tooltip(
              message: 'Imported',
              child: Icon(
                Icons.download_done_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => v == 'delete' ? onDelete() : onEdit?.call(),
            itemBuilder: (context) => [
              if (onEdit != null)
                const PopupMenuItem(value: 'edit', child: Text('Edit sets')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({
    required this.history,
    required this.movement,
    required this.unit,
  });

  final List<LiftEntry> history;
  final Movement? movement;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = history.length > 24
        ? history.sublist(history.length - 24)
        : history;
    final loaded = recent.any((e) => e.topWeight > 0);
    final timed = movement?.isTimed ?? false;
    final points = <FlSpot>[];
    for (var i = 0; i < recent.length; i++) {
      final e = recent[i];
      final y = loaded
          ? unit.fromKg(MovementInsights.bestMetric(e) ?? e.topWeight)
          : timed
          ? e.workSets
                .fold<int>(
                  0,
                  (m, s) => (s.seconds ?? 0) > m ? (s.seconds ?? 0) : m,
                )
                .toDouble()
          : e.workSets
                .fold<int>(0, (m, s) => s.reps > m ? s.reps : m)
                .toDouble();
      points.add(FlSpot(i.toDouble(), y));
    }
    final maxY = points.fold<double>(0, (m, p) => p.y > m ? p.y : m);
    final label = loaded
        ? 'Estimated 1RM (${unit.label})'
        : timed
        ? 'Longest hold (s)'
        : 'Best set (reps)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 6),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY == 0 ? 10 : maxY * 1.2,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppColors.divider, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, meta) => Text(
                      v.toStringAsFixed(0),
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: (recent.length / 4).clamp(1, 100).ceilToDouble(),
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= recent.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          DateFormat.MMMd().format(recent[i].startTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.cardElevated,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s.y.toStringAsFixed(loaded ? 1 : 0)}\n'
                        '${DateFormat.MMMd().format(recent[s.x.toInt()].startTime)}',
                        const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  preventCurveOverShooting: true,
                  color: AppColors.primary,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                      radius: 3,
                      color: AppColors.background,
                      strokeWidth: 2,
                      strokeColor: AppColors.primary,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.25),
                        AppColors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 350),
          ),
        ),
      ],
    );
  }
}

extension on Movement {
  /// A stand-in movement so the set logger can log a custom (imported)
  /// exercise: only the name and the rep-based kind matter.
  Movement copyAsCustom(String name) => Movement(
    id: id,
    name: name,
    kind: MovementKind.reps,
    phases: phases,
    primary: primary,
    cues: const [],
    tracking: tracking,
    clip: clip,
    equipmentOptions: const [
      {Equipment.dumbbells},
    ],
  );
}
