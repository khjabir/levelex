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
import '../../strength/logic/records.dart';
import '../../strength/models/lift_log.dart';
import '../models/movement_library.dart';
import '../../strength/strength_providers.dart';
import '../../workout/analysis/generic_analyzers.dart';
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
    this.saveFailed = false,
    this.lensDirection = CameraLensDirection.front,
    this.autoStartIn = 0,
    this.loadKg,
    this.setReps = const [],
    this.liftsSaved = const [],
    this.personalRecords = const [],
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

  /// The record could not be written, so it earns nothing.
  final bool saveFailed;
  final CameraLensDirection lensDirection;

  /// Quick workouts: seconds until the intro starts the item by itself
  /// (0 = no auto-start).
  final int autoStartIn;

  /// Working load for the current item (kg), when the user set one.
  final double? loadKg;

  /// Reps (seconds for timed items) of each finished set of the current
  /// item.
  final List<int> setReps;

  /// Lift-log entries written when the session finished.
  final List<LiftEntry> liftsSaved;

  /// Records set in this session (heaviest set, most reps, best e1RM…).
  final List<PersonalRecord> personalRecords;

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
    bool? saveFailed,
    CameraLensDirection? lensDirection,
    int? autoStartIn,
    double? loadKg,
    bool clearLoad = false,
    List<int>? setReps,
    List<LiftEntry>? liftsSaved,
    List<PersonalRecord>? personalRecords,
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
    saveFailed: saveFailed ?? this.saveFailed,
    lensDirection: lensDirection ?? this.lensDirection,
    autoStartIn: autoStartIn ?? this.autoStartIn,
    loadKg: clearLoad ? null : (loadKg ?? this.loadKg),
    setReps: setReps ?? this.setReps,
    liftsSaved: liftsSaved ?? this.liftsSaved,
    personalRecords: personalRecords ?? this.personalRecords,
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
    _voice = ref.read(voiceCoachProvider);
    ref.onDispose(_teardown);
    final plan = ref.read(annotatedPlanProvider);
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
      loadKg: plan.all.first.suggestedKg,
      autoStartIn: plan.request.quick ? _autoStartSeconds : 0,
      coachLine: CoachVoice.beforeItem(plan.all.first, first: true),
      lensDirection: settings.cameraFacing == CameraFacing.back
          ? CameraLensDirection.back
          : CameraLensDirection.front,
    );
  }

  /// Read once in [build]: `ref` throws inside `onDispose`, which used to
  /// stop the teardown before the camera and detectors were released.
  late VoiceCoach _voice;

  /// The current item's result is already in `results` (its last set
  /// finished and the session is closing), so [finish] must not add it a
  /// second time as a partial item.
  bool _currentItemRecorded = false;
  bool _finishing = false;
  bool _switchingCamera = false;

  /// Time left on the identity check when the session was paused.
  Duration? _verifyRemaining;
  DateTime? _verifyDeadline;

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

  static const _autoStartSeconds = 8;

  void _tick() {
    if (_disposed || state.paused || state.step == PtStep.finished) return;
    if (state.step == PtStep.intro && state.autoStartIn > 0) {
      final left = state.autoStartIn - 1;
      state = state.copyWith(autoStartIn: left);
      if (left == 0) {
        unawaited(beginItem());
        return;
      }
    }
    if (_elapsedBase == null) return;
    state = state.copyWith(elapsed: _activeElapsed);
  }

  /// Sets the working load (kg) for the current item; null clears it.
  void setLoad(double? kg) {
    if (state.step == PtStep.finished) return;
    state = state.copyWith(loadKg: kg, clearLoad: kg == null);
  }

  /// Skips the one identity check. The session is coached but not scored.
  void skipVerification() {
    if (state.verificationDone) return;
    _verifyTimer?.cancel();
    state = state.copyWith(
      verificationDone: true,
      verified: false,
      camera: state.camera == PtCameraPhase.verifying
          ? PtCameraPhase.tracking
          : state.camera,
      faceMessage:
          'Face check skipped: this session is coached but not scored '
          '(no streak, no XP).',
    );
    _onVerificationSettled();
  }

  /// Session time excluding pauses.
  Duration get _activeElapsed {
    final base = _elapsedBase;
    if (state.paused || base == null) return _elapsedBefore;
    return _elapsedBefore + DateTime.now().difference(base);
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
      autoStartIn: 0,
    );
    await _startSet();
  }

  /// Stops the quick-workout auto-start (the user wants to read first).
  void holdIntro() {
    if (state.autoStartIn > 0) state = state.copyWith(autoStartIn: 0);
  }

  Future<void> _startSet() async {
    final item = state.item;
    final spec = item.movement.tracking;
    _setTimer?.cancel();
    if (spec is TimerTracking) {
      _analyzer = null;
      if (state.camera != PtCameraPhase.error) {
        await _ensureCamera();
      }
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
    final cap = item.capSeconds;
    if (cap != null) {
      // Interval round: the clock ends the set even if the reps are short.
      _setTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.paused || state.step != PtStep.active) return;
        final next = state.secondsInSet + 1;
        state = state.copyWith(secondsInSet: next);
        if (next == 3 || next == 2 || next == 1) return;
        if (cap - next == 3) _sayCue(VoiceCue.three);
        if (cap - next == 2) _sayCue(VoiceCue.two);
        if (cap - next == 1) _sayCue(VoiceCue.one);
        if (next >= cap) _setDone();
      });
    }
    await _ensureCamera();
  }

  /// Opens the camera (or restarts its stream) and runs the one identity
  /// check if it has not happened yet.
  Future<void> _ensureCamera() async {
    if (_camera == null || !(_camera?.isInitialized ?? false)) {
      await _openCamera();
      return;
    }
    if (!(_camera?.isStreaming ?? false)) {
      try {
        await _camera!.startStream(onPose: _onPose, onError: _onCameraError);
      } on PoseDetectionException catch (e) {
        _cameraFailed(e);
        return;
      }
    }
    if (state.camera == PtCameraPhase.off ||
        state.camera == PtCameraPhase.starting ||
        state.camera == PtCameraPhase.error) {
      state = state.copyWith(
        cameraReady: true,
        clearError: true,
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
    final seconds = state.itemSeconds + (item.isTimed ? _setSeconds(item) : 0);
    final setReps = [
      ...state.setReps,
      item.isTimed ? _setSeconds(item) : state.repsInSet,
    ];
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
        setReps: setReps,
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
        setReps: setReps,
      );
      _say(line);
      _itemDone(skipped: false);
    }
  }

  /// Seconds of work in the current set. Camera holds count whole seconds
  /// as reps; timer items use the set timer.
  int _setSeconds(PlanItem item) => item.movement.tracking is TimerTracking
      ? state.secondsInSet
      : state.repsInSet;

  /// Ends the rest early.
  void skipRest() {
    if (state.step != PtStep.rest) return;
    if (state.plan.request.bare &&
        state.setIndex == 0 &&
        state.setReps.isEmpty) {
      // Rest between interval rounds: start the next round.
      _restTimer?.cancel();
      state = state.copyWith(step: PtStep.intro, restRemaining: 0);
      unawaited(beginItem());
      return;
    }
    _nextSet();
  }

  Future<void> _nextSet() async {
    _restTimer?.cancel();
    final next = state.setIndex + 1;
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
    final plan = ref.read(annotatedPlanProvider)!;
    state = state.copyWith(
      plan: plan,
      loadKg: plan.all[state.index].suggestedKg,
      clearLoad: plan.all[state.index].suggestedKg == null,
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
      // During rest the set just finished is already done.
      setsDone: !skipped
          ? item.sets
          : state.step == PtStep.rest
          ? state.setIndex + 1
          : state.setIndex,
      reps: state.itemReps,
      seconds: state.itemSeconds,
      skipped: skipped,
      mistakes: state.itemMistakes,
      weightKg: state.loadKg,
      setReps: state.setReps,
    );
    final results = [...state.results, result];
    if (state.isLast) {
      state = state.copyWith(results: results);
      _currentItemRecorded = true;
      unawaited(finish());
      return;
    }
    final nextIndex = state.index + 1;
    final next = state.items[nextIndex];
    if (state.plan.request.bare && !skipped) {
      // Interval flow: no intro card, rest (if any) then straight into
      // the next round. EMOM rounds rest for whatever is left of the
      // minute.
      var restSeconds = item.rest.inSeconds;
      final cap = item.capSeconds;
      if (restSeconds == 0 && cap != null && !item.isTimed) {
        restSeconds = (cap - state.secondsInSet).clamp(0, cap);
      }
      _restTimer?.cancel();
      state = state.copyWith(
        results: results,
        index: nextIndex,
        step: PtStep.rest,
        setIndex: 0,
        repsInSet: 0,
        secondsInSet: 0,
        itemReps: 0,
        itemSeconds: 0,
        itemMistakes: const {},
        setReps: const [],
        clearLoad: true,
        restRemaining: restSeconds,
        coachLine: restSeconds > 0
            ? 'Round ${nextIndex + 1} of ${state.items.length}: '
                  '${next.movement.name} next.'
            : 'Next: ${next.movement.name}.',
        clearCoachCue: true,
        clearPose: true,
        autoStartIn: 0,
      );
      _say(state.coachLine);
      if (restSeconds <= 0) {
        state = state.copyWith(step: PtStep.intro);
        unawaited(beginItem());
        return;
      }
      _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.paused || state.step != PtStep.rest) return;
        final left = state.restRemaining - 1;
        if (left <= 0) {
          _restTimer?.cancel();
          state = state.copyWith(step: PtStep.intro, restRemaining: 0);
          unawaited(beginItem());
        } else {
          state = state.copyWith(restRemaining: left);
          if (left == 3) _sayCue(VoiceCue.three);
          if (left == 2) _sayCue(VoiceCue.two);
          if (left == 1) _sayCue(VoiceCue.one);
        }
      });
      return;
    }
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
      setReps: const [],
      loadKg: next.suggestedKg,
      clearLoad: next.suggestedKg == null,
      coachLine: line,
      clearCoachCue: true,
      clearPose: true,
      autoStartIn: state.plan.request.quick ? _autoStartSeconds : 0,
    );
    _say(line);
    if (state.verificationDone) unawaited(_camera?.stopStream());
  }

  Future<void> pause() async {
    if (state.paused || state.step == PtStep.finished) return;
    final base = _elapsedBase;
    if (base != null) _elapsedBefore += DateTime.now().difference(base);
    // No frames arrive while paused, so the identity check's clock stops.
    final deadline = _verifyDeadline;
    if (_verifyTimer?.isActive ?? false) {
      _verifyTimer?.cancel();
      _verifyRemaining = deadline?.difference(DateTime.now());
    }
    state = state.copyWith(paused: true, coachLine: 'Paused.');
    _sayCue(VoiceCue.paused);
    await _camera?.stopStream();
  }

  Future<void> resume() async {
    if (!state.paused) return;
    _elapsedBase = DateTime.now();
    state = state.copyWith(paused: false, coachLine: 'Back in. Keep going.');
    final remaining = _verifyRemaining;
    _verifyRemaining = null;
    if (remaining != null && !state.verificationDone) {
      _armVerifyTimer(
        remaining < const Duration(seconds: 4)
            ? const Duration(seconds: 4)
            : remaining,
      );
    }
    if (state.step == PtStep.active && state.camera != PtCameraPhase.error) {
      if (_cameraReleasedByLifecycle || !(_camera?.isInitialized ?? false)) {
        await _openCamera();
      } else {
        await _ensureCamera();
      }
    }
  }

  /// Ends the session now, saving whatever was done.
  Future<void> finish() async {
    if (_finishing || state.step == PtStep.finished) return;
    _finishing = true;
    _setTimer?.cancel();
    _restTimer?.cancel();
    _verifyTimer?.cancel();
    final results = [...state.results];
    final item = state.items.isEmpty ? null : state.item;
    if (item != null && state.step != PtStep.intro && !_currentItemRecorded) {
      // Partial current item. During rest the last set is already in the
      // item totals; mid-set, add what this set has so far.
      final inSet = state.step == PtStep.active;
      final mistakes = Map<FormStatus, int>.from(state.itemMistakes);
      if (inSet) {
        for (final e in _coach.mistakes.entries) {
          mistakes[e.key] = (mistakes[e.key] ?? 0) + e.value;
        }
      }
      results.add(
        PtItemResult(
          movementId: item.movement.id,
          phase: item.phase,
          setsPlanned: item.sets,
          setsDone: inSet ? state.setIndex : state.setIndex + 1,
          reps: state.itemReps + (inSet && !item.isTimed ? state.repsInSet : 0),
          seconds:
              state.itemSeconds +
              (inSet && item.isTimed ? _setSeconds(item) : 0),
          skipped: false,
          mistakes: mistakes,
          weightKg: state.loadKg,
          setReps: state.setReps,
        ),
      );
    }
    final activeSeconds = _activeElapsed.inSeconds;
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
      plannedItems: state.items.length,
      activeSeconds: activeSeconds,
      routineId: state.plan.request.routineId,
      routineDayId: state.plan.request.routineDayId,
    );
    var saveFailed = false;
    try {
      await ref.read(ptRecordsProvider.notifier).add(record);
    } catch (e) {
      debugPrint('Saving PT record failed: $e');
      saveFailed = true;
    }
    // Every main-phase set goes to the lift log so the library can chart
    // it and the progression rule can read it next time.
    final lifts = _liftEntries(record);
    final prs = <PersonalRecord>[];
    if (lifts.isNotEmpty) {
      try {
        await ref.read(liftLogProvider.notifier).addAll(lifts);
        final all = ref.read(liftLogProvider);
        for (final e in lifts) {
          prs.addAll(RecordBook.detect(e, all));
        }
      } catch (e) {
        debugPrint('Saving lift log failed: $e');
      }
    }
    var line = saveFailed
        ? '${CoachVoice.summary(record)} I could not save this session, so it '
              'will not count toward your level.'
        : CoachVoice.summary(record);
    if (prs.isNotEmpty) {
      final names = {
        for (final p in prs) MovementLibrary.byId(p.movementId)?.name,
      }.whereType<String>().take(2).join(' and ');
      line += ' New personal record${prs.length > 1 ? 's' : ''} on $names!';
    }
    if (_disposed) return;
    state = state.copyWith(
      step: PtStep.finished,
      results: results,
      record: record,
      saveFailed: saveFailed,
      liftsSaved: lifts,
      personalRecords: prs,
      coachLine: line,
      clearPose: true,
      clearCoachCue: true,
    );
    _say(line);
  }

  List<LiftEntry> _liftEntries(PtRecord record) {
    final out = <LiftEntry>[];
    for (final r in record.items) {
      final m = r.movement;
      if (m == null || r.phase != PlanPhase.main || r.setReps.isEmpty) {
        continue;
      }
      final sets = [
        for (final n in r.setReps)
          if (n > 0)
            LiftSet(
              weightKg: r.weightKg ?? 0,
              reps: m.isTimed ? 0 : n,
              seconds: m.isTimed ? n : null,
            ),
      ];
      if (sets.isEmpty) continue;
      out.add(
        LiftEntry(
          id: _uuid.v4(),
          movementId: m.id,
          startTime: record.startTime,
          sets: sets,
          source: LiftSource.pt,
          sessionId: record.id,
        ),
      );
    }
    return out;
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
    // A camera that reported an error still claims to be initialised;
    // release it so the next set opens a fresh one.
    unawaited(_camera?.releaseCamera());
  }

  void _onCameraError(PoseDetectionException e) => _cameraFailed(e);

  Future<void> switchCamera() async {
    final c = _camera;
    if (c == null || !state.cameraReady || _switchingCamera) return;
    _switchingCamera = true;
    state = state.copyWith(cameraReady: false, clearPose: true);
    try {
      await c.switchCamera();
      if (_disposed) return;
      c.onFrame = _onFrame;
      state = state.copyWith(
        cameraReady: true,
        mirror: c.mirrorPreview,
        lensDirection: c.lensDirection,
      );
    } on PoseDetectionException catch (e) {
      _cameraFailed(e);
    } finally {
      _switchingCamera = false;
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
    _armVerifyTimer(const Duration(seconds: 12));
  }

  void _armVerifyTimer(Duration after) {
    _verifyTimer?.cancel();
    _verifyDeadline = DateTime.now().add(after);
    _verifyTimer = Timer(after, () {
      if (_disposed || state.verificationDone) return;
      state = state.copyWith(
        verificationDone: true,
        verified: false,
        camera: PtCameraPhase.tracking,
        faceMessage:
            "Couldn't confirm it's you. I'll still coach you, but this "
            'session will not be scored.',
      );
      _onVerificationSettled();
    });
  }

  /// The camera stays on after the identity check: every item shows the
  /// live view next to the guide.
  void _onVerificationSettled() {}

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
          _onVerificationSettled();
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
    if (_disposed) return;
    final analyzer = _analyzer;
    final mirror = _camera?.mirrorPreview ?? state.mirror;
    if (analyzer == null) {
      // Timer item: show the skeleton and whether the body is in frame.
      final visible =
          pose.hasPose &&
          (pose.confidenceOf(LandmarkType.leftShoulder) > 0.3 ||
              pose.confidenceOf(LandmarkType.rightShoulder) > 0.3) &&
          (pose.confidenceOf(LandmarkType.leftHip) > 0.3 ||
              pose.confidenceOf(LandmarkType.rightHip) > 0.3);
      state = state.copyWith(
        pose: pose,
        mirror: mirror,
        formStatus: visible ? FormStatus.goodForm : FormStatus.bodyNotVisible,
      );
      return;
    }
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
          ? fired.message
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
