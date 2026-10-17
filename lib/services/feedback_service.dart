import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays the success chime and haptic feedback, honouring user settings.
///
/// Every call is best-effort: audio failures are logged, never thrown.
class FeedbackService {
  FeedbackService({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  static const _successAsset = 'sounds/success.wav';

  final AudioPlayer _player;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    try {
      // Short UI sound: don't take audio focus from music apps and respect
      // the iOS silent switch.
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(AssetSource(_successAsset));
    } catch (e) {
      debugPrint('Audio setup failed (sound disabled): $e');
    }
  }

  /// Light tick when a rep is counted.
  Future<void> repCounted({required bool vibration}) async {
    if (!vibration) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Haptics are optional.
    }
  }

  /// Celebration when the set is complete.
  Future<void> setCompleted({
    required bool sound,
    required bool vibration,
  }) async {
    if (vibration) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {
        // Haptics are optional.
      }
    }
    if (sound) {
      await _ensureConfigured();
      try {
        await _player.stop();
        await _player.play(AssetSource(_successAsset));
      } catch (e) {
        debugPrint('Success sound failed: $e');
      }
    }
  }

  Future<void> dispose() => _player.dispose();
}
