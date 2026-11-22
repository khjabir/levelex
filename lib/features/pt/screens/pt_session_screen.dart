import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/levels/level_system.dart';
import '../../../models/coaching.dart';
import '../../../models/form_status.dart';
import '../../../widgets/animated_progress_bar.dart';
import '../../../widgets/badge_tile.dart';
import '../../../widgets/share_card.dart';
import '../../../widgets/share_sheet.dart';
import '../../engagement/engagement_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/celebration.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/progress_ring.dart';
import '../../../widgets/section_header.dart';
import '../../workout/widgets/camera_preview_fill.dart';
import '../../workout/widgets/coach_card.dart';
import '../../workout/widgets/pose_painter.dart';
import '../figure/guide_3d.dart';
import '../../strength/models/progression_rule.dart';
import '../../strength/strength_providers.dart';
import '../../strength/widgets/load_stepper.dart';
import '../../strength/widgets/plate_sheet.dart';
import '../models/equipment.dart';
import '../models/movement.dart';
import '../models/movement_library.dart';
import '../models/workout_plan.dart';
import '../planner/coach_voice.dart';
import '../pt_providers.dart';
import '../session/pt_session_controller.dart';
import 'pt_widgets.dart';

/// The guided session: intro card per movement, camera-tracked or timed
/// sets, rest countdowns and the summary.
class PtSessionScreen extends ConsumerStatefulWidget {
  const PtSessionScreen({super.key});

  @override
  ConsumerState<PtSessionScreen> createState() => _PtSessionScreenState();
}

class _PtSessionScreenState extends ConsumerState<PtSessionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    // `inactive` is a system dialog (the camera permission prompt), the
    // notification shade or a call banner: the app is still on screen, so
    // only a real move to the background pauses the session.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ref.read(ptSessionProvider.notifier).onAppBackgrounded();
    }
  }

  Future<void> _confirmExit() async {
    final state = ref.read(ptSessionProvider);
    final controller = ref.read(ptSessionProvider.notifier);
    if (state.step == PtStep.finished) {
      context.go(Routes.pt);
      return;
    }
    final wasPaused = state.paused;
    if (!wasPaused) await controller.pause();
    if (!mounted) return;
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End the session?'),
        content: const Text(
          'What you have done so far will be saved and summarised.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (end == true) {
      await controller.finish();
    } else if (!wasPaused) {
      // Only undo the pause this dialog made, not one the user chose.
      await controller.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ptSessionProvider);
    final controller = ref.read(ptSessionProvider.notifier);
    if (state.items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.pt);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor:
            state.step == PtStep.active && state.camera != PtCameraPhase.error
            ? Colors.black
            : AppColors.background,
        body: switch (state.step) {
          PtStep.intro => _IntroView(
            state: state,
            controller: controller,
            onExit: _confirmExit,
          ),
          PtStep.active when state.camera != PtCameraPhase.error =>
            _TrackedView(
              state: state,
              controller: controller,
              onExit: _confirmExit,
            ),
          PtStep.active => _TimedView(
            state: state,
            controller: controller,
            onExit: _confirmExit,
          ),
          PtStep.rest => _RestView(
            state: state,
            controller: controller,
            onExit: _confirmExit,
          ),
          PtStep.finished => _SummaryView(state: state),
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared header
// -----------------------------------------------------------------------------

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.state,
    required this.onExit,
    this.onCamera = false,
  });

  final PtSessionState state;
  final VoidCallback onExit;
  final bool onCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onCamera ? Colors.white : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'End session',
                onPressed: onExit,
                style: IconButton.styleFrom(
                  backgroundColor: onCamera
                      ? Colors.black45
                      : AppColors.surface,
                  foregroundColor: color,
                ),
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      state.item.phase.label.toUpperCase(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: onCamera ? Colors.white70 : AppColors.textMuted,
                        letterSpacing: 1.6,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${state.index + 1} of ${state.items.length} · '
                      '${formatClock(state.elapsed)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedProgressBar(
              value:
                  (state.index + (state.step == PtStep.intro ? 0 : 0.5)) /
                  state.items.length,
              height: 5,
              backgroundColor: onCamera ? Colors.white24 : AppColors.divider,
              semanticLabel: 'Session progress',
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Intro: 3D guide, equipment, cues
// -----------------------------------------------------------------------------

class _IntroView extends ConsumerWidget {
  const _IntroView({
    required this.state,
    required this.controller,
    required this.onExit,
  });

  final PtSessionState state;
  final PtSessionController controller;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final item = state.item;
    final m = item.movement;
    final profile = ref.watch(gymProfileProvider);
    return SafeArea(
      child: Column(
        children: [
          _SessionHeader(state: state, onExit: onExit),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              children:
                  [
                        TrainerBubble(text: state.coachLine, compact: true),
                        const SizedBox(height: 14),
                        AppCard(
                          glow: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 250,
                                child: Guide3D(
                                  key: ValueKey(m.clip),
                                  clipId: m.clip,
                                ),
                              ),
                              Text(
                                'Drag to rotate the guide',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                m.name,
                                style: theme.textTheme.headlineSmall,
                              ),
                              Text(
                                item.prescription +
                                    (item.sets > 1
                                        ? ' · rest ${item.rest.inSeconds}s'
                                        : ''),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.loaded) ...[
                          const SizedBox(height: 14),
                          AppCard(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: LoadStepper(
                              valueKg: state.loadKg,
                              unit: ref.watch(weightUnitProvider),
                              stepKg: ProgressionRule.incrementFor(
                                item.equipment,
                              ),
                              suggestedKg: item.suggestedKg,
                              why: item.suggestionWhy,
                              label:
                                  item.equipment.contains(Equipment.dumbbells)
                                  ? 'Load per dumbbell'
                                  : 'Load',
                              onChanged: controller.setLoad,
                              trailing:
                                  item.equipment.contains(Equipment.barbell)
                                  ? TextButton.icon(
                                      onPressed: () => showPlateSheet(
                                        context,
                                        targetKg: state.loadKg ?? 20,
                                      ),
                                      icon: const Icon(
                                        Icons.album_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Plates'),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                        if (item.equipment.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _EquipmentGuide(item: item, profile: profile),
                        ],
                        const SizedBox(height: 18),
                        const SectionHeader('How to do it'),
                        AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Column(
                            children: [
                              for (var i = 0; i < m.cues.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          gradient: AppColors.brandGradient,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${i + 1}',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: AppColors.onPrimary,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            m.cues[i],
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: AppColors.textPrimary,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              m.tracking.usesCamera
                                  ? Icons.videocam_outlined
                                  : Icons.timer_outlined,
                              size: 16,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                m.tracking.usesCamera
                                    ? 'The camera will count and coach this one. '
                                          'Prop the phone so your whole body is '
                                          'visible.'
                                    : 'Timed: the guide and the clock run; tap '
                                          'done when you finish early.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ]
                      .animate(interval: 40.ms)
                      .fadeIn(duration: 260.ms)
                      .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                _SmallAction(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Swap',
                  onPressed: () {
                    controller.holdIntro();
                    if (!controller.swapItem()) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No alternative with your equipment.'),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                _SmallAction(
                  icon: Icons.skip_next_rounded,
                  label: 'Skip',
                  onPressed: controller.skipItem,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: state.autoStartIn > 0
                        ? "I'M READY · ${state.autoStartIn}"
                        : "I'M READY",
                    icon: Icons.play_arrow_rounded,
                    height: 56,
                    onPressed: controller.beginItem,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipmentGuide extends StatelessWidget {
  const _EquipmentGuide({required this.item, required this.profile});

  final PlanItem item;
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos = <(Equipment, EquipmentItem)>[
      for (final e in item.equipment)
        if (profile.item(e) case final EquipmentItem it?)
          if (it.photoPath != null && File(it.photoPath!).existsSync()) (e, it),
    ];
    return AppCard(
      padding: const EdgeInsets.all(14),
      borderColor: AppColors.secondary.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.near_me_rounded,
                size: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'GRAB THIS',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1.4,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final (type, it) in photos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    Image.file(
                      File(it.photoPath!),
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.place_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${type.label}'
                                '${it.location?.isNotEmpty == true ? ' · ${it.location}' : ''}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in item.equipment)
                EquipmentChip(type: e, item: profile.item(e), large: true),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in item.equipment)
            Text(
              '${e.label}: ${profile.item(e)?.location?.isNotEmpty == true ? profile.item(e)!.location : e.whereHint}',
              style: theme.textTheme.bodySmall,
            ),
          if (item.movement.equipmentHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                item.movement.equipmentHint!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tracked set: camera + skeleton + mannequin PiP + coach
// -----------------------------------------------------------------------------

class _TrackedView extends ConsumerStatefulWidget {
  const _TrackedView({
    required this.state,
    required this.controller,
    required this.onExit,
  });

  final PtSessionState state;
  final PtSessionController controller;
  final VoidCallback onExit;

  @override
  ConsumerState<_TrackedView> createState() => _TrackedViewState();
}

class _TrackedViewState extends ConsumerState<_TrackedView> {
  bool _guideLarge = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = widget.controller;
    final theme = Theme.of(context);
    final item = state.item;
    final timerItem = item.movement.tracking is TimerTracking;
    final cap = item.capSeconds;
    final remaining = ((cap ?? item.seconds) - state.secondsInSet).clamp(
      0,
      9999,
    );
    final profile = ref.watch(gymProfileProvider);
    final cameraController = controller.cameraService?.controller;
    final exercise = switch (item.movement.tracking) {
      ExerciseTracking(:final type) => type,
      _ => null,
    };
    final cue = state.coachCue == null
        ? null
        : exercise != null
        ? CoachingLibrary.cue(state.coachCue!, exercise)
        : CoachingCue(
            status: state.coachCue!,
            title: state.coachCue!.shortLabel,
            instruction: state.coachCue!.message,
            spoken: state.coachCue!.message,
          );
    final highlight = switch (state.coachCue) {
      FormStatus.hipsTooHigh || FormStatus.hipsTooLow => {'hips', 'torso'},
      FormStatus.torsoLeaning => {'torso'},
      FormStatus.armsNotOverhead => {'arms'},
      _ => <String>{},
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        if (state.cameraReady && cameraController != null)
          CameraPreviewFill(
            controller: cameraController,
            overlay: CustomPaint(
              painter: PosePainter(
                pose: state.pose,
                mirror: state.mirror,
                good: state.formStatus.isGood,
                issue: state.coachCue,
              ),
            ),
          )
        else
          const ColoredBox(color: Colors.black),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0, 0.28, 0.6, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              _SessionHeader(
                state: state,
                onExit: widget.onExit,
                onCamera: true,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.movement.name.toUpperCase(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white70,
                            letterSpacing: 1.6,
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            AnimatedScale(
                              scale: state.repJustCounted ? 1.15 : 1,
                              duration: AppTokens.fast,
                              child: Text(
                                timerItem
                                    ? (item.isTimed
                                          ? formatClock(
                                              Duration(seconds: remaining),
                                            )
                                          : '${item.reps}')
                                    : '${state.repsInSet}',
                                style: theme.textTheme.displayMedium?.copyWith(
                                  color: state.repJustCounted
                                      ? AppColors.primary
                                      : Colors.white,
                                  fontSize: 58,
                                  height: 1,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: 8,
                                left: 6,
                              ),
                              child: Text(
                                timerItem
                                    ? (item.isTimed
                                          ? 'left'
                                          : 'reps, your pace')
                                    : '/ ${state.target}${item.isTimed ? ' s' : ''}',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          state.plan.request.bare
                              ? 'ROUND ${state.index + 1} OF ${state.items.length}'
                                    '${cap != null ? ' · ${formatClock(Duration(seconds: remaining))} LEFT' : ''}'
                              : 'SET ${state.setIndex + 1} OF ${item.sets}'
                                    '${state.loadKg != null && state.loadKg! > 0 ? ' · ${ref.watch(weightUnitProvider).format(state.loadKg!)}' : ''}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.primary,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (item.equipment.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 6,
                              children: [
                                for (final e in item.equipment)
                                  EquipmentChip(type: e, item: profile.item(e)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (state.cameraReady)
                    IconButton(
                      tooltip: 'Switch camera',
                      onPressed: controller.switchCamera,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.cameraswitch_outlined),
                    ),
                  const SizedBox(width: 12),
                ],
              ),
              const Spacer(),
              if (state.camera == PtCameraPhase.verifying ||
                  state.faceMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _CameraBanner(
                    icon: state.verified
                        ? Icons.verified_rounded
                        : Icons.face_retouching_natural,
                    text: state.faceMessage ?? 'Checking it\'s you…',
                    color: state.verified
                        ? AppColors.primary
                        : state.verificationDone
                        ? AppColors.warning
                        : AppColors.cyan,
                    action: state.verificationDone
                        ? null
                        : TextButton(
                            onPressed: controller.skipVerification,
                            child: const Text('Skip'),
                          ),
                  ),
                ),
              if (state.camera == PtCameraPhase.error)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _CameraBanner(
                    icon: Icons.videocam_off_outlined,
                    text: state.error?.userMessage ?? 'Camera unavailable.',
                    color: AppColors.danger,
                  ),
                ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CoachCard(
                  cue: cue,
                  status: state.formStatus,
                  positionHint:
                      exercise?.positionHint ??
                      'Get into the start position shown by the guide',
                  goodLabel: timerItem
                      ? 'I can see you. Follow the guide.'
                      : 'Good form',
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: state.paused
                              ? controller.resume
                              : controller.pause,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.45,
                            ),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          icon: Icon(
                            state.paused ? Icons.play_arrow : Icons.pause,
                          ),
                          label: Text(state.paused ? 'RESUME' : 'PAUSE'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: timerItem && !item.isTimed
                              ? () => _logManually(context)
                              : state.camera == PtCameraPhase.error
                              ? () => _logManually(context)
                              : controller.finishSetEarly,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.cardElevated,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: Text(
                            timerItem
                                ? (item.isTimed ? 'DONE EARLY' : 'LOG REPS')
                                : state.camera == PtCameraPhase.error
                                ? 'LOG SET'
                                : 'SET DONE',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 3D guide picture-in-picture.
        Positioned(
          right: 12,
          top: MediaQuery.paddingOf(context).top + 150,
          child: GestureDetector(
            onTap: () => setState(() => _guideLarge = !_guideLarge),
            child: AnimatedContainer(
              duration: AppTokens.normal,
              curve: AppTokens.curve,
              width: _guideLarge ? 220 : 120,
              height: _guideLarge ? 260 : 150,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    child: Guide3D(
                      clipId: item.movement.clip,
                      interactive: _guideLarge,
                      autoRotate: !_guideLarge,
                      compact: !_guideLarge,
                      highlight: highlight,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      _guideLarge ? 'Drag to rotate · tap to shrink' : 'GUIDE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                        letterSpacing: 1.2,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (state.paused)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Text(
                    'PAUSED',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _logManually(BuildContext context) async {
    final reps = await _askReps(context, widget.state.target);
    if (reps != null) widget.controller.logReps(reps);
  }
}

class _CameraBanner extends StatelessWidget {
  const _CameraBanner({
    required this.icon,
    required this.text,
    required this.color,
    this.action,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

Future<int?> _askReps(BuildContext context, int target) {
  var value = target;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('How many reps?'),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: value > 0 ? () => setState(() => value--) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: AppColors.primary),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => value++),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(value),
            child: const Text('Log'),
          ),
        ],
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Timed set without the camera
// -----------------------------------------------------------------------------

class _TimedView extends StatelessWidget {
  const _TimedView({
    required this.state,
    required this.controller,
    required this.onExit,
  });

  final PtSessionState state;
  final PtSessionController controller;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = state.item;
    final remaining = (item.seconds - state.secondsInSet).clamp(0, 9999);
    return SafeArea(
      child: Column(
        children: [
          _SessionHeader(state: state, onExit: onExit),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TrainerBubble(text: state.coachLine, compact: true),
          ),
          if (state.camera == PtCameraPhase.verifying ||
              state.faceMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: _CameraBanner(
                icon: state.verified
                    ? Icons.verified_rounded
                    : Icons.face_retouching_natural,
                text: state.faceMessage ?? 'Checking it\'s you…',
                color: state.verified
                    ? AppColors.primary
                    : state.verificationDone
                    ? AppColors.warning
                    : AppColors.cyan,
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Guide3D(
                    key: ValueKey(item.movement.clip),
                    clipId: item.movement.clip,
                    playing: !state.paused,
                  ),
                ),
                if (state.paused)
                  Center(
                    child: Text(
                      'PAUSED',
                      style: theme.textTheme.displaySmall?.copyWith(
                        letterSpacing: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(item.movement.name, style: theme.textTheme.headlineSmall),
                Text(
                  'SET ${state.setIndex + 1} OF ${item.sets}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (item.isTimed)
                  ProgressRing(
                    value: item.seconds == 0
                        ? 0
                        : state.secondsInSet / item.seconds,
                    size: 150,
                    thickness: 12,
                    animate: false,
                    semanticLabel: 'Time remaining',
                    child: Text(
                      formatClock(Duration(seconds: remaining)),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 40,
                      ),
                    ),
                  )
                else
                  Text(
                    '${item.reps} reps at your pace',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  item.movement.cues.first,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: state.paused
                          ? controller.resume
                          : controller.pause,
                      icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                      label: Text(state.paused ? 'RESUME' : 'PAUSE'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: item.isTimed
                        ? 'DONE EARLY'
                        : 'DONE: ${item.reps} REPS',
                    icon: Icons.check_rounded,
                    height: 56,
                    onPressed: item.isTimed
                        ? controller.finishSetEarly
                        : () async {
                            final reps = await _askReps(context, item.reps);
                            if (reps != null) controller.logReps(reps);
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Rest
// -----------------------------------------------------------------------------

class _RestView extends StatelessWidget {
  const _RestView({
    required this.state,
    required this.controller,
    required this.onExit,
  });

  final PtSessionState state;
  final PtSessionController controller;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = state.item;
    return SafeArea(
      child: Column(
        children: [
          _SessionHeader(state: state, onExit: onExit),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TrainerBubble(text: state.coachLine, compact: true),
          ),
          const Spacer(),
          Text(
            'REST',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 10),
          ProgressRing(
            value: item.rest.inSeconds == 0
                ? 0
                : 1 - state.restRemaining / item.rest.inSeconds,
            size: 200,
            thickness: 14,
            animate: false,
            semanticLabel: 'Rest remaining',
            gradient: const LinearGradient(
              colors: [AppColors.cyan, AppColors.secondary],
            ),
            child: Text(
              '${state.restRemaining}',
              style: theme.textTheme.displayLarge?.copyWith(fontSize: 72),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.plan.request.bare
                ? 'Next: round ${state.index + 1} of ${state.items.length} · ${item.movement.name}'
                : 'Next: set ${state.setIndex + 2} of ${item.sets} · ${item.movement.name}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: controller.skipItem,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('SKIP REST OF SETS'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'GO NOW',
                    icon: Icons.bolt_rounded,
                    height: 56,
                    onPressed: controller.skipRest,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Summary
// -----------------------------------------------------------------------------

class _SummaryView extends ConsumerWidget {
  const _SummaryView({required this.state});

  final PtSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final record = state.record;
    final level = ref.watch(levelProvider);
    final xp = record == null || state.saveFailed
        ? 0
        : LevelSystem.xpForPtRecord(record);
    final done = record?.itemsDone ?? 0;
    final total = record?.itemCount ?? 0;
    final complete = record != null && record.completion >= 0.8;
    final newBadges = ref.watch(
      newBadgesShownProvider(record?.id ?? 'pt-summary'),
    );
    if (newBadges.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(markAchievementsSeenProvider)();
      });
    }
    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  children:
                      [
                            Center(
                              child:
                                  Container(
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      gradient: complete
                                          ? AppColors.brandGradient
                                          : null,
                                      color: complete
                                          ? null
                                          : AppColors.cardElevated,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      complete
                                          ? Icons.emoji_events_rounded
                                          : Icons.auto_awesome_rounded,
                                      size: 42,
                                      color: complete
                                          ? AppColors.onPrimary
                                          : AppColors.textSecondary,
                                    ),
                                  ).animate().scale(
                                    begin: const Offset(0.5, 0.5),
                                    end: const Offset(1, 1),
                                    duration: 600.ms,
                                    curve: Curves.elasticOut,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              complete ? 'SESSION COMPLETE' : 'SESSION ENDED',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                letterSpacing: 2,
                                color: complete ? AppColors.primary : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TrainerBubble(text: state.coachLine),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _Stat(
                                  value:
                                      '${record?.duration.inMinutes ?? 0} min',
                                  label: 'duration',
                                  icon: Icons.schedule_rounded,
                                ),
                                const SizedBox(width: 10),
                                _Stat(
                                  value: '$done/$total',
                                  label: 'movements',
                                  icon: Icons.format_list_numbered_rounded,
                                ),
                                const SizedBox(width: 10),
                                _Stat(
                                  value: xp > 0 ? '+$xp' : '0',
                                  label: xp > 0 ? 'XP earned' : 'not scored',
                                  icon: Icons.bolt_rounded,
                                  color: xp > 0
                                      ? AppColors.primary
                                      : AppColors.warning,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Level ${level.level} · ${level.title}',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedProgressBar(
                                    value: level.progress,
                                    height: 8,
                                    semanticLabel: 'Level progress',
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${level.xpToNext} XP to level ${level.level + 1}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (state.personalRecords.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              const SectionHeader('New records'),
                              AppCard(
                                borderColor: AppColors.warning.withValues(
                                  alpha: 0.6,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  children: [
                                    for (final pr in state.personalRecords)
                                      ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.emoji_events_rounded,
                                          color: AppColors.warning,
                                        ),
                                        title: Text(
                                          MovementLibrary.byId(pr.movementId)
                                                  ?.name ??
                                              pr.movementId,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        subtitle: Text(pr.kind.label),
                                        trailing: Text(
                                          pr.label,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            if (newBadges.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              SectionHeader(
                                newBadges.length == 1
                                    ? 'New badge'
                                    : 'New badges',
                              ),
                              AppCard(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    for (final b in newBadges.take(3))
                                      Expanded(
                                        child: BadgeTile(
                                          title: b.achievement.title,
                                          icon: b.achievement.icon,
                                          tier: b.achievement.tier.name,
                                          earned: true,
                                          progress: 1,
                                          onTap: () =>
                                              context.push(Routes.achievements),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            if (record != null) ...[
                              const SizedBox(height: 20),
                              const SectionHeader('Next time'),
                              AppCard(
                                padding: const EdgeInsets.all(14),
                                borderColor: AppColors.cyan.withValues(
                                  alpha: 0.35,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.lightbulb_outline_rounded,
                                      color: AppColors.cyan,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        CoachVoice.nextTimeTip(record),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: AppColors.textPrimary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const SectionHeader('What you did'),
                              AppCard(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < record.items.length;
                                      i++
                                    ) ...[
                                      if (i > 0)
                                        const Divider(
                                          indent: 20,
                                          endIndent: 20,
                                        ),
                                      _ResultRow(result: record.items[i]),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ]
                          .animate(interval: 45.ms)
                          .fadeIn(duration: 300.ms)
                          .slideY(begin: 0.05, end: 0, curve: AppTokens.curve),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    if (record != null)
                      SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: () => showShareSheet(
                            context,
                            ShareCardData(
                              headline: complete
                                  ? 'SESSION COMPLETE'
                                  : 'MY PT SESSION',
                              title: state.plan.title,
                              subtitle:
                                  '$done of $total movements · '
                                  '${record.duration.inMinutes} min',
                              date: record.endTime,
                              stats: [
                                ShareStat(
                                  label: 'Reps',
                                  value: '${record.totalReps}',
                                ),
                                ShareStat(
                                  label: 'Minutes',
                                  value: '${record.duration.inMinutes}',
                                ),
                                ShareStat(label: 'XP', value: '$xp'),
                                ShareStat(
                                  label: 'Level',
                                  value: '${level.level}',
                                ),
                              ],
                              accent: complete ? 'primary' : 'cyan',
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 56),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('SHARE'),
                        ),
                      ),
                    if (record != null) const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: 'DONE',
                        icon: Icons.check_rounded,
                        onPressed: () => context.go(Routes.home),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (complete) const Positioned.fill(child: Celebration()),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    this.color = AppColors.textPrimary,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final dynamic result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = result.movement?.name ?? result.movementId;
    final skipped = result.skipped as bool;
    final text = skipped
        ? 'Skipped'
        : result.seconds > 0
        ? '${result.seconds}s'
        : '${result.reps} reps · ${result.setsDone}/${result.setsPlanned} sets';
    final mistakes = (result.mistakes as Map).values.fold<int>(
      0,
      (a, b) => a + (b as int),
    );
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(
        skipped ? Icons.remove_circle_outline : Icons.check_circle_rounded,
        color: skipped ? AppColors.textMuted : AppColors.primary,
      ),
      title: Text(name, style: theme.textTheme.titleSmall),
      subtitle: Text(
        '$text${mistakes > 0 ? ' · $mistakes coach note${mistakes == 1 ? '' : 's'}' : ''}',
      ),
    );
  }
}
