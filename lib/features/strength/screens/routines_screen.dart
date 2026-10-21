import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../../pt/pt_providers.dart';
import '../logic/routine_launcher.dart';
import '../logic/routine_schedule.dart';
import '../logic/starter_plans.dart';
import '../models/routine.dart';
import '../strength_providers.dart';

/// Weekly programmes: pick a starter plan or build your own, choose the one
/// the home screen follows, and start today's day.
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final routines = ref.watch(routinesProvider);
    final activeId = ref.watch(activeRoutineIdProvider);
    final runs = ref.watch(routineRunsProvider);
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Programmes'),
        actions: [
          IconButton(
            tooltip: 'New routine',
            onPressed: () => context.push(Routes.routineEdit),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children:
            [
                  if (routines.isEmpty)
                    AppCard(
                      glow: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Train on a plan',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'A programme repeats the same days every week so '
                            'loads can climb session by session. Start from '
                            'a proven template, fitted to your equipment, '
                            'or build your own.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  if (routines.isEmpty) const SizedBox(height: 14),
                  const SectionHeader('Start from a template'),
                  for (final plan in StarterPlans.all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        onTap: () => _useTemplate(context, ref, plan),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plan.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${plan.tagline} · ${plan.daysPerWeek} days a week',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.add_circle_outline_rounded,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (routines.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const SectionHeader('Your routines'),
                    for (final r in routines)
                      _RoutineCard(
                        routine: r,
                        active: r.id == activeId,
                        todayDay: RoutineScheduler.dayFor(r, today, runs),
                        weekDone: RoutineScheduler.weekProgress(r, today, runs),
                        onActivate: () => ref
                            .read(activeRoutineIdProvider.notifier)
                            .set(r.id == activeId ? null : r.id),
                        onEdit: () =>
                            context.push(Routes.routineEdit, extra: r),
                        onDelete: () => _delete(context, ref, r),
                        onStart: (day) => startRoutineDay(context, ref, r, day),
                      ),
                  ],
                ]
                .animate(interval: 40.ms)
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
      ),
    );
  }

  Future<void> _useTemplate(
    BuildContext context,
    WidgetRef ref,
    StarterPlan plan,
  ) async {
    final available = ref.read(gymProfileProvider).available;
    final routine = plan.build(available, newId: () => const Uuid().v4());
    if (routine.days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing in this plan fits your equipment yet.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(plan.name),
        content: Text(
          '${routine.days.length} days fitted to your gym'
          '${available.isEmpty ? ' (bodyweight only)' : ''}:\n\n'
          '${routine.days.map((d) => '• ${d.name}: ${d.exercises.length} exercises').join('\n')}'
          '\n\nMake it your active programme? You can edit every day '
          'afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use this plan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(routinesProvider.notifier).save(routine, activate: true);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Routine r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${r.name}?'),
        content: const Text('Your logged sessions are kept.'),
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
    if (ok == true) await ref.read(routinesProvider.notifier).remove(r.id);
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.active,
    required this.todayDay,
    required this.weekDone,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
    required this.onStart,
  });

  final Routine routine;
  final bool active;
  final RoutineDay? todayDay;
  final int weekDone;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<RoutineDay> onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = routine;
    final schedule = r.schedule == RoutineSchedule.rotation
        ? 'Rotation · ${r.days.map((d) => d.name).join(' → ')}'
        : r.trainingWeekdays
              .map((w) => DateFormat.E().format(DateTime(2024, 1, w)))
              .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        glow: active,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${r.days.length} days · $schedule',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'edit' => onEdit(),
                    'delete' => onDelete(),
                    _ => onActivate(),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'activate',
                      child: Text(active ? 'Stop following' : 'Follow this'),
                    ),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in r.days)
                  ActionChip(
                    label: Text(d.name),
                    avatar: Icon(
                      Icons.play_arrow_rounded,
                      size: 16,
                      color: d.id == todayDay?.id
                          ? AppColors.onPrimary
                          : AppColors.textSecondary,
                    ),
                    backgroundColor: d.id == todayDay?.id
                        ? AppColors.primary
                        : null,
                    labelStyle: TextStyle(
                      color: d.id == todayDay?.id
                          ? AppColors.onPrimary
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    onPressed: () => onStart(d),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  active ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 16,
                  color: active ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    active
                        ? 'Following · $weekDone of ${r.schedule == RoutineSchedule.rotation ? r.days.length : r.trainingWeekdays.length} this week'
                        : 'Not followed',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (todayDay != null)
                  SizedBox(
                    width: 130,
                    child: PrimaryButton(
                      label: 'START',
                      height: 40,
                      icon: Icons.play_arrow_rounded,
                      onPressed: () => onStart(todayDay!),
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
