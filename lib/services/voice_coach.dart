import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Everything the coach can say. Pure data so the rules are testable.
enum VoiceCue {
  lookAtCamera,
  verified,
  getInPosition,
  ready,
  three,
  two,
  one,
  go,
  rep,
  secondsHeld,
  complete,
  setEnded,
  paused,
  notRecognised,
  hipsLower,
  hipsHigher,
  moveBack,
  bodyNotVisible,
  cameraSwitched,

  /// Exercise-specific correction; the phrase comes from `CoachingLibrary`.
  coach,

  /// Free-form trainer line (MY PT): spoken verbatim, never rate-limited.
  trainer;

  /// How this cue competes with speech already in progress.
  bool get interrupts => switch (this) {
    VoiceCue.three ||
    VoiceCue.two ||
    VoiceCue.one ||
    VoiceCue.go ||
    VoiceCue.rep ||
    VoiceCue.secondsHeld ||
    VoiceCue.complete ||
    VoiceCue.setEnded ||
    VoiceCue.trainer ||
    VoiceCue.paused => true,
    _ => false,
  };

  /// Minimum spacing before the same cue is repeated.
  Duration get repeatInterval => switch (this) {
    VoiceCue.rep ||
    VoiceCue.secondsHeld ||
    VoiceCue.three ||
    VoiceCue.two ||
    VoiceCue.trainer ||
    VoiceCue.one => Duration.zero,
    VoiceCue.hipsLower ||
    VoiceCue.hipsHigher ||
    VoiceCue.moveBack ||
    VoiceCue.bodyNotVisible => const Duration(seconds: 6),
    VoiceCue.getInPosition ||
    VoiceCue.lookAtCamera => const Duration(seconds: 8),
    VoiceCue.coach => const Duration(seconds: 3),
    _ => const Duration(seconds: 2),
  };
}

/// Decides what to say and when, without touching any audio API. The
/// [VoiceCoach] wraps it with text-to-speech; tests exercise it directly.
class VoiceScript {
  VoiceScript({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<VoiceCue, DateTime> _lastSpoken = {};

  /// Text for [cue]; [count] is the rep number or the set total and [label]
  /// the unit ("push-ups", "seconds") or an exercise-specific hint.
  static String text(
    VoiceCue cue, {
    int count = 0,
    String? label,
  }) => switch (cue) {
    VoiceCue.lookAtCamera => 'Look at the camera',
    VoiceCue.verified => 'Verified. ${label ?? 'Get into position'}.',
    VoiceCue.getInPosition => label ?? 'Get into position',
    VoiceCue.ready => 'Ready',
    VoiceCue.three => 'Three',
    VoiceCue.two => 'Two',
    VoiceCue.one => 'One',
    VoiceCue.go => 'Go!',
    VoiceCue.rep => '$count',
    VoiceCue.secondsHeld => '$count seconds',
    VoiceCue.complete =>
      'Set complete. $count ${label ?? (count == 1 ? 'push-up' : 'push-ups')}. '
          'Well done!',
    VoiceCue.setEnded =>
      'Set ended. $count ${label ?? (count == 1 ? 'push-up' : 'push-ups')}.',
    VoiceCue.paused => 'Paused',
    VoiceCue.notRecognised => "I can't confirm it's you. Look at the camera.",
    VoiceCue.hipsLower => 'Keep your hips lower',
    VoiceCue.hipsHigher => 'Keep your hips higher',
    VoiceCue.moveBack => 'Move farther from the camera',
    VoiceCue.bodyNotVisible => 'Make sure your whole body is visible',
    VoiceCue.cameraSwitched => 'Camera switched',
    VoiceCue.coach => label ?? 'Check your form',
    VoiceCue.trainer => label ?? '',
  };

  /// Returns the phrase to speak now, or null when [cue] was spoken too
  /// recently. Records the time when it returns a phrase.
  String? phraseFor(VoiceCue cue, {int count = 0, String? label}) {
    final now = _clock();
    final last = _lastSpoken[cue];
    if (last != null && now.difference(last) < cue.repeatInterval) return null;
    _lastSpoken[cue] = now;
    return text(cue, count: count, label: label);
  }

  void reset() => _lastSpoken.clear();
}

/// Speaks workout cues through the platform text-to-speech engine.
///
/// Best-effort: a missing engine or audio failure never affects counting.
class VoiceCoach {
  VoiceCoach({FlutterTts? tts, VoiceScript? script})
    : _tts = tts ?? FlutterTts(),
      _script = script ?? VoiceScript();

  final FlutterTts _tts;
  final VoiceScript _script;
  bool _initialized = false;
  bool _available = true;
  bool enabled = true;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ], IosTextToSpeechAudioMode.voicePrompt);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);
    } catch (e) {
      debugPrint('Voice coach unavailable: $e');
      _available = false;
    }
  }

  /// Speaks [cue] if enabled and not rate-limited.
  Future<void> say(VoiceCue cue, {int count = 0, String? label}) async {
    if (!enabled || !_available) return;
    final phrase = _script.phraseFor(cue, count: count, label: label);
    if (phrase == null) return;
    try {
      if (!_initialized) await initialize();
      if (cue.interrupts) await _tts.stop();
      await _tts.speak(phrase);
    } catch (e) {
      debugPrint('Voice coach speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop.
    }
  }

  void resetScript() => _script.reset();

  Future<void> dispose() => stop();
}
