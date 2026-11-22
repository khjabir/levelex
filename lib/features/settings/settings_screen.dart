import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/constants/app_constants.dart';
import '../../models/exercise.dart';
import '../../models/user_settings.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';
import '../face/face_providers.dart';
import '../notifications/reminder_controller.dart';
import '../notifications/streak_nudge.dart';
import '../challenge/challenge_providers.dart';
import '../pt/pt_providers.dart';
import '../strength/data/backup_actions.dart';
import '../strength/strength_providers.dart';
import '../workout/exercise_icons.dart';
import '../workout/workout_intro_screen.dart';
import 'widgets/settings_widgets.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(reminderControllerProvider.notifier).refreshStatus();
      }
    });
  }

  /// Applies a settings change and keeps the OS reminder schedule in sync.
  Future<void> _update(UserSettings Function(UserSettings) change) async {
    final before = ref.read(settingsProvider);
    if (ReminderController.affectsSchedule(before, change(before)) ||
        before.trackSkippedSessions != change(before).trackSkippedSessions) {
      // Settle missed reminders under the rules that were in force, so the
      // new schedule only applies from now (turning reminders on at 11:30
      // must not record 09:00-11:00 as skipped).
      await ref.read(sessionsProvider.notifier).evaluateSkipped();
    }
    await ref.read(settingsProvider.notifier).updateSettings(change);
    final after = ref.read(settingsProvider);
    if (ReminderController.affectsSchedule(before, after)) {
      await ref.read(reminderControllerProvider.notifier).reschedule();
      await ref.read(streakNudgeProvider).sync();
    } else if (StreakNudge.affects(before, after)) {
      await ref.read(streakNudgeProvider).sync();
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
  }

  Future<void> _exportBackup() async {
    try {
      await BackupActions.export(ref);
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _importBackup() async {
    try {
      final text = await BackupActions.pickTextFile();
      if (text == null) return;
      final outcome = await BackupActions.importBackup(ref, text);
      _toast(outcome.message);
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  Future<void> _importOtherApp() async {
    try {
      final text = await BackupActions.pickTextFile();
      if (text == null) return;
      final outcome = await BackupActions.importFromOtherApp(ref, text);
      if (!mounted) return;
      if (outcome.unmatched.isEmpty) {
        _toast(outcome.message);
        return;
      }
      final names = outcome.unmatched.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Imported'),
          content: SingleChildScrollView(
            child: Text(
              '${outcome.message}\n\nKept as your own exercises:\n'
              '${names.take(25).map((e) => '• ${e.key} (${e.value} sets)').join('\n')}'
              '${names.length > 25 ? '\n…' : ''}',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  Future<void> _toggleReminders(bool enabled) async {
    await _update((s) => s.copyWith(remindersEnabled: enabled));
    if (!enabled) return;
    final granted = await ref
        .read(reminderControllerProvider.notifier)
        .requestPermission();
    if (!granted && mounted) _showBlockedDialog();
  }

  Future<void> _showBlockedDialog() async {
    final open = await confirmAction(
      context,
      title: 'Notifications are blocked',
      message:
          'Reminders cannot be shown until you allow notifications for '
          'Levelex in the system settings.',
      confirmLabel: 'Open settings',
    );
    if (open) {
      await ref.read(reminderControllerProvider.notifier).openSystemSettings();
    }
  }

  Future<void> _clearHistory() async {
    final ok = await confirmAction(
      context,
      title: 'Clear workout history?',
      message:
          'All sessions, daily totals and your streak will be deleted. '
          'Settings are kept. This cannot be undone.',
      confirmLabel: 'Clear history',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(sessionsProvider.notifier).clearHistory();
    await ref.read(ptRecordsProvider.notifier).clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Workout history cleared.')));
  }

  Future<void> _resetApp() async {
    final ok = await confirmAction(
      context,
      title: 'Reset app?',
      message:
          'This deletes your history and settings, cancels reminders and '
          'returns to onboarding. This cannot be undone.',
      confirmLabel: 'Reset everything',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(notificationServiceProvider).cancelReminders();
    await ref.read(sessionsProvider.notifier).clearHistory();
    await ref.read(ptRecordsProvider.notifier).clear();
    await ref.read(gymProfileProvider.notifier).clear();
    await ref.read(challengeRecordsProvider.notifier).clear();
    // "Everything" includes lifts, weigh-ins, progress photos, routines and
    // the challenge players, which used to survive a reset.
    final strength = ref.read(strengthRepositoryProvider);
    for (final photo in strength.photos()) {
      try {
        final file = File(photo.path);
        if (file.existsSync()) await file.delete();
      } catch (_) {
        // A photo that cannot be deleted is left behind; the record goes.
      }
    }
    await strength.clear();
    await ref.read(challengeRepositoryProvider).savePlayers(const []);
    await ref.read(settingsProvider.notifier).reset();
    // The face template lived in the settings store just wiped; without a
    // rebuild the app still believed a face was registered.
    for (final provider in [
      faceTemplateProvider,
      liftLogProvider,
      bodyWeightProvider,
      bodyGoalProvider,
      progressPhotosProvider,
      routinesProvider,
      activeRoutineIdProvider,
      progressionRulesProvider,
      challengeConfigProvider,
    ]) {
      ref.invalidate(provider);
    }
    if (!mounted) return;
    context.go(Routes.onboarding);
  }

  Future<void> _eraseFaceData() async {
    final ok = await confirmAction(
      context,
      title: 'Erase face data?',
      message:
          'Your registered face will be deleted. Because the face protects '
          'your score, all workout history, XP and your streak are erased '
          'too. You will register again before your next set.',
      confirmLabel: 'Erase face and score',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(faceTemplateProvider.notifier).erase();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Face data and score erased.')),
    );
  }

  void _showCameraInstructions() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera setup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final type in ExerciseType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(type.icon, size: 20, color: AppColors.secondary),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${type.label}: ${type.placement}')),
                  ],
                ),
              ),
            for (final (icon, text) in WorkoutIntroScreen.steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: AppColors.secondary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final reminderStatus = ref.watch(reminderControllerProvider);
    final faceTemplate = ref.watch(faceTemplateProvider);
    final version = ref.watch(appVersionProvider);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const SectionHeader('Targets per set'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final type in ExerciseType.values)
                    _TargetRow(
                      type: type,
                      value: settings.targetFor(type),
                      onChanged: (v) => _update((s) => s.withTarget(type, v)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Goals & rest days'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weekly goal',
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              'Active days you aim for each week.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: settings.weeklyGoal > 1
                            ? () => _update(
                                (s) => s.copyWith(weeklyGoal: s.weeklyGoal - 1),
                              )
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '${settings.weeklyGoal}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        onPressed: settings.weeklyGoal < 7
                            ? () => _update(
                                (s) => s.copyWith(weeklyGoal: s.weeklyGoal + 1),
                              )
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const Divider(),
                  Text('Rest days', style: theme.textTheme.titleMedium),
                  Text(
                    'These never break your streak. Reminders still run.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                        FilterChip(
                          label: Text(
                            const [
                              'Mon',
                              'Tue',
                              'Wed',
                              'Thu',
                              'Fri',
                              'Sat',
                              'Sun',
                            ][d - 1],
                          ),
                          selected: settings.restWeekdays.contains(d),
                          onSelected: (on) => _update(
                            (s) => s.copyWith(
                              restWeekdays: on
                                  ? {...s.restWeekdays, d}
                                  : (s.restWeekdays.toSet()..remove(d)),
                            ),
                          ),
                          showCheckmark: false,
                          selectedColor: AppColors.secondary.withValues(
                            alpha: 0.3,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Streak nudge'),
                    subtitle: Text(
                      'One evening reminder at ${settings.nudgeTime.label} '
                      'when nothing is logged yet that day.',
                    ),
                    value: settings.nudgeEnabled,
                    onChanged: (v) =>
                        _update((s) => s.copyWith(nudgeEnabled: v)),
                  ),
                  if (settings.nudgeEnabled)
                    TimeTile(
                      title: 'Nudge time',
                      icon: Icons.nightlight_outlined,
                      value: settings.nudgeTime,
                      onChanged: (t) =>
                          _update((s) => s.copyWith(nudgeTime: t)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Reminders'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(settings.reminderExercise.icon),
                    title: const Text('Reminder exercise'),
                    subtitle: Text(
                      'Daily goal: ${ref.watch(dailyGoalProvider)} '
                      '${settings.reminderExercise.countLabel(2)}',
                    ),
                    // Capped width: at large text sizes the dropdown took
                    // the whole tile and the list failed to lay out.
                    trailing: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                      ),
                      child: DropdownButton<ExerciseType>(
                        value: settings.reminderExercise,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final type in ExerciseType.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(
                                type.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (type) {
                          if (type != null) {
                            _update((s) => s.copyWith(reminderExercise: type));
                          }
                        },
                      ),
                    ),
                  ),
                  const Divider(indent: 20, endIndent: 20),
                  ListTile(
                    leading: const Icon(Icons.repeat),
                    title: const Text('Reminder interval'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: IntervalPicker(
                        value: settings.reminderInterval,
                        onChanged: (d) =>
                            _update((s) => s.copyWith(reminderInterval: d)),
                      ),
                    ),
                  ),
                  TimeTile(
                    title: 'Start time',
                    icon: Icons.wb_sunny_outlined,
                    value: settings.reminderStartTime,
                    onChanged: (t) {
                      if (t >= settings.reminderEndTime) {
                        _showTimeError();
                        return;
                      }
                      _update((s) => s.copyWith(reminderStartTime: t));
                    },
                  ),
                  TimeTile(
                    title: 'End time',
                    icon: Icons.nightlight_outlined,
                    value: settings.reminderEndTime,
                    onChanged: (t) {
                      if (t <= settings.reminderStartTime) {
                        _showTimeError();
                        return;
                      }
                      _update((s) => s.copyWith(reminderEndTime: t));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Notifications'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Enable reminders'),
                    subtitle: Text(
                      settings.remindersEnabled
                          ? '${IntervalPicker.label(settings.reminderInterval)}, '
                                '${settings.reminderStartTime.label} – '
                                '${settings.reminderEndTime.label}'
                          : 'Reminders are off',
                    ),
                    value: settings.remindersEnabled,
                    onChanged: _toggleReminders,
                  ),
                  if (settings.remindersEnabled &&
                      reminderStatus.permissionGranted == false)
                    ListTile(
                      leading: const Icon(
                        Icons.error_outline,
                        color: AppColors.danger,
                      ),
                      title: const Text('Notifications are blocked'),
                      subtitle: const Text('Tap to open system settings'),
                      onTap: () => ref
                          .read(reminderControllerProvider.notifier)
                          .openSystemSettings(),
                    ),
                  if (isAndroid &&
                      settings.remindersEnabled &&
                      !reminderStatus.exactAlarmsAllowed)
                    ListTile(
                      leading: const Icon(
                        Icons.schedule,
                        color: AppColors.warning,
                      ),
                      title: const Text('Allow exact timing'),
                      subtitle: const Text(
                        'Without it, reminders may arrive a few minutes late.',
                      ),
                      onTap: () => ref
                          .read(reminderControllerProvider.notifier)
                          .requestExactAlarms(),
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.volume_up_outlined),
                    title: const Text('Sound'),
                    subtitle: const Text(
                      'Reminder sound, voice coach and set-complete chime',
                    ),
                    value: settings.soundEnabled,
                    onChanged: (v) =>
                        _update((s) => s.copyWith(soundEnabled: v)),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.record_voice_over_outlined),
                    title: const Text('Voice coach'),
                    subtitle: const Text(
                      'Spoken ready, countdown, rep counts and form cues',
                    ),
                    value: settings.voiceEnabled && settings.soundEnabled,
                    onChanged: settings.soundEnabled
                        ? (v) => _update((s) => s.copyWith(voiceEnabled: v))
                        : null,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.vibration),
                    title: const Text('Vibration'),
                    subtitle: const Text('Haptic tick on every counted rep'),
                    value: settings.vibrationEnabled,
                    onChanged: (v) =>
                        _update((s) => s.copyWith(vibrationEnabled: v)),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.flag_outlined),
                    title: const Text('Track skipped sessions'),
                    subtitle: const Text(
                      'Count reminders you miss. Never retroactive.',
                    ),
                    value: settings.trackSkippedSessions,
                    onChanged: (v) =>
                        _update((s) => s.copyWith(trackSkippedSessions: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Camera'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.videocam_outlined),
                    title: const Text('Camera instructions'),
                    subtitle: const Text('How to position your phone'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showCameraInstructions,
                  ),
                  ListTile(
                    leading: const Icon(Icons.cameraswitch_outlined),
                    title: const Text('Camera'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SegmentedButton<CameraFacing>(
                        segments: [
                          for (final f in CameraFacing.values)
                            ButtonSegment(value: f, label: Text(f.label)),
                        ],
                        selected: {settings.cameraFacing},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) => _update(
                          (s) => s.copyWith(cameraFacing: selection.first),
                        ),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.troubleshoot_outlined),
                    title: const Text('Show tracking details'),
                    subtitle: const Text(
                      'Live numbers on the workout screen (for troubleshooting)',
                    ),
                    value: settings.showTrackingDetails,
                    onChanged: (v) =>
                        _update((s) => s.copyWith(showTrackingDetails: v)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Coaching strictness'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SegmentedButton<FormSensitivity>(
                        segments: [
                          for (final s in FormSensitivity.values)
                            ButtonSegment(value: s, label: Text(s.label)),
                        ],
                        selected: {settings.formSensitivity},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) => _update(
                          (s) => s.copyWith(formSensitivity: selection.first),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Relaxed counts shallower reps and only flags clearly '
                      'broken form. Strict demands full depth and a straight '
                      'body.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Face verification'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      faceTemplate == null
                          ? Icons.face_retouching_natural
                          : Icons.verified_user_outlined,
                      color: faceTemplate == null
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                    title: Text(
                      faceTemplate == null
                          ? 'No face registered'
                          : 'Face registered',
                    ),
                    subtitle: Text(
                      faceTemplate == null
                          ? 'Required before your first set'
                          : 'Since ${MaterialLocalizations.of(context).formatMediumDate(faceTemplate.registeredAt)}. '
                                'Only you can score workouts.',
                    ),
                    trailing: faceTemplate == null
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: faceTemplate == null
                        ? () => context.push(Routes.faceRegistration)
                        : null,
                  ),
                  if (faceTemplate != null)
                    ListTile(
                      leading: const Icon(
                        Icons.delete_forever_outlined,
                        color: AppColors.danger,
                      ),
                      title: const Text(
                        'Erase face data',
                        style: TextStyle(color: AppColors.danger),
                      ),
                      subtitle: const Text('Also erases your score and streak'),
                      onTap: _eraseFaceData,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('3D guide'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<GuideQuality>(
                    segments: [
                      for (final q in GuideQuality.values)
                        ButtonSegment(value: q, label: Text(q.label)),
                    ],
                    selected: {settings.guideQuality},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        _update((x) => x.copyWith(guideQuality: s.first)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    settings.guideQuality.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Lifting'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weight unit',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Loads are stored in kg and shown in this unit.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<WeightUnit>(
                    segments: [
                      for (final u in WeightUnit.values)
                        ButtonSegment(value: u, label: Text(u.label)),
                    ],
                    selected: {settings.weightUnit},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        _update((x) => x.copyWith(weightUnit: s.first)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Data & backup'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.ios_share_rounded),
                    title: const Text('Export backup'),
                    subtitle: const Text(
                      'One JSON file with sets, MY PT sessions, lifts, '
                      'weigh-ins, routines and challenges. No face data.',
                    ),
                    onTap: _exportBackup,
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('Import backup'),
                    subtitle: const Text(
                      'Merges a Levelex backup into this phone.',
                    ),
                    onTap: _importBackup,
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_rounded),
                    title: const Text('Import from another app'),
                    subtitle: const Text(
                      'CSV from FitNotes, Strong or Hevy, or an Apple Health '
                      'export for body weight.',
                    ),
                    onTap: _importOtherApp,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Data'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Clear workout history'),
                    onTap: _clearHistory,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.restart_alt,
                      color: AppColors.danger,
                    ),
                    title: const Text(
                      'Reset app',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    onTap: _resetApp,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('About'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('App version'),
                    trailing: Text(
                      version.when(
                        data: (v) => v,
                        loading: () => '…',
                        error: (_, _) => 'unknown',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.privacy),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Open-source licenses'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: AppStrings.appName,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTimeError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('End time must be after start time.')),
    );
  }
}

/// Compact −/+ row for one exercise's target.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.type,
    required this.value,
    required this.onChanged,
  });

  final ExerciseType type;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = type.isTimed ? 5 : 1;
    final min = type.isTimed ? 10 : Defaults.minPushUpsPerSession;
    final max = type.isTimed ? 300 : Defaults.maxPushUpsPerSession;
    return ListTile(
      leading: Icon(type.icon),
      title: Text(type.label),
      subtitle: Text(type.isTimed ? 'seconds per set' : 'reps per set'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease',
            onPressed: value > min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase',
            onPressed: value < max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
