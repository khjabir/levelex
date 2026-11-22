import 'dart:math' as math;

/// Phase of a repetition cycle.
enum CyclePhase {
  /// Waiting for the user to settle in the rest position.
  ready,

  /// The rest position (arms extended, standing, lying…).
  rest,

  /// The working position (bottom of a push-up, bottom of a squat, arms
  /// overhead…).
  work,

  /// Target reached.
  completed,
}

/// Why a transition was refused on a frame.
enum CycleRejection { notValid, tooSoon, cooldown, vetoed }

/// Tuning for [RepCycleCounter].
class CycleConfig {
  const CycleConfig({
    required this.restDefault,
    required this.workDefault,
    this.restIsHigh = true,
    this.adaptive = true,
    this.minRange = 35,
    this.margin = 0.3,
    this.minGap = 15,
    this.decayPerFrame = 0.3,
    this.minFrames = 2,
    this.minWorkDuration = const Duration(milliseconds: 250),
    this.cooldown = const Duration(milliseconds: 400),
    this.shallowFraction = 0.4,
    this.maxDropout = const Duration(milliseconds: 900),
    this.maxAdaptiveLoosening,
  });

  /// Default threshold for the rest position (before adapting).
  final double restDefault;

  /// Default threshold for the work position (before adapting).
  final double workDefault;

  /// True when larger signal values mean "rest" (e.g. a straight elbow).
  final bool restIsHigh;

  /// Adapt thresholds to the observed signal range.
  final bool adaptive;

  /// Observed range needed before adapting.
  final double minRange;

  /// Fraction of the observed range inside each extreme where the adaptive
  /// thresholds sit.
  final double margin;

  /// Minimum distance kept between the two thresholds.
  final double minGap;

  /// How fast the observed extremes relax towards the current value.
  final double decayPerFrame;

  /// Consecutive agreeing frames needed for a transition.
  final int minFrames;

  /// Minimum time in the work position for a rep to be real.
  final Duration minWorkDuration;

  /// Minimum time between two counted reps.
  final Duration cooldown;

  /// Depth (0..1 towards the work threshold) a movement must reach before
  /// an aborted descent is reported as a shallow attempt. Below this it is
  /// treated as a wobble and ignored.
  final double shallowFraction;

  /// A gap in tracking up to this long (fast moves blur, ML Kit drops the
  /// body for a frame) keeps the rep in progress; a longer one starts over.
  final Duration maxDropout;

  /// How far past the default work threshold the adaptive one may move
  /// towards the rest position (null: no limit). Keeps a user's habitual
  /// quarter reps from teaching the counter to accept quarter reps.
  final double? maxAdaptiveLoosening;
}

/// Result of feeding one frame to [RepCycleCounter].
class CycleUpdate {
  const CycleUpdate({
    required this.phase,
    required this.repCounted,
    required this.depth,
    required this.restThreshold,
    required this.workThreshold,
    this.rejection,
    this.enteredWork = false,
    this.shallowAttempt = false,
  });

  final CyclePhase phase;
  final bool repCounted;

  /// 0 at rest, 1 at the work threshold.
  final double depth;
  final double restThreshold;
  final double workThreshold;
  final CycleRejection? rejection;

  /// True on the frame the work position was accepted.
  final bool enteredWork;

  /// True on the frame a descent that never reached the work position
  /// returned to rest (a half rep).
  final bool shallowAttempt;
}

/// Counts repetitions on a scalar signal with hysteresis, debouncing,
/// adaptive thresholds, timing rules and optional exercise-specific vetoes.
///
/// A rep is rest → work → rest. The signal can be anything monotonic with
/// the movement (elbow angle, knee angle, hand height…).
class RepCycleCounter {
  RepCycleCounter({required this.config, this.target});

  final CycleConfig config;
  final int? target;

  CyclePhase _phase = CyclePhase.ready;
  int _reps = 0;
  CyclePhase? _pending;
  int _pendingFrames = 0;
  DateTime? _workEnteredAt;
  DateTime? _lastRepAt;
  double? _max;
  double? _min;
  double _attemptPeak = 0;
  bool _attemptVetoed = false;
  DateTime? _lastValidAt;

  CyclePhase get phase => _phase;
  int get repCount => _reps;

  double get restThreshold => _thresholds().$1;
  double get workThreshold => _thresholds().$2;

  void reset() {
    _phase = CyclePhase.ready;
    _reps = 0;
    _pending = null;
    _pendingFrames = 0;
    _workEnteredAt = null;
    _lastRepAt = null;
    _max = null;
    _min = null;
    _attemptPeak = 0;
    _attemptVetoed = false;
    _lastValidAt = null;
  }

  /// A frame without a usable body. The phase survives a short dropout so a
  /// rep that blurs for a frame still counts; debouncing restarts.
  void hold(DateTime now) {
    _pending = null;
    _pendingFrames = 0;
    final last = _lastValidAt;
    if (last == null || now.difference(last) > config.maxDropout) {
      invalidate();
    }
  }

  /// Drops in-flight debouncing and returns to [CyclePhase.ready] without
  /// touching the count (used after a long track break or an orientation
  /// change).
  void invalidate() {
    _pending = null;
    _pendingFrames = 0;
    if (_phase != CyclePhase.completed) _phase = CyclePhase.ready;
    _workEnteredAt = null;
    _attemptPeak = 0;
    _attemptVetoed = false;
    _lastValidAt = null;
  }

  (double, double) _thresholds() {
    var rest = config.restDefault;
    var work = config.workDefault;
    final max = _max;
    final min = _min;
    if (config.adaptive && max != null && min != null) {
      final range = max - min;
      if (range >= config.minRange) {
        final hi = max - config.margin * range;
        final lo = min + config.margin * range;
        if (config.restIsHigh) {
          rest = hi;
          work = lo;
        } else {
          rest = lo;
          work = hi;
        }
        final loosen = config.maxAdaptiveLoosening;
        if (loosen != null) {
          work = config.restIsHigh
              ? math.min(work, config.workDefault + loosen)
              : math.max(work, config.workDefault - loosen);
        }
      }
    }
    // Keep the hysteresis band open.
    if (config.restIsHigh && rest - work < config.minGap) {
      work = rest - config.minGap;
    } else if (!config.restIsHigh && work - rest < config.minGap) {
      work = rest + config.minGap;
    }
    return (rest, work);
  }

  void _observe(double v) {
    final max = _max;
    final min = _min;
    _max = max == null ? v : math.max(v, max - config.decayPerFrame);
    _min = min == null ? v : math.min(v, min + config.decayPerFrame);
  }

  /// Feeds one frame. [valid] false means the frame cannot be trusted (no
  /// transitions, no adaptation). [vetoWork] may refuse entering the work
  /// position (e.g. "shoulders did not move"); [vetoRest] likewise for the
  /// return to rest.
  CycleUpdate update({
    required double? signal,
    required DateTime now,
    required bool valid,
    bool Function()? vetoWork,
    bool Function()? vetoRest,
  }) {
    final last = _lastValidAt;
    if (last != null && now.difference(last) > config.maxDropout) {
      // Too long without a usable frame: whatever was in flight is stale.
      invalidate();
    }
    if (!valid || signal == null) {
      _pending = null;
      _pendingFrames = 0;
      final (r, w) = _thresholds();
      return CycleUpdate(
        phase: _phase,
        repCounted: false,
        depth: 0,
        restThreshold: r,
        workThreshold: w,
        rejection: CycleRejection.notValid,
      );
    }
    _lastValidAt = now;
    _observe(signal);
    final (rest, work) = _thresholds();
    final depth = _depth(signal, rest, work);
    if (_phase == CyclePhase.rest && depth > _attemptPeak) {
      _attemptPeak = depth;
    }

    if (_phase == CyclePhase.completed) {
      return CycleUpdate(
        phase: _phase,
        repCounted: false,
        depth: depth,
        restThreshold: rest,
        workThreshold: work,
      );
    }

    final CyclePhase? candidate;
    final atRest = config.restIsHigh ? signal >= rest : signal <= rest;
    final atWork = config.restIsHigh ? signal <= work : signal >= work;
    if (atRest) {
      candidate = CyclePhase.rest;
    } else if (atWork) {
      candidate = CyclePhase.work;
    } else {
      candidate = null;
    }

    if (candidate == null) {
      _pending = null;
      _pendingFrames = 0;
      return CycleUpdate(
        phase: _phase,
        repCounted: false,
        depth: depth,
        restThreshold: rest,
        workThreshold: work,
      );
    }
    if (candidate == _pending) {
      _pendingFrames++;
    } else {
      _pending = candidate;
      _pendingFrames = 1;
    }
    if (_pendingFrames < config.minFrames) {
      return CycleUpdate(
        phase: _phase,
        repCounted: false,
        depth: depth,
        restThreshold: rest,
        workThreshold: work,
      );
    }

    var counted = false;
    var enteredWork = false;
    var shallow = false;
    CycleRejection? rejection;
    switch (_phase) {
      case CyclePhase.ready:
        if (candidate == CyclePhase.rest) _phase = CyclePhase.rest;
      case CyclePhase.rest:
        if (candidate == CyclePhase.work) {
          if (vetoWork != null && vetoWork()) {
            rejection = CycleRejection.vetoed;
            _attemptVetoed = true;
            _pending = null;
            _pendingFrames = 0;
          } else {
            _phase = CyclePhase.work;
            _workEnteredAt = now;
            enteredWork = true;
            _attemptPeak = 0;
            _attemptVetoed = false;
          }
        } else if (_pendingFrames == config.minFrames) {
          // Back at rest without having reached the work position.
          if (_attemptPeak >= config.shallowFraction && !_attemptVetoed) {
            shallow = true;
          }
          _attemptPeak = 0;
          _attemptVetoed = false;
        }
      case CyclePhase.work:
        if (candidate == CyclePhase.rest) {
          final enteredAt = _workEnteredAt;
          if (enteredAt != null &&
              now.difference(enteredAt) < config.minWorkDuration) {
            rejection = CycleRejection.tooSoon;
            _phase = CyclePhase.rest;
          } else if (_lastRepAt != null &&
              now.difference(_lastRepAt!) < config.cooldown) {
            rejection = CycleRejection.cooldown;
            _phase = CyclePhase.rest;
          } else if (vetoRest != null && vetoRest()) {
            rejection = CycleRejection.vetoed;
            _phase = CyclePhase.rest;
          } else {
            _reps++;
            _lastRepAt = now;
            counted = true;
            _phase = target != null && _reps >= target!
                ? CyclePhase.completed
                : CyclePhase.rest;
          }
        }
      case CyclePhase.completed:
        break;
    }
    return CycleUpdate(
      phase: _phase,
      repCounted: counted,
      depth: depth,
      restThreshold: rest,
      workThreshold: work,
      rejection: rejection,
      enteredWork: enteredWork,
      shallowAttempt: shallow,
    );
  }

  double _depth(double signal, double rest, double work) {
    final span = (rest - work).abs();
    if (span == 0) return 0;
    final d = config.restIsHigh
        ? (rest - signal) / span
        : (signal - rest) / span;
    return d.clamp(0.0, 1.0);
  }
}
