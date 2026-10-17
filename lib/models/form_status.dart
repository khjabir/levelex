/// User-facing feedback about posture and movement.
///
/// Posture statuses describe the current frame; the two *events*
/// ([goDeeper], [slowDown]) describe the rep that just ended. Exercise-specific
/// wording lives in `CoachingLibrary`; the strings here are generic fallbacks.
enum FormStatus {
  goodForm,
  hipsTooHigh,
  hipsTooLow,
  moveBack,
  armNotVisible,
  bodyNotVisible,
  lowConfidence,

  /// Body is visible but not in the start posture (e.g. standing before a
  /// push-up).
  notInPosition,

  /// The torso leans far forward (squats, lunges).
  torsoLeaning,

  /// Jumping jacks: the arms did not reach overhead.
  armsNotOverhead,

  /// Event: a rep was started but did not reach the work position.
  goDeeper,

  /// Event: the rep bounced back before the minimum work duration.
  slowDown;

  /// Friendly generic text.
  String get message => switch (this) {
    FormStatus.goodForm => 'Good form',
    FormStatus.hipsTooHigh => 'Keep your hips lower',
    FormStatus.hipsTooLow => 'Keep your hips higher',
    FormStatus.moveBack => 'Move farther from the camera',
    FormStatus.armNotVisible => "Can't see your arm clearly",
    FormStatus.bodyNotVisible => 'Make sure your whole body is visible',
    FormStatus.lowConfidence => 'Hold still — tracking is unstable',
    FormStatus.notInPosition => 'Get into the start position',
    FormStatus.torsoLeaning => 'Keep your chest up',
    FormStatus.armsNotOverhead => 'Reach all the way overhead',
    FormStatus.goDeeper => 'Go deeper: that rep was too shallow',
    FormStatus.slowDown => 'Slow down and control the movement',
  };

  /// Short label for compact HUD display.
  String get shortLabel => switch (this) {
    FormStatus.goodForm => 'GOOD',
    FormStatus.hipsTooHigh => 'HIPS HIGH',
    FormStatus.hipsTooLow => 'HIPS LOW',
    FormStatus.moveBack => 'MOVE BACK',
    FormStatus.armNotVisible => 'ARM?',
    FormStatus.bodyNotVisible => 'BODY?',
    FormStatus.lowConfidence => 'UNSTABLE',
    FormStatus.notInPosition => 'NOT IN POSITION',
    FormStatus.torsoLeaning => 'CHEST UP',
    FormStatus.armsNotOverhead => 'ARMS UP',
    FormStatus.goDeeper => 'DEEPER',
    FormStatus.slowDown => 'SLOWER',
  };

  /// True when the body is tracked well enough that the user is "in position".
  bool get isTracking => switch (this) {
    FormStatus.goodForm ||
    FormStatus.hipsTooHigh ||
    FormStatus.hipsTooLow ||
    FormStatus.torsoLeaning ||
    FormStatus.armsNotOverhead => true,
    _ => false,
  };

  /// A posture mistake the coach should correct (tracked, but not good).
  bool get isPostureMistake => isTracking && this != FormStatus.goodForm;

  /// A one-off movement mistake reported when a rep ends.
  bool get isEvent =>
      this == FormStatus.goDeeper || this == FormStatus.slowDown;

  /// Anything the coach counts as a mistake.
  bool get isMistake => isPostureMistake || isEvent;

  bool get isGood => this == FormStatus.goodForm;
}
