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
import '../../../models/face_template.dart';
import '../../../models/form_status.dart';
import '../../../models/pose_result.dart';
import '../../../models/user_settings.dart';
import '../../../services/face_service.dart';
import '../../../services/pose_detection_service.dart';
import '../../../services/voice_coach.dart';
import '../../workout/analysis/coaching_tracker.dart';
import '../../workout/analysis/exercise_analyzer.dart';
import '../analysis/generic_analyzers.dart';
import '../models/movement.dart';
import '../models/pt_record.dart';
import '../models/workout_plan.dart';
import '../planner/coach_voice.dart';
import '../pt_providers.dart';

/// Where the guided session is.
enum PtStep { intro, active, rest, finished }

/// Camera state during a tracked item.
enum PtCameraPhase { off, starting, verifying, tracking, error }

/// Immutable snapshot of the guided session.
class PtSessionState {
  const PtSessionState({
    required this.plan,
    this.index = 0,
    this.step = PtStep.intro,
    this.setIndex = 0,
    this.repsInSet = 0,
    this.secondsInSet = 0,
    this.restRemaining = 0,
    this.elapsed = Duration.zero,
    this.paused = false,
    this.results = const [],
    this.itemReps = 0,
    this.itemSeconds = 0,
    this.itemMistakes = const {},
    this.camera = PtCameraPhase.off,
    this.cameraReady = false,
    this.mirror = false,
    this.pose,
    this.formStatus = FormStatus.bodyNotVisible,
    this.coachCue,
    this.depth = 0,
    this.repJustCounted = false,
    this.faceMessage,
    this.verified = false,
    this.verificationDone = false,
    this.error,
    this.coachLine = '',
    this.record,
    this.lensDirection = CameraLensDirection.front,
  });

  final WorkoutPlan plan;
  final int index;
  final PtStep step;
  final int setIndex;
  final int repsInSet;
  final int secondsInSet;
  final int restRemaining;
  final Duration elapsed;
  final bool paused;
  final List<PtItemResult> results;

  /// Totals for the current item across finished sets.
  final int itemReps;
  final int itemSeconds;
  final Map<FormStatus, int> itemMistakes;

  final PtCameraPhase camera;
  final bool cameraReady;
  final bool mirror;
  final PoseResult? pose;
  final FormStatus formStatus;
  final FormStatus? coachCue;
  final double depth;
  final bool repJustCounted;
  final String? faceMessage;
  final bool verified;
  final bool verificationDone;
  final PoseDetectionException? error;

  /// The trainer's current line.
  final String coachLine;
  final PtRecord? record;
  final CameraLensDirection lensDirection;

  List<PlanItem> get items => plan.all;
  PlanItem get item => items[index];
  bool get isLast => index >= items.length - 1;
  bool get usesCamera => item.movement.tracking.usesCamera;
  int get target => item.isTimed ? item.seconds : item.reps;
  double get itemProgress => items.isEmpty ? 0 : index / items.length;
  Duration get plannedTotal => plan.estimatedTotal;

  PtSessionState copyWith({
    WorkoutPlan? plan,
    int? index,
    PtStep? step,
    int? setIndex,
    int? repsInSet,
    int? secondsInSet,
    int? restRemaining,
    Duration? elapsed,
    bool? paused,
    List<PtItemResult>? results,
    int? itemReps,
    int? itemSeconds,
    Map<FormStatus, int>? itemMistakes,
    PtCameraPhase? camera,
    bool? cameraReady,
    bool? mirror,
    PoseResult? pose,
    bool clearPose = false,
    FormStatus? formStatus,
    FormStatus? coachCue,
    bool clearCoachCue = false,
    double? depth,
    bool? repJustCounted,
    String? faceMessage,
    bool clearFaceMessage = false,
    bool? verified,
    bool? verificationDone,
    PoseDetectionException? error,
    bool clearError = false,
    String? coachLine,
    PtRecord? record,
    CameraLensDirection? lensDirection,
  }) => PtSessionState(
    plan: plan ?? this.plan,
    index: index ?? this.index,
    step: step ?? this.step,
    setIndex: setIndex ?? this.setIndex,
    repsInSet: repsInSet ?? this.repsInSet,
    secondsInSet: secondsInSet ?? this.secondsInSet,
    restRemaining: restRemaining ?? this.restRemaining,
    elapsed: elapsed ?? this.elapsed,
    paused: paused ?? this.paused,
    results: results ?? this.results,
    itemReps: itemReps ?? this.itemReps,
    itemSeconds: itemSeconds ?? this.itemSeconds,
    itemMistakes: itemMistakes ?? this.itemMistakes,
    camera: camera ?? this.camera,
    cameraReady: cameraReady ?? this.cameraReady,
    mirror: mirror ?? this.mirror,
    pose: clearPose ? null : (pose ?? this.pose),
    formStatus: formStatus ?? this.formStatus,
    coachCue: clearCoachCue ? null : (coachCue ?? this.coachCue),
    depth: depth ?? this.depth,
    repJustCounted: repJustCounted ?? false,
    faceMessage: clearFaceMessage ? null : (faceMessage ?? this.faceMessage),
    verified: verified ?? this.verified,
    verificationDone: verificationDone ?? this.verificationDone,
    error: clearError ? null : (error ?? this.error),
    coachLine: coachLine ?? this.coachLine,
    record: record ?? this.record,
    lensDirection: lensDirection ?? this.lensDirection,
  );
}

/// Drives a MY PT session: warm-up → workout → cool-down, item by item, set
/// by set, with camera tracking where the movement supports it, timers
/// elsewhere, one identity check, and a saved record at the end.
class PtSessionController extends Notifier<PtSessionState> {
  PoseDetectionService? _camera;
  FaceService? _face;
  ExerciseAnalyzer? _analyzer;
  final CoachingTracker _coach = CoachingTracker();
  Timer? _ticker;
  Timer? _setTimer;
  Timer? _restTimer;
  Timer? _verifyTimer;
  DateTime? _startedAt;
  DateTime? _elapsedBase;
  Duration _elapsedBefore = Duration.zero;
  bool _disposed = false;
  bool _cameraReleasedByLifecycle = false;
  int _matchStreak = 0;
  final _uuid = const Uuid();

  @override
  PtSessionState build() {
    ref.onDispose(_teardown);
    final plan = ref.read(ptPlanProvider);
    if (plan == null || plan.all.isEmpty) {
      return PtSessionState(
        plan: const WorkoutPlan(
          request: PtRequest(),
          warmUp: [],
          main: [],
          coolDown: [],
          rationale: '',
        ),
        step: PtStep.finished,
      );
    }
    final settings = ref.read(settingsProvider);
    _startedAt = DateTime.now();
    _elapsedBase = _startedAt;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return PtSessionState(
      plan: plan,
      coachLine: CoachVoice.beforeItem(plan.all.first, first: true),
      lensDirection: settings.cameraFacing == CameraFacing.back
          ? CameraLensDirection.back
          : CameraLensDirection.front,
    );
  }

  VoiceCoach get _voice => ref.read(voiceCoachProvider);

  void _say(String text) {
    final settings = ref.read(settingsProvider);
    _voice.enabled = settings.voiceEnabled && settings.soundEnabled;
    unawaited(_voice.say(VoiceCue.trainer, label: text));
  }

  void _sayCue(VoiceCue cue, {int count = 0, String? label}) {
    final settings = ref.read(settingsProvider);
    _voice.enabled = settings.voiceEnabled && settings.soundEnabled;
    unawaited(_voice.say(cue, count: count, label: label));
  }

  PoseDetectionService? get cameraService => _camera;

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------

  void _tick() {
    if (_disposed || state.paused || state.step == PtStep.finished) return;
    final base = _elapsedBase;
    if (base == null) return;
    state = state.copyWith(
      elapsed: _elapsedBefore + DateTime.now().difference(base),
    );
  }

  // ---------------------------------------------------------------------------
  // Flow
  // ---------------------------------------------------------------------------

  /// Leaves the intro card and starts set one of the current item.
  Future<void> beginItem() async {
    if (state.step != PtStep.intro) return;
    _say(CoachVoice.encouragement(0, state.item.sets));
    state = state.copyWith(
      step: PtStep.active,
      setIndex: 0,
      repsInSet: 0,
      secondsInSet: 0,
      itemReps: 0,
      itemSeconds: 0,
      itemMistakes: const {},
      clearCoachCue: true,
    );
    await _startSet();
  }

  Future<void> _startSet() async {
    final item = state.item;
    final spec = item.movement.tracking;
    _setTimer?.cancel();
    if (spec is TimerTracking) {
      await _releaseCamera();
      if (item.isTimed) {
        _setTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (state.paused || state.step != PtStep.active) return;
          final next = state.secondsInSet + 1;
          state = state.copyWith(secondsInSet: next);
          if (next >= item.seconds) _setDone();
        });
      }
      return;
    }
    _analyzer = PtAnalyzerFactory.create(
      spec,
      label: item.movement.name,
      thresholds: PushUpThresholds.forSensitivity(
        ref.read(settingsProvider).formSensitivity,
      ),
      target: state.target,
    );
    _coach.reset();
    if (_camera == null || !(_camera?.isInitialized ?? false)) {
      await _openCamera();
    } else if (!(_camera?.isStreaming ?? false)) {
      try {
        await _camera!.startStream(onPose: _onPose, onError: _onCameraError);
      } on PoseDetectionException catch (e) {
        _cameraFailed(e);
      }
    }
    if (state.camera == PtCameraPhase.off ||
        state.camera == PtCameraPhase.starting) {
      state = state.copyWith(
        camera: state.verificationDone
            ? PtCameraPhase.tracking
            : PtCameraPhase.verifying,
      );
      if (!state.verificationDone) _startVerification();
    }
  }

  void _setDone() {
    final item = state.item;
    final mistakes = Map<FormStatus, int>.from(state.itemMistakes);
    for (final e in _coach.mistakes.entries) {
      mistakes[e.key] = (mistakes[e.key] ?? 0) + e.value;
    }
    final reps = state.itemReps + (item.isTimed ? 0 : state.repsInSet);
    final seconds =
        state.itemSeconds +
        (item.isTimed
            ? (item.movement.tracking is TimerTracking
                  ? state.secondsInSet
                  : state.repsInSet)
            : 0);
    _setTimer?.cancel();
    final line = CoachVoice.afterSet(
      item: item,
      setIndex: state.setIndex,
      repsDone: item.isTimed ? item.reps : state.repsInSet,
      mistakes: _coach.totalMistakes,
    );
    if (state.setIndex + 1 < item.sets) {
      state = state.copyWith(
        step: PtStep.rest,
        itemReps: reps,
        itemSeconds: seconds,
        itemMistakes: mistakes,
        restRemaining: item.rest.inSeconds,
        coachLine: line,
        clearCoachCue: true,
      );
      _say(line);
      _restTimer?.cancel();
      _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.paused || state.step != PtStep.rest) return;
        final left = state.restRemaining - 1;
        if (left <= 0) {
          _nextSet();
        } else {
          state = state.copyWith(restRemaining: left);
          if (left == 3) _sayCue(VoiceCue.three);
          if (left == 2) _sayCue(VoiceCue.two);
          if (left == 1) _sayCue(VoiceCue.one);
        }
      });
    } else {
      state = state.copyWith(
        itemReps: reps,
        itemSeconds: seconds,
        itemMistakes: mistakes,
      );
      _say(line);
      _itemDone(skipped: false);
    }
  }

  /// Ends the rest early.
  void skipRest() {
    if (state.step != PtStep.rest) return;
    _nextSet();
  }

  Future<void> _nextSet() async {
    _restTimer?.cancel();
    final next = state.setIndex + 1;
    _analyzer?.resetCounting();
    _coach.reset();
    state = state.copyWith(
      step: PtStep.active,
      setIndex: next,
      repsInSet: 0,
      secondsInSet: 0,
      clearCoachCue: true,
      coachLine: CoachVoice.encouragement(next, state.item.sets),
    );
    _say(CoachVoice.encouragement(next, state.item.sets));
    await _startSet();
  }

  /// For untracked rep movements: the user reports what they did.
  void logReps(int reps) {
    if (state.step != PtStep.active) return;
    state = state.copyWith(repsInSet: reps);
    _setDone();
  }

  /// For timed items without a camera: the user says they are done early.
  void finishSetEarly() {
    if (state.step != PtStep.active) return;
    _setDone();
  }

  void skipItem() {
    if (state.step == PtStep.finished) return;
    _setTimer?.cancel();
    _restTimer?.cancel();
    _itemDone(skipped: true);
  }

  /// Swaps the current item for an alternative (intro only).
  bool swapItem() {
    if (state.step != PtStep.intro) return false;
    final notifier = ref.read(ptPlanProvider.notifier);
    if (!notifier.swap(state.item)) return false;
    final plan = ref.read(ptPlanProvider)!;
    state = state.copyWith(
      plan: plan,
      coachLine: CoachVoice.beforeItem(plan.all[state.index], first: false),
    );
    return true;
  }

  void _itemDone({required bool skipped}) {
    final item = state.item;
    final result = PtItemResult(
      movementId: item.movement.id,
      phase: item.phase,
      setsPlanned: item.sets,
      setsDone: skipped ? state.setIndex : item.sets,
      reps: state.itemReps,
      seconds: state.itemSeconds,
      skipped: skipped,
      mistakes: state.itemMistakes,
    );
    final results = [...state.results, result];
    if (state.isLast) {
      state = state.copyWith(results: results);
      unawaited(finish());
      return;
    }
    final nextIndex = state.index + 1;
    final next = state.items[nextIndex];
    final line = CoachVoice.beforeItem(next, first: false);
    state = state.copyWith(
      results: results,
      index: nextIndex,
      step: PtStep.intro,
      setIndex: 0,
      repsInSet: 0,
      secondsInSet: 0,
      itemReps: 0,
      itemSeconds: 0,
      itemMistakes: const {},
      coachLine: line,
      clearCoachCue: true,
      clearPose: true,
    );
    _say(line);
    if (!next.movement.tracking.usesCamera) {
      unawaited(_releaseCamera());
    } else {
      unawaited(_camera?.stopStream());
    }
  }

  Future<void> pause() async {
    if (state.paused || state.step == PtStep.finished) return;
    final base = _elapsedBase;
    if (base != null) _elapsedBefore += DateTime.now().difference(base);
    state = state.copyWith(paused: true, coachLine: 'Paused.');
    _sayCue(VoiceCue.paused);
    await _camera?.stopStream();
  }

  Future<void> resume() async {
    if (!state.paused) return;
    _elapsedBase = DateTime.now();
    state = state.copyWith(paused: false, coachLine: 'Back in. Keep going.');
    if (state.step == PtStep.active && state.usesCamera) {
      if (_cameraReleasedByLifecycle || !(_camera?.isInitialized ?? false)) {
        await _openCamera();
      } else {
        try {
          await _camera!.startStream(onPose: _onPose, onError: _onCameraError);
        } on PoseDetectionException catch (e) {
          _cameraFailed(e);
        }
      }
    }
  }

  /// Ends the session now, saving whatever was done.
  Future<void> finish() async {
    if (state.step == PtStep.finished) return;
    _setTimer?.cancel();
    _restTimer?.cancel();
    _verifyTimer?.cancel();
    final results = [...state.results];
    final item = state.items.isEmpty ? null : state.item;
    if (item != null && state.step != PtStep.intro) {
      // Partial current item.
      final partialReps = state.itemReps + (item.isTimed ? 0 : state.repsInSet);
      final partialSeconds =
          state.itemSeconds + (item.isTimed ? state.secondsInSet : 0);
      results.add(
        PtItemResult(
          movementId: item.movement.id,
          phase: item.phase,
          setsPlanned: item.sets,
          setsDone: state.setIndex,
          reps: partialReps,
          seconds: partialSeconds,
          skipped: false,
          mistakes: state.itemMistakes,
        ),
      );
    }
    await _releaseCamera();
    unawaited(_setWakelock(false));
    final now = DateTime.now();
    final record = PtRecord(
      id: _uuid.v4(),
      startTime: _startedAt ?? now,
      endTime: now,
      mode: state.plan.request.mode,
      plannedMinutes: state.plan.request.duration.inMinutes,
      items: results,
      verified: state.verified,
    );
    try {
      await ref.read(ptRecordsProvider.notifier).add(record);
    } catch (e) {
      debugPrint('Saving PT record failed: $e');
    }
    final line = CoachVoice.summary(record);
    if (_disposed) return;
    state = state.copyWith(
      step: PtStep.finished,
      results: results,
      record: record,
      coachLine: line,
      clearPose: true,
      clearCoachCue: true,
    );
    _say(line);
  }

  // ---------------------------------------------------------------------------
  // Camera & tracking
  // ---------------------------------------------------------------------------

  Future<void> _openCamera() async {
    state = state.copyWith(camera: PtCameraPhase.starting, clearError: true);
    final permission = await ref
        .read(permissionServiceProvider)
        .requestCamera();
    if (_disposed) return;
    if (permission != CameraPermissionResult.granted) {
      _cameraFailed(
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
      await service.initialize();
      if (_disposed) {
        await service.releaseCamera();
        return;
      }
      await service.startStream(onPose: _onPose, onError: _onCameraError);
    } on PoseDetectionException catch (e) {
      _cameraFailed(e);
      return;
    } catch (e) {
      _cameraFailed(
        PoseDetectionException(
          PoseDetectionErrorKind.cameraUnavailable,
          e.toString(),
        ),
      );
      return;
    }
    service.onFrame = _onFrame;
    _cameraReleasedByLifecycle = false;
    state = state.copyWith(
      cameraReady: true,
      mirror: service.mirrorPreview,
      lensDirection: service.lensDirection,
      camera: state.verificationDone
          ? PtCameraPhase.tracking
          : PtCameraPhase.verifying,
    );
    unawaited(_setWakelock(true));
    if (!state.verificationDone) _startVerification();
  }

  Future<void> _releaseCamera() async {
    final c = _camera;
    if (c == null) return;
    await c.stopStream();
    await c.releaseCamera();
    state = state.copyWith(
      cameraReady: false,
      camera: PtCameraPhase.off,
      clearPose: true,
    );
  }

  void _cameraFailed(PoseDetectionException e) {
    debugPrint('MY PT camera error: $e');
    if (_disposed) return;
    state = state.copyWith(
      camera: PtCameraPhase.error,
      error: e,
      cameraReady: false,
      clearPose: true,
      coachLine: 'Camera is unavailable; log this set by hand.',
    );
  }

  void _onCameraError(PoseDetectionException e) => _cameraFailed(e);

  Future<void> switchCamera() async {
    final c = _camera;
    if (c == null || !state.cameraReady) return;
    try {
      await c.switchCamera();
      c.onFrame = _onFrame;
      state = state.copyWith(
        mirror: c.mirrorPreview,
        lensDirection: c.lensDirection,
      );
    } on PoseDetectionException catch (e) {
      _cameraFailed(e);
    }
  }

  void _startVerification() {
    final template = ref.read(workoutServiceProvider).faceTemplate;
    if (template == null) {
      state = state.copyWith(
        verificationDone: true,
        verified: false,
        camera: PtCameraPhase.tracking,
        faceMessage: 'No face registered: this session will not be scored.',
      );
      return;
    }
    _matchStreak = 0;
    state = state.copyWith(
      camera: PtCameraPhase.verifying,
      faceMessage: 'Look at the camera so I know it is you…',
    );
    unawaited(
      (_face ??= FaceService()).initialize().catchError((Object e) {
        debugPrint('Face model failed: $e');
      }),
    );
    _verifyTimer?.cancel();
    _verifyTimer = Timer(const Duration(seconds: 12), () {
      if (state.verificationDone) return;
      state = state.copyWith(
        verificationDone: true,
        verified: false,
        camera: PtCameraPhase.tracking,
        faceMessage:
            "Couldn't confirm it's you. I'll still coach you, but this "
            'session will not be scored.',
      );
    });
  }

  Future<void> _onFrame(CameraFrame frame) async {
    if (_disposed || state.verificationDone) return;
    final face = _face;
    final template = ref.read(workoutServiceProvider).faceTemplate;
    if (face == null || template == null) return;
    final analysis = await face.analyze(frame);
    if (analysis == null || _disposed || state.verificationDone) return;
    final sample = analysis.sample;
    if (sample == null) return;
    switch (template.compare(sample.embedding)) {
      case FaceMatch.match:
        _matchStreak++;
        if (_matchStreak >= FaceConstants.requiredMatches) {
          _verifyTimer?.cancel();
          state = state.copyWith(
            verificationDone: true,
            verified: true,
            camera: PtCameraPhase.tracking,
            faceMessage: 'Verified. Let\'s go.',
          );
          _sayCue(VoiceCue.verified, label: 'Let\'s go');
          Timer(const Duration(seconds: 3), () {
            if (!_disposed) state = state.copyWith(clearFaceMessage: true);
          });
        }
      case FaceMatch.mismatch:
        _matchStreak = 0;
      case FaceMatch.unknown:
        break;
    }
  }

  void _onPose(PoseResult pose) {
    final analyzer = _analyzer;
    if (_disposed || analyzer == null) return;
    final mirror = _camera?.mirrorPreview ?? state.mirror;
    if (state.step != PtStep.active ||
        state.paused ||
        state.camera != PtCameraPhase.tracking) {
      // Keep the skeleton visible while verifying or resting.
      state = state.copyWith(pose: pose, mirror: mirror);
      return;
    }
    final analysis = analyzer.processPose(pose);
    final fired = _coach.observe(analysis, pose.timestamp);
    final cue = _coach.cueAt(pose.timestamp);
    state = state.copyWith(
      pose: pose,
      mirror: mirror,
      formStatus: analysis.formStatus,
      repsInSet: analysis.repCount,
      repJustCounted: analysis.repCounted,
      depth: analysis.depth,
      coachCue: cue,
      clearCoachCue: cue == null,
    );
    if (fired != null) {
      final exercise = switch (state.item.movement.tracking) {
        ExerciseTracking(:final type) => type,
        _ => null,
      };
      final spoken = exercise == null
          ? (fired.isEvent ? fired.message : fired.message)
          : CoachingLibrary.cue(fired, exercise)?.spoken;
      _sayCue(VoiceCue.coach, label: spoken);
    }
    if (analysis.repCounted) {
      if (state.item.isTimed) {
        final remaining = state.target - analysis.repCount;
        if (remaining > 0 && remaining <= 3) {
          _sayCue(
            remaining == 3
                ? VoiceCue.three
                : remaining == 2
                ? VoiceCue.two
                : VoiceCue.one,
          );
        } else if (analysis.repCount % 10 == 0) {
          _sayCue(VoiceCue.secondsHeld, count: analysis.repCount);
        }
      } else {
        _sayCue(VoiceCue.rep, count: analysis.repCount);
      }
      unawaited(
        ref
            .read(feedbackServiceProvider)
            .repCounted(vibration: ref.read(settingsProvider).vibrationEnabled),
      );
    }
    if (analysis.isCompleted) _setDone();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> onAppBackgrounded() async {
    if (_disposed || state.step == PtStep.finished) return;
    if (!state.paused) await pause();
    if (_camera != null) {
      _cameraReleasedByLifecycle = true;
      await _camera!.releaseCamera();
      state = state.copyWith(cameraReady: false, clearPose: true);
    }
    unawaited(_setWakelock(false));
  }

  Future<void> _setWakelock(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }

  void _teardown() {
    _disposed = true;
    _ticker?.cancel();
    _setTimer?.cancel();
    _restTimer?.cancel();
    _verifyTimer?.cancel();
    unawaited(_voice.stop());
    final c = _camera;
    final f = _face;
    _camera = null;
    _face = null;
    _analyzer = null;
    unawaited(_setWakelock(false));
    if (c != null) unawaited(c.dispose());
    if (f != null) unawaited(f.dispose());
  }
}

final ptSessionProvider =
    NotifierProvider.autoDispose<PtSessionController, PtSessionState>(
      PtSessionController.new,
    );
