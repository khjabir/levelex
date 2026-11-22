import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../../pt/models/movement_library.dart';
import '../../pt/models/workout_plan.dart';
import '../models/progression_rule.dart';
import '../models/routine.dart';
import '../strength_providers.dart';

/// Create or edit a routine: days, their exercises, and the schedule.
class RoutineEditScreen extends ConsumerStatefulWidget {
  const RoutineEditScreen({super.key, this.routine});

  final Routine? routine;

  @override
  ConsumerState<RoutineEditScreen> createState() => _RoutineEditScreenState();
}

class _RoutineEditScreenState extends ConsumerState<RoutineEditScreen> {
  late Routine _r;
  late final TextEditingController _name;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _r =
        widget.routine ??
        Routine(
          id: _uuid.v4(),
          name: 'My routine',
          createdAt: DateTime.now(),
          days: [RoutineDay(id: _uuid.v4(), name: 'Day A')],
          weekdays: {DateTime.monday: ''},
        );
    if (widget.routine == null) {
      _r = _r.copyWith(weekdays: {DateTime.monday: _r.days.first.id});
    }
    _name = TextEditingController(text: _r.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routine == null ? 'New routine' : 'Edit routine'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) => _r = _r.copyWith(name: v),
          ),
          const SizedBox(height: 18),
          const SectionHeader('Schedule'),
          SegmentedButton<RoutineSchedule>(
            segments: [
              for (final s in RoutineSchedule.values)
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {_r.schedule},
            onSelectionChanged: (s) =>
                setState(() => _r = _r.copyWith(schedule: s.first)),
          ),
          const SizedBox(height: 6),
          Text(_r.schedule.description, style: theme.textTheme.bodySmall),
          if (_r.schedule == RoutineSchedule.weekdays) ...[
            const SizedBox(height: 12),
            Text(
              'Tap a weekday to cycle through your days.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var w = 1; w <= 7; w++) ...[
                  Expanded(
                    child: _WeekdayCell(
                      weekday: w,
                      routine: _r,
                      onTap: () => _cycleWeekday(w),
                    ),
                  ),
                  if (w < 7) const SizedBox(width: 4),
                ],
              ],
            ),
          ],
          const SizedBox(height: 18),
          SectionHeader(
            'Days',
            trailing: TextButton.icon(
              onPressed: _addDay,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add day'),
            ),
          ),
          for (final day in _r.days)
            _DayCard(
              day: day,
              onRename: () => _renameDay(day),
              onDelete: _r.days.length > 1 ? () => _deleteDay(day) : null,
              onMode: (m) => _updateDay(day.copyWith(mode: m)),
              onMinutes: (min) => _updateDay(day.copyWith(minutes: min)),
              onAddExercise: () => _addExercise(day),
              onEditExercise: (i) => _editExercise(day, i),
              onRemoveExercise: (i) => _updateDay(
                day.copyWith(exercises: [...day.exercises]..removeAt(i)),
              ),
              onMoveExercise: (i, up) {
                final list = [...day.exercises];
                final j = up ? i - 1 : i + 1;
                if (j < 0 || j >= list.length) return;
                final tmp = list[i];
                list[i] = list[j];
                list[j] = tmp;
                _updateDay(day.copyWith(exercises: list));
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: PrimaryButton(
            label: 'SAVE ROUTINE',
            icon: Icons.check_rounded,
            onPressed: _save,
          ),
        ),
      ),
    );
  }

  void _updateDay(RoutineDay day) => setState(() {
    _r = _r.copyWith(days: [for (final d in _r.days) d.id == day.id ? day : d]);
  });

  void _cycleWeekday(int weekday) {
    final ids = _r.days.map((d) => d.id).toList();
    final current = _r.weekdays[weekday];
    final next = current == null
        ? ids.first
        : (ids.indexOf(current) + 1 >= ids.length
              ? null
              : ids[ids.indexOf(current) + 1]);
    final map = Map<int, String>.from(_r.weekdays);
    if (next == null) {
      map.remove(weekday);
    } else {
      map[weekday] = next;
    }
    setState(() => _r = _r.copyWith(weekdays: map));
  }

  Future<void> _addDay() async {
    final letters = 'ABCDEFG';
    final name = 'Day ${letters[_r.days.length.clamp(0, 6)]}';
    setState(() {
      _r = _r.copyWith(
        days: [
          ..._r.days,
          RoutineDay(id: _uuid.v4(), name: name),
        ],
      );
    });
  }

  Future<void> _renameDay(RoutineDay day) async {
    final controller = TextEditingController(text: day.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Day name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) _updateDay(day.copyWith(name: name));
  }

  void _deleteDay(RoutineDay day) {
    setState(() {
      _r = _r.copyWith(
        days: [
          for (final d in _r.days)
            if (d.id != day.id) d,
        ],
        weekdays: {
          for (final e in _r.weekdays.entries)
            if (e.value != day.id) e.key: e.value,
        },
      );
    });
  }

  Future<void> _addExercise(RoutineDay day) async {
    final id = await context.push<String>(Routes.libraryPick);
    if (id == null) return;
    final m = MovementLibrary.byId(id);
    if (m == null) return;
    final ex = m.isTimed
        ? RoutineExercise(
            movementId: id,
            sets: 3,
            repsMin: 0,
            repsMax: 0,
            seconds: m.baseSeconds,
          )
        : RoutineExercise(movementId: id, sets: 3, repsMin: 8, repsMax: 12);
    _updateDay(day.copyWith(exercises: [...day.exercises, ex]));
  }

  Future<void> _editExercise(RoutineDay day, int index) async {
    final ex = day.exercises[index];
    final edited = await showModalBottomSheet<RoutineExercise>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _ExerciseSheet(exercise: ex),
    );
    if (edited == null) return;
    final list = [...day.exercises];
    list[index] = edited;
    _updateDay(day.copyWith(exercises: list));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give the routine a name.')));
      return;
    }
    if (_r.days.every((d) => d.exercises.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise.')),
      );
      return;
    }
    final routine = _r.copyWith(name: name);
    final isNew = widget.routine == null;
    await ref
        .read(routinesProvider.notifier)
        .save(
          routine,
          activate: isNew && ref.read(activeRoutineIdProvider) == null,
        );
    if (mounted) context.pop();
  }
}

class _WeekdayCell extends StatelessWidget {
  const _WeekdayCell({
    required this.weekday,
    required this.routine,
    required this.onTap,
  });

  final int weekday;
  final Routine routine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = routine.day(routine.weekdays[weekday]);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: day == null
              ? AppColors.cardElevated
              : AppColors.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: day == null ? AppColors.outline : AppColors.primary,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat.E()
                    .format(DateTime(2024, 1, weekday))
                    .substring(0, 2),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                day == null ? 'Rest' : _short(day.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: day == null ? AppColors.textMuted : AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _short(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) return name.length > 5 ? name.substring(0, 5) : name;
    return parts.map((p) => p.isEmpty ? '' : p[0]).join().toUpperCase();
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.onRename,
    required this.onDelete,
    required this.onMode,
    required this.onMinutes,
    required this.onAddExercise,
    required this.onEditExercise,
    required this.onRemoveExercise,
    required this.onMoveExercise,
  });

  final RoutineDay day;
  final VoidCallback onRename;
  final VoidCallback? onDelete;
  final ValueChanged<WorkoutMode> onMode;
  final ValueChanged<int> onMinutes;
  final VoidCallback onAddExercise;
  final ValueChanged<int> onEditExercise;
  final ValueChanged<int> onRemoveExercise;
  final void Function(int index, bool up) onMoveExercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onRename,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            day.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Delete day',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<WorkoutMode>(
                      value: day.mode,
                      isExpanded: true,
                      items: [
                        for (final m in WorkoutMode.values)
                          if (m != WorkoutMode.custom)
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                '${m.label} warm-up & cool-down',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                      ],
                      onChanged: (m) => m == null ? null : onMode(m),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: day.minutes > 15
                      ? () => onMinutes(day.minutes - 5)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                ),
                Text('${day.minutes} min', style: theme.textTheme.labelLarge),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: day.minutes < 180
                      ? () => onMinutes(day.minutes + 5)
                      : null,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                ),
              ],
            ),
            const Divider(),
            for (var i = 0; i < day.exercises.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => onEditExercise(i),
                title: Text(
                  MovementLibrary.byId(day.exercises[i].movementId)?.name ??
                      day.exercises[i].movementId,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${day.exercises[i].prescription}'
                  '${day.exercises[i].policy != null ? ' · ${day.exercises[i].policy!.label}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: i == 0 ? null : () => onMoveExercise(i, true),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: i == day.exercises.length - 1
                          ? null
                          : () => onMoveExercise(i, false),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onRemoveExercise(i),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: onAddExercise,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add exercise'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseSheet extends StatefulWidget {
  const _ExerciseSheet({required this.exercise});

  final RoutineExercise exercise;

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  late RoutineExercise _e = widget.exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = MovementLibrary.byId(_e.movementId);
    final timed = _e.seconds != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m?.name ?? _e.movementId, style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            _Row(
              label: 'Sets',
              value: '${_e.sets}',
              onMinus: _e.sets > 1
                  ? () => setState(() => _e = _e.copyWith(sets: _e.sets - 1))
                  : null,
              onPlus: _e.sets < 10
                  ? () => setState(() => _e = _e.copyWith(sets: _e.sets + 1))
                  : null,
            ),
            if (timed)
              _Row(
                label: 'Seconds',
                value: '${_e.seconds}',
                onMinus: (_e.seconds ?? 0) > 10
                    ? () => setState(
                        () => _e = _e.copyWith(seconds: _e.seconds! - 5),
                      )
                    : null,
                onPlus: (_e.seconds ?? 0) < 300
                    ? () => setState(
                        () => _e = _e.copyWith(seconds: _e.seconds! + 5),
                      )
                    : null,
              )
            else ...[
              _Row(
                label: 'Reps from',
                value: '${_e.repsMin}',
                onMinus: _e.repsMin > 1
                    ? () => setState(
                        () => _e = _e.copyWith(repsMin: _e.repsMin - 1),
                      )
                    : null,
                onPlus: _e.repsMin < _e.repsMax
                    ? () => setState(
                        () => _e = _e.copyWith(repsMin: _e.repsMin + 1),
                      )
                    : null,
              ),
              _Row(
                label: 'Reps to',
                value: '${_e.repsMax}',
                onMinus: _e.repsMax > _e.repsMin
                    ? () => setState(
                        () => _e = _e.copyWith(repsMax: _e.repsMax - 1),
                      )
                    : null,
                onPlus: _e.repsMax < 30
                    ? () => setState(
                        () => _e = _e.copyWith(repsMax: _e.repsMax + 1),
                      )
                    : null,
              ),
              const SizedBox(height: 6),
              Text('Progression', style: theme.textTheme.labelLarge),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Exercise default'),
                    selected: _e.policy == null,
                    onSelected: (_) =>
                        setState(() => _e = _e.copyWith(clearPolicy: true)),
                  ),
                  for (final p in const [
                    ProgressionPolicy.linear,
                    ProgressionPolicy.double_,
                    ProgressionPolicy.greyskull,
                    ProgressionPolicy.triple,
                    ProgressionPolicy.off,
                  ])
                    ChoiceChip(
                      label: Text(p.label),
                      selected: _e.policy == p,
                      onSelected: (_) =>
                          setState(() => _e = _e.copyWith(policy: p)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            PrimaryButton(
              label: 'DONE',
              height: 50,
              onPressed: () => Navigator.of(context).pop(_e),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
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
          width: 56,
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
