import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/services/voice_coach.dart';

void main() {
  group('VoiceScript', () {
    test('rep counts are spoken as plain numbers and never rate-limited', () {
      var now = DateTime(2026, 1, 1, 9);
      final script = VoiceScript(clock: () => now);
      expect(script.phraseFor(VoiceCue.rep, count: 1), '1');
      expect(script.phraseFor(VoiceCue.rep, count: 2), '2');
      now = now.add(const Duration(milliseconds: 50));
      expect(script.phraseFor(VoiceCue.rep, count: 3), '3');
    });

    test('countdown and go are the expected words', () {
      final script = VoiceScript();
      expect(script.phraseFor(VoiceCue.three), 'Three');
      expect(script.phraseFor(VoiceCue.two), 'Two');
      expect(script.phraseFor(VoiceCue.one), 'One');
      expect(script.phraseFor(VoiceCue.go), 'Go!');
      expect(VoiceCue.go.interrupts, isTrue);
    });

    test('form cues are rate-limited to one per six seconds', () {
      var now = DateTime(2026, 1, 1, 9);
      final script = VoiceScript(clock: () => now);
      expect(script.phraseFor(VoiceCue.hipsLower), 'Keep your hips lower');
      now = now.add(const Duration(seconds: 3));
      expect(script.phraseFor(VoiceCue.hipsLower), isNull);
      now = now.add(const Duration(seconds: 4));
      expect(script.phraseFor(VoiceCue.hipsLower), 'Keep your hips lower');
    });

    test('completion phrase pluralises correctly', () {
      expect(
        VoiceScript.text(VoiceCue.complete, count: 10),
        'Set complete. 10 push-ups. Well done!',
      );
      expect(
        VoiceScript.text(VoiceCue.setEnded, count: 1),
        'Set ended. 1 push-up.',
      );
      expect(
        VoiceScript.text(VoiceCue.complete, count: 12, label: 'squats'),
        'Set complete. 12 squats. Well done!',
      );
      expect(VoiceScript.text(VoiceCue.secondsHeld, count: 20), '20 seconds');
    });

    test('reset clears the rate limiter', () {
      final script = VoiceScript(clock: () => DateTime(2026));
      expect(script.phraseFor(VoiceCue.ready), 'Ready');
      expect(script.phraseFor(VoiceCue.ready), isNull);
      script.reset();
      expect(script.phraseFor(VoiceCue.ready), 'Ready');
    });
  });
}
