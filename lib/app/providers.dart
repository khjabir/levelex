import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/permissions/permission_service.dart';
import '../core/levels/level_system.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/reminder_calculator.dart';
import '../core/utils/stats_calculator.dart';
import '../features/pt/models/pt_record.dart';
import '../features/pt/pt_providers.dart';
import '../models/daily_stats.dart';
import '../models/exercise.dart';
import '../models/form_status.dart';
import '../models/user_settings.dart';
import '../models/workout_session.dart';
import '../services/feedback_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/voice_coach.dart';
import '../services/workout_service.dart';

// -----------------------------------------------------------------------------
// Services (concrete instances are injected in main.dart via overrides)
// -----------------------------------------------------------------------------

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('Overridden at app start'),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => throw UnimplementedError('Overridden at app start'),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('Overridden at app start'),
);

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PermissionService(),
);

final feedbackServiceProvider = Provider<FeedbackService>((ref) {
  final service = FeedbackService();
  ref.onDispose(service.dispose);
  return service;
});

final voiceCoachProvider = Provider<VoiceCoach>((ref) {
  final coach = VoiceCoach();
  ref.onDispose(coach.dispose);
  return coach;
});

final workoutServiceProvider = Provider<WorkoutService>(
  (ref) => WorkoutService(
    sessions: ref.watch(sessionRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    pt: ref.watch(ptRepositoryProvider),
  ),
);

// -----------------------------------------------------------------------------
// Settings
// -----------------------------------------------------------------------------

class SettingsNotifier extends Notifier<UserSettings> {
  @override
  UserSettings build() => ref.watch(settingsRepositoryProvider).settings;

  /// Applies [change] and persists the result.
  Future<void> updateSettings(
    UserSettings Function(UserSettings current) change,
  ) async {
    final next = change(state);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }

  /// Restores factory defaults (used by "Reset app").
  Future<void> reset() async {
    await ref.read(settingsRepositoryProvider).clear();
    state = const UserSettings();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, UserSettings>(
  SettingsNotifier.new,
);

// -----------------------------------------------------------------------------
// Sessions
// -----------------------------------------------------------------------------

class SessionsNotifier extends Notifier<List<WorkoutSession>> {
  @override
  List<WorkoutSession> build() => ref.watch(sessionRepositoryProvider).all();

  WorkoutService get _service => ref.read(workoutServiceProvider);

  void refresh() => state = ref.read(sessionRepositoryProvider).all();

  Future<WorkoutSession> recordWorkout({
    required String id,
    required DateTime startTime,
    required int targetReps,
    required int reps,
    double? formScore,
    ExerciseType exercise = ExerciseType.pushUp,
    Map<FormStatus, int> mistakes = const {},
    bool verified = true,
  }) async {
    final session = await _service.recordWorkout(
      id: id,
      startTime: startTime,
      targetReps: targetReps,
      reps: reps,
      formScore: formScore,
      exercise: exercise,
      mistakes: mistakes,
      verified: verified,
    );
    refresh();
    return session;
  }

  /// Records reminders that were missed since the last check.
  Future<List<WorkoutSession>> evaluateSkipped() async {
    final created = await _service.evaluateSkippedSessions(
      ref.read(settingsProvider),
    );
    if (created.isNotEmpty) refresh();
    return created;
  }

  /// Saves a set that was interrupted by the app being killed.
  Future<WorkoutSession?> recoverInterrupted() async {
    final recovered = await _service.recoverInterruptedWorkout();
    if (recovered != null) refresh();
    return recovered;
  }

  Future<void> clearHistory() async {
    await _service.clearHistory();
    refresh();
  }
}

final sessionsProvider =
    NotifierProvider<SessionsNotifier, List<WorkoutSession>>(
      SessionsNotifier.new,
    );

// -----------------------------------------------------------------------------
// Clock (ticks so "next reminder" and "today" stay current)
// -----------------------------------------------------------------------------

class ClockNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => state = DateTime.now(),
    );
    ref.onDispose(timer.cancel);
    return DateTime.now();
  }

  void refresh() => state = DateTime.now();
}

final clockProvider = NotifierProvider<ClockNotifier, DateTime>(
  ClockNotifier.new,
);

// -----------------------------------------------------------------------------
// Derived state
// -----------------------------------------------------------------------------

final reminderScheduleProvider = Provider<ReminderSchedule>(
  (ref) => ReminderSchedule.fromSettings(ref.watch(settingsProvider)),
);

/// Daily goal for the reminder exercise = target × scheduled sessions.
final dailyGoalProvider = Provider<int>((ref) {
  final settings = ref.watch(settingsProvider);
  final schedule = ref.watch(reminderScheduleProvider);
  return settings.targetFor(settings.reminderExercise) * schedule.slotsPerDay;
});

/// Today's total for one exercise (reps, or seconds when timed).
final todayTotalForExerciseProvider = Provider.family<int, ExerciseType>((
  ref,
  type,
) {
  final sessions = ref.watch(sessionsProvider);
  final now = ref.watch(clockProvider);
  var total = 0;
  for (final s in sessions) {
    if (s.skipped || s.exercise != type) continue;
    if (!AppDateUtils.isSameDay(s.startTime, now)) continue;
    total += s.completedReps;
  }
  return total;
});

final nextReminderProvider = Provider<DateTime?>(
  (ref) => ref
      .watch(reminderScheduleProvider)
      .nextReminderAfter(ref.watch(clockProvider)),
);

final todayStatsProvider = Provider<DailyStats>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final now = ref.watch(clockProvider);
  final trackSkipped = ref.watch(
    settingsProvider.select((s) => s.trackSkippedSessions),
  );
  return StatsCalculator.statsForDay(
    sessions,
    now,
    includeSkipped: trackSkipped,
  );
});

final currentStreakProvider = Provider<int>(
  (ref) => StatsCalculator.currentStreak(
    ref.watch(sessionsProvider),
    ref.watch(clockProvider),
    ptRecords: ref.watch(ptRecordsProvider),
  ),
);

/// Today's sessions, newest first.
final todaySessionsProvider = Provider<List<WorkoutSession>>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final now = ref.watch(clockProvider);
  final trackSkipped = ref.watch(
    settingsProvider.select((s) => s.trackSkippedSessions),
  );
  final today = sessions
      .where((s) => AppDateUtils.isSameDay(s.startTime, now))
      .where((s) => trackSkipped || !s.skipped)
      .toList();
  today.sort((a, b) => b.startTime.compareTo(a.startTime));
  return today;
});

/// Per-day statistics for every day with activity, newest first.
final historyProvider = Provider<List<DailyStats>>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final trackSkipped = ref.watch(
    settingsProvider.select((s) => s.trackSkippedSessions),
  );
  final byDay = StatsCalculator.statsByDay(
    sessions,
    includeSkipped: trackSkipped,
    ptRecords: ref.watch(ptRecordsProvider),
  );
  final list = byDay.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  return list;
});

/// Sessions for a specific day, newest first.
final sessionsForDayProvider = Provider.family<List<WorkoutSession>, DateTime>((
  ref,
  day,
) {
  final sessions = ref.watch(sessionsProvider);
  final trackSkipped = ref.watch(
    settingsProvider.select((s) => s.trackSkippedSessions),
  );
  final list = sessions
      .where((s) => AppDateUtils.isSameDay(s.startTime, day))
      .where((s) => trackSkipped || !s.skipped)
      .toList();
  list.sort((a, b) => b.startTime.compareTo(a.startTime));
  return list;
});

/// MY PT sessions for a specific day, newest first.
final ptRecordsForDayProvider = Provider.family<List<PtRecord>, DateTime>((
  ref,
  day,
) {
  final list = ref
      .watch(ptRecordsProvider)
      .where((r) => AppDateUtils.isSameDay(r.startTime, day))
      .toList();
  list.sort((a, b) => b.startTime.compareTo(a.startTime));
  return list;
});

// -----------------------------------------------------------------------------
// Levels
// -----------------------------------------------------------------------------

/// Lifetime XP across every attempted session.
final totalXpProvider = Provider<int>(
  (ref) => LevelSystem.totalXp(
    ref.watch(sessionsProvider),
    ptRecords: ref.watch(ptRecordsProvider),
  ),
);

/// Current level, title and progress towards the next level.
final levelProvider = Provider<LevelInfo>(
  (ref) => LevelSystem.levelFor(ref.watch(totalXpProvider)),
);
