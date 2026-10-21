import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../models/coaching.dart';
import '../../models/form_status.dart';
import '../../widgets/animated_progress_bar.dart';

import 'package:camera/camera.dart' show CameraLensDirection;

import 'widgets/camera_preview_fill.dart';
import 'widgets/coach_card.dart';
import 'widgets/pose_painter.dart';
import 'workout_controller.dart';

/// Live camera workout: preview, skeleton overlay, rep HUD, form feedback and
/// pause/finish controls. All logic lives in [WorkoutController].
class WorkoutCameraScreen extends ConsumerStatefulWidget {
  const WorkoutCameraScreen({super.key});

  @override
  ConsumerState<WorkoutCameraScreen> createState() =>
      _WorkoutCameraScreenState();
}

class _WorkoutCameraScreenState extends ConsumerState<WorkoutCameraScreen>
    with WidgetsBindingObserver {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The workout works in portrait or landscape: the phone is often propped
    // on its side next to the user. Everything else stays portrait.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(workoutControllerProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final controller = ref.read(workoutControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        controller.onAppBackgrounded();
      case AppLifecycleState.resumed:
        controller.onAppResumed();
    }
  }

  void _onFinished() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final state = ref.read(workoutControllerProvider);
    if (state.result == null) {
      context.go(Routes.home);
    } else {
      context.pushReplacement(
        Routes.workoutComplete,
        extra: WorkoutOutcome(
          session: state.result,
          report: state.report ?? '',
          mistakes: state.mistakes,
          verified: state.verified,
        ),
      );
    }
  }

  Future<void> _confirmExit() async {
    final state = ref.read(workoutControllerProvider);
    final controller = ref.read(workoutControllerProvider.notifier);
    if (state.phase == WorkoutPhase.error ||
        state.phase == WorkoutPhase.initializing ||
        state.phase == WorkoutPhase.verifying ||
        state.repCount == 0) {
      await controller.finish();
      return;
    }
    final wasRunning = state.isRunning;
    if (wasRunning) await controller.pause();
    if (!mounted) return;
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this set?'),
        content: Text(
          'Your ${state.repCount} '
          '${state.exercise.countLabel(state.repCount)} so far will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End set'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (end == true) {
      await controller.finish();
    } else if (wasRunning) {
      await controller.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workoutControllerProvider.select((s) => s.phase), (_, phase) {
      if (phase == WorkoutPhase.finished) _onFinished();
    });
    final state = ref.watch(workoutControllerProvider);
    final controller = ref.read(workoutControllerProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _CameraLayer(state: state),
            const _Vignette(),
            if (state.phase == WorkoutPhase.active ||
                state.phase == WorkoutPhase.countdown ||
                state.phase == WorkoutPhase.calibrating)
              _DepthGauge(state: state),
            if (ref.watch(
                  settingsProvider.select((s) => s.showTrackingDetails),
                ) &&
                state.phase != WorkoutPhase.finished)
              _TrackingDetails(state: state),
            SafeArea(
              child: Column(
                children: [
                  _TopHud(
                    state: state,
                    onClose: _confirmExit,
                    onSwitchCamera: controller.switchCamera,
                  ),
                  if (state.identityWarning) const _IdentityBanner(),
                  Expanded(
                    child: Center(
                      child: _CenterOverlay(
                        state: state,
                        controller: controller,
                      ),
                    ),
                  ),
                  _BottomBar(
                    state: state,
                    controller: controller,
                    onFinish: _confirmExit,
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

class _CameraLayer extends ConsumerWidget {
  const _CameraLayer({required this.state});

  final WorkoutState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraController = ref
        .read(workoutControllerProvider.notifier)
        .service
        ?.controller;
    if (!state.cameraReady || cameraController == null) {
      return const ColoredBox(color: Colors.black);
    }
    return CameraPreviewFill(
      controller: cameraController,
      overlay: CustomPaint(
        painter: PosePainter(
          pose: state.pose,
          mirror: state.mirror,
          good: state.formStatus.isGood,
          issue: state.coachCue,
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.75),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.85),
            ],
            stops: const [0, 0.25, 0.65, 1],
          ),
        ),
      ),
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({
    required this.state,
    required this.onClose,
    required this.onSwitchCamera,
  });

  final WorkoutState state;
  final VoidCallback onClose;
  final VoidCallback onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final canSwitch =
        state.canSwitchCamera &&
        state.cameraReady &&
        state.phase != WorkoutPhase.finished;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoundButton(
            icon: Icons.close,
            label: 'End workout',
            onPressed: onClose,
          ),
          Expanded(
            child: Semantics(
              label: 'Reps',
              value: '${state.repCount} of ${state.targetReps}',
              liveRegion: true,
              excludeSemantics: true,
              child: Column(
                children: [
                  Text(
                    state.exercise.isTimed ? 'SECONDS' : 'REP',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 2,
                    ),
                  ),
                  AnimatedScale(
                    scale: state.repJustCounted ? 1.18 : 1,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: Colors.white,
                          fontSize: landscape ? 36 : 56,
                          height: 1.1,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 12),
                          ],
                        ),
                        children: [
                          TextSpan(
                            text: '${state.repCount}',
                            style: TextStyle(
                              color: state.repJustCounted
                                  ? AppColors.primary
                                  : Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${state.targetReps}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: landscape ? 22 : 30,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    state.exercise.label.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 2,
                    ),
                  ),
                  if (!state.verified)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          'UNVERIFIED · NO STREAK / XP',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.warning,
                            letterSpacing: 1,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: AnimatedProgressBar(
                      value: state.progress,
                      height: 8,
                      backgroundColor: Colors.white24,
                      semanticLabel: 'Set progress',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canSwitch)
            _RoundButton(
              icon: Icons.cameraswitch_outlined,
              label: state.lensDirection == CameraLensDirection.front
                  ? 'Switch to back camera'
                  : 'Switch to front camera',
              onPressed: onSwitchCamera,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
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
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _CenterOverlay extends ConsumerWidget {
  const _CenterOverlay({required this.state, required this.controller});

  final WorkoutState state;
  final WorkoutController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    switch (state.phase) {
      case WorkoutPhase.idle:
      case WorkoutPhase.initializing:
        return const _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Starting camera…', style: TextStyle(color: Colors.white)),
            ],
          ),
        );
      case WorkoutPhase.verifying:
        return _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.face_retouching_natural,
                color: Colors.white,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'Checking it\'s you',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.faceStatus.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => confirmBypassVerification(
                  context,
                  controller,
                  restart: false,
                ),
                child: const Text('Skip verification'),
              ),
            ],
          ),
        );
      case WorkoutPhase.calibrating:
        return _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: state.calibrationProgress,
                      strokeWidth: 5,
                      backgroundColor: Colors.white24,
                    ),
                    const Icon(
                      Icons.accessibility_new,
                      color: Colors.white,
                      size: 30,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                state.exercise.isTimed
                    ? 'Get into plank position'
                    : 'Get into position',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.formStatus.isTracking &&
                        state.formStatus != FormStatus.notInPosition
                    ? 'Hold still…'
                    : state.formStatus == FormStatus.notInPosition
                    ? state.exercise.positionHint
                    : state.formStatus.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: controller.startCountdownNow,
                child: const Text('Start countdown now'),
              ),
            ],
          ),
        );
      case WorkoutPhase.countdown:
        final text = state.countdownValue > 0
            ? '${state.countdownValue}'
            : 'GO!';
        return Semantics(
          liveRegion: true,
          label: text,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween(begin: 1.4, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: ShaderMask(
              key: ValueKey(text),
              shaderCallback: (rect) =>
                  (state.countdownValue > 0
                          ? const LinearGradient(
                              colors: [Colors.white, Colors.white],
                            )
                          : AppColors.brandGradient)
                      .createShader(rect),
              child: Text(
                text,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontSize: 128,
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      case WorkoutPhase.active:
        return const SizedBox.shrink();
      case WorkoutPhase.paused:
        return _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.pause_circle_outline,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Paused',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.pausedByIdentity
                    ? 'Registered user not detected. Tap resume to verify '
                          'again.'
                    : state.cameraReady
                    ? 'Tap resume when you are back in position.'
                    : 'Reconnecting to the camera…',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        );
      case WorkoutPhase.finished:
        return const CircularProgressIndicator();
      case WorkoutPhase.error:
        if (state.isFaceError) {
          return _FaceErrorPanel(state: state, controller: controller);
        }
        return _ErrorPanel(state: state, controller: controller);
    }
  }
}

class _FaceErrorPanel extends StatelessWidget {
  const _FaceErrorPanel({required this.state, required this.controller});

  final WorkoutState state;
  final WorkoutController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notRegistered =
        state.faceStatus == FaceVerificationStatus.notRegistered;
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            notRegistered ? Icons.face_retouching_natural : Icons.no_accounts,
            color: notRegistered ? AppColors.secondary : AppColors.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            notRegistered ? 'Face not registered' : 'Not recognised',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            state.faceStatus.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          if (notRegistered)
            FilledButton.icon(
              onPressed: () => context.pushReplacement(Routes.faceRegistration),
              icon: const Icon(Icons.face),
              label: const Text('REGISTER FACE'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            )
          else
            FilledButton.icon(
              onPressed: controller.start,
              icon: const Icon(Icons.refresh),
              label: const Text('TRY AGAIN'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            ),
          TextButton(
            onPressed: () =>
                confirmBypassVerification(context, controller, restart: true),
            child: const Text('Continue without verification'),
          ),
          TextButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}

/// Explains what skipping the face check means, then either restarts the
/// set without a check or skips the one in progress.
Future<void> confirmBypassVerification(
  BuildContext context,
  WorkoutController controller, {
  required bool restart,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Skip the face check?'),
      content: const Text(
        'Your reps will still be counted, coached and saved. Because nobody '
        'confirmed it was you, this set will be marked unverified: it will '
        'not count towards your streak and earns no XP.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Skip and continue'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  if (restart) {
    await controller.start(bypassIdentity: true);
  } else {
    controller.skipVerification();
  }
}

class _ErrorPanel extends ConsumerWidget {
  const _ErrorPanel({required this.state, required this.controller});

  final WorkoutState state;
  final WorkoutController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final error = state.error;
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            color: AppColors.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            'Camera problem',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            error?.userMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          if (state.permissionPermanentlyDenied)
            FilledButton.icon(
              onPressed: () =>
                  ref.read(permissionServiceProvider).openSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('OPEN SETTINGS'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            )
          else
            FilledButton.icon(
              onPressed: controller.start,
              icon: const Icon(Icons.refresh),
              label: const Text('TRY AGAIN'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            ),
          TextButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}

/// Vertical gauge on the right edge showing how deep the current rep is,
/// so the user can see what the tracker sees.
class _DepthGauge extends StatelessWidget {
  const _DepthGauge({required this.state});

  final WorkoutState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final down = state.isWorking;
    return Positioned(
      right: 12,
      top: 0,
      bottom: 0,
      child: SafeArea(
        child: Center(
          child: Semantics(
            label: 'Rep depth',
            value: '${(state.depth * 100).round()} percent',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.exercise.isTimed ? 'HOLD' : (down ? 'DOWN' : 'UP'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 14,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 120),
                      heightFactor: state.depth.clamp(0.02, 1.0),
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: down
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [AppColors.cyan, AppColors.secondary],
                                )
                              : AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  state.limbsUsed == 2
                      ? Icons.accessibility_new
                      : Icons.accessibility,
                  size: 16,
                  color: state.limbsUsed == 0 ? Colors.white30 : Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Optional live numbers for troubleshooting (Settings → Camera).
class _TrackingDetails extends StatelessWidget {
  const _TrackingDetails({required this.state});

  final WorkoutState state;

  String _f(double? v) => v == null ? '–' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final text = [
      '${state.exercise.label}  ${state.phase.name}',
      'signal ${_f(state.signal)}  rest ${_f(state.restThreshold)}  '
          'work ${_f(state.workThreshold)}',
      'tilt ${_f(state.bodyTilt)}  limbs ${state.limbsUsed}  '
          'track ${state.trackQuality.name}',
      'form ${state.formStatus.name}  depth ${(state.depth * 100).round()}%',
    ].join('\n');
    return Positioned(
      left: 12,
      bottom: 150,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.white,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while identity spot checks keep failing, before the set pauses.
class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.no_accounts, color: AppColors.onPrimary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Can't confirm it's you. Look at the camera.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.controller,
    required this.onFinish,
  });

  final WorkoutState state;
  final WorkoutController controller;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final canPause = state.isRunning;
    final canResume = state.phase == WorkoutPhase.paused && state.cameraReady;
    final status = state.formStatus;
    final showForm =
        state.phase == WorkoutPhase.active ||
        state.phase == WorkoutPhase.countdown;
    final cue = state.coachCue == null
        ? null
        : CoachingLibrary.cue(state.coachCue!, state.exercise);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: showForm ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: CoachCard(
              cue: cue,
              status: status,
              positionHint: state.exercise.positionHint,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: OutlinedButton.icon(
                    onPressed: canPause
                        ? controller.pause
                        : canResume
                        ? controller.resume
                        : null,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.45),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    icon: Icon(canPause ? Icons.pause : Icons.play_arrow),
                    label: Text(canPause ? 'PAUSE' : 'RESUME'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: state.phase == WorkoutPhase.finished
                        ? null
                        : onFinish,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.flag),
                    label: const Text('FINISH'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
