import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../models/user_settings.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../../face/face_providers.dart';
import '../figure/guide_3d.dart';
import '../models/movement.dart';
import '../models/workout_plan.dart';
import '../../strength/strength_providers.dart';
import '../pt_providers.dart';
import 'pt_widgets.dart';

/// The generated session: warm-up, workout and cool-down, with swaps.
class PlanPreviewScreen extends ConsumerWidget {
  const PlanPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(annotatedPlanProvider);
    final profile = ref.watch(gymProfileProvider);
    final faceRegistered = ref.watch(faceRegisteredProvider);
    if (plan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.pt);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final minutes = plan.estimatedTotal.inMinutes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your session'),
        actions: [
          IconButton(
            tooltip: 'Shuffle the plan',
            onPressed: ref.read(ptPlanProvider.notifier).shuffle,
            icon: const Icon(Icons.shuffle_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children:
                    [
                          TrainerBubble(text: plan.rationale),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _Fact(
                                icon: Icons.schedule_rounded,
                                text: '≈ $minutes min',
                              ),
                              const SizedBox(width: 8),
                              _Fact(
                                icon: Icons.format_list_numbered_rounded,
                                text: '${plan.all.length} movements',
                              ),
                              const SizedBox(width: 8),
                              _Fact(
                                icon: Icons.videocam_outlined,
                                text:
                                    '${plan.all.where((i) => i.movement.tracking.usesCamera).length} tracked',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final m in plan.musclesCovered)
                                MuscleChip(m, selected: true),
                            ],
                          ),
                          for (final phase in PlanPhase.values) ...[
                            const SizedBox(height: 22),
                            SectionHeader(
                              '${phase.label} · '
                              '${plan.items(phase).fold<int>(0, (s, i) => s + i.estimated.inSeconds) ~/ 60} min',
                            ),
                            for (final item in plan.items(phase))
                              _PlanItemCard(
                                unit: ref.watch(weightUnitProvider),
                                item: item,
                                profile: profile,
                                onSwap: () {
                                  final ok = ref
                                      .read(ptPlanProvider.notifier)
                                      .swap(item);
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'No alternative for this one with '
                                          'your equipment.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                          ],
                        ]
                        .animate(interval: 35.ms)
                        .fadeIn(duration: 280.ms)
                        .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!faceRegistered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Register your face in Settings to score sessions and '
                        'earn XP. You can still train without it.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  PrimaryButton(
                    label: 'START SESSION',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => context.push(Routes.ptSession),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cardElevated,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanItemCard extends StatelessWidget {
  const _PlanItemCard({
    required this.item,
    required this.profile,
    required this.onSwap,
    required this.unit,
  });

  final PlanItem item;
  final dynamic profile;
  final VoidCallback onSwap;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = item.movement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Guide3D(
                clipId: m.clip,
                interactive: false,
                autoRotate: false,
                showFloor: false,
                compact: true,
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
                    '${item.prescription}'
                    '${item.sets > 1 ? ' · ${item.rest.inSeconds}s rest' : ''}'
                    '${m.tracking.usesCamera ? ' · camera tracked' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (item.suggestedKg != null && item.suggestedKg! > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${unit.format(item.suggestedKg!)}'
                        '${item.suggestionWhy != null ? ' · ${item.suggestionWhy}' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final e in item.equipment)
                        EquipmentChip(type: e, item: profile.item(e)),
                      for (final mg in m.primary.take(2)) MuscleChip(mg),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Swap for another movement',
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
