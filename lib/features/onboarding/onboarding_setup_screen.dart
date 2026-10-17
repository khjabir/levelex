import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_settings.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../notifications/reminder_controller.dart';
import '../settings/widgets/settings_widgets.dart';

/// Collects the initial reminder/workout preferences after onboarding.
class OnboardingSetupScreen extends ConsumerStatefulWidget {
  const OnboardingSetupScreen({super.key});

  @override
  ConsumerState<OnboardingSetupScreen> createState() =>
      _OnboardingSetupScreenState();
}

class _OnboardingSetupScreenState extends ConsumerState<OnboardingSetupScreen> {
  late UserSettings _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(settingsProvider);
  }

  void _update(UserSettings Function(UserSettings) change) =>
      setState(() => _draft = change(_draft));

  Future<void> _finish() async {
    if (_draft.reminderEndTime <= _draft.reminderStartTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (_) =>
              _draft.copyWith(onboardingCompleted: true, setupCompletedAt: now),
        );

    final reminders = ref.read(reminderControllerProvider.notifier);
    var granted = true;
    if (_draft.remindersEnabled) {
      granted = await reminders.requestPermission();
    } else {
      await reminders.reschedule();
    }
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked. Enable them in system settings to '
            'get reminders.',
          ),
        ),
      );
    }
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set your targets')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              AppStrings.onboardingSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Push-ups per set'),
            AppCard(
              child: RepStepper(
                value: _draft.pushUpsPerSession,
                onChanged: (v) =>
                    _update((s) => s.copyWith(pushUpsPerSession: v)),
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Remind me'),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IntervalPicker(
                    value: _draft.reminderInterval,
                    onChanged: (d) =>
                        _update((s) => s.copyWith(reminderInterval: d)),
                  ),
                  const SizedBox(height: 8),
                  TimeTile(
                    title: 'Start time',
                    icon: Icons.wb_sunny_outlined,
                    value: _draft.reminderStartTime,
                    onChanged: (t) =>
                        _update((s) => s.copyWith(reminderStartTime: t)),
                  ),
                  TimeTile(
                    title: 'End time',
                    icon: Icons.nightlight_outlined,
                    value: _draft.reminderEndTime,
                    onChanged: (t) =>
                        _update((s) => s.copyWith(reminderEndTime: t)),
                  ),
                  SwitchListTile(
                    title: const Text('Enable reminders'),
                    subtitle: Text(
                      _draft.remindersEnabled
                          ? _scheduleSummary(_draft)
                          : 'You can turn them on later in Settings',
                    ),
                    value: _draft.remindersEnabled,
                    onChanged: (v) =>
                        _update((s) => s.copyWith(remindersEnabled: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'START LEVELLING UP',
              icon: Icons.bolt_rounded,
              loading: _saving,
              onPressed: _saving ? null : _finish,
            ),
          ],
        ),
      ),
    );
  }

  static String _scheduleSummary(UserSettings s) {
    final start = s.reminderStartTime;
    final end = s.reminderEndTime;
    return '${IntervalPicker.label(s.reminderInterval)}, '
        '${start.label} – ${end.label}';
  }
}
