import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/data/pt_repository.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/models/reminder_time.dart';
import 'package:levelex/models/user_settings.dart';
import 'package:levelex/models/workout_session.dart';
import 'package:levelex/services/storage_service.dart';
import 'package:levelex/services/workout_service.dart';

PtRecord ptRecord(
  DateTime start, {
  Duration length = const Duration(minutes: 30),
  bool verified = true,
  bool finished = true,
}) => PtRecord(
  id: 'pt-${start.toIso8601String()}',
  startTime: start,
  endTime: start.add(length),
  mode: WorkoutMode.fullBody,
  plannedMinutes: length.inMinutes,
  items: [
    PtItemResult(
      movementId: 'push_up',
      phase: PlanPhase.main,
      setsPlanned: 3,
      setsDone: finished ? 3 : 1,
      reps: finished ? 30 : 10,
      seconds: 0,
      skipped: false,
    ),
  ],
  verified: verified,
  plannedItems: 1,
);

void main() {
  late InMemorySessionRepository sessions;
  late InMemorySettingsRepository settings;
  late DateTime now;
  late WorkoutService service;

  final setupAt = DateTime(2026, 3, 10, 8, 30);
  final hourlySettings = const UserSettings(
    pushUpsPerSession: 10,
    reminderInterval: Duration(hours: 1),
    reminderStartTime: ReminderTime(hour: 9, minute: 0),
    reminderEndTime: ReminderTime(hour: 18, minute: 0),
  ).copyWith(onboardingCompleted: true, setupCompletedAt: setupAt);

  setUp(() {
    sessions = InMemorySessionRepository();
    settings = InMemorySettingsRepository(hourlySettings);
    now = DateTime(2026, 3, 10, 12, 30);
    service = WorkoutService(
      sessions: sessions,
      settings: settings,
      clock: () => now,
    );
  });

  group('recordWorkout', () {
    test('marks completed when target reached and clears the draft', () async {
      await settings.saveDraft(
        WorkoutDraft(id: 'a', startTime: now, targetReps: 10, reps: 3),
      );
      final session = await service.recordWorkout(
        id: 'a',
        startTime: now,
        targetReps: 10,
        reps: 10,
        formScore: 0.9,
      );
      expect(session.status, SessionStatus.completed);
      expect(session.endTime, now);
      expect(settings.draft, isNull);
      expect(sessions.all().single.id, 'a');
    });

    test('recordWorkout stores the verified flag', () async {
      final session = await service.recordWorkout(
        id: 'u1',
        startTime: DateTime(2026, 3, 10, 9),
        targetReps: 10,
        reps: 10,
        verified: false,
      );
      expect(session.verified, isFalse);
      expect(WorkoutSession.fromMap(session.toMap()).verified, isFalse);
      expect(sessions.all().single.verified, isFalse);
    });

    test('marks incomplete when short of the target', () async {
      final session = await service.recordWorkout(
        id: 'b',
        startTime: now,
        targetReps: 10,
        reps: 4,
      );
      expect(session.status, SessionStatus.incomplete);
      expect(session.isAttempted, isTrue);
    });
  });

  group('recoverInterruptedWorkout', () {
    test('stores a draft with reps as an incomplete session', () async {
      await settings.saveDraft(
        WorkoutDraft(
          id: 'draft',
          startTime: DateTime(2026, 3, 10, 9, 5),
          targetReps: 10,
          reps: 6,
        ),
      );
      final recovered = await service.recoverInterruptedWorkout();
      expect(recovered, isNotNull);
      expect(recovered!.completedReps, 6);
      expect(recovered.status, SessionStatus.incomplete);
      expect(settings.draft, isNull);
      expect(sessions.all().length, 1);
    });

    test('discards an empty draft', () async {
      await settings.saveDraft(
        WorkoutDraft(id: 'draft', startTime: now, targetReps: 10, reps: 0),
      );
      expect(await service.recoverInterruptedWorkout(), isNull);
      expect(settings.draft, isNull);
      expect(sessions.all(), isEmpty);
    });

    test('does nothing without a draft', () async {
      expect(await service.recoverInterruptedWorkout(), isNull);
    });
  });

  group('evaluateSkippedSessions', () {
    test('records missed reminders after setup as skipped sessions', () async {
      // Setup at 8:30, now 12:30 → 9, 10 and 11 o'clock windows have closed.
      final created = await service.evaluateSkippedSessions(hourlySettings);
      expect(created.map((s) => s.startTime), [
        DateTime(2026, 3, 10, 9),
        DateTime(2026, 3, 10, 10),
        DateTime(2026, 3, 10, 11),
      ]);
      expect(created.every((s) => s.skipped), isTrue);
      expect(sessions.all().length, 3);
      expect(settings.skipEvaluatedUntil, now);
    });

    test('does not double count on repeated evaluation', () async {
      await service.evaluateSkippedSessions(hourlySettings);
      now = DateTime(2026, 3, 10, 13, 30);
      final created = await service.evaluateSkippedSessions(hourlySettings);
      expect(created.map((s) => s.startTime), [DateTime(2026, 3, 10, 12)]);
      expect(sessions.all().length, 4);
    });

    test('an attempted set covers its reminder window', () async {
      await service.recordWorkout(
        id: 'w',
        startTime: DateTime(2026, 3, 10, 10, 20),
        targetReps: 10,
        reps: 2,
      );
      final created = await service.evaluateSkippedSessions(hourlySettings);
      expect(created.map((s) => s.startTime), [
        DateTime(2026, 3, 10, 9),
        DateTime(2026, 3, 10, 11),
      ]);
    });

    test('a verified MY PT session covers every window it overlaps', () async {
      final pt = InMemoryPtRepository();
      await pt.upsertRecord(
        ptRecord(
          DateTime(2026, 3, 10, 9, 40),
          length: const Duration(minutes: 40),
        ),
      );
      service = WorkoutService(
        sessions: sessions,
        settings: settings,
        pt: pt,
        clock: () => now,
      );
      final created = await service.evaluateSkippedSessions(hourlySettings);
      expect(created.map((s) => s.startTime), [DateTime(2026, 3, 10, 11)]);
    });

    test('an unverified MY PT session does not cover a reminder', () async {
      final pt = InMemoryPtRepository();
      await pt.upsertRecord(
        ptRecord(DateTime(2026, 3, 10, 10, 10), verified: false),
      );
      service = WorkoutService(
        sessions: sessions,
        settings: settings,
        pt: pt,
        clock: () => now,
      );
      final created = await service.evaluateSkippedSessions(hourlySettings);
      expect(created.length, 3);
    });

    test('records nothing when tracking is off but still advances', () async {
      final off = hourlySettings.copyWith(trackSkippedSessions: false);
      final created = await service.evaluateSkippedSessions(off);
      expect(created, isEmpty);
      expect(settings.skipEvaluatedUntil, now);

      // Re-enabling later must not be retroactive.
      now = DateTime(2026, 3, 10, 13, 30);
      final later = await service.evaluateSkippedSessions(hourlySettings);
      expect(later.map((s) => s.startTime), [DateTime(2026, 3, 10, 12)]);
    });

    test('records nothing before onboarding completed', () async {
      final created = await service.evaluateSkippedSessions(
        const UserSettings(),
      );
      expect(created, isEmpty);
      expect(sessions.all(), isEmpty);
    });

    test('records nothing when reminders are disabled', () async {
      final created = await service.evaluateSkippedSessions(
        hourlySettings.copyWith(remindersEnabled: false),
      );
      expect(created, isEmpty);
    });
  });

  group('face registration', () {
    List<double> vec(int seed) => [
      for (var i = 0; i < 8; i++) ((i * 7 + seed * 13) % 11) / 11 - 0.5,
    ];

    test('registers once and refuses a second registration', () async {
      expect(service.hasRegisteredFace, isFalse);
      final template = await service.registerFace([vec(1), vec(1), vec(1)]);
      expect(template.sampleCount, 3);
      expect(template.registeredAt, now);
      expect(service.hasRegisteredFace, isTrue);
      expect(settings.faceTemplate, isNotNull);
      await expectLater(() => service.registerFace([vec(2)]), throwsStateError);
    });

    test('erasing face data also erases the score', () async {
      await service.registerFace([vec(1)]);
      await service.recordWorkout(
        id: 'w',
        startTime: now,
        targetReps: 10,
        reps: 10,
      );
      expect(sessions.all(), isNotEmpty);
      await service.eraseFaceData();
      expect(service.hasRegisteredFace, isFalse);
      expect(sessions.all(), isEmpty);
      // A new registration is possible afterwards.
      await service.registerFace([vec(3)]);
      expect(service.hasRegisteredFace, isTrue);
    });
  });

  group('clearHistory', () {
    test('removes sessions and the draft', () async {
      await service.recordWorkout(
        id: 'x',
        startTime: now,
        targetReps: 10,
        reps: 10,
      );
      await settings.saveDraft(
        WorkoutDraft(id: 'd', startTime: now, targetReps: 10, reps: 1),
      );
      await service.clearHistory();
      expect(sessions.all(), isEmpty);
      expect(settings.draft, isNull);
    });
  });
}
