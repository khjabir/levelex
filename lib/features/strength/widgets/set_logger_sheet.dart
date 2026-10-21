import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../models/user_settings.dart';
import '../../../widgets/primary_button.dart';
import '../../pt/models/movement.dart';
import '../models/lift_log.dart';
import '../strength_providers.dart';

/// Opens the set logger for [movement] and returns the saved entry, or null
/// when dismissed. [template] pre-fills the rows (usually the last session).
Future<LiftEntry?> showSetLoggerSheet(
  BuildContext context, {
  required Movement movement,
  LiftEntry? template,
  double? suggestedKg,
  String? why,
  DateTime? date,
  String? customName,
}) {
  return showModalBottomSheet<LiftEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _SetLoggerSheet(
        movement: movement,
        template: template,
        suggestedKg: suggestedKg,
        why: why,
        date: date,
        customName: customName,
      ),
    ),
  );
}

class _SetLoggerSheet extends ConsumerStatefulWidget {
  const _SetLoggerSheet({
    required this.movement,
    this.template,
    this.suggestedKg,
    this.why,
    this.date,
    this.customName,
  });

  final Movement movement;
  final LiftEntry? template;
  final double? suggestedKg;
  final String? why;
  final DateTime? date;
  final String? customName;

  @override
  ConsumerState<_SetLoggerSheet> createState() => _SetLoggerSheetState();
}

class _SetLoggerSheetState extends ConsumerState<_SetLoggerSheet> {
  late List<LiftSet> _rows;
  late DateTime _date;
  final _note = TextEditingController();

  bool get _timed => widget.movement.isTimed;

  @override
  void initState() {
    super.initState();
    _date = widget.date ?? DateTime.now();
    final t = widget.template;
    if (t != null && t.sets.isNotEmpty) {
      _rows = [
        for (final s in t.sets)
          widget.suggestedKg != null && !s.warmUp
              ? s.copyWith(weightKg: widget.suggestedKg)
              : s,
      ];
    } else {
      final kg = widget.suggestedKg ?? 0;
      _rows = [
        for (var i = 0; i < 3; i++)
          _timed
              ? LiftSet(
                  weightKg: 0,
                  reps: 0,
                  seconds: widget.movement.baseSeconds,
                )
              : LiftSet(weightKg: kg, reps: widget.movement.baseReps),
      ];
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = ref.watch(weightUnitProvider);
    final m = widget.movement;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.customName ?? m.name,
                          style: theme.textTheme.titleLarge,
                        ),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Text(
                            _dateLabel(_date),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.cyan,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (widget.why != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.why!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const SizedBox(width: 34),
                  Expanded(
                    flex: 5,
                    child: Text(
                      m.bodyweight
                          ? '+ ${unit.label.toUpperCase()}'
                          : unit.label.toUpperCase(),
                      style: _colStyle(theme),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: Text(
                      _timed ? 'SECONDS' : 'REPS',
                      textAlign: TextAlign.center,
                      style: _colStyle(theme),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                itemCount: _rows.length,
                itemBuilder: (context, i) => _SetRow(
                  key: ValueKey('row$i${_rows.length}'),
                  index: i,
                  set: _rows[i],
                  unit: unit,
                  timed: _timed,
                  onChanged: (s) => setState(() => _rows[i] = s),
                  onRemove: _rows.length > 1
                      ? () => setState(() => _rows.removeAt(i))
                      : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _rows.add(_rows.last)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add set'),
                  ),
                  const Spacer(),
                  Text(_summary(unit), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: TextField(
                controller: _note,
                decoration: const InputDecoration(
                  hintText: 'Note (optional)',
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PrimaryButton(
                label: 'SAVE',
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _colStyle(ThemeData theme) => theme.textTheme.labelSmall?.copyWith(
    color: AppColors.textMuted,
    letterSpacing: 1.2,
  );

  String _summary(WeightUnit unit) {
    final work = [
      for (final r in _rows)
        if (r.isWork) r,
    ];
    if (_timed) {
      final s = work.fold<int>(0, (a, r) => a + (r.seconds ?? 0));
      return '${work.length} sets · ${s}s';
    }
    final reps = work.fold<int>(0, (a, r) => a + r.reps);
    final vol = work.fold<double>(0, (a, r) => a + r.volume);
    return '${work.length} sets · $reps reps'
        '${vol > 0 ? ' · ${unit.format(vol)}' : ''}';
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today · tap to change date';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final rows = [
      for (final r in _rows)
        if (r.reps > 0 || (r.seconds ?? 0) > 0) r,
    ];
    if (rows.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter at least one set.')));
      return;
    }
    final entry = LiftEntry(
      id: const Uuid().v4(),
      movementId: widget.template?.movementId ?? widget.movement.id,
      customName: widget.customName,
      startTime: _date,
      sets: rows,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      source: LiftSource.manual,
    );
    await ref.read(liftLogProvider.notifier).add(entry);
    if (mounted) Navigator.of(context).pop(entry);
  }
}

class _SetRow extends StatefulWidget {
  const _SetRow({
    super.key,
    required this.index,
    required this.set,
    required this.unit,
    required this.timed,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final LiftSet set;
  final WeightUnit unit;
  final bool timed;
  final ValueChanged<LiftSet> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _weight = TextEditingController(
    text: widget.set.weightKg == 0
        ? ''
        : widget.unit.format(widget.set.weightKg, withUnit: false),
  );

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.set;
    final count = widget.timed ? (s.seconds ?? 0) : s.reps;
    final step = widget.timed ? 5 : 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onChanged(s.copyWith(warmUp: !s.warmUp)),
            child: Tooltip(
              message: s.warmUp
                  ? 'Warm-up set (tap for work set)'
                  : 'Tap to mark as warm-up',
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.warmUp
                      ? AppColors.warning.withValues(alpha: 0.2)
                      : AppColors.cardElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s.warmUp ? 'W' : '${widget.index + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: s.warmUp ? AppColors.warning : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v.replaceAll(',', '.'));
                if (parsed != null && parsed >= 0) {
                  widget.onChanged(
                    s.copyWith(
                      weightKg:
                          ((widget.unit.toKg(parsed)) * 100).round() / 100,
                    ),
                  );
                } else if (v.isEmpty) {
                  widget.onChanged(s.copyWith(weightKg: 0));
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: count - step >= 0
                      ? () => widget.onChanged(_withCount(s, count - step))
                      : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 22),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      widget.onChanged(_withCount(s, count + step)),
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: widget.onRemove == null
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove set',
                    onPressed: widget.onRemove,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  LiftSet _withCount(LiftSet s, int value) =>
      widget.timed ? s.copyWith(seconds: value) : s.copyWith(reps: value);
}
