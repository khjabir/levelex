import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/app_card.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    (Icons.videocam_outlined, 'Camera', AppStrings.privacyStatement),
    (
      Icons.memory,
      'Pose data',
      'Body landmarks are computed by Google ML Kit on your device and used '
          'only to count reps and give form feedback. They are discarded '
          'immediately and never sent anywhere.',
    ),
    (
      Icons.face_retouching_natural,
      'Face verification',
      'To stop others from scoring in your name, your face is registered '
          'once. It is stored only as a short numeric signature (an '
          'embedding) computed on your device; no photo is kept and nothing '
          'is uploaded. You can erase it in Settings at any time, which also '
          'erases your score so identities cannot be swapped.',
    ),
    (
      Icons.phone_android,
      'Your data stays on your phone',
      'Workout history, streaks and settings are stored locally. There is no '
          'account, no cloud sync and no analytics.',
    ),
    (
      Icons.notifications_none,
      'Notifications',
      'Reminders are scheduled with the operating system and contain no '
          'personal data.',
    ),
    (
      Icons.wifi_off,
      'Works offline',
      'Every feature works without an internet connection.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            for (final (icon, title, body) in _sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: AppColors.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                              body,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
