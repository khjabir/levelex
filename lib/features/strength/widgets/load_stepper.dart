import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/user_settings.dart';

/// A −/+ control for a load in kg, shown in the user's unit, with an
/// optional suggestion line underneath ("Try 22.5 kg: …").
class LoadStepper extends StatelessWidget {
  const LoadStepper({
    super.key,
    required this.valueKg,
    required this.unit,
    required this.onChanged,
    this.stepKg = 2.5,
    this.suggestedKg,
    this.why,
    this.label = 'Load',
    this.trailing,
  });

  final double? valueKg;
  final WeightUnit unit;
  final ValueChanged<double> onChanged;
  final double stepKg;
  final double? suggestedKg;
  final String? why;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = valueKg ?? 0;
    final step = unit == WeightUnit.kg
        ? stepKg
        : unit.toKg(unit.fromKg(stepKg).roundToDouble().clamp(1, 1000));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.textMuted,
                  letterSpacing: 1.4,
                  fontSize: 11,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _Btn(
              icon: Icons.remove_rounded,
              onTap: value - step >= 0
                  ? () => onChanged(_round(value - step))
                  : () => onChanged(0),
              semantic: 'Decrease load',
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _typeValue(context, value),
                child: Column(
                  children: [
                    Text(
                      unit.format(value, withUnit: false),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      unit.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Btn(
              icon: Icons.add_rounded,
              onTap: () => onChanged(_round(value + step)),
              semantic: 'Increase load',
            ),
          ],
        ),
        if (suggestedKg != null && why != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: (valueKg ?? -1) == suggestedKg
                    ? AppColors.primary
                    : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  why!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if ((valueKg ?? -1) != suggestedKg)
                TextButton(
                  onPressed: () => onChanged(suggestedKg!),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text('Use ${unit.format(suggestedKg!)}'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  double _round(double kg) => (kg * 100).round() / 100;

  Future<void> _typeValue(BuildContext context, double current) async {
    final controller =
        TextEditingController(text: unit.format(current, withUnit: false))
          ..selection = TextSelection(
            baseOffset: 0,
            extentOffset: unit.format(current, withUnit: false).length,
          );
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Load in ${unit.label}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: unit.label),
          onSubmitted: (v) =>
              Navigator.of(context)
                  .pop(double.tryParse(v.replaceAll(',', '.'))),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop(double.tryParse(controller.text.replaceAll(',', '.'))),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null && result >= 0) onChanged(_round(unit.toKg(result)));
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.onTap, required this.semantic});

  final IconData icon;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: Material(
        color: AppColors.cardElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
