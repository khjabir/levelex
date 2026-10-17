import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/reminder_calculator.dart';
import 'package:levelex/models/reminder_time.dart';
import 'package:levelex/models/user_settings.dart';
import 'package:levelex/models/workout_session.dart';

ReminderSchedule hourly({bool enabled = true}) => ReminderSchedule(
  interval: const Duration(hours: 1),
  start: const ReminderTime(hour: 9, minute: 0),
  end: const ReminderTime(hour: 18, minute: 0),
  enabled: enabled,
);

WorkoutSession attempt(DateTime at, {int reps = 10}) => WorkoutSession(
  id: at.toIso8601String(),
  startTime: at,
  targetReps: 10,
  completedReps: reps,
  status: reps >= 10 ? SessionStatus.completed : SessionStatus.incomplete,
);

void main() {
  group('ReminderSchedule.dailySlots', () {
    test('hourly 9-18 gives 10 slots inclusive of both ends', () {
      final slots = hourly().dailySlots;
      expect(slots.length, 10);
      expect(slots.first, const ReminderTime(hour: 9, minute: 0));
      expect(slots.last, const ReminderTime(hour: 18, minute: 0));
    });

    test('30 minute interval doubles the slots', () {
      final s = ReminderSchedule(
        interval: const Duration(minutes: 30),
        start: const ReminderTime(hour: 9, minute: 0),
        end: const ReminderTime(hour: 10, minute: 0),
        enabled: true,
      );
      expect(s.dailySlots.map((t) => t.label), [
        '9:00 AM',
        '9:30 AM',
        '10:00 AM',
      ]);
    });

    test('interval that does not divide the window stops before end', () {
      final s = ReminderSchedule(
        interval: const Duration(minutes: 45),
        start: const ReminderTime(hour: 9, minute: 0),
        end: const ReminderTime(hour: 11, minute: 0),
        enabled: true,
      );
      expect(s.dailySlots.map((t) => t.minutesSinceMidnight), [540, 585, 630]);
    });

    test('end before start yields a single slot at start', () {
      final s = ReminderSchedule(
        interval: const Duration(hours: 1),
        start: const ReminderTime(hour: 18, minute: 0),
        end: const ReminderTime(hour: 9, minute: 0),
        enabled: true,
      );
      expect(s.dailySlots, [const ReminderTime(hour: 18, minute: 0)]);
    });

    test('fromSettings mirrors the user settings', () {
      final s = ReminderSchedule.fromSettings(const UserSettings());
      expect(s.interval, const Duration(hours: 1));
      expect(s.slotsPerDay, 10);
      expect(s.enabled, isTrue);
    });
  });

  group('ReminderSchedule.nextReminderAfter', () {
    test('returns the next slot later today', () {
      final next = hourly().nextReminderAfter(DateTime(2026, 3, 10, 9, 30));
      expect(next, DateTime(2026, 3, 10, 10));
    });

    test('exactly at a slot moves to the following slot', () {
      final next = hourly().nextReminderAfter(DateTime(2026, 3, 10, 10));
      expect(next, DateTime(2026, 3, 10, 11));
    });

    test('after the last slot rolls over to tomorrow morning', () {
      final next = hourly().nextReminderAfter(DateTime(2026, 3, 10, 18, 5));
      expect(next, DateTime(2026, 3, 11, 9));
    });

    test('rolls over month boundary', () {
      final next = hourly().nextReminderAfter(DateTime(2026, 1, 31, 23));
      expect(next, DateTime(2026, 2, 1, 9));
    });

    test('null when disabled', () {
      expect(
        hourly(enabled: false).nextReminderAfter(DateTime(2026, 3, 10, 9)),
        isNull,
      );
    });
  });

  group('ReminderSchedule.upcoming', () {
    test('lists the requested number of future reminders across days', () {
      final list = hourly().upcoming(DateTime(2026, 3, 10, 16, 30), 5);
      expect(list, [
        DateTime(2026, 3, 10, 17),
        DateTime(2026, 3, 10, 18),
        DateTime(2026, 3, 11, 9),
        DateTime(2026, 3, 11, 10),
        DateTime(2026, 3, 11, 11),
      ]);
    });

    test('zero count yields nothing', () {
      expect(hourly().upcoming(DateTime(2026, 3, 10), 0), isEmpty);
    });
  });

  group('ReminderSchedule.skippedSlots', () {
    final from = DateTime(2026, 3, 10, 8);

    test('a slot is skipped only once its full window has passed', () {
      final skipped = hourly().skippedSlots(
        from: from,
        now: DateTime(2026, 3, 10, 10, 30),
        sessions: const [],
      );
      // 9:00 window closed at 10:00; 10:00 window still open.
      expect(skipped, [DateTime(2026, 3, 10, 9)]);
    });

    test('an attempted workout inside the window prevents a skip', () {
      final skipped = hourly().skippedSlots(
        from: from,
        now: DateTime(2026, 3, 10, 11, 59),
        sessions: [attempt(DateTime(2026, 3, 10, 9, 20), reps: 3)],
      );
      // 9:00 covered by the partial attempt, 10:00 skipped, 11:00 still open.
      expect(skipped, [DateTime(2026, 3, 10, 10)]);
    });

    test('slots before `from` are never counted', () {
      final skipped = hourly().skippedSlots(
        from: DateTime(2026, 3, 10, 11, 30),
        now: DateTime(2026, 3, 10, 13, 30),
        sessions: const [],
      );
      expect(skipped, [DateTime(2026, 3, 10, 12)]);
    });

    test('spans multiple days', () {
      final skipped = hourly().skippedSlots(
        from: DateTime(2026, 3, 9, 17, 30),
        now: DateTime(2026, 3, 10, 10, 30),
        sessions: [attempt(DateTime(2026, 3, 10, 9, 5))],
      );
      expect(skipped, [DateTime(2026, 3, 9, 18)]);
    });

    test('a window closes exactly when a full interval has elapsed', () {
      final skipped = hourly().skippedSlots(
        from: from,
        now: DateTime(2026, 3, 10, 10),
        sessions: const [],
      );
      expect(skipped, [DateTime(2026, 3, 10, 9)]);
    });

    test('windows already evaluated are not reported again', () {
      final first = hourly().skippedSlots(
        from: from,
        now: DateTime(2026, 3, 10, 11, 30),
        sessions: const [],
      );
      expect(first, [DateTime(2026, 3, 10, 9), DateTime(2026, 3, 10, 10)]);
      final second = hourly().skippedSlots(
        from: from,
        evaluatedUntil: DateTime(2026, 3, 10, 11, 30),
        now: DateTime(2026, 3, 10, 12, 30),
        sessions: const [],
      );
      expect(second, [DateTime(2026, 3, 10, 11)]);
    });

    test('disabled reminders never produce skips', () {
      final skipped = hourly(enabled: false).skippedSlots(
        from: from,
        now: DateTime(2026, 3, 11),
        sessions: const [],
      );
      expect(skipped, isEmpty);
    });

    test('skipped records themselves are not treated as attempts', () {
      final skippedRecord = WorkoutSession(
        id: 's',
        startTime: DateTime(2026, 3, 10, 9),
        targetReps: 10,
        completedReps: 0,
        status: SessionStatus.skipped,
      );
      final skipped = hourly().skippedSlots(
        from: from,
        now: DateTime(2026, 3, 10, 10, 30),
        sessions: [skippedRecord],
      );
      expect(skipped, [DateTime(2026, 3, 10, 9)]);
    });
  });

  group('ReminderTime', () {
    test('formats 12-hour labels', () {
      expect(const ReminderTime(hour: 0, minute: 5).label, '12:05 AM');
      expect(const ReminderTime(hour: 12, minute: 0).label, '12:00 PM');
      expect(const ReminderTime(hour: 18, minute: 30).label, '6:30 PM');
    });

    test('fromMinutes clamps into the day', () {
      expect(ReminderTime.fromMinutes(-5).minutesSinceMidnight, 0);
      expect(ReminderTime.fromMinutes(5000).minutesSinceMidnight, 1439);
    });
  });

  group('UserSettings serialisation', () {
    test('round-trips through JSON', () {
      final s = const UserSettings().copyWith(
        pushUpsPerSession: 15,
        reminderInterval: const Duration(minutes: 90),
        reminderStartTime: const ReminderTime(hour: 7, minute: 15),
        remindersEnabled: false,
        onboardingCompleted: true,
        setupCompletedAt: DateTime(2026, 3, 1, 8),
      );
      final restored = UserSettings.fromJson(s.toJson());
      expect(restored.pushUpsPerSession, 15);
      expect(restored.reminderInterval, const Duration(minutes: 90));
      expect(
        restored.reminderStartTime,
        const ReminderTime(hour: 7, minute: 15),
      );
      expect(restored.remindersEnabled, isFalse);
      expect(restored.onboardingCompleted, isTrue);
      expect(restored.setupCompletedAt, DateTime(2026, 3, 1, 8));
    });

    test('missing keys fall back to defaults', () {
      final restored = UserSettings.fromMap(const {});
      expect(restored.pushUpsPerSession, 10);
      expect(restored.onboardingCompleted, isFalse);
    });
  });

  group('WorkoutSession serialisation', () {
    test('round-trips through a map', () {
      final s = WorkoutSession(
        id: 'abc',
        startTime: DateTime(2026, 3, 10, 9),
        endTime: DateTime(2026, 3, 10, 9, 2),
        targetReps: 10,
        completedReps: 10,
        status: SessionStatus.completed,
        formScore: 0.8,
      );
      final restored = WorkoutSession.fromMap(s.toMap());
      expect(restored.id, 'abc');
      expect(restored.startTime, s.startTime);
      expect(restored.endTime, s.endTime);
      expect(restored.status, SessionStatus.completed);
      expect(restored.formScore, 0.8);
      expect(restored.isCompleted, isTrue);
    });
  });
}
