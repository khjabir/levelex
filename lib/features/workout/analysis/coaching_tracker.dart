import '../../../models/form_status.dart';
import 'exercise_analyzer.dart';

/// Turns per-frame analyses into coaching: which cue to show right now and
/// how many times each mistake happened during the set.
///
/// Posture mistakes (hips sagging, chest down…) count once per episode and
/// only after they persisted for [episodeMinDuration], so a single noisy
/// frame never becomes a "mistake". Movement events (too shallow, too fast)
/// count immediately. Pure Dart, no timers: the caller passes the clock.
class CoachingTracker {
  CoachingTracker({
    this.episodeMinDuration = const Duration(milliseconds: 700),
    this.cueDuration = const Duration(milliseconds: 2800),
  });

  final Duration episodeMinDuration;
  final Duration cueDuration;

  final Map<FormStatus, int> _counts = {};
  FormStatus? _runStatus;
  DateTime? _runSince;
  bool _runCounted = false;
  FormStatus? _cue;
  DateTime? _cueUntil;

  /// Mistakes so far (status → episodes/events).
  Map<FormStatus, int> get mistakes => Map.unmodifiable(_counts);

  int get totalMistakes => _counts.values.fold(0, (a, b) => a + b);

  /// The cue that fired on the last [observe] call, if any (for voice).
  FormStatus? lastFired;

  /// Feeds one frame. Returns the status whose cue just fired, if any.
  FormStatus? observe(ExerciseAnalysis analysis, DateTime now) {
    lastFired = null;
    final event = analysis.event;
    if (event != null && event.isEvent) {
      _counts[event] = (_counts[event] ?? 0) + 1;
      _show(event, now);
      lastFired = event;
    }

    final status = analysis.formStatus;
    if (status.isPostureMistake) {
      if (status != _runStatus) {
        _runStatus = status;
        _runSince = now;
        _runCounted = false;
      } else if (!_runCounted &&
          now.difference(_runSince!) >= episodeMinDuration) {
        _runCounted = true;
        _counts[status] = (_counts[status] ?? 0) + 1;
        if (lastFired == null) {
          _show(status, now);
          lastFired = status;
        }
      }
      // Keep a confirmed posture cue on screen while the mistake persists,
      // unless an event cue is currently showing.
      if (_runCounted && (_cue == null || _cue == status)) {
        _show(status, now);
      }
    } else {
      _runStatus = null;
      _runSince = null;
      _runCounted = false;
    }
    return lastFired;
  }

  void _show(FormStatus status, DateTime now) {
    _cue = status;
    _cueUntil = now.add(cueDuration);
  }

  /// The cue to display at [now], or null.
  FormStatus? cueAt(DateTime now) {
    final until = _cueUntil;
    if (until == null || now.isAfter(until)) return null;
    return _cue;
  }

  void reset() {
    _counts.clear();
    _runStatus = null;
    _runSince = null;
    _runCounted = false;
    _cue = null;
    _cueUntil = null;
    lastFired = null;
  }
}
