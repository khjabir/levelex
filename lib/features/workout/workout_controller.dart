import 'dart:async';

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/permissions/permission_service.dart';
import '../../models/coaching.dart';
import '../../models/exercise.dart';
import '../../models/face_template.dart';
import '../../models/form_status.dart';
import '../../models/pose_result.dart';
import '../../models/user_settings.dart';
import '../../models/workout_session.dart';
import '../../services/face_service.dart';
import '../../services/pose_detection_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_coach.dart';
import '../../services/workout_service.dart';
import 'analysis/analyzer_factory.dart';
import 'analysis/body_tracker.dart';
import 'analysis/coaching_tracker.dart';
import 'push_up_analyzer.dart';

/// What the completion screen receives: the saved session (null when nothing
/// was recorded) and the tracker's plain-text report.
class WorkoutOutcome {
  const WorkoutOutcome({
    required this.session,
    required this.report,
    this.mistakes = const {},
    this.xpEarned = 0,
    this.verified = true,
  });

  final WorkoutSession? session;
  final String report;

  /// False when the face check was skipped: the set is saved but does not
  /// count towards the streak or XP.
  final bool verified;

  /// Coaching mistakes during the set (status → episodes).
  final Map<FormStatus, int> mistakes;

  /// Experience points the saved session is worth.
  final int xpEarned;
}

/// Where the workout screen is in its flow.
enum WorkoutPhase {
  idle,
  initializing,

  /// Camera is running; confirming the registered user is in front of it.
  verifying,

  /// Waiting for the body to be stably in the start position.
  calibrating,

  /// 3-2-1-GO. Reps are not counted yet.
  countdown,

  /// Counting reps (or timing a hold).
  active,

  /// Paused by the user, by the app going to the background, or because the
  /// registered user was no longer recognised.
  paused,

  /// The set is over; [WorkoutState.result] holds the saved session (null if
  /// nothing was recorded).
  finished,

  /// Camera, detector or identity failure; see [WorkoutState.error] and
  /// [WorkoutState.faceStatus].
  error,
}

/// Progress of face verification.
enum FaceVerificationStatus {
  pending,
  lookingForFace,
  tooSmall,
  turnedAway,
  matched,

  /// Somebody other than the registered user.
  mismatched,
  timedOut,
  notRegistered,

  /// The face model could not be loaded.
  unavailable;

  String get message => switch (this) {
    FaceVerificationStatus.pending => 'Preparing face check…',
    FaceVerificationStatus.lookingForFace => 'Look at the camera',
    FaceVerificationStatus.tooSmall => 'Move closer to the camera',
    FaceVerificationStatus.turnedAway => 'Look straight at the camera',
    FaceVerificationStatus.matched => 'Welcome back!',
    FaceVerificationStatus.mismatched =>
      "This doesn't look like the registered user",
    FaceVerificationStatus.timedOut => "We couldn't recognise you",
    FaceVerificationStatus.notRegistered =>
      'Register your face once before your first set',
    FaceVerificationStatus.unavailable =>
      'Face verification is unavailable on this device',
  };
}

/// Immutable snapshot rendered by the workout screen.
class WorkoutState {
  const WorkoutState({
    required this.phase,
    required this.targetReps,
    this.exercise = ExerciseType.pushUp,
    this.repCount = 0,
    this.formStatus = FormStatus.bodyNotVisible,
    this.isWorking = false,
    this.countdownValue = CameraConstants.countdownSeconds,
    this.calibrationProgress = 0,
    this.pose,
    this.mirror = false,
    this.cameraReady = false,
    this.error,
    this.permissionPermanentlyDenied = false,
    this.result,
    this.repJustCounted = false,
    this.faceStatus = FaceVerificationStatus.pending,
    this.lensDirection = CameraLensDirection.front,
    this.canSwitchCamera = false,
    this.pausedByIdentity = false,
    this.depth = 0,
    this.limbsUsed = 0,
    this.identityWarning = false,
    this.secondsHeld = 0,
    this.signal,
    this.restThreshold,
    this.workThreshold,
    this.bodyTilt,
    this.trackQuality = TrackQuality.missing,
    this.report,
    this.coachCue,
    this.mistakes = const {},
    this.verified = true,
  });

  final WorkoutPhase phase;
  final ExerciseType exercise;

  /// Target reps, or target seconds for timed exercises.
  final int targetReps;

  /// Reps so far, or whole seconds held for timed exercises.
  final int repCount;
  final FormStatus formStatus;

  /// True while the analyzer is in the work phase (bottom of a push-up,
  /// holding a plank, …).
  final bool isWorking;

  /// Seconds left in the countdown; `0` means "GO!".
  final int countdownValue;

  /// `0..1` while calibrating.
  final double calibrationProgress;

  /// Latest pose for the overlay painter.
  final PoseResult? pose;

  /// Whether landmark x coordinates must be flipped to match the preview.
  final bool mirror;
  final bool cameraReady;
  final PoseDetectionException? error;
  final bool permissionPermanentlyDenied;
  final WorkoutSession? result;

  /// Pulses true for the frame on which a rep was counted (for animations).
  final bool repJustCounted;
  final FaceVerificationStatus faceStatus;
  final CameraLensDirection lensDirection;
  final bool canSwitchCamera;

  /// True when the current pause was triggered by an identity mismatch.
  final bool pausedByIdentity;

  /// How far into the work position the current rep is (0..1).
  final double depth;

  /// Arms or legs contributing to the signal (0, 1 or 2).
  final int limbsUsed;

  /// True while mid-set spot checks keep failing (before pausing).
  final bool identityWarning;

  /// Timed exercises: seconds held so far.
  final double secondsHeld;

  /// Live tracking numbers for the optional details overlay.
  final double? signal;
  final double? restThreshold;
  final double? workThreshold;
  final double? bodyTilt;
  final TrackQuality trackQuality;

  /// Tracking report, available once the set has finished.
  final String? report;

  /// Correction the coach is showing right now, if any.
  final FormStatus? coachCue;

  /// Mistakes so far in this set.
  final Map<FormStatus, int> mistakes;

  /// False once the user chose to skip the face check.
  final bool verified;

  double get progress => targetReps == 0 ? 0 : repCount / targetReps;
  bool get isRunning =>
      phase == WorkoutPhase.calibrating ||
      phase == WorkoutPhase.countdown ||
      phase == WorkoutPhase.active;

  /// Error phase caused by identity rather than the camera.
  bool get isFaceError =>
      phase == WorkoutPhase.error &&
      error == null &&
      faceStatus != FaceVerificationStatus.matched;

  WorkoutState copyWith({
    WorkoutPhase? phase,
    ExerciseType? exercise,
    int? targetReps,
    int? repCount,
    FormStatus? formStatus,
    bool? isWorking,
    int? countdownValue,
    double? calibrationProgress,
    PoseResult? pose,
    bool clearPose = false,
    bool? mirror,
    bool? cameraReady,
    PoseDetectionException? error,
    bool clearError = false,
    bool? permissionPermanentlyDenied,
    WorkoutSession? result,
    bool? repJustCounted,
    FaceVerificationStatus? faceStatus,
    CameraLensDirection? lensDirection,
    bool? canSwitchCamera,
    bool? pausedByIdentity,
    double? depth,
    int? limbsUsed,
    bool? identityWarning,
    double? secondsHeld,
    double? signal,
    double? restThreshold,
    double? workThreshold,
    double? bodyTilt,
    TrackQuality? trackQuality,
    String? report,
    FormStatus? coachCue,
    bool clearCoachCue = false,
    Map<FormStatus, int>? mistakes,
    bool? verified,
  }) {
    return WorkoutState(
      phase: phase ?? this.phase,
      exercise: exercise ?? this.exercise,
      targetReps: targetReps ?? this.targetReps,
      repCount: repCount ?? this.repCount,
      formStatus: formStatus ?? this.formStatus,
      isWorking: isWorking ?? this.isWorking,
      countdownValue: countdownValue ?? this.countdownValue,
      calibrationProgress: calibrationProgress ?? this.calibrationProgress,
      pose: clearPose ? null : (pose ?? this.pose),
      mirror: mirror ?? this.mirror,
      cameraReady: cameraReady ?? this.cameraReady,
      error: clearError ? null : (error ?? this.error),
      permissionPermanentlyDenied:
          permissionPermanentlyDenied ?? this.permissionPermanentlyDenied,
      result: result ?? this.result,
      repJustCounted: repJustCounted ?? false,
      faceStatus: faceStatus ?? this.faceStatus,
      lensDirection: lensDirection ?? this.lensDirection,
      canSwitchCamera: canSwitchCamera ?? this.canSwitchCamera,
      pausedByIdentity: pausedByIdentity ?? this.pausedByIdentity,
      depth: depth ?? this.depth,
      limbsUsed: limbsUsed ?? this.limbsUsed,
      identityWarning: identityWarning ?? this.identityWarning,
      secondsHeld: secondsHeld ?? this.secondsHeld,
      signal: signal ?? this.signal,
      restThreshold: restThreshold ?? this.restThreshold,
      workThreshold: workThreshold ?? this.workThreshold,
      bodyTilt: bodyTilt ?? this.bodyTilt,
      trackQuality: trackQuality ?? this.trackQuality,
      report: report ?? this.report,
      coachCue: clearCoachCue ? null : (coachCue ?? this.coachCue),
      mistakes: mistakes ?? this.mistakes,
      verified: verified ?? this.verified,
    );
  }
}

/// Drives one set: camera permission, camera + detector lifecycle, identity
/// verification, calibration, countdown, counting/timing and saving.
///
/// The widget layer only renders [WorkoutState] and forwards user actions and
/// app-lifecycle events here.
class WorkoutController extends Notifier<WorkoutState> {
  PoseDetectionService? _service;
  FaceService? _faceService;
  ExerciseAnalyzer? _analyzer;
  final CoachingTracker _coach = CoachingTracker();
  Timer? _countdownTimer;
  Timer? _goTimer;
  Timer? _verificationTimer;
  DateTime? _calibrationStartedAt;
  DateTime? _verificationStartedAt;
  String? _sessionId;
  DateTime? _startTime;
  bool _cameraReleasedByLifecycle = false;
  bool _finishing = false;
  bool _disposed = false;
  int _matchStreak = 0;
  int _mismatchStreak = 0;
  FormStatus? _persistingForm;
  DateTime? _formSince;

  @override
  WorkoutState build() {
    ref.onDispose(_teardown);
    final settings = ref.read(settingsProvider);
    return WorkoutState(
      phase: WorkoutPhase.idle,
      exercise: settings.selectedExercise,
      targetReps: settings.targetFor(settings.selectedExercise),
      lensDirection: _lensFor(settings.cameraFacing),
    );
  }

  PoseDetectionService? get service => _service;

  VoiceCoach get _voice => ref.read(voiceCoachProvider);

  void _say(VoiceCue cue, {int count = 0, String? label}) {
    final settings = ref.read(settingsProvider);
    _voice.enabled = settings.voiceEnabled && settings.soundEnabled;
    unawaited(
      _voice.say(
        cue,
        count: count,
        label: label ?? state.exercise.countLabel(count),
      ),
    );
  }

  static CameraLensDirection _lensFor(CameraFacing facing) =>
      facing == CameraFacing.back
      ? CameraLensDirection.back
      : CameraLensDirection.front;

  // ---------------------------------------------------------------------------
  // Starting
  // ---------------------------------------------------------------------------

  /// Requests camera permission, opens the camera and begins verification.
  /// With [bypassIdentity] the face check is skipped: the set is tracked and
  /// saved but marked unverified (no streak, no XP).
  Future<void> start({bool bypassIdentity = false}) async {
    if (state.phase != WorkoutPhase.idle && state.phase != WorkoutPhase.error) {
      return;
    }
    _cancelTimers();
    _matchStreak = 0;
    _mismatchStreak = 0;
    _voice.resetScript();
    unawaited(_voice.initialize());
    state = state.copyWith(
      phase: WorkoutPhase.initializing,
      clearError: true,
      permissionPermanentlyDenied: false,
      repCount: 0,
      faceStatus: FaceVerificationStatus.pending,
      pausedByIdentity: false,
      verified: !bypassIdentity,
    );

    if (!bypassIdentity &&
        !ref.read(workoutServiceProvider).hasRegisteredFace) {
      state = state.copyWith(
        phase: WorkoutPhase.error,
        faceStatus: FaceVerificationStatus.notRegistered,
      );
      return;
    }

    final permission = await ref
        .read(permissionServiceProvider)
        .requestCamera();
    if (_disposed || state.phase != WorkoutPhase.initializing) return;
    if (permission != CameraPermissionResult.granted) {
      state = state.copyWith(
        phase: WorkoutPhase.error,
        error: const PoseDetectionException(
          PoseDetectionErrorKind.permissionDenied,
          'camera permission not granted',
        ),
        permissionPermanentlyDenied:
            permission == CameraPermissionResult.permanentlyDenied,
      );
      return;
    }

    final settings = ref.read(settingsProvider);
    final exercise = settings.selectedExercise;
    final target = settings.targetFor(exercise);
    _analyzer = ExerciseAnalyzerFactory.create(
      exercise,
      thresholds: PushUpThresholds.forSensitivity(settings.formSensitivity),
      target: target,
    );
    _sessionId = WorkoutService.newSessionId();
    _startTime = DateTime.now();
    state = state.copyWith(targetReps: target, exercise: exercise);

    final opened = await _openCamera();
    if (!opened) return;
    if (bypassIdentity) {
      state = state.copyWith(faceStatus: FaceVerificationStatus.matched);
      _say(VoiceCue.getInPosition, label: state.exercise.positionHint);
      _enterCalibration();
    } else {
      await _enterVerification();
    }
    // If the app went to the background while the camera was opening, pause
    // right away so the camera is never held while backgrounded.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      await onAppBackgrounded();
    }
  }

  /// Opens the camera and starts streaming. Returns false (and sets the error
  /// state) on failure.
  Future<bool> _openCamera() async {
    final service = _service ??= PoseDetectionService(
      preferredLens: state.lensDirection,
    );
    try {
      await service.initialize();
      if (_disposed || _finishing) {
        await service.releaseCamera();
        return false;
      }
      await service.startStream(onPose: _onPose, onError: _onDetectionError);
    } on PoseDetectionException catch (e) {
      _fail(e);
      return false;
    } catch (e) {
      _fail(
        PoseDetectionException(
          PoseDetectionErrorKind.cameraUnavailable,
          e.toString(),
        ),
      );
      return false;
    }
    service.onFrame = _onFrame;
    _cameraReleasedByLifecycle = false;
    final canSwitch = await service.hasOtherCamera();
    if (_disposed) return false;
    state = state.copyWith(
      cameraReady: true,
      mirror: service.mirrorPreview,
      lensDirection: service.lensDirection,
      canSwitchCamera: canSwitch,
    );
    unawaited(_setWakelock(true));
    return true;
  }

  void _fail(PoseDetectionException error) {
    debugPrint('Workout error: $error');
    if (_disposed || state.phase == WorkoutPhase.finished) return;
    _cancelTimers();
    state = state.copyWith(
      phase: WorkoutPhase.error,
      error: error,
      cameraReady: false,
      clearPose: true,
    );
    unawaited(_setWakelock(false));
  }

  void _onDetectionError(PoseDetectionException error) {
    if (state.phase == WorkoutPhase.finished) return;
    _fail(error);
  }

  // ---------------------------------------------------------------------------
  // Identity verification
  // ---------------------------------------------------------------------------

  Future<void> _enterVerification() async {
    _matchStreak = 0;
    _mismatchStreak = 0;
    _verificationStartedAt = DateTime.now();
    state = state.copyWith(
      phase: WorkoutPhase.verifying,
      faceStatus: FaceVerificationStatus.pending,
      clearError: true,
      pausedByIdentity: false,
    );
    final face = _faceService ??= FaceService();
    try {
      await face.initialize();
    } catch (e) {
      debugPrint('Face model failed to load: $e');
      if (_disposed) return;
      state = state.copyWith(
        phase: WorkoutPhase.error,
        faceStatus: FaceVerificationStatus.unavailable,
      );
      return;
    }
    if (_disposed || state.phase != WorkoutPhase.verifying) return;
    state = state.copyWith(faceStatus: FaceVerificationStatus.lookingForFace);
    _say(VoiceCue.lookAtCamera);
    _verificationTimer?.cancel();
    _verificationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _verificationStartedAt;
      if (state.phase != WorkoutPhase.verifying || started == null) return;
      if (DateTime.now().difference(started) >
          FaceConstants.verificationTimeout) {
        _verificationTimer?.cancel();
        state = state.copyWith(
          phase: WorkoutPhase.error,
          faceStatus: FaceVerificationStatus.timedOut,
          clearPose: true,
        );
      }
    });
  }

  /// Skips the face check mid-verification. The set continues unverified.
  void skipVerification() {
    if (state.phase != WorkoutPhase.verifying) return;
    _verificationTimer?.cancel();
    state = state.copyWith(
      verified: false,
      faceStatus: FaceVerificationStatus.matched,
    );
    _say(VoiceCue.getInPosition, label: state.exercise.positionHint);
    _enterCalibration();
  }

  /// Low-rate raw frames: identity checks before and during the set.
  Future<void> _onFrame(CameraFrame frame) async {
    if (!state.verified) return; // Bypassed: no checks at all.
    final face = _faceService;
    final template = ref.read(workoutServiceProvider).faceTemplate;
    if (face == null || template == null || _disposed) return;
    final phase = state.phase;
    final verifying = phase == WorkoutPhase.verifying;
    final spotCheck =
        phase == WorkoutPhase.calibrating ||
        phase == WorkoutPhase.countdown ||
        phase == WorkoutPhase.active;
    if (!verifying && !spotCheck) return;

    final analysis = await face.analyze(frame);
    if (analysis == null || _disposed || state.phase != phase) return;

    final sample = analysis.sample;
    if (sample == null) {
      if (verifying) {
        state = state.copyWith(
          faceStatus: switch (analysis.failure) {
            FaceSampleFailure.tooSmall => FaceVerificationStatus.tooSmall,
            FaceSampleFailure.turnedAway => FaceVerificationStatus.turnedAway,
            _ => FaceVerificationStatus.lookingForFace,
          },
        );
      }
      return;
    }

    if (!verifying &&
        (sample.faceWidthRatio < FaceConstants.spotCheckMinFaceWidthRatio ||
            sample.yaw.abs() > FaceConstants.spotCheckMaxHeadYaw)) {
      return; // Mid-set: only judge clearly visible, frontal faces.
    }
    final match = template.compare(sample.embedding);
    if (verifying) {
      _handleVerificationSample(match);
    } else {
      _handleSpotCheck(match);
    }
  }

  void _handleVerificationSample(FaceMatch match) {
    switch (match) {
      case FaceMatch.match:
        _matchStreak++;
        _mismatchStreak = 0;
        if (_matchStreak >= FaceConstants.requiredMatches) {
          _verificationTimer?.cancel();
          state = state.copyWith(faceStatus: FaceVerificationStatus.matched);
          _say(VoiceCue.verified, label: state.exercise.positionHint);
          _enterCalibration();
        }
      case FaceMatch.mismatch:
        _mismatchStreak++;
        _matchStreak = 0;
        if (_mismatchStreak >= FaceConstants.mismatchesToReject) {
          _verificationTimer?.cancel();
          state = state.copyWith(
            phase: WorkoutPhase.error,
            faceStatus: FaceVerificationStatus.mismatched,
            clearPose: true,
          );
        }
      case FaceMatch.unknown:
        state = state.copyWith(
          faceStatus: FaceVerificationStatus.lookingForFace,
        );
    }
  }

  void _handleSpotCheck(FaceMatch match) {
    switch (match) {
      case FaceMatch.match:
        _mismatchStreak = 0;
        if (state.identityWarning) {
          state = state.copyWith(identityWarning: false);
        }
      case FaceMatch.mismatch:
        _mismatchStreak++;
        if (_mismatchStreak >= FaceConstants.mismatchesToPause) {
          _mismatchStreak = 0;
          unawaited(_pauseForIdentity());
        } else if (_mismatchStreak >= FaceConstants.mismatchesToPause ~/ 2) {
          if (!state.identityWarning) {
            state = state.copyWith(identityWarning: true);
            _say(VoiceCue.notRecognised);
          }
        }
      case FaceMatch.unknown:
        break;
    }
  }

  Future<void> _pauseForIdentity() async {
    if (!state.isRunning) return;
    _cancelTimers();
    state = state.copyWith(
      phase: WorkoutPhase.paused,
      faceStatus: FaceVerificationStatus.mismatched,
      pausedByIdentity: true,
      identityWarning: false,
      clearPose: true,
    );
    _say(VoiceCue.paused);
    await _service?.stopStream();
  }

  // ---------------------------------------------------------------------------
  // Calibration & countdown
  // ---------------------------------------------------------------------------

  void _enterCalibration() {
    _calibrationStartedAt = null;
    _persistingForm = null;
    state = state.copyWith(
      phase: WorkoutPhase.calibrating,
      calibrationProgress: 0,
      countdownValue: CameraConstants.countdownSeconds,
      pausedByIdentity: false,
      identityWarning: false,
    );
  }

  /// Lets the user skip the automatic calibration wait.
  void startCountdownNow() {
    if (state.phase != WorkoutPhase.calibrating) return;
    _beginCountdown();
  }

  static VoiceCue _countdownCue(int n) => switch (n) {
    3 => VoiceCue.three,
    2 => VoiceCue.two,
    _ => VoiceCue.one,
  };

  void _beginCountdown() {
    _cancelTimers();
    var remaining = CameraConstants.countdownSeconds;
    state = state.copyWith(
      phase: WorkoutPhase.countdown,
      countdownValue: remaining,
    );
    _say(VoiceCue.ready);
    // "Ready" needs a beat before the numbers start.
    _goTimer = Timer(const Duration(milliseconds: 900), () {
      if (state.phase != WorkoutPhase.countdown) return;
      _say(_countdownCue(remaining));
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        remaining--;
        if (remaining > 0) {
          state = state.copyWith(countdownValue: remaining);
          _say(_countdownCue(remaining));
          return;
        }
        timer.cancel();
        // Show "GO!" briefly, then start counting.
        state = state.copyWith(countdownValue: 0);
        _say(VoiceCue.go);
        _goTimer = Timer(const Duration(milliseconds: 700), _activate);
      });
    });
  }

  void _activate() {
    if (state.phase != WorkoutPhase.countdown) return;
    // Keep the body tracker warm so the first rep counts right away.
    _analyzer?.resetCounting();
    _coach.reset();
    state = state.copyWith(
      phase: WorkoutPhase.active,
      repCount: 0,
      clearCoachCue: true,
      mistakes: const {},
    );
  }

  // ---------------------------------------------------------------------------
  // Pose processing
  // ---------------------------------------------------------------------------

  void _onPose(PoseResult pose) {
    final analyzer = _analyzer;
    if (analyzer == null || _disposed) return;
    final mirror = _service?.mirrorPreview ?? state.mirror;

    switch (state.phase) {
      case WorkoutPhase.verifying:
        state = state.copyWith(pose: pose, mirror: mirror);
      case WorkoutPhase.calibrating:
        final analysis = analyzer.processPose(pose);
        _resetCounting(analyzer); // Only feedback matters before the countdown.
        _updateCalibration(analysis, pose, mirror);
      case WorkoutPhase.countdown:
        final analysis = analyzer.processPose(pose);
        _resetCounting(analyzer);
        state = state.copyWith(
          pose: pose,
          mirror: mirror,
          formStatus: analysis.formStatus,
          bodyTilt: analysis.bodyTilt,
          trackQuality: analysis.trackQuality,
        );
      case WorkoutPhase.active:
        final analysis = analyzer.processPose(pose);
        final fired = _coach.observe(analysis, pose.timestamp);
        final cue = _coach.cueAt(pose.timestamp);
        state = state.copyWith(
          pose: pose,
          mirror: mirror,
          formStatus: analysis.formStatus,
          isWorking: analysis.isWorking,
          repCount: analysis.repCount,
          repJustCounted: analysis.repCounted,
          depth: analysis.depth,
          limbsUsed: analysis.limbsUsed,
          secondsHeld: analysis.secondsHeld,
          signal: analysis.signal,
          restThreshold: analysis.restThreshold,
          workThreshold: analysis.workThreshold,
          bodyTilt: analysis.bodyTilt,
          trackQuality: analysis.trackQuality,
          coachCue: cue,
          clearCoachCue: cue == null,
          mistakes: fired == null ? null : _coach.mistakes,
        );
        if (fired != null) {
          _say(
            VoiceCue.coach,
            label: CoachingLibrary.cue(fired, state.exercise)?.spoken,
          );
        } else if (!analysis.formStatus.isTracking) {
          _maybeSpeakFormCue(analysis.formStatus, pose.timestamp);
        }
        if (analysis.repCounted) _onRepCounted(analysis.repCount);
        if (analysis.isCompleted) {
          unawaited(_finish(targetReached: true));
        }
      case WorkoutPhase.idle:
      case WorkoutPhase.initializing:
      case WorkoutPhase.paused:
      case WorkoutPhase.finished:
      case WorkoutPhase.error:
        break;
    }
  }

  /// Before the set starts the analyzer only provides feedback; its counter
  /// is cleared every frame so nothing leaks into the set, while the
  /// continuity tracker stays warm.
  void _resetCounting(ExerciseAnalyzer analyzer) => analyzer.resetCounting();

  void _updateCalibration(
    ExerciseAnalysis analysis,
    PoseResult pose,
    bool mirror,
  ) {
    final now = pose.timestamp;
    double progress;
    // Calibration completes only once the body is in the start position.
    if (analysis.formStatus.isTracking && analysis.inPosition) {
      _calibrationStartedAt ??= now;
      final elapsed = now.difference(_calibrationStartedAt!);
      progress =
          elapsed.inMilliseconds /
          CameraConstants.calibrationDuration.inMilliseconds;
    } else {
      _calibrationStartedAt = null;
      progress = 0;
    }
    state = state.copyWith(
      pose: pose,
      mirror: mirror,
      formStatus: analysis.formStatus,
      calibrationProgress: progress.clamp(0, 1),
      depth: analysis.depth,
      limbsUsed: analysis.limbsUsed,
      bodyTilt: analysis.bodyTilt,
      trackQuality: analysis.trackQuality,
    );
    if (progress >= 1) {
      _beginCountdown();
    } else if (!analysis.inPosition || !analysis.formStatus.isTracking) {
      _maybeSpeakFormCue(analysis.formStatus, now);
    }
  }

  /// Speaks a form/visibility cue once the same status has persisted for a
  /// moment (the script rate-limits repeats).
  void _maybeSpeakFormCue(FormStatus status, DateTime now) {
    if (status != _persistingForm) {
      _persistingForm = status;
      _formSince = now;
      return;
    }
    final since = _formSince;
    if (since == null || now.difference(since) < const Duration(seconds: 2)) {
      return;
    }
    final cue = switch (status) {
      FormStatus.hipsTooHigh => VoiceCue.hipsLower,
      FormStatus.hipsTooLow => VoiceCue.hipsHigher,
      FormStatus.moveBack => VoiceCue.moveBack,
      FormStatus.bodyNotVisible ||
      FormStatus.armNotVisible => VoiceCue.bodyNotVisible,
      FormStatus.notInPosition => VoiceCue.getInPosition,
      FormStatus.goodForm ||
      FormStatus.lowConfidence ||
      FormStatus.torsoLeaning ||
      FormStatus.armsNotOverhead ||
      FormStatus.goDeeper ||
      FormStatus.slowDown => null,
    };
    if (cue == null) return;
    if (cue == VoiceCue.getInPosition) {
      _say(cue, label: state.exercise.positionHint);
    } else {
      _say(cue);
    }
  }

  void _onRepCounted(int count) {
    final settings = ref.read(settingsProvider);
    if (state.exercise.isTimed) {
      final remaining = state.targetReps - count;
      if (remaining > 0 && remaining <= 3) {
        _say(_countdownCue(remaining));
      } else if (count % 10 == 0) {
        _say(VoiceCue.secondsHeld, count: count);
      }
    } else {
      _say(VoiceCue.rep, count: count);
    }
    unawaited(
      ref
          .read(feedbackServiceProvider)
          .repCounted(vibration: settings.vibrationEnabled),
    );
    final id = _sessionId;
    final start = _startTime;
    if (id != null && start != null) {
      unawaited(
        ref
            .read(workoutServiceProvider)
            .saveDraft(
              WorkoutDraft(
                id: id,
                startTime: start,
                targetReps: state.targetReps,
                reps: count,
                exercise: state.exercise,
              ),
            )
            .catchError((Object e) => debugPrint('Draft save failed: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Camera switching
  // ---------------------------------------------------------------------------

  /// Flips between the front and back camera, remembers the choice, and
  /// re-runs calibration because the view changed.
  Future<void> switchCamera() async {
    final service = _service;
    if (service == null || !state.cameraReady || !state.canSwitchCamera) {
      return;
    }
    final wasRunning = state.isRunning;
    _cancelTimers();
    state = state.copyWith(cameraReady: false, clearPose: true);
    try {
      await service.switchCamera();
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
    if (_disposed) return;
    service.onFrame = _onFrame;
    final facing = service.lensDirection == CameraLensDirection.back
        ? CameraFacing.back
        : CameraFacing.front;
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(cameraFacing: facing)),
    );
    state = state.copyWith(
      cameraReady: true,
      mirror: service.mirrorPreview,
      lensDirection: service.lensDirection,
    );
    _say(VoiceCue.cameraSwitched);
    if (wasRunning) _enterCalibration();
  }

  // ---------------------------------------------------------------------------
  // Pause / resume / finish
  // ---------------------------------------------------------------------------

  Future<void> pause() async {
    if (!state.isRunning) return;
    _cancelTimers();
    state = state.copyWith(
      phase: WorkoutPhase.paused,
      clearPose: true,
      pausedByIdentity: false,
    );
    _say(VoiceCue.paused);
    await _service?.stopStream();
  }

  Future<void> resume() async {
    if (state.phase != WorkoutPhase.paused) return;
    if (_cameraReleasedByLifecycle || !(_service?.isInitialized ?? false)) {
      final opened = await _openCamera();
      if (!opened || _disposed) return;
    } else {
      try {
        await _service!.startStream(
          onPose: _onPose,
          onError: _onDetectionError,
        );
      } on PoseDetectionException catch (e) {
        _fail(e);
        return;
      }
    }
    // A pause caused by an identity mismatch requires re-verification; a
    // normal pause resumes through calibration so the user can get back
    // into position.
    if (state.pausedByIdentity) {
      await _enterVerification();
    } else {
      _enterCalibration();
    }
  }

  /// Ends the set early. Reps performed so far are saved as an incomplete
  /// session; a set with zero reps is discarded.
  Future<void> finish() => _finish(targetReached: false);

  Future<void> _finish({required bool targetReached}) async {
    if (_finishing || state.phase == WorkoutPhase.finished) return;
    _finishing = true;
    _cancelTimers();
    final reps = state.repCount;
    final formScore = _analyzer?.formScore;
    final mistakes = Map<FormStatus, int>.from(_coach.mistakes);
    final report = _buildReport();

    await _service?.stopStream();
    await _service?.releaseCamera();
    unawaited(_setWakelock(false));

    WorkoutSession? session;
    final id = _sessionId;
    final start = _startTime;
    if (reps > 0 && id != null && start != null) {
      try {
        session = await ref
            .read(sessionsProvider.notifier)
            .recordWorkout(
              id: id,
              startTime: start,
              targetReps: state.targetReps,
              reps: reps,
              formScore: formScore,
              exercise: state.exercise,
              mistakes: mistakes,
              verified: state.verified,
            );
      } catch (e) {
        debugPrint('Saving session failed: $e');
      }
    } else {
      unawaited(ref.read(workoutServiceProvider).clearDraft());
    }

    if (targetReached) {
      final settings = ref.read(settingsProvider);
      _say(VoiceCue.complete, count: reps);
      unawaited(
        ref
            .read(feedbackServiceProvider)
            .setCompleted(
              sound: settings.soundEnabled,
              vibration: settings.vibrationEnabled,
            ),
      );
    } else if (reps > 0) {
      _say(VoiceCue.setEnded, count: reps);
    } else {
      unawaited(_voice.stop());
    }

    if (_disposed) return;
    state = state.copyWith(
      phase: WorkoutPhase.finished,
      result: session,
      report: report,
      mistakes: mistakes,
      cameraReady: false,
      clearPose: true,
      clearCoachCue: true,
    );
  }

  /// Plain-text tracking summary for support: numbers only, no images.
  String _buildReport() {
    final analyzer = _analyzer;
    return [
      if (analyzer != null) analyzer.diagnostics.report(),
      'camera=${state.lensDirection.name} mirror=${state.mirror} '
          'target=${state.targetReps} counted=${state.repCount}',
      'form sensitivity=${ref.read(settingsProvider).formSensitivity.name} '
          'verified=${state.verified}',
      'mistakes=${_coach.mistakes.entries.map((e) => '${e.key.name}=${e.value}').join(',')}',
    ].join('\n');
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  /// Called when the app leaves the foreground: stop processing and release
  /// the camera so it is never held in the background.
  Future<void> onAppBackgrounded() async {
    if (_disposed ||
        state.phase == WorkoutPhase.finished ||
        state.phase == WorkoutPhase.idle ||
        state.phase == WorkoutPhase.initializing) {
      return;
    }
    _cancelTimers();
    if (state.isRunning || state.phase == WorkoutPhase.verifying) {
      state = state.copyWith(phase: WorkoutPhase.paused, clearPose: true);
    }
    _cameraReleasedByLifecycle = true;
    state = state.copyWith(cameraReady: false);
    await _service?.releaseCamera();
    unawaited(_setWakelock(false));
  }

  /// Called when the app returns to the foreground. The camera is reopened
  /// (so the preview is visible) but counting stays paused until the user
  /// taps resume.
  Future<void> onAppResumed() async {
    if (_disposed ||
        state.phase != WorkoutPhase.paused ||
        !_cameraReleasedByLifecycle) {
      return;
    }
    final service = _service;
    if (service == null) return;
    try {
      await service.initialize();
      if (_disposed) return;
      _cameraReleasedByLifecycle = false;
      state = state.copyWith(cameraReady: true, mirror: service.mirrorPreview);
    } on PoseDetectionException catch (e) {
      _fail(e);
    } catch (e) {
      _fail(
        PoseDetectionException(
          PoseDetectionErrorKind.cameraUnavailable,
          e.toString(),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _cancelTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _goTimer?.cancel();
    _goTimer = null;
    _verificationTimer?.cancel();
    _verificationTimer = null;
  }

  Future<void> _setWakelock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Wakelock is a nicety; ignore failures.
    }
  }

  void _teardown() {
    _disposed = true;
    _cancelTimers();
    unawaited(ref.read(voiceCoachProvider).stop());
    final service = _service;
    final face = _faceService;
    _service = null;
    _faceService = null;
    _analyzer = null;
    unawaited(_setWakelock(false));
    if (service != null) unawaited(service.dispose());
    if (face != null) unawaited(face.dispose());
  }
}

final workoutControllerProvider =
    NotifierProvider.autoDispose<WorkoutController, WorkoutState>(
      WorkoutController.new,
    );
