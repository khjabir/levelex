import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../models/coaching.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/celebration.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../../pt/figure/guide_3d.dart';
import '../../workout/exercise_icons.dart';
import '../../workout/widgets/camera_preview_fill.dart';
import '../../workout/widgets/coach_card.dart';
import '../../workout/widgets/pose_painter.dart';
import '../models/challenge.dart';
import '../session/round_controller.dart';
import 'player_avatar.dart';

/// Plays the challenge round by round and shows the podium at the end.
class ChallengePlayScreen extends ConsumerStatefulWidget {
  const ChallengePlayScreen({super.key});

  @override
  ConsumerState<ChallengePlayScreen> createState() =>
      _ChallengePlayScreenState();
}

class _ChallengePlayScreenState extends ConsumerState<ChallengePlayScreen>
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
    final controller = ref.read(challengeControllerProvider.notifier);
    switch (state) {
      // `inactive` (a system dialog, the notification shade) keeps the app
      // on screen; only a real move to the background ends the round.
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        controller.onAppBackgrounded();
      case AppLifecycleState.resumed:
        controller.onAppResumed();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _confirmExit() async {
    final state = ref.read(challengeControllerProvider);
    final live =
        state.phase == RoundPhase.active ||
        state.phase == RoundPhase.countdown ||
        state.phase == RoundPhase.roundOver;
    if (state.phase == RoundPhase.finished || (state.scores.isEmpty && !live)) {
      context.go(Routes.challenge);
      return;
    }
    final controller = ref.read(challengeControllerProvider.notifier);
    controller.holdRound();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the challenge?'),
        content: const Text(
          'Rounds played so far will be lost. The clock is stopped while '
          'you decide.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      context.go(Routes.challenge);
    } else {
      controller.releaseRound();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(challengeControllerProvider);
    final controller = ref.read(challengeControllerProvider.notifier);
    if (state.config.players.length < 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.challenge);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final onCamera =
        state.phase == RoundPhase.starting ||
        state.phase == RoundPhase.countdown ||
        state.phase == RoundPhase.active ||
        state.phase == RoundPhase.error;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: onCamera ? Colors.black : AppColors.background,
        body: switch (state.phase) {
          RoundPhase.upNext => _UpNextView(
            state: state,
            controller: controller,
            onExit: _confirmExit,
          ),
          RoundPhase.roundOver => _RoundOverView(
            state: state,
            controller: controller,
            onExit: _confirmExit,
          ),
          RoundPhase.finished => _ResultsView(
            state: state,
            controller: controller,
          ),
          _ => _RoundView(
            state: state,
            controller: controller,
            onExit: _confirmExit,
          ),
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.onExit,
    this.onCamera = false,
  });

  final ChallengeState state;
  final VoidCallback onExit;
  final bool onCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onCamera ? Colors.white : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave challenge',
            onPressed: onExit,
            style: IconButton.styleFrom(
              backgroundColor: onCamera ? Colors.black45 : AppColors.surface,
              foregroundColor: color,
            ),
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'CHALLENGE',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: onCamera ? Colors.white70 : AppColors.textMuted,
                    letterSpacing: 1.6,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${state.config.describe} · player '
                  '${state.playerIndex + 1} of ${state.config.players.length}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _UpNextView extends StatelessWidget {
  const _UpNextView({
    required this.state,
    required this.controller,
    required this.onExit,
  });

  final ChallengeState state;
  final ChallengeController controller;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = state.player;
    return SafeArea(
      child: Column(
        children: [
          _Header(state: state, onExit: onExit),
          // The middle scrolls when it does not fit (small phones, many
          // players, large text) so the button below always stays on screen.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlayerAvatar(player: player, size: 132).animate().scale(
                      begin: const Offset(0.6, 0.6),
                      end: const Offset(1, 1),
                      duration: 500.ms,
                      curve: Curves.elasticOut,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'UP NEXT',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(player.name, style: theme.textTheme.displaySmall),
                    const SizedBox(height: 6),
                    Text(
                      state.config.describe,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 180,
                      child: Guide3D(clipId: state.config.exercise.clipId),
                    ),
                    if (state.scores.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'To beat: ${state.scores.map((s) => s.reps).reduce((a, b) => a > b ? a : b)} '
                        '${state.config.exercise.countLabel(2)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: PrimaryButton(
              label: "${player.name.toUpperCase()}, I'M READY",
              icon: Icons.videocam_rounded,
              onPressed: controller.startRound,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundView extends ConsumerWidget {
  const _RoundView({
    required this.state,
    required this.controller,
    required this.onExit,
  });

  final ChallengeState state;
  final ChallengeController controller;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cameraController = controller.cameraService?.controller;
    final exercise = state.config.exercise;
    final cue = state.coachCue == null
        ? null
        : CoachingLibrary.cue(state.coachCue!, exercise);
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
                stops: const [0, 0.3, 0.6, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              _Header(state: state, onExit: onExit, onCamera: true),
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 20),
                  PlayerAvatar(player: state.player, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.player.name.toUpperCase(),
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
                                '${state.reps}',
                                style: theme.textTheme.displayMedium?.copyWith(
                                  color: state.repJustCounted
                                      ? AppColors.primary
                                      : Colors.white,
                                  fontSize: 58,
                                  height: 1,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: 8,
                                left: 6,
                              ),
                              child: Text(
                                state.timed
                                    ? exercise.countLabel(state.reps)
                                    : '/ ${state.config.value}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        state.timed ? 'TIME LEFT' : 'TIME',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white54,
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        state.timed
                            ? '${state.secondsLeft}'
                            : state.elapsed.toStringAsFixed(1),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: state.timed && state.secondsLeft <= 5
                              ? AppColors.warning
                              : Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
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
              if (state.phase == RoundPhase.countdown)
                Column(
                  children: [
                    Text(
                      state.countdownValue > 0 && state.formStatus.isTracking
                          ? '${state.countdownValue}'
                          : 'GET IN POSITION',
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: state.formStatus.isTracking ? 120 : 28,
                        color: Colors.white,
                        letterSpacing: state.formStatus.isTracking ? 0 : 3,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 24),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: controller.startCountdownNow,
                      child: const Text('Start now'),
                    ),
                  ],
                ),
              if (state.phase == RoundPhase.starting)
                const CircularProgressIndicator(),
              if (state.phase == RoundPhase.error)
                _ErrorCard(state: state, controller: controller),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CoachCard(
                  cue: cue,
                  status: state.formStatus,
                  positionHint: exercise.positionHint,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: state.phase == RoundPhase.active
                        ? controller.endRoundNow
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('END ROUND'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          top: MediaQuery.paddingOf(context).top + 150,
          child: Container(
            width: 110,
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Guide3D(
              clipId: exercise.clipId,
              interactive: false,
              compact: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends ConsumerWidget {
  const _ErrorCard({required this.state, required this.controller});

  final ChallengeState state;
  final ChallengeController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            color: AppColors.danger,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            state.error?.userMessage ?? 'Camera problem',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.error?.kind.name == 'permissionDenied'
                ? () => ref.read(permissionServiceProvider).openSettings()
                : controller.startRound,
            icon: const Icon(Icons.refresh),
            label: Text(
              state.error?.kind.name == 'permissionDenied'
                  ? 'OPEN SETTINGS'
                  : 'TRY AGAIN',
            ),
            style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
          ),
        ],
      ),
    );
  }
}

class _RoundOverView extends StatelessWidget {
  const _RoundOverView({
    required this.state,
    required this.controller,
    required this.onExit,
  });

  final ChallengeState state;
  final ChallengeController controller;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = state.lastScore!;
    final ranked = ChallengeRecord.ranked(state.scores, state.config.mode);
    return SafeArea(
      child: Column(
        children: [
          _Header(state: state, onExit: onExit),
          // The middle scrolls when it does not fit (small phones, many
          // players, large text) so the button below always stays on screen.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlayerAvatar(player: score.player, size: 96),
                    const SizedBox(height: 12),
                    Text(
                      score.player.name,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${score.reps}',
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 96,
                      ),
                    ).animate().scale(
                      begin: const Offset(0.5, 0.5),
                      end: const Offset(1, 1),
                      duration: 500.ms,
                      curve: Curves.elasticOut,
                    ),
                    Text(
                      state.config.exercise.countLabel(score.reps) +
                          (state.timed
                              ? ''
                              : ' in ${score.seconds.toStringAsFixed(1)} s'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (var i = 0; i < ranked.length; i++)
                              _RankRow(
                                index: i,
                                score: ranked[i],
                                exercise: state.config.exercise,
                                timed: state.timed,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: PrimaryButton(
              label: state.isLastPlayer ? 'SEE RESULTS' : 'NEXT PLAYER',
              icon: state.isLastPlayer
                  ? Icons.emoji_events_rounded
                  : Icons.skip_next_rounded,
              onPressed: controller.next,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.index,
    required this.score,
    required this.exercise,
    required this.timed,
  });

  final int index;
  final ChallengeScore score;
  final dynamic exercise;
  final bool timed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: PlayerAvatar(
        player: score.player,
        size: 36,
        crowned: index == 0,
      ),
      title: Text(score.player.name, style: theme.textTheme.titleSmall),
      subtitle: timed ? null : Text('${score.seconds.toStringAsFixed(1)} s'),
      trailing: Text(
        '${score.reps}',
        style: theme.textTheme.titleLarge?.copyWith(
          color: index == 0 ? AppColors.primary : AppColors.textPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.state, required this.controller});

  final ChallengeState state;
  final ChallengeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = state.record;
    final ranked = record?.scores ?? const <ChallengeScore>[];
    final winner = ranked.isEmpty ? null : ranked.first;
    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
                  children:
                      [
                            if (winner != null)
                              Center(
                                child: PlayerAvatar(
                                  player: winner.player,
                                  size: 140,
                                  crowned: true,
                                ),
                              ).animate().scale(
                                begin: const Offset(0.5, 0.5),
                                end: const Offset(1, 1),
                                duration: 700.ms,
                                curve: Curves.elasticOut,
                              ),
                            const SizedBox(height: 22),
                            Text(
                              record?.tie == true ? 'SHARED CUP' : 'CHAMPION',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppColors.warning,
                                letterSpacing: 3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              winner?.player.name ?? '',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.displaySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              state.coachLine,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const SectionHeader('Final standings'),
                            AppCard(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                children: [
                                  for (var i = 0; i < ranked.length; i++)
                                    _RankRow(
                                      index: i,
                                      score: ranked[i],
                                      exercise: state.config.exercise,
                                      timed: state.timed,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  state.config.exercise.icon,
                                  size: 16,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${state.config.describe}. Challenge rounds '
                                    'are not scored towards your streak or XP.',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ]
                          .animate(interval: 50.ms)
                          .fadeIn(duration: 300.ms)
                          .slideY(begin: 0.05, end: 0, curve: AppTokens.curve),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryButton(
                      label: 'REMATCH',
                      icon: Icons.replay_rounded,
                      onPressed: controller.rematch,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => context.go(Routes.home),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('DONE'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Positioned.fill(child: Celebration()),
      ],
    );
  }
}
