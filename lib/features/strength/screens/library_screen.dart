import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/section_header.dart';
import '../../pt/mannequin/mannequin_3d.dart';
import '../../pt/models/movement.dart';
import '../../pt/models/movement_library.dart';
import '../../pt/models/muscle_group.dart';
import '../../pt/pt_providers.dart';
import '../../pt/screens/pt_widgets.dart';
import '../models/lift_log.dart';
import '../strength_providers.dart';

/// Every movement the coach knows, browsable by muscle and equipment, with
/// the 3D guide and your history. In [pickMode] a tap returns the id.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  MuscleGroup? _muscle;
  bool _myGymOnly = false;
  bool _loggedOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lifts = ref.watch(liftLogProvider);
    final available = ref.watch(gymProfileProvider).available;
    final unit = ref.watch(weightUnitProvider);
    final query = _search.text.trim().toLowerCase();

    final lastByMovement = <String, LiftEntry>{};
    for (final e in lifts) {
      lastByMovement[e.movementId] = e; // chronological: last wins
    }

    bool matches(Movement m) {
      if (query.isNotEmpty &&
          !m.name.toLowerCase().contains(query) &&
          !m.primary.any((g) => g.label.toLowerCase().contains(query))) {
        return false;
      }
      if (_muscle != null && !m.muscles.contains(_muscle)) return false;
      if (_myGymOnly && !m.canDoWith(available)) return false;
      if (_loggedOnly && !lastByMovement.containsKey(m.id)) return false;
      return true;
    }

    final all = MovementLibrary.all.where(matches).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final main = [
      for (final m in all)
        if (m.phases.contains(PlanPhase.main)) m,
    ];
    final warm = [
      for (final m in all)
        if (!m.phases.contains(PlanPhase.main) &&
            m.phases.contains(PlanPhase.warmUp))
          m,
    ];
    final cool = [
      for (final m in all)
        if (!m.phases.contains(PlanPhase.main) &&
            !m.phases.contains(PlanPhase.warmUp))
          m,
    ];
    final custom = <String, LiftEntry>{
      for (final e in lifts)
        if (e.isCustom &&
            (query.isEmpty || e.name.toLowerCase().contains(query)) &&
            _muscle == null)
          e.movementId: e,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Pick an exercise' : 'Exercise library'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search ${MovementLibrary.all.length} movements',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close_rounded),
                      ),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              children: [
                _FilterChip(
                  label: 'My gym',
                  icon: Icons.fitness_center_rounded,
                  selected: _myGymOnly,
                  onTap: () => setState(() => _myGymOnly = !_myGymOnly),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Logged',
                  icon: Icons.history_rounded,
                  selected: _loggedOnly,
                  onTap: () => setState(() => _loggedOnly = !_loggedOnly),
                ),
                const SizedBox(width: 10),
                for (final g in MuscleGroup.values) ...[
                  MuscleChip(
                    g,
                    selected: _muscle == g,
                    onTap: () =>
                        setState(() => _muscle = _muscle == g ? null : g),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: all.isEmpty && custom.isEmpty
                ? Center(
                    child: Text(
                      'Nothing matches. Try another muscle or clear the '
                      'filters.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      if (custom.isNotEmpty) ...[
                        const SectionHeader('Your exercises'),
                        for (final e in custom.values)
                          _CustomTile(
                            entry: e,
                            unit: unit,
                            onTap: () => _open(e.movementId),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (main.isNotEmpty) ...[
                        SectionHeader('Workout · ${main.length}'),
                        for (final m in main)
                          _MovementTile(
                            movement: m,
                            last: lastByMovement[m.id],
                            unit: unit,
                            doable: m.canDoWith(available),
                            onTap: () => _open(m.id),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (warm.isNotEmpty) ...[
                        SectionHeader('Warm-up · ${warm.length}'),
                        for (final m in warm)
                          _MovementTile(
                            movement: m,
                            last: lastByMovement[m.id],
                            unit: unit,
                            doable: m.canDoWith(available),
                            onTap: () => _open(m.id),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (cool.isNotEmpty) ...[
                        SectionHeader('Cool-down · ${cool.length}'),
                        for (final m in cool)
                          _MovementTile(
                            movement: m,
                            last: lastByMovement[m.id],
                            unit: unit,
                            doable: m.canDoWith(available),
                            onTap: () => _open(m.id),
                          ),
                      ],
                    ].animate(interval: 20.ms).fadeIn(duration: 220.ms),
                  ),
          ),
        ],
      ),
    );
  }

  void _open(String movementId) {
    if (widget.pickMode) {
      context.pop(movementId);
      return;
    }
    context.push(Routes.movement(movementId));
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? AppColors.onPrimary : AppColors.textSecondary,
      ),
      label: Text(label),
      showCheckmark: false,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? AppColors.onPrimary : AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.outline),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.movement,
    required this.last,
    required this.unit,
    required this.doable,
    required this.onTap,
  });

  final Movement movement;
  final LiftEntry? last;
  final dynamic unit;
  final bool doable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = movement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Mannequin3D(
                clipId: m.clip,
                interactive: false,
                autoRotate: false,
                showFloor: false,
                compact: true,
                playing: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      m.primary.map((g) => g.label).join(', '),
                      if (m.bodyweight)
                        'bodyweight'
                      else
                        m.equipmentOptions
                            .map((o) => o.map((e) => e.label).join(' + '))
                            .join(' / '),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (last != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Last: ${_lastLabel(last!, m)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!doable)
              const Tooltip(
                message: 'Needs equipment your gym does not list',
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  String _lastLabel(LiftEntry e, Movement m) {
    final work = e.workSets;
    if (work.isEmpty) return '—';
    if (m.isTimed) {
      return '${work.length} × ${work.map((s) => s.seconds ?? 0).reduce((a, b) => a > b ? a : b)}s';
    }
    final top = e.topWeight;
    final reps = work.map((s) => s.reps).join('/');
    return top > 0 ? '${unit.format(top)} × $reps' : '$reps reps';
  }
}

class _CustomTile extends StatelessWidget {
  const _CustomTile({
    required this.entry,
    required this.unit,
    required this.onTap,
  });

  final LiftEntry entry;
  final dynamic unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            const Icon(Icons.person_outline_rounded, color: AppColors.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Imported · last ${entry.topWeight > 0 ? unit.format(entry.topWeight) : '${entry.totalReps} reps'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
