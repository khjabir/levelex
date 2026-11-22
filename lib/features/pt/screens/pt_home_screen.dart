import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/levels/level_system.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../models/muscle_group.dart';
import '../models/pt_record.dart';
import '../models/workout_plan.dart';
import '../planner/coach_voice.dart';
import '../../strength/strength_providers.dart';
import '../pt_providers.dart';
import 'pt_widgets.dart';

/// MY PT: tell the trainer how long you have, what to train and what you
/// have, and get a guided session.
class PtHomeScreen extends ConsumerWidget {
  const PtHomeScreen({super.key});

  static const durations = [10, 15, 20, 30, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final request = ref.watch(ptRequestProvider);
    final profile = ref.watch(gymProfileProvider);
    final records = ref.watch(ptRecordsProvider);
    final level = ref.watch(levelProvider);
    final now = ref.watch(clockProvider);
    final recent = records.reversed.take(5).toList();
    final notifier = ref.read(ptRequestProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const TrainerAvatar(size: 32),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('MY PT', maxLines: 1),
                  Text(
                    'AI-assisted personal trainer · on-device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children:
              [
                    TrainerBubble(
                      text:
                          '${CoachVoice.greeting(now, title: level.title)} '
                          'Tell me how long you have and what we are '
                          'training, and I will build the session, walk you '
                          'through every movement and watch your form.',
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader('How long do you have?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in durations)
                          _Choice(
                            label: '$m min',
                            selected: request.duration.inMinutes == m,
                            onTap: () => notifier.update(
                              (r) => r.copyWith(duration: Duration(minutes: m)),
                            ),
                          ),

                        _Choice(
                          label: durations.contains(request.duration.inMinutes)
                              ? 'Custom'
                              : 'Custom · ${request.duration.inMinutes} min',

                          selected: !durations.contains(
                            request.duration.inMinutes,
                          ),

                          onTap: () async {
                            final minutes = await _askMinutes(
                              context,

                              request.duration.inMinutes,
                            );

                            if (minutes != null) {
                              notifier.update(
                                (r) => r.copyWith(
                                  duration: Duration(minutes: minutes),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader('What are we training?'),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      // Taller cards as the text grows, so the description
                      // never clips (1.9 clipped even at the default size
                      // on a 360 dp phone).
                      childAspectRatio:
                          1.55 /
                          MediaQuery.textScalerOf(context)
                              .scale(1)
                              .clamp(1.0, 2.0),
                      children: [
                        for (final mode in WorkoutMode.values)
                          _ModeCard(
                            mode: mode,
                            selected: request.mode == mode,
                            onTap: () =>
                                notifier.update((r) => r.copyWith(mode: mode)),
                          ),
                      ],
                    ),
                    if (request.mode == WorkoutMode.custom) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in MuscleGroup.values)
                            MuscleChip(
                              m,
                              selected: request.focus.contains(m),
                              onTap: () => notifier.update(
                                (r) => r.copyWith(
                                  focus: r.focus.contains(m)
                                      ? (r.focus.toSet()..remove(m))
                                      : {...r.focus, m},
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const SectionHeader('Your level'),
                    SegmentedButton<PtLevel>(
                      segments: [
                        for (final l in PtLevel.values)
                          ButtonSegment(value: l, label: Text(l.label)),
                      ],
                      selected: {request.level},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          notifier.update((r) => r.copyWith(level: s.first)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      request.level.description,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader('Programmes'),
                    AppCard(
                      onTap: () => context.push(Routes.routines),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ref.watch(activeRoutineProvider)?.name ??
                                      'Follow a weekly plan',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                  ref.watch(activeRoutineProvider) == null
                                      ? 'Push/Pull/Legs, Upper/Lower, Full '
                                            'Body or 5×5, with loads that '
                                            'climb session by session.'
                                      : 'Loads progress automatically from '
                                            'what you log.',
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
                    const SizedBox(height: 24),
                    const SectionHeader('Your gym'),
                    AppCard(
                      onTap: () => context.push(Routes.ptEquipment),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.fitness_center_rounded,
                              color: AppColors.secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.bodyweightOnly
                                      ? 'Bodyweight only'
                                      : '${profile.items.length} items available',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                  profile.bodyweightOnly
                                      ? 'Add your equipment and photos so I can '
                                            'plan with it and point you to it.'
                                      : profile.items
                                            .map((i) => i.type.label)
                                            .join(', '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'BUILD MY SESSION',
                      icon: Icons.auto_awesome_rounded,
                      onPressed:
                          request.mode == WorkoutMode.custom &&
                              request.focus.isEmpty
                          ? null
                          : () {
                              ref
                                  .read(ptPlanProvider.notifier)
                                  .generate(
                                    request.copyWith(
                                      equipment: profile.available,
                                    ),
                                  );
                              context.push(Routes.ptPlan);
                            },
                    ),
                    if (recent.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const SectionHeader('Recent sessions'),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < recent.length; i++) ...[
                              if (i > 0)
                                const Divider(indent: 20, endIndent: 20),
                              PtRecordTile(record: recent[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ]
                  .animate(interval: 40.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05, end: 0, curve: AppTokens.curve),
        ),
      ),
    );
  }
}

/// Asks for a session length in minutes (5–180).
Future<int?> _askMinutes(BuildContext context, int initial) {
  final controller = TextEditingController(text: '$initial')
    ..selection = TextSelection(baseOffset: 0, extentOffset: '$initial'.length);
  String? error;
  int? parse() {
    final v = int.tryParse(controller.text.trim());
    return v == null || v < 5 || v > 180 ? null : v;
  }

  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Custom session length'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Minutes',
            helperText: '5 to 180 minutes',
            errorText: error,
          ),
          onSubmitted: (_) {
            final v = parse();
            if (v == null) {
              setState(() => error = 'Enter 5–180 minutes');
            } else {
              Navigator.of(context).pop(v);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = parse();
              if (v == null) {
                setState(() => error = 'Enter 5–180 minutes');
              } else {
                Navigator.of(context).pop(v);
              }
            },
            child: const Text('Use'),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTokens.fast,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.brandGradient : null,
            color: selected ? null : AppColors.cardElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final WorkoutMode mode;
  final bool selected;
  final VoidCallback onTap;

  static IconData _icon(WorkoutMode m) => switch (m) {
    WorkoutMode.push => Icons.arrow_upward_rounded,
    WorkoutMode.pull => Icons.arrow_downward_rounded,
    WorkoutMode.legs => Icons.directions_walk_rounded,
    WorkoutMode.upper => Icons.accessibility_new_rounded,
    WorkoutMode.lower => Icons.airline_seat_legroom_extra_rounded,
    WorkoutMode.fullBody => Icons.sports_gymnastics_rounded,
    WorkoutMode.core => Icons.center_focus_strong_rounded,
    WorkoutMode.hiit => Icons.bolt_rounded,
    WorkoutMode.mobility => Icons.self_improvement_rounded,
    WorkoutMode.custom => Icons.tune_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label}: ${mode.description}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTokens.normal,
          curve: AppTokens.curve,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _icon(mode),
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      mode.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One MY PT session in a list: mode, length, progress and XP.
class PtRecordTile extends StatelessWidget {
  const PtRecordTile({super.key, required this.record});

  final PtRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final xp = LevelSystem.xpForPtRecord(record);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          size: 18,
          color: AppColors.primary,
        ),
      ),
      title: Text(
        '${record.mode.label} · ${record.duration.inMinutes} min',
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        '${DateFormat.MMMd().add_jm().format(record.startTime)} · '
        '${record.itemsDone}/${record.itemCount} movements'
        '${record.verified ? '' : ' · not scored'}',
      ),
      trailing: xp > 0
          ? Text(
              '+$xp XP',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
              ),
            )
          : null,
    );
  }
}
