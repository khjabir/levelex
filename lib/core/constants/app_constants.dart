/// Application-wide constants and tunable thresholds.
///
/// Every number that influences push-up detection lives here so it can be
/// adjusted in one place (and overridden in tests).
library;

/// Brand and copy constants.
abstract final class AppStrings {
  static const appName = 'Levelex';
  static const tagline = 'Level up, one rep at a time.';
  static const onboardingSubtitle =
      'Short sets through the day, counted and coached by your camera.';
  static const setEnforced = 'Set complete. Level up. ⚡';
  static const privacyStatement =
      'Levelex processes camera frames on your device to track your body, '
      'count reps and correct your form. Camera footage is never uploaded '
      'or stored.';
  static const cameraPermissionRationale =
      'Levelex uses the camera to track your body position, count reps and '
      'coach your form. Frames are analysed on-device and never leave your '
      'phone.';
}

/// Notification channel configuration (Android) and shared identifiers.
abstract final class NotificationConstants {
  static const channelId = 'levelex_reminders';
  static const channelName = 'Workout reminders';
  static const channelDescription = 'Reminders to do a quick set.';
  static const title = '⚡ Levelex';
  static const payloadWorkout = 'open_workout';

  /// Base id for reminder notifications. Reminder ids are
  /// `reminderIdBase + index` so they never collide with other notifications.
  static const reminderIdBase = 1000;

  /// Evening "streak at risk" nudges (today / tomorrow).
  static const nudgeIdToday = 900;
  static const nudgeIdTomorrow = 901;

  /// Maximum number of pending reminders we keep scheduled at once. iOS keeps
  /// at most 64 pending local notifications per app; we stay comfortably below.
  static const maxPendingReminders = 60;
}

/// Default values used when the user has not configured anything yet.
abstract final class Defaults {
  static const pushUpsPerSession = 10;
  static const reminderIntervalMinutes = 60;
  static const reminderStartHour = 9;
  static const reminderEndHour = 18;
  static const minPushUpsPerSession = 1;
  static const maxPushUpsPerSession = 100;
  static const minIntervalMinutes = 15;
  static const maxIntervalMinutes = 12 * 60;
}

/// How strict the body-alignment ("form") check is.
enum FormSensitivity {
  /// Only flags clearly broken form.
  low,

  /// Balanced default.
  medium,

  /// Flags smaller deviations.
  high;

  String get label => switch (this) {
    FormSensitivity.low => 'Relaxed',
    FormSensitivity.medium => 'Balanced',
    FormSensitivity.high => 'Strict',
  };
}

/// Tunable thresholds for the push-up state machine and form feedback.
///
/// Angles are in degrees and computed in 3D (ML Kit depth included), so they
/// are largely independent of where the camera stands. Confidence values are
/// ML Kit likelihoods in `[0, 1]`. Lengths are fractions of the upper-arm
/// length so they scale with distance to the camera.
class PushUpThresholds {
  const PushUpThresholds({
    this.upAngle = 145,
    this.downAngle = 110,
    this.adaptiveThresholds = true,
    this.adaptiveMinRange = 40,
    this.adaptiveMargin = 0.3,
    this.minLandmarkConfidence = 0.4,
    this.presenceConfidence = 0.3,
    this.minFramesForTransition = 2,
    this.repCooldown = const Duration(milliseconds: 400),
    this.minRepDuration = const Duration(milliseconds: 200),
    this.straightBodyMinAngle = 155,
    this.hipDeviationRatio = 0.10,
    this.edgeMargin = 0.02,
    this.maxBodyTiltDegrees = 65,
    this.minShoulderTravelRatio = 0.12,
    this.maxWristTravelRatio = 1.0,
    this.maxHandsRaisedRatio = -0.45,
    this.shallowFraction = 0.4,
  });

  /// Builds thresholds for a coaching strictness. Relaxed counts shallower,
  /// sloppier reps and only flags clearly broken form; strict demands full
  /// depth and a straight body.
  factory PushUpThresholds.forSensitivity(FormSensitivity sensitivity) {
    return switch (sensitivity) {
      FormSensitivity.low => const PushUpThresholds(
        downAngle: 120,
        adaptiveMargin: 0.35,
        minShoulderTravelRatio: 0.08,
        straightBodyMinAngle: 145,
        hipDeviationRatio: 0.14,
        shallowFraction: 0.5,
      ),
      FormSensitivity.medium => const PushUpThresholds(),
      FormSensitivity.high => const PushUpThresholds(
        downAngle: 100,
        adaptiveMargin: 0.25,
        minShoulderTravelRatio: 0.2,
        straightBodyMinAngle: 162,
        hipDeviationRatio: 0.08,
        shallowFraction: 0.3,
      ),
    };
  }

  /// Default elbow angle at (or above) which the arms count as extended.
  final double upAngle;

  /// Default elbow angle at (or below) which the arms count as bent.
  final double downAngle;

  /// When true, the UP/DOWN angles adapt to the user's observed range of
  /// motion (useful for partial lock-out or unusual camera angles).
  final bool adaptiveThresholds;

  /// Observed range (max − min elbow angle) needed before adapting.
  final double adaptiveMinRange;

  /// Fraction of the observed range inside each extreme at which the adaptive
  /// UP/DOWN thresholds are placed.
  final double adaptiveMargin;

  /// Minimum likelihood for a landmark to be trusted when counting reps.
  final double minLandmarkConfidence;

  /// Minimum likelihood for a landmark to be considered "present" at all
  /// (used for visibility feedback rather than counting).
  final double presenceConfidence;

  /// Number of consecutive frames that must agree before a state changes.
  /// Provides hysteresis against single noisy frames.
  final int minFramesForTransition;

  /// Minimum time between two counted reps.
  final Duration repCooldown;

  /// Minimum time between entering DOWN and returning to UP for the movement
  /// to count as a real push-up.
  final Duration minRepDuration;

  /// Shoulder→hip→ankle angle at or above which the body counts as straight.
  final double straightBodyMinAngle;

  /// Hip deviation from the shoulder–ankle line, as a fraction of the
  /// shoulder–ankle distance, beyond which hips are flagged high/low.
  final double hipDeviationRatio;

  /// Normalised margin from the frame edge; landmarks inside the margin mean
  /// the body is partially out of frame.
  final double edgeMargin;

  /// Maximum angle between the body line and the horizontal plane for the
  /// body to count as being in push-up position. Only applied when the real
  /// gravity direction is known (motion sensor); standing is ~90°.
  final double maxBodyTiltDegrees;

  /// How far the shoulders must travel (3D) between UP and DOWN, as a
  /// fraction of the upper-arm length, for the DOWN phase to be real.
  final double minShoulderTravelRatio;

  /// Hands must stay planted: wrist travel during the descent may be at most
  /// this fraction of the shoulder travel.
  final double maxWristTravelRatio;

  /// Wrists higher than the shoulders (along "up") by more than this fraction
  /// of the upper arm mean the hands are raised, not on the floor.
  final double maxHandsRaisedRatio;

  /// How far (0..1) towards the work position an aborted rep must get before
  /// the coach calls it "too shallow".
  final double shallowFraction;
}

/// Frame-processing limits for the camera pipeline.
abstract final class CameraConstants {
  /// Minimum interval between two pose inferences (~12 FPS).
  static const minFrameInterval = Duration(milliseconds: 80);

  /// Seconds of stable, visible pose required to finish calibration.
  static const calibrationDuration = Duration(milliseconds: 1500);

  /// Countdown length before counting starts.
  static const countdownSeconds = 3;

  /// Minimum spacing between two face-verification samples.
  static const faceCheckInterval = Duration(milliseconds: 700);
}

/// Face registration / verification tuning.
abstract final class FaceConstants {
  /// Bundled face-embedding model (MobileFaceNet, Apache-2.0).
  static const modelAsset = 'assets/models/mobilefacenet.tflite';

  /// Embeddings averaged during registration.
  static const registrationSamples = 5;

  /// Consecutive matching samples needed to start a set.
  static const requiredMatches = 2;

  /// Consecutive confident mismatches that end verification.
  static const mismatchesToReject = 3;

  /// Consecutive confident mismatches, during a set, that pause it. Kept
  /// high: faces are often in profile or badly lit mid-push-up.
  static const mismatchesToPause = 6;

  /// Mid-set spot checks only use clearly visible, frontal faces.
  static const spotCheckMinFaceWidthRatio = 0.16;
  static const spotCheckMaxHeadYaw = 20.0;

  /// Give up verifying after this long without a match.
  static const verificationTimeout = Duration(seconds: 25);

  /// Minimum face width as a fraction of the frame width for a usable sample.
  static const minFaceWidthRatio = 0.12;

  /// Maximum absolute head yaw (degrees) for a usable sample.
  static const maxHeadYaw = 30.0;
}
