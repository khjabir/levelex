import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/workout/analysis/coaching_tracker.dart';
import 'package:levelex/features/workout/analysis/exercise_analyzer.dart';
import 'package:levelex/features/workout/analysis/rep_cycle_counter.dart';
import 'package:levelex/models/coaching.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/form_status.dart';

ExerciseAnalysis frame(FormStatus status, {FormStatus? event}) =>
    ExerciseAnalysis(
      repCount: 0,
      phase: CyclePhase.rest,
      formStatus: status,
      repCounted: false,
      event: event,
    );

void main() {
  group('CoachingTracker', () {
    test('a posture mistake counts once per episode after it persists', () {
      final t = CoachingTracker();
      var now = DateTime(2026, 1, 1);
      // 5 frames × 80 ms = 400 ms: not yet an episode.
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(milliseconds: 80));
        t.observe(frame(FormStatus.hipsTooLow), now);
      }
      expect(t.mistakes, isEmpty);
      expect(t.cueAt(now), isNull);
      // Another 400 ms: now it is.
      FormStatus? fired;
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(milliseconds: 80));
        fired = t.observe(frame(FormStatus.hipsTooLow), now) ?? fired;
      }
      expect(fired, FormStatus.hipsTooLow);
      expect(t.mistakes[FormStatus.hipsTooLow], 1);
      expect(t.cueAt(now), FormStatus.hipsTooLow);
      // Staying in the mistake does not add more episodes.
      for (var i = 0; i < 20; i++) {
        now = now.add(const Duration(milliseconds: 80));
        t.observe(frame(FormStatus.hipsTooLow), now);
      }
      expect(t.mistakes[FormStatus.hipsTooLow], 1);
      // Fix it, then sag again: a second episode.
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(milliseconds: 80));
        t.observe(frame(FormStatus.goodForm), now);
      }
      for (var i = 0; i < 12; i++) {
        now = now.add(const Duration(milliseconds: 80));
        t.observe(frame(FormStatus.hipsTooLow), now);
      }
      expect(t.mistakes[FormStatus.hipsTooLow], 2);
    });

    test('single noisy frames never count', () {
      final t = CoachingTracker();
      var now = DateTime(2026, 1, 1);
      for (var i = 0; i < 30; i++) {
        now = now.add(const Duration(milliseconds: 80));
        t.observe(
          frame(i.isEven ? FormStatus.hipsTooHigh : FormStatus.goodForm),
          now,
        );
      }
      expect(t.mistakes, isEmpty);
    });

    test('events count immediately and the cue expires', () {
      final t = CoachingTracker(cueDuration: const Duration(seconds: 2));
      final now = DateTime(2026, 1, 1);
      final fired = t.observe(
        frame(FormStatus.goodForm, event: FormStatus.goDeeper),
        now,
      );
      expect(fired, FormStatus.goDeeper);
      expect(t.mistakes[FormStatus.goDeeper], 1);
      expect(t.cueAt(now.add(const Duration(seconds: 1))), FormStatus.goDeeper);
      expect(t.cueAt(now.add(const Duration(seconds: 3))), isNull);
      t.observe(frame(FormStatus.goodForm, event: FormStatus.slowDown), now);
      expect(t.totalMistakes, 2);
    });

    test('reset clears counts and cues', () {
      final t = CoachingTracker();
      final now = DateTime(2026, 1, 1);
      t.observe(frame(FormStatus.goodForm, event: FormStatus.goDeeper), now);
      t.reset();
      expect(t.mistakes, isEmpty);
      expect(t.cueAt(now), isNull);
    });
  });

  group('CoachingLibrary', () {
    test('every mistake has exercise-aware copy', () {
      for (final exercise in ExerciseType.values) {
        for (final status in FormStatus.values.where((s) => s.isMistake)) {
          final cue = CoachingLibrary.cue(status, exercise);
          expect(cue, isNotNull, reason: '$status for $exercise');
          expect(cue!.instruction, isNotEmpty);
          expect(cue.spoken, isNotEmpty);
          expect(CoachingLibrary.tip(status, exercise), isNotEmpty);
        }
      }
    });

    test('push-up depth cue talks about the chest and elbows', () {
      final cue = CoachingLibrary.cue(
        FormStatus.goDeeper,
        ExerciseType.pushUp,
      )!;
      expect(cue.title, 'Go lower');
      expect(cue.instruction, contains('elbows'));
    });

    test('notes are sorted by frequency', () {
      final notes = CoachingLibrary.notes({
        FormStatus.goDeeper: 1,
        FormStatus.hipsTooLow: 3,
        FormStatus.slowDown: 0,
      }, ExerciseType.pushUp);
      expect(notes.map((n) => n.status), [
        FormStatus.hipsTooLow,
        FormStatus.goDeeper,
      ]);
      expect(notes.first.count, 3);
    });
  });
}
