import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/primary_button.dart';
import '../../pt/models/movement.dart';
import '../models/progression_rule.dart';
import '../strength_providers.dart';

/// Lets the user pick how a movement progresses. Saved per movement; "Use
/// default" removes the override.
Future<void> showProgressionRuleSheet(
  BuildContext context, {
  required Movement movement,
  required ProgressionRule rule,
  required bool custom,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) =>
        _RuleSheet(movement: movement, rule: rule, custom: custom),
  );
}

class _RuleSheet extends ConsumerStatefulWidget {
  const _RuleSheet({
    required this.movement,
    required this.rule,
    required this.custom,
  });

  final Movement movement;
  final ProgressionRule rule;
  final bool custom;

  @override
  ConsumerState<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends ConsumerState<_RuleSheet> {
  late ProgressionRule _rule = widget.rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = ref.watch(weightUnitProvider);
    final timed = widget.movement.isTimed;
    final policies = timed
        ? const [ProgressionPolicy.off, ProgressionPolicy.time]
        : const [
            ProgressionPolicy.off,
            ProgressionPolicy.linear,
            ProgressionPolicy.greyskull,
            ProgressionPolicy.double_,
            ProgressionPolicy.triple,
          ];
    final r = _rule;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          children: [
            Text('Progression', style: theme.textTheme.titleLarge),
            Text(
              'How the next load for ${widget.movement.name} is chosen from '
              'what you logged. The reason is always shown with the '
              'suggestion.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            for (final p in policies)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _rule = r.copyWith(policy: p)),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: r.policy == p
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.cardElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: r.policy == p
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          r.policy == p
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: r.policy == p
                              ? AppColors.primary
                              : AppColors.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                p.description,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            if (r.policy != ProgressionPolicy.off) ...[
              if (!timed) ...[
                _Stepper(
                  label: 'Sets',
                  value: '${r.sets}',
                  onMinus: r.sets > 1
                      ? () =>
                            setState(() => _rule = r.copyWith(sets: r.sets - 1))
                      : null,
                  onPlus: r.sets < 10
                      ? () =>
                            setState(() => _rule = r.copyWith(sets: r.sets + 1))
                      : null,
                ),
                if (r.policy == ProgressionPolicy.triple)
                  _Stepper(
                    label: 'Up to sets',
                    value: '${r.setsMax ?? r.sets + 2}',
                    onMinus: (r.setsMax ?? r.sets + 2) > r.sets
                        ? () => setState(
                            () => _rule = r.copyWith(
                              setsMax: (r.setsMax ?? r.sets + 2) - 1,
                            ),
                          )
                        : null,
                    onPlus: (r.setsMax ?? r.sets + 2) < 12
                        ? () => setState(
                            () => _rule = r.copyWith(
                              setsMax: (r.setsMax ?? r.sets + 2) + 1,
                            ),
                          )
                        : null,
                  ),
                if (r.policy == ProgressionPolicy.double_ ||
                    r.policy == ProgressionPolicy.triple)
                  _Stepper(
                    label: 'Reps from',
                    value: '${r.repsMin}',
                    onMinus: r.repsMin > 1
                        ? () => setState(
                            () => _rule = r.copyWith(repsMin: r.repsMin - 1),
                          )
                        : null,
                    onPlus: r.repsMin < r.repsMax - 1
                        ? () => setState(
                            () => _rule = r.copyWith(repsMin: r.repsMin + 1),
                          )
                        : null,
                  ),
                _Stepper(
                  label:
                      r.policy == ProgressionPolicy.double_ ||
                          r.policy == ProgressionPolicy.triple
                      ? 'Reps to'
                      : 'Reps per set',
                  value: '${r.repsMax}',
                  onMinus:
                      r.repsMax >
                          (r.policy == ProgressionPolicy.double_ ||
                                  r.policy == ProgressionPolicy.triple
                              ? r.repsMin + 1
                              : 1)
                      ? () => setState(
                          () => _rule = r.copyWith(repsMax: r.repsMax - 1),
                        )
                      : null,
                  onPlus: r.repsMax < 30
                      ? () => setState(
                          () => _rule = r.copyWith(repsMax: r.repsMax + 1),
                        )
                      : null,
                ),
                _Stepper(
                  label: 'Weight step',
                  value: unit.format(r.incrementKg),
                  onMinus: r.incrementKg > 0.5
                      ? () => setState(
                          () => _rule = r.copyWith(
                            incrementKg: (r.incrementKg - 0.5).clamp(0.5, 20),
                          ),
                        )
                      : null,
                  onPlus: r.incrementKg < 20
                      ? () => setState(
                          () => _rule = r.copyWith(
                            incrementKg: (r.incrementKg + 0.5).clamp(0.5, 20),
                          ),
                        )
                      : null,
                ),
              ] else ...[
                _Stepper(
                  label: 'Hold (s)',
                  value: '${r.seconds}',
                  onMinus: r.seconds > 10
                      ? () => setState(
                          () => _rule = r.copyWith(seconds: r.seconds - 5),
                        )
                      : null,
                  onPlus: r.seconds < 300
                      ? () => setState(
                          () => _rule = r.copyWith(seconds: r.seconds + 5),
                        )
                      : null,
                ),
                _Stepper(
                  label: 'Grow by (s)',
                  value: '${r.secondsStep}',
                  onMinus: r.secondsStep > 1
                      ? () => setState(
                          () => _rule = r.copyWith(
                            secondsStep: r.secondsStep - 1,
                          ),
                        )
                      : null,
                  onPlus: r.secondsStep < 30
                      ? () => setState(
                          () => _rule = r.copyWith(
                            secondsStep: r.secondsStep + 1,
                          ),
                        )
                      : null,
                ),
              ],
              if (r.policy != ProgressionPolicy.greyskull)
                _Stepper(
                  label: 'Deload after misses',
                  value: '${r.stallLimit}',
                  onMinus: r.stallLimit > 1
                      ? () => setState(
                          () =>
                              _rule = r.copyWith(stallLimit: r.stallLimit - 1),
                        )
                      : null,
                  onPlus: r.stallLimit < 6
                      ? () => setState(
                          () =>
                              _rule = r.copyWith(stallLimit: r.stallLimit + 1),
                        )
                      : null,
                ),
              _Stepper(
                label: 'Deload by',
                value: '${(r.deloadFraction * 100).round()} %',
                onMinus: r.deloadFraction > 0.05
                    ? () => setState(
                        () => _rule = r.copyWith(
                          deloadFraction: r.deloadFraction - 0.05,
                        ),
                      )
                    : null,
                onPlus: r.deloadFraction < 0.3
                    ? () => setState(
                        () => _rule = r.copyWith(
                          deloadFraction: r.deloadFraction + 0.05,
                        ),
                      )
                    : null,
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.custom)
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(progressionRulesProvider.notifier)
                          .set(widget.movement.id, null);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Use default'),
                  ),
                const Spacer(),
                SizedBox(
                  width: 160,
                  child: PrimaryButton(
                    label: 'SAVE',
                    height: 50,
                    onPressed: () async {
                      await ref
                          .read(progressionRulesProvider.notifier)
                          .set(widget.movement.id, _rule);
                      if (context.mounted) Navigator.of(context).pop();
                    },
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

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    this.onMinus,
    this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          onPressed: onMinus,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 72,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
