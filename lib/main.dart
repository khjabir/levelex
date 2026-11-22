import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/routes.dart';
import 'features/workout/workout_launch.dart';
import 'features/challenge/challenge_providers.dart';
import 'features/pt/pt_providers.dart';
import 'features/strength/strength_providers.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never crash on an unhandled async error (e.g. a camera hiccup); log it.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final storage = await StorageService.initialize();
  final notifications = NotificationService();

  late final ProviderContainer container;
  final launchedFromReminder = await notifications.initialize(
    onTap: (_) => _openWorkoutFromReminder(container),
  );

  container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(storage.settings),
      sessionRepositoryProvider.overrideWithValue(storage.sessions),
      ptRepositoryProvider.overrideWithValue(storage.pt),
      challengeRepositoryProvider.overrideWithValue(storage.challenges),
      strengthRepositoryProvider.overrideWithValue(storage.strength),
      notificationServiceProvider.overrideWithValue(notifications),
      initialLocationProvider.overrideWithValue(Routes.home),
    ],
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const LevelexApp()),
  );
  if (launchedFromReminder && storage.settings.settings.onboardingCompleted) {
    // Open the reminder's set on top of home, so back returns to the app
    // instead of closing it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openWorkoutFromReminder(container),
    );
  }
}

/// Routes a reminder tap to the reminder's exercise and target, unless a
/// workout, MY PT session or challenge is in progress (replacing the screen
/// would end it unsaved; the tap still brings the app to the front).
void _openWorkoutFromReminder(ProviderContainer container) {
  try {
    final router = container.read(routerProvider);
    final current = router.state.matchedLocation;
    if (current.startsWith(Routes.workout) ||
        current.startsWith(Routes.ptSession) ||
        current.startsWith(Routes.challengePlay) ||
        current.startsWith(Routes.onboarding)) {
      return;
    }
    final settings = container.read(settingsProvider);
    final exercise = settings.reminderExercise;
    container
        .read(workoutLaunchProvider.notifier)
        .set(
          WorkoutLaunch(
            exercise: exercise,
            target: settings.targetFor(exercise),
          ),
        );
    if (current != Routes.home) router.go(Routes.home);
    router.push(Routes.workout);
  } catch (e) {
    debugPrint('Could not open workout from reminder: $e');
  }
}
