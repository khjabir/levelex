import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../models/user_settings.dart';
import '../../services/notification_service.dart';

/// Current state of the reminder system as seen by the UI.
class ReminderStatus {
  const ReminderStatus({
    this.permissionGranted,
    this.exactAlarmsAllowed = true,
    this.outcome,
  });

  /// Null until checked.
  final bool? permissionGranted;

  /// Android only; always true on iOS.
  final bool exactAlarmsAllowed;
  final ReminderScheduleOutcome? outcome;

  ReminderStatus copyWith({
    bool? permissionGranted,
    bool? exactAlarmsAllowed,
    ReminderScheduleOutcome? outcome,
  }) => ReminderStatus(
    permissionGranted: permissionGranted ?? this.permissionGranted,
    exactAlarmsAllowed: exactAlarmsAllowed ?? this.exactAlarmsAllowed,
    outcome: outcome ?? this.outcome,
  );
}

/// Keeps OS-scheduled reminders in sync with the user's settings and exposes
/// permission state to the UI.
class ReminderController extends Notifier<ReminderStatus> {
  @override
  ReminderStatus build() => const ReminderStatus();

  NotificationService get _service => ref.read(notificationServiceProvider);

  /// Asks the OS for notification permission and schedules reminders when
  /// granted. Returns whether permission is granted.
  Future<bool> requestPermission() async {
    final granted = await _service.requestPermission();
    state = state.copyWith(permissionGranted: granted);
    await reschedule();
    return granted;
  }

  /// Re-creates all scheduled reminders from the current settings.
  Future<void> reschedule() async {
    final settings = ref.read(settingsProvider);
    final outcome = await _service.scheduleReminders(settings);
    await refreshStatus(outcome: outcome);
  }

  /// Re-reads permission state without touching the schedule.
  Future<void> refreshStatus({ReminderScheduleOutcome? outcome}) async {
    final granted = await _service.hasPermission();
    final exact = await _service.canScheduleExact();
    state = ReminderStatus(
      permissionGranted: granted,
      exactAlarmsAllowed: exact,
      outcome: outcome ?? state.outcome,
    );
  }

  Future<void> requestExactAlarms() async {
    await _service.requestExactAlarmPermission();
    await reschedule();
  }

  Future<void> openSystemSettings() =>
      _service.openSystemNotificationSettings();

  /// True when a change between [previous] and [next] requires rescheduling.
  static bool affectsSchedule(UserSettings previous, UserSettings next) =>
      previous.remindersEnabled != next.remindersEnabled ||
      previous.reminderInterval != next.reminderInterval ||
      previous.reminderStartTime != next.reminderStartTime ||
      previous.reminderEndTime != next.reminderEndTime ||
      previous.pushUpsPerSession != next.pushUpsPerSession ||
      previous.reminderExercise != next.reminderExercise ||
      previous.targets != next.targets ||
      previous.soundEnabled != next.soundEnabled ||
      previous.vibrationEnabled != next.vibrationEnabled;
}

final reminderControllerProvider =
    NotifierProvider<ReminderController, ReminderStatus>(
      ReminderController.new,
    );
