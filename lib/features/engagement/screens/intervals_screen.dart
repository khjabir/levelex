import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../../pt/figure/guide_3d.dart';
import '../../pt/models/movement.dart';
import '../../pt/models/movement_library.dart';
import '../../pt/models/workout_plan.dart';
import '../../pt/pt_providers.dart';

/// A named interval format.
class IntervalPreset {
  const IntervalPreset({
    required this.id,
    required this.name,
    required this.tagline,
    required this.workSeconds,
    required this.restSeconds,
    required this.rounds,
    required this.movementIds,
    this.repsPerRound,
  });

  final String id;
  final String name;
  final String tagline;
  final int workSeconds;
  final int restSeconds;
  final int rounds;
  final List<String> movementIds;

  /// EMOM-style: a rep count per round instead of a work clock.
  final int? repsPerRound;

  int get totalSeconds => rounds * (workSeconds + restSeconds);

  static const all = [
    IntervalPreset(
      id: 'tabata',
      name: 'Tabata',
      tagline: '20 s on, 10 s off, 8 rounds. Four brutal minutes.',
      workSeconds: 20,
      restSeconds: 10,
      rounds: 8,
      movementIds: ['burpee', 'squat', 'mountain_climbers', 'jumping_jack'],
    ),
    IntervalPreset(
      id: 'hiit',
      name: 'HIIT 30/15',
      tagline: '30 s work, 15 s rest, 10 rounds. Full body cardio.',
      workSeconds: 30,
      restSeconds: 15,
      rounds: 10,
      movementIds: ['high_knees', 'push_up', 'squat_jump', 'plank', 'lunge'],
    ),
    IntervalPreset(
      id: 'emom',
      name: 'EMOM 10',
      tagline: 'Every minute on the minute: 12 reps, rest what is left.',
      workSeconds: 60,
      restSeconds: 0,
      rounds: 10,
      movementIds: ['squat', 'push_up'],
      repsPerRound: 12,
    ),
    IntervalPreset(
      id: 'amrap',
      name: 'AMRAP 12',
      tagline: 'As many rounds as possible in 12 minutes.',
      workSeconds: 60,
      restSeconds: 0,
      rounds: 12,
      movementIds: ['squat', 'push_up', 'sit_up', 'lunge'],
    ),
    IntervalPreset(
      id: 'core',
      name: 'Core 40/20',
      tagline: '40 s on, 20 s off through the trunk. 8 rounds.',
      workSeconds: 40,
      restSeconds: 20,
      rounds: 8,
      movementIds: [
        'plank',
        'sit_up',
        'side_plank',
        'mountain_climbers',
        'bird_dog',
      ],
    ),
  ];
}

/// Build-your-own interval session: pick a format, tune work, rest and
/// rounds, choose the movements, and run it through the MY PT engine with
/// the camera, voice cues, logging and XP.
class IntervalsScreen extends ConsumerStatefulWidget {
  const IntervalsScreen({super.key});

  @override
  ConsumerState<IntervalsScreen> createState() => _IntervalsScreenState();
}

class _IntervalsScreenState extends ConsumerState<IntervalsScreen> {
  IntervalPreset _preset = IntervalPreset.all.first;
  late int _work = _preset.workSeconds;
  late int _rest = _preset.restSeconds;
  late int _rounds = _preset.rounds;
  late List<String> _movements = List.of(_preset.movementIds);
  late int? _reps = _preset.repsPerRound;

  void _apply(IntervalPreset p) => setState(() {
    _preset = p;
    _work = p.workSeconds;
    _rest = p.restSeconds;
    _rounds = p.rounds;
    _movements = List.of(p.movementIds);
    _reps = p.repsPerRound;
  });

  int get _total => _rounds * (_work + _rest);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final movements = [
      for (final id in _movements)
        if (MovementLibrary.byId(id) != null) MovementLibrary.byId(id)!,
    ];
    final minutes = (_total / 60).ceil();
    return Scaffold(
      appBar: AppBar(title: const Text('Intervals')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children:
                  [
                        const SectionHeader('Format'),
                        SizedBox(
                          height: 104,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: IntervalPreset.all.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final p = IntervalPreset.all[i];
                              final selected = p.id == _preset.id;
                              return SizedBox(
                                width: 170,
                                child: AppCard(
                                  onTap: () => _apply(p),
                                  glow: selected,
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: selected
                                                  ? AppColors.primary
                                                  : null,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: Text(
                                          p.tagline,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SectionHeader('Timing'),
                        AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                          child: Column(
                            children: [
                              _Stepper(
                                label: _reps != null ? 'Minute' : 'Work',
                                value: '$_work s',
                                onMinus: _work > 10
                                    ? () => setState(() => _work -= 5)
                                    : null,
                                onPlus: _work < 300
                                    ? () => setState(() => _work += 5)
                                    : null,
                              ),
                              if (_reps != null)
                                _Stepper(
                                  label: 'Reps each minute',
                                  value: '$_reps',
                                  onMinus: _reps! > 1
                                      ? () => setState(() => _reps = _reps! - 1)
                                      : null,
                                  onPlus: _reps! < 50
                                      ? () => setState(() => _reps = _reps! + 1)
                                      : null,
                                )
                              else
                                _Stepper(
                                  label: 'Rest',
                                  value: '$_rest s',
                                  onMinus: _rest > 0
                                      ? () => setState(() => _rest -= 5)
                                      : null,
                                  onPlus: _rest < 180
                                      ? () => setState(() => _rest += 5)
                                      : null,
                                ),
                              _Stepper(
                                label: 'Rounds',
                                value: '$_rounds',
                                onMinus: _rounds > 1
                                    ? () => setState(() => _rounds--)
                                    : null,
                                onPlus: _rounds < 40
                                    ? () => setState(() => _rounds++)
                                    : null,
                              ),
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 4, 8, 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.timer_outlined,
                                      size: 18,
                                      color: AppColors.cyan,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'About $minutes min · '
                                        '${movements.length} movement'
                                        '${movements.length == 1 ? '' : 's'} '
                                        'in rotation',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _reps = _reps == null ? 12 : null;
                                        if (_reps != null) {
                                          _work = 60;
                                          _rest = 0;
                                        }
                                      }),
                                      child: Text(
                                        _reps == null
                                            ? 'Switch to EMOM'
                                            : 'Switch to clock',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SectionHeader(
                          'Movements',
                          trailing: TextButton.icon(
                            onPressed: _addMovement,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add'),
                          ),
                        ),
                        if (movements.isEmpty)
                          AppCard(
                            child: Text(
                              'Add at least one movement.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        for (var i = 0; i < movements.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Guide3D(
                                      clipId: movements[i].clip,
                                      interactive: false,
                                      autoRotate: false,
                                      showFloor: false,
                                      compact: true,
                                      playing: false,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          movements[i].name,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        Text(
                                          movements[i].tracking.usesCamera
                                              ? 'camera counts reps'
                                              : 'on the clock',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: movements.length > 1
                                        ? () => setState(
                                            () => _movements.removeAt(i),
                                          )
                                        : null,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'Rounds rotate through the movements in order. The '
                          'camera stays on, counting reps where it can; timed '
                          'moves run on the clock. The session is logged and '
                          'earns XP like any MY PT session.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ]
                      .animate(interval: 40.ms)
                      .fadeIn(duration: 240.ms)
                      .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: PrimaryButton(
                label: 'START ${_preset.name.toUpperCase()}',
                icon: Icons.play_arrow_rounded,
                onPressed: movements.isEmpty ? null : () => _start(movements),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMovement() async {
    final id = await context.push<String>(Routes.libraryPick);
    // Only library movements can run as intervals (an unknown id would sit
    // hidden in the list and shift the remove buttons).
    if (id == null || !mounted || MovementLibrary.byId(id) == null) return;
    setState(() => _movements.add(id));
  }

  void _start(List<Movement> movements) {
    final profile = ref.read(gymProfileProvider);
    final level = ref.read(ptRequestProvider).level;
    final fixed = <FixedItem>[];
    for (var r = 0; r < _rounds; r++) {
      final m = movements[r % movements.length];
      final reps = _reps;
      fixed.add(
        FixedItem(
          movementId: m.id,
          sets: 1,
          // Clock rounds: a generous rep target so the clock, not the
          // count, ends the round; EMOM: the rep count, then rest the
          // remainder of the minute.
          reps: reps ?? (m.isTimed ? 0 : (_work / m.secondsPerRep * 2).ceil()),
          seconds: _work,
          restSeconds: reps != null ? 0 : _rest,
          capSeconds: m.isTimed ? null : _work,
        ),
      );
    }
    ref
        .read(ptPlanProvider.notifier)
        .generate(
          PtRequest(
            duration: Duration(seconds: _total),
            mode: WorkoutMode.hiit,
            level: level,
            equipment: profile.available,
            fixed: fixed,
            bare: true,
            quick: true,
            title: _preset.name,
          ),
        );
    context.push(Routes.ptSession);
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
          width: 64,
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
