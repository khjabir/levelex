import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/stats_calculator.dart';
import '../../models/user_settings.dart';
import '../pt/pt_providers.dart';

/// Keeps the evening "streak at risk" nudge in step with what was done:
/// scheduled for today only while nothing is done yet, and for tomorrow in
/// case the app is not opened again before then. Rest days get no nudge.
class StreakNudge {
  StreakNudge(this.ref);

  final Ref ref;

  Future<void> sync() async {
    try {
      final settings = ref.read(settingsProvider);
      final service = ref.read(notificationServiceProvider);
      if (!settings.onboardingCompleted || !settings.nudgeEnabled) {
        await service.cancelStreakNudge();
        return;
      }
      final now = DateTime.now();
      final sessions = ref.read(sessionsProvider);
      final pt = ref.read(ptRecordsProvider);
      final done = StatsCalculator.completedDays(sessions, ptRecords: pt);
      final today = AppDateUtils.dateOnly(now);
      final tomorrow = AppDateUtils.addDays(today, 1);
      DateTime? slot(DateTime day) {
        if (settings.restWeekdays.contains(day.weekday)) return null;
        if (done.contains(day)) return null;
        final at = settings.nudgeTime.onDay(day);
        return at.isAfter(now) ? at : null;
      }

      final streak = StatsCalculator.currentStreak(
        sessions,
        now,
        ptRecords: pt,
        restWeekdays: settings.restWeekdays,
      );
      final todaySafe =
          done.contains(today) || settings.restWeekdays.contains(today.weekday);
      await service.scheduleStreakNudge(
        settings,
        today: slot(today),
        tomorrow: slot(tomorrow),
        streak: streak,
        tomorrowStreak: todaySafe ? streak : 0,
      );
    } catch (e) {
      debugPrint('Streak nudge sync failed: $e');
    }
  }

  /// Whether a settings change requires re-syncing the nudge.
  static bool affects(UserSettings a, UserSettings b) =>
      a.nudgeEnabled != b.nudgeEnabled ||
      a.nudgeTime != b.nudgeTime ||
      a.restWeekdays != b.restWeekdays ||
      a.soundEnabled != b.soundEnabled ||
      a.vibrationEnabled != b.vibrationEnabled;
}

final streakNudgeProvider = Provider<StreakNudge>((ref) => StreakNudge(ref));
