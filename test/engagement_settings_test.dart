import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/models/reminder_time.dart';
import 'package:levelex/models/user_settings.dart';

void main() {
  group('UserSettings engagement fields', () {
    test('round-trip through JSON', () {
      const original = UserSettings(
        weeklyGoal: 5,
        restWeekdays: {DateTime.sunday, DateTime.wednesday},
        nudgeEnabled: false,
        nudgeTime: ReminderTime(hour: 20, minute: 15),
        achievementsSeen: {'first_set', 'streak_3'},
      );
      final back = UserSettings.fromJson(original.toJson());
      expect(back.weeklyGoal, 5);
      expect(back.restWeekdays, {DateTime.sunday, DateTime.wednesday});
      expect(back.nudgeEnabled, isFalse);
      expect(back.nudgeTime, const ReminderTime(hour: 20, minute: 15));
      expect(back.achievementsSeen, {'first_set', 'streak_3'});
    });

    test('defaults and bounds for older settings files', () {
      final back = UserSettings.fromJson('{"pushUpsPerSession": 12}');
      expect(back.weeklyGoal, 3);
      expect(back.restWeekdays, isEmpty);
      expect(back.nudgeEnabled, isTrue);
      expect(back.nudgeTime, const ReminderTime(hour: 19, minute: 30));
      expect(back.achievementsSeen, isEmpty);
      final clamped = UserSettings.fromJson(
        '{"weeklyGoal": 99, "restWeekdays": [0, 3, 8, "x"]}',
      );
      expect(clamped.weeklyGoal, 14);
      expect(clamped.restWeekdays, {3});
    });
  });
}
