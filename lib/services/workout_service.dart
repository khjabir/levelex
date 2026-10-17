import 'package:uuid/uuid.dart';

import '../core/utils/reminder_calculator.dart';
import '../models/exercise.dart';
import '../models/form_status.dart';
import '../models/face_template.dart';
import '../models/user_settings.dart';
import '../models/workout_session.dart';
import 'storage_service.dart';

/// Records workouts, recovers interrupted sets and evaluates skipped
/// reminders. Holds no UI state; the Riverpod layer calls into it and then
/// refreshes its own state from the repositories.
class WorkoutService {
  WorkoutService({
    required this.sessions,
    required this.settings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SessionRepository sessions;
  final SettingsRepository settings;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  static String newSessionId() => _uuid.v4();

  /// Persists a finished set. Reps at or above the target mark the session
  /// completed; fewer reps mark it incomplete.
  Future<WorkoutSession> recordWorkout({
    required String id,
    required DateTime startTime,
    required int targetReps,
    required int reps,
    double? formScore,
    DateTime? endTime,
    ExerciseType exercise = ExerciseType.pushUp,
    Map<FormStatus, int> mistakes = const {},
  }) async {
    final session = WorkoutSession(
      id: id,
      startTime: startTime,
      endTime: endTime ?? _clock(),
      targetReps: targetReps,
      completedReps: reps,
      status: reps >= targetReps
          ? SessionStatus.completed
          : SessionStatus.incomplete,
      formScore: formScore,
      exercise: exercise,
      mistakes: mistakes,
    );
    await sessions.upsert(session);
    await settings.saveDraft(null);
    return session;
  }

  /// Saves progress of the set currently in progress.
  Future<void> saveDraft(WorkoutDraft draft) => settings.saveDraft(draft);

  Future<void> clearDraft() => settings.saveDraft(null);

  /// If the app was killed during a set with at least one rep, stores that
  /// set so the reps are not lost. Returns the recovered session, if any.
  Future<WorkoutSession?> recoverInterruptedWorkout() async {
    final draft = settings.draft;
    if (draft == null) return null;
    await settings.saveDraft(null);
    if (draft.reps <= 0) return null;
    return recordWorkout(
      id: draft.id,
      startTime: draft.startTime,
      targetReps: draft.targetReps,
      reps: draft.reps,
      endTime: draft.startTime.add(const Duration(minutes: 5)),
      exercise: draft.exercise,
    );
  }

  /// Finds reminders that passed without any attempt since the last
  /// evaluation and records them as skipped sessions.
  ///
  /// Only reminders after onboarding finished are considered, each reminder
  /// gets its full interval before it counts as missed, and nothing is
  /// recorded when the user turned skipped-session tracking off (the
  /// evaluation marker still advances so re-enabling is never retroactive).
  Future<List<WorkoutSession>> evaluateSkippedSessions(
    UserSettings userSettings, {
    DateTime? now,
  }) async {
    final current = now ?? _clock();
    final from = userSettings.setupCompletedAt;
    if (from == null || !userSettings.onboardingCompleted) return const [];

    final evaluatedUntil = settings.skipEvaluatedUntil;
    final created = <WorkoutSession>[];

    if (userSettings.remindersEnabled && userSettings.trackSkippedSessions) {
      final schedule = ReminderSchedule.fromSettings(userSettings);
      final existing = sessions.all();
      final slots = schedule.skippedSlots(
        from: from,
        evaluatedUntil: evaluatedUntil,
        now: current,
        sessions: existing,
      );
      final alreadyRecorded = {
        for (final s in existing)
          if (s.skipped) s.startTime,
      };
      for (final slot in slots) {
        if (alreadyRecorded.contains(slot)) continue;
        created.add(
          WorkoutSession(
            id: 'skipped-${slot.millisecondsSinceEpoch}',
            startTime: slot,
            endTime: slot,
            targetReps: userSettings.targetFor(userSettings.reminderExercise),
            completedReps: 0,
            status: SessionStatus.skipped,
            exercise: userSettings.reminderExercise,
          ),
        );
      }
      if (created.isNotEmpty) await sessions.upsertAll(created);
    }

    await settings.setSkipEvaluatedUntil(current);
    return created;
  }

  Future<void> clearHistory() async {
    await sessions.clear();
    await settings.saveDraft(null);
    await settings.setSkipEvaluatedUntil(_clock());
  }

  // ---------------------------------------------------------------------------
  // Face registration
  // ---------------------------------------------------------------------------

  FaceTemplate? get faceTemplate => settings.faceTemplate;
  bool get hasRegisteredFace => settings.faceTemplate != null;

  /// Enrols the user. Allowed only once: the template can only be replaced by
  /// erasing it first, which also erases the score (see [eraseFaceData]).
  /// Throws [StateError] if a face is already registered.
  Future<FaceTemplate> registerFace(List<List<double>> samples) async {
    if (hasRegisteredFace) {
      throw StateError('A face is already registered');
    }
    final template = FaceTemplate(
      embedding: FaceMatcher.average(samples),
      registeredAt: _clock(),
      sampleCount: samples.length,
    );
    await settings.saveFaceTemplate(template);
    return template;
  }

  /// Deletes the face template together with every session, so nobody can
  /// swap identities and keep the score.
  Future<void> eraseFaceData() async {
    await settings.saveFaceTemplate(null);
    await clearHistory();
  }
}
