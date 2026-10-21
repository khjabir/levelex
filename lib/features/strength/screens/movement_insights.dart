import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../models/user_settings.dart';
import '../../../widgets/app_card.dart';
import '../../pt/models/movement.dart';
import '../logic/one_rm.dart';
import '../logic/progression.dart';
import '../logic/records.dart';
import '../models/lift_log.dart';
import '../models/progression_rule.dart';

/// Records, estimated 1RM and the next prescription for one movement.
class MovementInsights extends StatelessWidget {
  const MovementInsights({
    super.key,
    required this.movementId,
    required this.movement,
    required this.history,
    required this.rule,
    required this.unit,
  });

  final String movementId;
  final Movement? movement;
  final List<LiftEntry> history;
  final ProgressionRule rule;
  final WeightUnit unit;

  /// The number the progress chart follows for a loaded lift: estimated
  /// 1RM when the reps allow it, else the heaviest set.
  static double? bestMetric(LiftEntry e) =>
      OneRm.bestForEntry(e) ?? (e.topWeight > 0 ? e.topWeight : null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bests = RecordBook.bestsFor(movementId, history);
    final oneRm = OneRm.bestInHistory(history);
    final loaded = history.any((e) => e.topWeight > 0);
    final next = ProgressionEngine.next(rule: rule, history: history);
    final stalls = ProgressionEngine.stallCount(rule, history);
    final timed = movement?.isTimed ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (history.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: _Fact(
                  label: loaded
                      ? 'Est. 1RM'
                      : (timed ? 'Longest hold' : 'Best set'),
                  value: loaded
                      ? (oneRm == null ? '—' : unit.format(oneRm))
                      : timed
                      ? '${_bestSeconds()}s'
                      : '${_bestReps()} reps',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Fact(
                  label: loaded ? 'Heaviest' : 'Sessions',
                  value: loaded
                      ? (bests.weight == null
                            ? '—'
                            : unit.format(bests.weight!))
                      : '${history.length}',
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Fact(
                  label: 'Last',
                  value: DateFormat.MMMd().format(history.last.startTime),
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        if (history.isNotEmpty) const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          borderColor: switch (next.kind) {
            PrescriptionKind.up => AppColors.primary.withValues(alpha: 0.5),
            PrescriptionKind.deload => AppColors.warning.withValues(alpha: 0.6),
            _ => null,
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (next.kind) {
                  PrescriptionKind.up => Icons.trending_up_rounded,
                  PrescriptionKind.deload => Icons.trending_down_rounded,
                  PrescriptionKind.hold => Icons.trending_flat_rounded,
                  PrescriptionKind.first => Icons.flag_outlined,
                  PrescriptionKind.off => Icons.block_rounded,
                },
                color: switch (next.kind) {
                  PrescriptionKind.up => AppColors.primary,
                  PrescriptionKind.deload => AppColors.warning,
                  _ => AppColors.textSecondary,
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _headline(next),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(next.why, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      '${rule.policy.label}'
                      '${stalls > 0 ? ' · $stalls missed in a row' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (bests.repsAtWeight.isNotEmpty && loaded) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e
                  in (bests.repsAtWeight.entries.toList()
                        ..sort((a, b) => b.key.compareTo(a.key)))
                      .take(6))
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${unit.format(e.key)} × ${e.value}',
                    style: theme.textTheme.labelMedium,
                  ),
                  side: const BorderSide(color: AppColors.outline),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _headline(Prescription p) {
    final load = p.weightKg != null && p.weightKg! > 0
        ? '${unit.format(p.weightKg!)} · '
        : '';
    final target = (movement?.isTimed ?? false)
        ? '${p.sets} × ${p.seconds ?? rule.seconds}s'
        : '${p.sets} × ${p.repLabel}';
    return switch (p.kind) {
      PrescriptionKind.first => 'Next: set your baseline',
      PrescriptionKind.off => 'Next: $load$target',
      PrescriptionKind.up => 'Next: $load$target  ↑',
      PrescriptionKind.hold => 'Next: $load$target',
      PrescriptionKind.deload => 'Next: $load$target  (deload)',
    };
  }

  int _bestReps() => history.fold<int>(
    0,
    (m, e) => e.workSets.fold<int>(m, (mm, s) => s.reps > mm ? s.reps : mm),
  );

  int _bestSeconds() => history.fold<int>(
    0,
    (m, e) => e.workSets.fold<int>(
      m,
      (mm, s) => (s.seconds ?? 0) > mm ? (s.seconds ?? 0) : mm,
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
