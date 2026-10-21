import 'dart:convert';

import '../core/constants/app_constants.dart';
import 'exercise.dart';
import 'reminder_time.dart';

/// Which camera the workout screen opens with.
enum CameraFacing {
  front,
  back;

  String get label => this == front ? 'Front (selfie)' : 'Back';
}

/// Unit loads are shown in. Everything is stored in kilograms.
enum WeightUnit {
  kg('kg', 1.0),
  lb('lb', 2.2046226218);

  const WeightUnit(this.label, this.perKg);

  final String label;

  /// How many of this unit make one kilogram.
  final double perKg;

  double fromKg(double kg) => kg * perKg;
  double toKg(double value) => value / perKg;

  /// The smallest step a stepper should move in this unit, in kg.
  double get stepKg => this == kg ? 0.5 : toKg(1);

  /// A load formatted in this unit, e.g. "22.5 kg" or "50 lb".
  String format(double kg, {bool withUnit = true}) {
    final v = fromKg(kg);
    final rounded = (v * 100).round() / 100;
    var text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(
            rounded * 10 == (rounded * 10).roundToDouble() ? 1 : 2,
          );
    if (text == '-0') text = '0';
    return withUnit ? '$text $label' : text;
  }

  static WeightUnit fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => kg);
}

/// All user-configurable preferences. Immutable; use [copyWith] to change.
class UserSettings {
  const UserSettings({
    this.pushUpsPerSession = Defaults.pushUpsPerSession,
    this.reminderInterval = const Duration(
      minutes: Defaults.reminderIntervalMinutes,
    ),
    this.reminderStartTime = const ReminderTime(
      hour: Defaults.reminderStartHour,
      minute: 0,
    ),
    this.reminderEndTime = const ReminderTime(
      hour: Defaults.reminderEndHour,
      minute: 0,
    ),
    this.remindersEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.onboardingCompleted = false,
    this.trackSkippedSessions = true,
    this.formSensitivity = FormSensitivity.medium,
    this.setupCompletedAt,
    this.cameraFacing = CameraFacing.front,
    this.voiceEnabled = true,
    this.selectedExercise = ExerciseType.pushUp,
    this.reminderExercise = ExerciseType.pushUp,
    this.targets = const {},
    this.showTrackingDetails = false,
    this.weightUnit = WeightUnit.kg,
  });

  final int pushUpsPerSession;
  final Duration reminderInterval;
  final ReminderTime reminderStartTime;
  final ReminderTime reminderEndTime;
  final bool remindersEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool onboardingCompleted;

  /// When false, missed reminders are never recorded as skipped sessions.
  final bool trackSkippedSessions;
  final FormSensitivity formSensitivity;

  /// When onboarding was completed. Reminders before this moment are never
  /// counted as skipped.
  final DateTime? setupCompletedAt;

  /// Camera used for workouts. The back camera lets someone else hold the
  /// phone and watch.
  final CameraFacing cameraFacing;

  /// Spoken coaching: ready, countdown, rep counts, form cues.
  final bool voiceEnabled;

  /// Exercise chosen on the home screen for the next set.
  final ExerciseType selectedExercise;

  /// Exercise the hourly reminder asks for (and the daily goal counts).
  final ExerciseType reminderExercise;

  /// Per-exercise targets (reps, or seconds for timed exercises). Missing
  /// entries use the exercise default; push-ups mirror [pushUpsPerSession].
  final Map<ExerciseType, int> targets;

  /// Show live tracking numbers on the camera screen.
  final bool showTrackingDetails;

  /// Unit for loads in the lift log and MY PT.
  final WeightUnit weightUnit;

  /// Target for [type].
  int targetFor(ExerciseType type) {
    if (type == ExerciseType.pushUp) return pushUpsPerSession;
    return targets[type] ?? type.defaultTarget;
  }

  /// Copy with the target for [type] changed.
  UserSettings withTarget(ExerciseType type, int value) {
    if (type == ExerciseType.pushUp) return copyWith(pushUpsPerSession: value);
    return copyWith(targets: {...targets, type: value});
  }

  UserSettings copyWith({
    int? pushUpsPerSession,
    Duration? reminderInterval,
    ReminderTime? reminderStartTime,
    ReminderTime? reminderEndTime,
    bool? remindersEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? onboardingCompleted,
    bool? trackSkippedSessions,
    FormSensitivity? formSensitivity,
    DateTime? setupCompletedAt,
    CameraFacing? cameraFacing,
    bool? voiceEnabled,
    ExerciseType? selectedExercise,
    ExerciseType? reminderExercise,
    Map<ExerciseType, int>? targets,
    bool? showTrackingDetails,
    WeightUnit? weightUnit,
  }) {
    return UserSettings(
      pushUpsPerSession: pushUpsPerSession ?? this.pushUpsPerSession,
      reminderInterval: reminderInterval ?? this.reminderInterval,
      reminderStartTime: reminderStartTime ?? this.reminderStartTime,
      reminderEndTime: reminderEndTime ?? this.reminderEndTime,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      trackSkippedSessions: trackSkippedSessions ?? this.trackSkippedSessions,
      formSensitivity: formSensitivity ?? this.formSensitivity,
      setupCompletedAt: setupCompletedAt ?? this.setupCompletedAt,
      cameraFacing: cameraFacing ?? this.cameraFacing,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      selectedExercise: selectedExercise ?? this.selectedExercise,
      reminderExercise: reminderExercise ?? this.reminderExercise,
      targets: targets ?? this.targets,
      showTrackingDetails: showTrackingDetails ?? this.showTrackingDetails,
      weightUnit: weightUnit ?? this.weightUnit,
    );
  }

  Map<String, dynamic> toMap() => {
    'pushUpsPerSession': pushUpsPerSession,
    'reminderIntervalMinutes': reminderInterval.inMinutes,
    'reminderStartMinutes': reminderStartTime.minutesSinceMidnight,
    'reminderEndMinutes': reminderEndTime.minutesSinceMidnight,
    'remindersEnabled': remindersEnabled,
    'soundEnabled': soundEnabled,
    'vibrationEnabled': vibrationEnabled,
    'onboardingCompleted': onboardingCompleted,
    'trackSkippedSessions': trackSkippedSessions,
    'formSensitivity': formSensitivity.name,
    'setupCompletedAt': setupCompletedAt?.millisecondsSinceEpoch,
    'cameraFacing': cameraFacing.name,
    'voiceEnabled': voiceEnabled,
    'selectedExercise': selectedExercise.id,
    'reminderExercise': reminderExercise.id,
    'targets': {for (final e in targets.entries) e.key.id: e.value},
    'showTrackingDetails': showTrackingDetails,
    'weightUnit': weightUnit.name,
  };

  factory UserSettings.fromMap(Map<String, dynamic> map) {
    const defaults = UserSettings();
    final sensitivityName = map['formSensitivity'] as String?;
    final facingName = map['cameraFacing'] as String?;
    return UserSettings(
      pushUpsPerSession:
          (map['pushUpsPerSession'] as int?) ?? defaults.pushUpsPerSession,
      reminderInterval: Duration(
        minutes:
            (map['reminderIntervalMinutes'] as int?) ??
            defaults.reminderInterval.inMinutes,
      ),
      reminderStartTime: ReminderTime.fromMinutes(
        (map['reminderStartMinutes'] as int?) ??
            defaults.reminderStartTime.minutesSinceMidnight,
      ),
      reminderEndTime: ReminderTime.fromMinutes(
        (map['reminderEndMinutes'] as int?) ??
            defaults.reminderEndTime.minutesSinceMidnight,
      ),
      remindersEnabled:
          (map['remindersEnabled'] as bool?) ?? defaults.remindersEnabled,
      soundEnabled: (map['soundEnabled'] as bool?) ?? defaults.soundEnabled,
      vibrationEnabled:
          (map['vibrationEnabled'] as bool?) ?? defaults.vibrationEnabled,
      onboardingCompleted:
          (map['onboardingCompleted'] as bool?) ?? defaults.onboardingCompleted,
      trackSkippedSessions:
          (map['trackSkippedSessions'] as bool?) ??
          defaults.trackSkippedSessions,
      formSensitivity: FormSensitivity.values.firstWhere(
        (s) => s.name == sensitivityName,
        orElse: () => defaults.formSensitivity,
      ),
      setupCompletedAt: switch (map['setupCompletedAt']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
      cameraFacing: CameraFacing.values.firstWhere(
        (f) => f.name == facingName,
        orElse: () => defaults.cameraFacing,
      ),
      voiceEnabled: (map['voiceEnabled'] as bool?) ?? defaults.voiceEnabled,
      selectedExercise: ExerciseType.fromId(map['selectedExercise'] as String?),
      reminderExercise: ExerciseType.fromId(map['reminderExercise'] as String?),
      targets: switch (map['targets']) {
        final Map raw => {
          for (final e in raw.entries)
            if (e.value is int)
              ExerciseType.fromId(e.key as String?): e.value as int,
        },
        _ => const {},
      },
      showTrackingDetails:
          (map['showTrackingDetails'] as bool?) ?? defaults.showTrackingDetails,
      weightUnit: WeightUnit.fromName(map['weightUnit'] as String?),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory UserSettings.fromJson(String json) =>
      UserSettings.fromMap(jsonDecode(json) as Map<String, dynamic>);
}
