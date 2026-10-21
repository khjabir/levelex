import 'dart:io';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/app_constants.dart';
import '../core/utils/reminder_calculator.dart';
import '../models/reminder_time.dart';
import '../models/user_settings.dart';

typedef NotificationTapHandler = void Function(String? payload);

/// How reminders ended up being scheduled.
enum ReminderScheduleOutcome {
  /// Reminders are disabled in settings; nothing scheduled.
  disabled,

  /// Scheduled with exact timing.
  exact,

  /// Scheduled, but Android may deliver them a few minutes late because the
  /// exact-alarm permission is not granted.
  inexact,

  /// Scheduling failed (e.g. notification permission missing).
  failed,
}

/// Wraps `flutter_local_notifications` for hourly reminders.
///
/// Reminders are OS-level scheduled notifications: no Dart timer or
/// background isolate is involved. Each reminder time of day is scheduled as a
/// daily-repeating notification, so a normal schedule (e.g. hourly 9–18) uses
/// only ~10 pending notifications and keeps firing without the app running.
/// Very dense schedules that would exceed iOS's 64 pending-notification limit
/// fall back to scheduling the next [NotificationConstants.maxPendingReminders]
/// individual occurrences, which are refreshed whenever the app is opened.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => Platform.isAndroid
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

  IOSFlutterLocalNotificationsPlugin? get _ios => Platform.isIOS
      ? _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
      : null;

  /// Initialises the plugin and time zone database.
  ///
  /// Returns true when the app was launched by tapping a reminder, so the
  /// caller can open the workout screen directly.
  Future<bool> initialize({required NotificationTapHandler onTap}) async {
    if (_initialized) return false;
    await _configureTimeZone();

    const androidSettings = AndroidInitializationSettings('ic_notification');
    // Permissions are requested explicitly later (after onboarding), not at
    // initialisation time.
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: darwinSettings,
        ),
        onDidReceiveNotificationResponse: (response) => onTap(response.payload),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Notification plugin failed to initialise: $e');
      return false;
    }

    await _createAndroidChannel();

    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _configureTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // tz.local stays UTC. Scheduled instants are still converted correctly;
      // only DST shifts between app launches could drift daily repeats.
      debugPrint('Could not resolve local time zone, using UTC: $e');
    }
  }

  Future<void> _createAndroidChannel() async {
    final android = _android;
    if (android == null) return;
    try {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationConstants.channelId,
          NotificationConstants.channelName,
          description: NotificationConstants.channelDescription,
          importance: Importance.high,
        ),
      );
    } catch (e) {
      debugPrint('Could not create notification channel: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Requests permission to show notifications. Returns true when granted.
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        // Android < 13 needs no runtime permission; the plugin returns true.
        return await _android?.requestNotificationsPermission() ?? true;
      }
      if (Platform.isIOS) {
        return await _ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
    return false;
  }

  /// Whether the app may currently show notifications.
  Future<bool> hasPermission() async {
    try {
      if (Platform.isAndroid) {
        return await _android?.areNotificationsEnabled() ?? true;
      }
      if (Platform.isIOS) {
        final options = await _ios?.checkPermissions();
        return options?.isEnabled ?? false;
      }
    } catch (e) {
      debugPrint('Notification permission check failed: $e');
    }
    return false;
  }

  /// Android only: whether exact alarms are allowed. Always true elsewhere.
  Future<bool> canScheduleExact() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Android only: opens the system screen to allow exact alarms.
  Future<bool> requestExactAlarmPermission() async {
    try {
      return await _android?.requestExactAlarmsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openSystemNotificationSettings() async {
    try {
      if (Platform.isAndroid) {
        await _android?.openAppNotificationSettings();
      } else if (Platform.isIOS) {
        await _ios?.openAppNotificationSettings();
      }
    } catch (e) {
      debugPrint('Could not open notification settings: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  /// Cancels and re-creates every reminder according to [settings].
  Future<ReminderScheduleOutcome> scheduleReminders(
    UserSettings settings, {
    DateTime? now,
  }) async {
    if (!_initialized) return ReminderScheduleOutcome.failed;
    await cancelReminders();
    if (!settings.remindersEnabled) return ReminderScheduleOutcome.disabled;

    final current = now ?? DateTime.now();
    final schedule = ReminderSchedule.fromSettings(settings);
    final slots = schedule.dailySlots;
    final exercise = settings.reminderExercise;
    final body = exercise.isTimed
        ? 'Time to move. Hold a ${exercise.singular} for '
              '${settings.targetFor(exercise)} seconds.'
        : 'Time for your ${exercise.label.toLowerCase()}. Complete '
              '${settings.targetFor(exercise)} reps.';
    final details = _details(settings);

    var exact = Platform.isAndroid ? await canScheduleExact() : true;
    var mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    var scheduledAny = false;

    Future<bool> scheduleOne(
      int id,
      DateTime when, {
      DateTimeComponents? repeat,
    }) async {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: NotificationConstants.title,
          body: body,
          scheduledDate: tz.TZDateTime.from(when, tz.local),
          notificationDetails: details,
          androidScheduleMode: mode,
          payload: NotificationConstants.payloadWorkout,
          matchDateTimeComponents: repeat,
        );
        return true;
      } catch (e) {
        debugPrint('Scheduling reminder $id failed: $e');
        if (exact) {
          // Exact alarm permission may have been revoked; retry inexact.
          exact = false;
          mode = AndroidScheduleMode.inexactAllowWhileIdle;
          return scheduleOne(id, when, repeat: repeat);
        }
        return false;
      }
    }

    if (slots.length <= NotificationConstants.maxPendingReminders) {
      for (var i = 0; i < slots.length; i++) {
        final ok = await scheduleOne(
          NotificationConstants.reminderIdBase + i,
          _nextInstanceOf(slots[i], current),
          repeat: DateTimeComponents.time,
        );
        scheduledAny |= ok;
      }
    } else {
      final upcoming = schedule.upcoming(
        current,
        NotificationConstants.maxPendingReminders,
      );
      for (var i = 0; i < upcoming.length; i++) {
        final ok = await scheduleOne(
          NotificationConstants.reminderIdBase + i,
          upcoming[i],
        );
        scheduledAny |= ok;
      }
    }

    if (!scheduledAny) return ReminderScheduleOutcome.failed;
    return exact
        ? ReminderScheduleOutcome.exact
        : ReminderScheduleOutcome.inexact;
  }

  /// Schedules the evening "streak at risk" nudge for [today] and [tomorrow]
  /// (either may be null to skip that day). One-off notifications, so a day
  /// that is already done gets no nudge.
  Future<void> scheduleStreakNudge(
    UserSettings settings, {
    DateTime? today,
    DateTime? tomorrow,
    required int streak,
  }) async {
    if (!_initialized) return;
    await cancelStreakNudge();
    final details = _details(settings);
    final exact = Platform.isAndroid ? await canScheduleExact() : true;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final body = streak > 0
        ? 'Nothing logged yet today. One quick set keeps your '
              '$streak-day streak alive.'
        : 'Nothing logged yet today. A quick set now starts a streak.';
    final slots = [
      (NotificationConstants.nudgeIdToday, today),
      (NotificationConstants.nudgeIdTomorrow, tomorrow),
    ];
    for (final (id, at) in slots) {
      if (at == null) continue;
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: NotificationConstants.title,
          body: body,
          scheduledDate: tz.TZDateTime.from(at, tz.local),
          notificationDetails: details,
          androidScheduleMode: mode,
          payload: NotificationConstants.payloadWorkout,
        );
      } catch (e) {
        debugPrint('Scheduling streak nudge $id failed: $e');
      }
    }
  }

  Future<void> cancelStreakNudge() async {
    try {
      await _plugin.cancel(id: NotificationConstants.nudgeIdToday);
      await _plugin.cancel(id: NotificationConstants.nudgeIdTomorrow);
    } catch (e) {
      debugPrint('Cancelling streak nudge failed: $e');
    }
  }

  Future<void> cancelReminders() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Cancelling reminders failed: $e');
    }
  }

  Future<int> pendingCount() async {
    try {
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
  }

  /// The next occurrence of [time] strictly after [now].
  static DateTime _nextInstanceOf(ReminderTime time, DateTime now) {
    final today = time.onDay(now);
    if (today.isAfter(now)) return today;
    return time.onDay(DateTime(now.year, now.month, now.day + 1));
  }

  NotificationDetails _details(UserSettings settings) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationConstants.channelId,
        NotificationConstants.channelName,
        channelDescription: NotificationConstants.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: 'ic_notification',
        color: const Color(0xFF39FF88),
        // Channel sound/vibration are fixed once created on Android 8+, so a
        // "sound off" preference silences the notification itself.
        silent: !settings.soundEnabled,
        playSound: settings.soundEnabled,
        enableVibration: settings.vibrationEnabled,
        ticker: NotificationConstants.title,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: settings.soundEnabled,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: NotificationConstants.channelId,
      ),
    );
  }
}
