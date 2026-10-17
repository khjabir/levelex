import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../features/notifications/reminder_controller.dart';
import 'providers.dart';
import 'routes.dart';
import 'theme.dart';

/// Global messenger so startup code can show a snackbar from outside a page.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Root widget: theme, router and app-level lifecycle housekeeping
/// (recovering interrupted sets, evaluating skipped reminders, keeping the
/// OS schedule fresh).
class LevelexApp extends ConsumerStatefulWidget {
  const LevelexApp({super.key});

  @override
  ConsumerState<LevelexApp> createState() => _LevelexAppState();
}

class _LevelexAppState extends ConsumerState<LevelexApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStartup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onStartup() async {
    final sessions = ref.read(sessionsProvider.notifier);
    try {
      final recovered = await sessions.recoverInterrupted();
      if (recovered != null) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              'Recovered ${recovered.completedReps} reps from an '
              'interrupted set.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Draft recovery failed: $e');
    }
    await _housekeeping(reschedule: true);
  }

  Future<void> _housekeeping({required bool reschedule}) async {
    ref.read(clockProvider.notifier).refresh();
    final settings = ref.read(settingsProvider);
    if (!settings.onboardingCompleted) return;
    try {
      await ref.read(sessionsProvider.notifier).evaluateSkipped();
    } catch (e) {
      debugPrint('Skipped-session evaluation failed: $e');
    }
    try {
      final reminders = ref.read(reminderControllerProvider.notifier);
      if (reschedule) {
        await reminders.reschedule();
      } else {
        await reminders.refreshStatus();
      }
    } catch (e) {
      debugPrint('Reminder refresh failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh "today"/"next reminder", record anything missed while away,
      // and top up the schedule (matters for dense schedules on iOS).
      _housekeeping(reschedule: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp.router(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        routerConfig: router,
        scaffoldMessengerKey: scaffoldMessengerKey,
      ),
    );
  }
}
