import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../logic/plates.dart';
import '../strength_providers.dart';

/// Shows which plates to load per side for [targetKg]; the chosen bar is
/// remembered for the session.
Future<void> showPlateSheet(BuildContext context, {required double targetKg}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _PlateSheet(targetKg: targetKg),
  );
}

class _PlateSheet extends ConsumerStatefulWidget {
  const _PlateSheet({required this.targetKg});

  final double targetKg;

  @override
  ConsumerState<_PlateSheet> createState() => _PlateSheetState();
}

class _PlateSheetState extends ConsumerState<_PlateSheet> {
  static BarType _bar = BarType.olympic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = ref.watch(weightUnitProvider);
    final load = PlateCalculator.solve(
      targetKg: widget.targetKg,
      barKg: _bar.kg,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Load ${unit.format(widget.targetKg)}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in BarType.values)
                  ChoiceChip(
                    label: Text('${b.label} ${unit.format(b.kg)}'),
                    selected: _bar == b,
                    onSelected: (_) => setState(() => _bar = b),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: _BarDiagram(load: load, unit: unit),
            ),
            const SizedBox(height: 12),
            Text(
              load.perSide.isEmpty
                  ? (load.remainderKg < 0
                        ? 'The bar alone is heavier than the target.'
                        : 'Empty bar.')
                  : '${load.perSide.map((p) => unit.format(p, withUnit: false)).join(' + ')} '
                        '${unit.label} per side',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            if (load.remainderKg.abs() > 0.01)
              Text(
                load.remainderKg > 0
                    ? 'Closest with standard plates: '
                          '${unit.format(load.achievedKg)} '
                          '(${unit.format(load.remainderKg)} short).'
                    : 'Bar weighs ${unit.format(load.barKg)}.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              'Standard plates: ${PlateCalculator.standardKg.map((p) => unit.format(p, withUnit: false)).join(', ')} ${unit.label}.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarDiagram extends StatelessWidget {
  const _BarDiagram({required this.load, required this.unit});

  final PlateLoad load;
  final dynamic unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plates = load.perSide;
    final maxW = plates.isEmpty ? 25.0 : plates.first;
    return SizedBox(
      height: 120,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 30, height: 10, color: AppColors.textMuted),
          for (final p in plates.reversed)
            Container(
              width: p >= 10 ? 18 : 12,
              height: 40 + 80 * (p / maxW).clamp(0.2, 1.0),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _plateColor(p),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black26),
              ),
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  unit.format(p, withUnit: false),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          Container(width: 110, height: 10, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Color _plateColor(double kg) {
    if (kg >= 25) return const Color(0xFFE53935);
    if (kg >= 20) return const Color(0xFF1E88E5);
    if (kg >= 15) return const Color(0xFFFDD835);
    if (kg >= 10) return const Color(0xFF43A047);
    if (kg >= 5) return const Color(0xFFEEEEEE);
    return const Color(0xFFBDBDBD);
  }
}
