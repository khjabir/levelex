import 'dart:async';

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../models/coaching.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import '../../../models/user_settings.dart';
import '../../../services/pose_detection_service.dart';
import '../../../services/voice_coach.dart';
import '../../workout/analysis/analyzer_factory.dart';
import '../../workout/analysis/coaching_tracker.dart';
import '../../workout/analysis/exercise_analyzer.dart';
import '../challenge_providers.dart';
import '../models/challenge.dart';

/// Where a challenge is.
enum RoundPhase {
  /// Between rounds: the next player's card.
  upNext,
  starting,

  /// Player is getting in position; 3-2-1 once they are.
  countdown,
  active,

  /// Round just ended; score shown.
  roundOver,

  /// Everyone has played.
  finished,
  error,
}

class ChallengeState {
  const ChallengeState({
    required this.config,
    this.playerIndex = 0,
    this.phase = RoundPhase.upNext,
    this.countdownValue = 3,
    this.reps = 0,
    this.elapsed = 0,
    this.scores = const [],
    this.pose,
    this.mirror = false,
    this.cameraReady = false,
    this.formStatus = FormStatus.bodyNotVisible,
    this.coachCue,
    this.depth = 0,
    this.repJustCounted = false,
    this.error,
    this.record,
    this.lensDirection = CameraLensDirection.front,
    this.coachLine = '',
  });

  final ChallengeConfig config;
  final int playerIndex;
  final RoundPhase phase;
  final int countdownValue;

  /// Reps (or seconds held) in the current round.
  final int reps;

  /// Seconds elapsed in the current round.
  final double elapsed;
  final List<ChallengeScore> scores;
  final PoseResult? pose;
  final bool mirror;
  final bool cameraReady;
  final FormStatus formStatus;
  final FormStatus? coachCue;
  final double depth;
  final bool repJustCounted;
  final PoseDetectionException? error;
  final ChallengeRecord? record;
  final CameraLensDirection lensDirection;
  final String coachLine;

  ChallengePlayer get player => config.players[playerIndex];
  bool get isLastPlayer => playerIndex >= config.players.length - 1;
  bool get timed => config.mode == ChallengeMode.timed;

  /// Seconds left in a timed round.
  int get secondsLeft => (config.value - elapsed).ceil().clamp(0, 9999);
  ChallengeScore? get lastScore => scores.isEmpty ? null : scores.last;

  ChallengeState copyWith({
    ChallengeConfig? config,
    int? playerIndex,
    RoundPhase? phase,
    int? countdownValue,
    int? reps,
    double? elapsed,
    List<ChallengeScore>? scores,
    PoseResult? pose,
    bool clearPose = false,
    bool? mirror,
    bool? cameraReady,
    FormStatus? formStatus,
    FormStatus? coachCue,
    bool clearCoachCue = false,
    double? depth,
    bool? repJustCounted,
    PoseDetectionException? error,
    bool clearError = false,
    ChallengeRecord? record,
    CameraLensDirection? lensDirection,
    String? coachLine,
  }) => ChallengeState(
    config: config ?? this.config,
    playerIndex: playerIndex ?? this.playerIndex,
    phase: phase ?? this.phase,
    countdownValue: countdownValue ?? this.countdownValue,
    reps: reps ?? this.reps,
    elapsed: elapsed ?? this.elapsed,
    scores: scores ?? this.scores,
    pose: clearPose ? null : (pose ?? this.pose),
    mirror: mirror ?? this.mirror,
    cameraReady: cameraReady ?? this.cameraReady,
    formStatus: formStatus ?? this.formStatus,
    coachCue: clearCoachCue ? null : (coachCue ?? this.coachCue),
    depth: depth ?? this.depth,
    repJustCounted: repJustCounted ?? false,
    error: clearError ? null : (error ?? this.error),
    record: record ?? this.record,
    lensDirection: lensDirection ?? this.lensDirection,
    coachLine: coachLine ?? this.coachLine,
  );
}

/// Runs a quick challenge: each player in turn does a camera-counted round
/// of the chosen exercise. No identity check (the players are other people),
/// so nothing here touches the owner's streak or XP.
class ChallengeController extends Notifier<ChallengeState> {
  PoseDetectionService? _camera;
  ExerciseAnalyzer? _analyzer;
  final CoachingTracker _coach = CoachingTracker();
  Timer? _countdown;
  Timer? _roundTimer;
  DateTime? _roundStart;
  DateTime? _inPositionSince;
  bool _disposed = false;
  bool _ending = false;
  bool _savingResults = false;
  bool _switchingCamera = false;
  DateTime? _heldAt;
  static const _uuid = Uuid();

  /// Read once: `ref` throws inside `onDispose`, which used to stop the
  /// teardown before the camera was released.
  late VoiceCoach _voice;

  @override
  ChallengeState build() {
    _voice = ref.read(voiceCoachProvider);
    ref.onDispose(_teardown);
    final config = ref.read(challengeConfigProvider);
    final settings = ref.read(settingsProvider);
    return ChallengeState(
      config: config,
      lensDirection: settings.cameraFacing == CameraFacing.back
          ? CameraLensDirection.back
          : CameraLensDirection.front,
      coachLine: config.players.isEmpty
          ? ''
          : '${config.players.first.name}, you are up first. ${config.describe}.',
    );
  }

  Future<void> _setWakelock(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }

  void _say(String text) {
    final settings = ref.read(settingsProvider);
    _voice.enabled = settings.voiceEnabled && settings.soundEnabled;
    unawaited(_voice.say(VoiceCue.trainer, label: text));
  }

  void _cue(VoiceCue cue, {int count = 0, String? label}) {
    final settings = ref.read(settingsProvider);
    _voice.enabled = settings.voiceEnabled && settings.soundEnabled;
    unawaited(_voice.say(cue, count: count, label: label));
  }

  PoseDetectionService? get cameraService => _camera;

  /// The current player taps "ready": opens the camera and waits for them
  /// to get in position before the 3-2-1.
  Future<void> startRound() async {
    if (state.phase != RoundPhase.upNext && state.phase != RoundPhase.error) {
      return;
    }
    _ending = false;
    _inPositionSince = null;
    final target = state.timed ? null : state.config.value;
    _analyzer = ExerciseAnalyzerFactory.create(
      state.config.exercise,
      thresholds: PushUpThresholds.forSensitivity(
        ref.read(settingsProvider).formSensitivity,
      ),
      target: target ?? 9999,
    );
    _coach.reset();
    state = state.copyWith(
      phase: RoundPhase.starting,
      reps: 0,
      elapsed: 0,
      clearError: true,
      clearCoachCue: true,
      coachLine: '${state.player.name}: get into position.',
    );
    _say('${state.player.name}, get into position.');
    await _openCamera();
  }

  Future<void> _openCamera() async {
    final permission = await ref
        .read(permissionServiceProvider)
        .requestCamera();
    if (_disposed) return;
    if (permission != CameraPermissionResult.granted) {
      _fail(
        const PoseDetectionException(
          PoseDetectionErrorKind.permissionDenied,
          'camera permission not granted',
        ),
      );
      return;
    }
    final service = _camera ??= PoseDetectionService(
      preferredLens: state.lensDirection,
    );
    try {
      if (!service.isInitialized) await service.initialize();
      if (_disposed) return;
      if (!service.isStreaming) {
        await service.startStream(onPose: _onPose, onError: _fail);
      }
    } on PoseDetectionException catch (e) {
      _fail(e);
      return;
    } catch (e) {
      _fail(
        PoseDetectionException(
          PoseDetectionErrorKind.cameraUnavailable,
          e.toString(),
        ),
      );
      return;
    }
    state = state.copyWith(
      cameraReady: true,
      mirror: service.mirrorPreview,
      lensDirection: service.lensDirection,
      phase: RoundPhase.countdown,
      countdownValue: 3,
    );
    // A 30 s round plus getting in position outlasts many auto-locks, and
    // the lock ended the round.
    unawaited(_setWakelock(true));
  }

  void _fail(PoseDetectionException e) {
    debugPrint('Challenge camera error: $e');
    if (_disposed) return;
    _countdown?.cancel();
    _countdown = null;
    _roundTimer?.cancel();
    state = state.copyWith(
      phase: RoundPhase.error,
      error: e,
      cameraReady: false,
      clearPose: true,
    );
    unawaited(_setWakelock(false));
    unawaited(_camera?.releaseCamera());
  }

  Future<void> switchCamera() async {
    final c = _camera;
    if (c == null || !state.cameraReady || _switchingCamera) return;
    _switchingCamera = true;
    state = state.copyWith(cameraReady: false, clearPose: true);
    try {
      await c.switchCamera();
      if (_disposed) return;
      state = state.copyWith(
        cameraReady: true,
        mirror: c.mirrorPreview,
        lensDirection: c.lensDirection,
      );
    } on PoseDetectionException catch (e) {
      _fail(e);
    } finally {
      _switchingCamera = false;
    }
  }

  /// Stops the round's clock while the player is asked whether to leave.
  void holdRound() {
    if (state.phase != RoundPhase.active || _heldAt != null) return;
    _heldAt = DateTime.now();
  }

  /// Restarts the clock where [holdRound] stopped it.
  void releaseRound() {
    final held = _heldAt;
    _heldAt = null;
    final start = _roundStart;
    if (held == null || start == null) return;
    _roundStart = start.add(DateTime.now().difference(held));
  }

  void _onPose(PoseResult pose) {
    final analyzer = _analyzer;
    if (_disposed || analyzer == null) return;
    final mirror = _camera?.mirrorPreview ?? state.mirror;
    switch (state.phase) {
      case RoundPhase.countdown:
        final analysis = analyzer.processPose(pose);
        analyzer.resetCounting();
        state = state.copyWith(
          pose: pose,
          mirror: mirror,
          formStatus: analysis.formStatus,
        );
        if (analysis.inPosition && analysis.formStatus.isTracking) {
          _inPositionSince ??= pose.timestamp;
          if (pose.timestamp.difference(_inPositionSince!) >=
                  const Duration(milliseconds: 800) &&
              _countdown == null) {
            _beginCountdown();
          }
        } else {
          _inPositionSince = null;
        }
      case RoundPhase.active:
        if (_heldAt != null) return;
        final analysis = analyzer.processPose(pose);
        final fired = _coach.observe(analysis, pose.timestamp);
        final cue = _coach.cueAt(pose.timestamp);
        state = state.copyWith(
          pose: pose,
          mirror: mirror,
          formStatus: analysis.formStatus,
          reps: analysis.repCount,
          repJustCounted: analysis.repCounted,
          depth: analysis.depth,
          coachCue: cue,
          clearCoachCue: cue == null,
        );
        if (fired != null) {
          _cue(
            VoiceCue.coach,
            label: CoachingLibrary.cue(fired, state.config.exercise)?.spoken,
          );
        }
        if (analysis.repCounted) {
          _cue(VoiceCue.rep, count: analysis.repCount);
          unawaited(
            ref
                .read(feedbackServiceProvider)
                .repCounted(
                  vibration: ref.read(settingsProvider).vibrationEnabled,
                ),
          );
        }
        if (!state.timed && analysis.isCompleted) _endRound();
      default:
        state = state.copyWith(pose: pose, mirror: mirror);
    }
  }

  /// Lets the player start without waiting to be detected in position.
  void startCountdownNow() {
    if (state.phase == RoundPhase.countdown && _countdown == null) {
      _beginCountdown();
    }
  }

  void _beginCountdown() {
    var n = 3;
    state = state.copyWith(countdownValue: n);
    _cue(VoiceCue.three);
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      n--;
      if (n > 0) {
        state = state.copyWith(countdownValue: n);
        _cue(n == 2 ? VoiceCue.two : VoiceCue.one);
        return;
      }
      t.cancel();
      _countdown = null;
      _activate();
    });
  }

  void _activate() {
    _analyzer?.resetCounting();
    _coach.reset();
    _roundStart = DateTime.now();
    state = state.copyWith(
      phase: RoundPhase.active,
      reps: 0,
      elapsed: 0,
      countdownValue: 0,
      coachLine: 'Go, ${state.player.name}!',
    );
    _cue(VoiceCue.go);
    _roundTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final start = _roundStart;
      if (start == null || state.phase != RoundPhase.active) return;
      if (_heldAt != null) return;
      final elapsed = DateTime.now().difference(start).inMilliseconds / 1000.0;
      state = state.copyWith(elapsed: elapsed);
      if (state.timed && elapsed >= state.config.value) {
        _endRound();
      } else if (state.timed) {
        final left = state.config.value - elapsed;
        if (left <= 3.05 && left > 2.8) _cue(VoiceCue.three);
        if (left <= 2.05 && left > 1.8) _cue(VoiceCue.two);
        if (left <= 1.05 && left > 0.8) _cue(VoiceCue.one);
      }
    });
  }

  /// Ends the current round early (the player stops).
  void endRoundNow() {
    if (state.phase == RoundPhase.active) _endRound();
  }

  void _endRound() {
    if (_ending) return;
    _ending = true;
    _roundTimer?.cancel();
    _countdown?.cancel();
    _countdown = null;
    final start = _roundStart;
    final seconds = start == null
        ? 0.0
        : DateTime.now().difference(start).inMilliseconds / 1000.0;
    final score = ChallengeScore(
      player: state.player,
      reps: state.reps,
      // A timed round cut short (the app went to the background) shows the
      // time it really lasted.
      seconds: state.timed
          ? double.parse(
              seconds.clamp(0, state.config.value).toStringAsFixed(1),
            )
          : double.parse(seconds.toStringAsFixed(1)),
      formScore: _analyzer?.formScore,
    );
    _heldAt = null;
    final scores = [...state.scores, score];
    unawaited(_camera?.stopStream());
    final unit = state.config.exercise.countLabel(score.reps);
    final line = state.isLastPlayer
        ? 'Time, ${state.player.name}: ${score.reps} $unit. That is everyone.'
        : 'Time, ${state.player.name}: ${score.reps} $unit. '
              'Next up: ${state.config.players[state.playerIndex + 1].name}.';
    state = state.copyWith(
      phase: RoundPhase.roundOver,
      scores: scores,
      coachLine: line,
      clearCoachCue: true,
      clearPose: true,
    );
    _say(line);
  }

  /// Moves to the next player, or to the results.
  Future<void> next() async {
    if (state.phase != RoundPhase.roundOver) return;
    if (state.isLastPlayer) {
      await _finish();
      return;
    }
    state = state.copyWith(
      playerIndex: state.playerIndex + 1,
      phase: RoundPhase.upNext,
      reps: 0,
      elapsed: 0,
      coachLine:
          '${state.config.players[state.playerIndex + 1].name}, you are up.',
    );
  }

  Future<void> _finish() async {
    if (_savingResults) return;
    _savingResults = true;
    unawaited(_setWakelock(false));
    final ranked = ChallengeRecord.ranked(state.scores, state.config.mode);
    final record = ChallengeRecord(
      id: _uuid.v4(),
      date: DateTime.now(),
      exercise: state.config.exercise,
      mode: state.config.mode,
      value: state.config.value,
      scores: ranked,
    );
    await _camera?.releaseCamera();
    try {
      await ref.read(challengeRecordsProvider.notifier).add(record);
    } catch (e) {
      debugPrint('Saving challenge failed: $e');
    }
    if (_disposed) return;
    final line = record.tie
        ? 'A tie! ${record.scores[0].player.name} and '
              '${record.scores[1].player.name} share the cup.'
        : '${record.winner!.player.name} takes the cup with '
              '${record.winner!.reps} ${state.config.exercise.countLabel(record.winner!.reps)}!';
    state = state.copyWith(
      phase: RoundPhase.finished,
      record: record,
      coachLine: line,
      cameraReady: false,
    );
    _say(line);
    unawaited(
      ref
          .read(feedbackServiceProvider)
          .setCompleted(
            sound: ref.read(settingsProvider).soundEnabled,
            vibration: ref.read(settingsProvider).vibrationEnabled,
          ),
    );
  }

  /// Same players, same rules, fresh scores.
  void rematch() {
    _ending = false;
    _savingResults = false;
    state = ChallengeState(
      config: state.config,
      lensDirection: state.lensDirection,
      coachLine: 'Rematch! ${state.config.players.first.name}, you are up.',
    );
  }

  Future<void> onAppBackgrounded() async {
    if (_disposed) return;
    _countdown?.cancel();
    _countdown = null;
    _heldAt = null;
    if (state.phase == RoundPhase.active) _endRound();
    final wasStarting =
        state.phase == RoundPhase.starting ||
        state.phase == RoundPhase.countdown;
    await _camera?.releaseCamera();
    unawaited(_setWakelock(false));
    if (_disposed) return;
    state = state.copyWith(
      cameraReady: false,
      clearPose: true,
      // Nothing reopens the camera mid-countdown: back to "ready" so the
      // player can start again.
      phase: wasStarting ? RoundPhase.upNext : null,
      coachLine: wasStarting
          ? '${state.player.name}, tap ready when you are set.'
          : null,
    );
  }

  /// Back from the settings app: a camera permission granted there lets
  /// the player try again straight away.
  Future<void> onAppResumed() async {
    if (_disposed || state.phase != RoundPhase.error) return;
    if (state.error?.kind != PoseDetectionErrorKind.permissionDenied) return;
    final status = await ref.read(permissionServiceProvider).cameraStatus();
    if (_disposed || status != CameraPermissionResult.granted) return;
    state = state.copyWith(phase: RoundPhase.upNext, clearError: true);
  }

  void _teardown() {
    _disposed = true;
    _countdown?.cancel();
    _roundTimer?.cancel();
    unawaited(_voice.stop());
    unawaited(_setWakelock(false));
    final c = _camera;
    _camera = null;
    _analyzer = null;
    if (c != null) unawaited(c.dispose());
  }
}

final challengeControllerProvider =
    NotifierProvider.autoDispose<ChallengeController, ChallengeState>(
      ChallengeController.new,
    );
