import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/challenge/screens/challenge_play_screen.dart';
import '../features/challenge/screens/challenge_setup_screen.dart';
import '../features/face/face_registration_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/onboarding_setup_screen.dart';
import '../features/pt/screens/equipment_screen.dart';
import '../features/pt/screens/plan_preview_screen.dart';
import '../features/pt/screens/pt_home_screen.dart';
import '../features/pt/screens/pt_session_screen.dart';
import '../features/settings/privacy_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/strength/models/routine.dart';
import '../features/strength/screens/body_screen.dart';
import '../features/strength/screens/library_screen.dart';
import '../features/strength/screens/movement_detail_screen.dart';
import '../features/strength/screens/progress_screen.dart';
import '../features/strength/screens/routine_edit_screen.dart';
import '../features/strength/screens/routines_screen.dart';
import '../features/workout/workout_camera_screen.dart';
import '../features/workout/workout_complete_screen.dart';
import '../features/workout/workout_controller.dart' show WorkoutOutcome;
import '../features/workout/workout_intro_screen.dart';
import 'providers.dart';

/// Route paths used across the app.
abstract final class Routes {
  static const home = '/';
  static const onboarding = '/onboarding';
  static const onboardingSetup = '/onboarding/setup';
  static const workout = '/workout';
  static const workoutCamera = '/workout/camera';
  static const workoutComplete = '/workout/complete';
  static const history = '/history';
  static const settings = '/settings';
  static const privacy = '/settings/privacy';
  static const faceRegistration = '/face/register';
  static const pt = '/pt';
  static const ptEquipment = '/pt/equipment';
  static const ptPlan = '/pt/plan';
  static const ptSession = '/pt/session';
  static const challenge = '/challenge';
  static const challengePlay = '/challenge/play';
  static const library = '/library';
  static const libraryPick = '/library/pick';
  static String movement(String id) =>
      '/library/movement/${Uri.encodeComponent(id)}';
  static const body = '/body';
  static const progress = '/progress';
  static const routines = '/routines';
  static const routineEdit = '/routines/edit';
}

/// Where the app opens. Overridden at startup when a reminder launched it.
final initialLocationProvider = Provider<String>((ref) => Routes.home);

/// Fade + slight rise, the app's standard page transition.
CustomTransitionPage<void> _page(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: ref.read(initialLocationProvider),
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final onboarded = ref.read(settingsProvider).onboardingCompleted;
      final location = state.matchedLocation;
      final inOnboarding = location.startsWith(Routes.onboarding);
      if (!onboarded && !inOnboarding) return Routes.onboarding;
      if (onboarded && inOnboarding) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.home,
        pageBuilder: (context, state) => _page(state, const HomeScreen()),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (context, state) => _page(state, const OnboardingScreen()),
        routes: [
          GoRoute(
            path: 'setup',
            pageBuilder: (context, state) =>
                _page(state, const OnboardingSetupScreen()),
          ),
        ],
      ),
      GoRoute(
        path: Routes.workout,
        pageBuilder: (context, state) =>
            _page(state, const WorkoutIntroScreen()),
        routes: [
          GoRoute(
            path: 'camera',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              child: const WorkoutCameraScreen(),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: 'complete',
            pageBuilder: (context, state) => _page(
              state,
              WorkoutCompleteScreen(outcome: state.extra as WorkoutOutcome?),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.history,
        pageBuilder: (context, state) => _page(state, const HistoryScreen()),
      ),
      GoRoute(
        path: Routes.challenge,
        pageBuilder: (context, state) =>
            _page(state, const ChallengeSetupScreen()),
        routes: [
          GoRoute(
            path: 'play',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              child: const ChallengePlayScreen(),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.pt,
        pageBuilder: (context, state) => _page(state, const PtHomeScreen()),
        routes: [
          GoRoute(
            path: 'equipment',
            pageBuilder: (context, state) =>
                _page(state, const EquipmentScreen()),
          ),
          GoRoute(
            path: 'plan',
            pageBuilder: (context, state) =>
                _page(state, const PlanPreviewScreen()),
          ),
          GoRoute(
            path: 'session',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              child: const PtSessionScreen(),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.library,
        pageBuilder: (context, state) => _page(state, const LibraryScreen()),
        routes: [
          GoRoute(
            path: 'pick',
            pageBuilder: (context, state) =>
                _page(state, const LibraryScreen(pickMode: true)),
          ),
          GoRoute(
            path: 'movement/:id',
            pageBuilder: (context, state) => _page(
              state,
              MovementDetailScreen(
                movementId: Uri.decodeComponent(
                  state.pathParameters['id'] ?? '',
                ),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.body,
        pageBuilder: (context, state) => _page(state, const BodyScreen()),
      ),
      GoRoute(
        path: Routes.progress,
        pageBuilder: (context, state) => _page(state, const ProgressScreen()),
      ),
      GoRoute(
        path: Routes.routines,
        pageBuilder: (context, state) => _page(state, const RoutinesScreen()),
        routes: [
          GoRoute(
            path: 'edit',
            pageBuilder: (context, state) => _page(
              state,
              RoutineEditScreen(routine: state.extra as Routine?),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.faceRegistration,
        pageBuilder: (context, state) =>
            _page(state, const FaceRegistrationScreen()),
      ),
      GoRoute(
        path: Routes.settings,
        pageBuilder: (context, state) => _page(state, const SettingsScreen()),
        routes: [
          GoRoute(
            path: 'privacy',
            pageBuilder: (context, state) =>
                _page(state, const PrivacyScreen()),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
