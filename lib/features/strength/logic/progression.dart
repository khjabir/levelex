import 'dart:math' as math;

import '../models/lift_log.dart';
import '../models/progression_rule.dart';

/// Reads a movement's logged sessions and decides the next prescription.
///
/// The engine is pure: the same rule and history always give the same answer,
/// and every answer carries a one-sentence `why` quoting the numbers it read.
/// A session is read honestly: its weight is the top work-set weight, only
/// sets at that weight count, a set is hit only when its reps reach the
/// target, and logging fewer sets than the rule asks is a miss.
abstract final class ProgressionEngine {
  /// The next prescription for one movement. [history] holds that movement's
  /// entries in any order; entries without work sets are ignored.
  static Prescription next({
    required ProgressionRule rule,
    required List<LiftEntry> history,
  }) {
    final sessions = _sessions(history);
    final last = sessions.isEmpty ? null : sessions.last;
    if (rule.policy == ProgressionPolicy.off) {
      return Prescription(
        policy: rule.policy,
        kind: PrescriptionKind.off,
        sets: rule.sets,
        reps: rule.repsMax,
        repsMin: rule.repsMin < rule.repsMax ? rule.repsMin : null,
        weightKg: last?.weight,
        why: 'Progression is off: same prescription as last time.',
        basedOn: last?.entry,
      );
    }
    if (last == null) return _first(rule);
    final bodyweight = sessions.every((s) => s.weight == 0);
    final streak = _streak(rule, sessions);
    return switch (rule.policy) {
      ProgressionPolicy.linear => _linear(rule, sessions, bodyweight, streak),
      ProgressionPolicy.greyskull => _greyskull(rule, sessions, bodyweight),
      ProgressionPolicy.double_ => _double(rule, sessions, bodyweight, streak),
      ProgressionPolicy.triple => _triple(rule, sessions, bodyweight, streak),
      ProgressionPolicy.time => _time(rule, sessions, streak),
      ProgressionPolicy.off => throw StateError('handled above'),
    };
  }

  /// How many sessions in a row (newest backwards, at the current weight)
  /// have stalled under [rule]. Zero when the last session progressed, when
  /// nothing is logged, or when progression is off.
  static int stallCount(ProgressionRule rule, List<LiftEntry> chronological) =>
      _streak(rule, _sessions(chronological));

  /// [kg] rounded to the nearest multiple of [step], to two decimals.
  static double snap(double kg, double step) {
    if (step <= 0) return _round2(kg);
    return _round2((kg / step).round() * step);
  }

  /// [kg] rounded down to a multiple of [step], to two decimals.
  static double snapDown(double kg, double step) {
    if (step <= 0) return _round2(kg);
    return _round2((kg / step + 1e-9).floor() * step);
  }

  // ---------------------------------------------------------------------
  // Policies
  // ---------------------------------------------------------------------

  static Prescription _first(ProgressionRule rule) {
    final ranged =
        rule.policy == ProgressionPolicy.double_ ||
        rule.policy == ProgressionPolicy.triple;
    return Prescription(
      policy: rule.policy,
      kind: PrescriptionKind.first,
      sets: rule.sets,
      reps: ranged ? rule.repsMin : rule.repsMax,
      repsMin: ranged ? rule.repsMin : null,
      seconds: rule.policy == ProgressionPolicy.time ? rule.seconds : null,
      why: 'Nothing logged yet, so this session sets the baseline.',
    );
  }

  static Prescription _linear(
    ProgressionRule rule,
    List<_Session> sessions,
    bool bodyweight,
    int streak,
  ) {
    final last = sessions.last;
    final target = rule.repsMax;
    final where = _at(last.weight, bodyweight);
    if (_allHit(last, target, rule.sets)) {
      final n = last.top.length;
      if (bodyweight) {
        return _up(
          rule,
          last,
          weight: 0,
          reps: target + 1,
          why:
              'All $n sets hit $target $where last time, so aim for '
              '${target + 1} reps.',
        );
      }
      return _up(
        rule,
        last,
        weight: _round2(last.weight + rule.incrementKg),
        reps: target,
        why:
            'All $n sets hit $target $where last time, so add '
            '${_kg(rule.incrementKg)} kg.',
      );
    }
    if (streak >= rule.stallLimit) {
      return _deload(
        rule,
        last,
        bodyweight,
        'Missed reps $streak sessions running $where',
      );
    }
    return _hold(
      rule,
      last,
      reps: target,
      why:
          '${_describe(last, rule, bodyweight)}, miss $streak of '
          '${rule.stallLimit}: ${_holdVerb(bodyweight)} and chase $target.',
    );
  }

  static Prescription _greyskull(
    ProgressionRule rule,
    List<_Session> sessions,
    bool bodyweight,
  ) {
    final last = sessions.last;
    final target = rule.repsMax;
    final where = _at(last.weight, bodyweight);
    if (_greyskullHit(last, rule)) {
      final top = last.top;
      final lastReps = top.last.reps;
      final earlier = [for (final s in top.take(top.length - 1)) s.reps];
      final doubled = lastReps >= 2 * target;
      final jumps = doubled ? 2 : 1;
      final how = doubled
          ? 'Last set went $lastReps, double the $target target, $where'
          : 'Last set went $lastReps against a $target target $where';
      final withEarlier = earlier.isEmpty
          ? ''
          : ' with the earlier sets at ${_list(earlier)}';
      if (bodyweight) {
        return _up(
          rule,
          last,
          weight: 0,
          reps: target + jumps,
          why: '$how$withEarlier, so aim for ${target + jumps} reps.',
        );
      }
      final add = _round2(rule.incrementKg * jumps);
      return _up(
        rule,
        last,
        weight: _round2(last.weight + add),
        reps: target,
        why: '$how$withEarlier, so add ${_kg(add)} kg.',
      );
    }
    return _deload(
      rule,
      last,
      bodyweight,
      '${_describe(last, rule, bodyweight)} against a $target target, and '
      'Greyskull resets on the first miss',
    );
  }

  static Prescription _double(
    ProgressionRule rule,
    List<_Session> sessions,
    bool bodyweight,
    int streak,
  ) {
    final last = sessions.last;
    final target = rule.repsMax;
    final where = _at(last.weight, bodyweight);
    if (_allHit(last, target, rule.sets)) {
      final n = last.top.length;
      if (bodyweight) {
        return _up(
          rule,
          last,
          weight: 0,
          reps: target + 1,
          repsMin: rule.repsMin,
          why:
              'All $n sets hit $target $where last time, so aim for '
              '${target + 1} reps.',
        );
      }
      return _up(
        rule,
        last,
        weight: _round2(last.weight + rule.incrementKg),
        reps: target,
        repsMin: rule.repsMin,
        why:
            'All $n sets hit $target $where last time, so add '
            '${_kg(rule.incrementKg)} kg and start again at ${_range(rule)}.',
      );
    }
    if (streak >= rule.stallLimit) {
      return _deload(
        rule,
        last,
        bodyweight,
        'Stalled $streak sessions running $where (best set '
        '${last.bestReps}, target $target)',
        ranged: true,
      );
    }
    return _hold(
      rule,
      last,
      reps: target,
      repsMin: rule.repsMin,
      why:
          '${_describe(last, rule, bodyweight)}, '
          '${_progressNote(rule, sessions, streak)}: '
          '${_holdVerb(bodyweight)} and chase $target.',
    );
  }

  static Prescription _triple(
    ProgressionRule rule,
    List<_Session> sessions,
    bool bodyweight,
    int streak,
  ) {
    final last = sessions.last;
    final target = rule.repsMax;
    final maxSets = math.max(rule.setsMax ?? rule.sets, rule.sets);
    final n = last.top.length;
    final where = _at(last.weight, bodyweight);
    if (_allHit(last, target, rule.sets)) {
      if (n < maxSets) {
        return _up(
          rule,
          last,
          weight: last.weight,
          reps: target,
          repsMin: rule.repsMin,
          sets: n + 1,
          why:
              'All $n sets hit $target $where last time, so add a set: '
              '${n + 1} × ${_range(rule)} (the weight goes up after '
              '$maxSets sets).',
        );
      }
      if (bodyweight) {
        return _up(
          rule,
          last,
          weight: 0,
          reps: target + 1,
          repsMin: rule.repsMin,
          why:
              'All $n sets hit $target $where last time, so aim for '
              '${target + 1} reps and go back to ${rule.sets} sets.',
        );
      }
      return _up(
        rule,
        last,
        weight: _round2(last.weight + rule.incrementKg),
        reps: target,
        repsMin: rule.repsMin,
        why:
            'All $n sets hit $target $where last time, so add '
            '${_kg(rule.incrementKg)} kg and go back to ${rule.sets} sets '
            'at ${_range(rule)}.',
      );
    }
    final current = n.clamp(rule.sets, maxSets);
    if (streak >= rule.stallLimit) {
      return _deload(
        rule,
        last,
        bodyweight,
        'Stalled $streak sessions running $where (best set '
        '${last.bestReps}, target $target)',
        ranged: true,
      );
    }
    return _hold(
      rule,
      last,
      reps: target,
      repsMin: rule.repsMin,
      sets: current,
      why:
          '${_describe(last, rule, bodyweight, asked: current)}, '
          '${_progressNote(rule, sessions, streak)}: '
          '${_holdVerb(bodyweight)} and chase $target in all $current sets.',
    );
  }

  static Prescription _time(
    ProgressionRule rule,
    List<_Session> sessions,
    int streak,
  ) {
    final last = sessions.last;
    final target = rule.seconds;
    final held = last.held;
    if (_allHeld(last, target, rule.sets)) {
      final next = target + rule.secondsStep;
      return Prescription(
        policy: rule.policy,
        kind: PrescriptionKind.up,
        sets: rule.sets,
        reps: rule.repsMax,
        weightKg: last.weight,
        seconds: next,
        why:
            'All ${held.length} holds reached $target s last time '
            '(${_list(held)} s), so add ${rule.secondsStep} s: aim for '
            '$next s.',
        basedOn: last.entry,
      );
    }
    final logged = held.length < rule.sets
        ? 'You logged only ${held.length} of ${rule.sets} holds '
              '(${_list(held)} s)'
        : 'You held ${_list(held)} s';
    if (streak >= rule.stallLimit) {
      final next = math.max(10, target - rule.secondsStep);
      final drop = target - next;
      return Prescription(
        policy: rule.policy,
        kind: PrescriptionKind.deload,
        sets: rule.sets,
        reps: rule.repsMax,
        weightKg: last.weight,
        seconds: next,
        why: drop > 0
            ? 'Missed $target s $streak sessions running, so ease back '
                  '$drop s to $next s.'
            : 'Missed $target s $streak sessions running, but $next s is '
                  'the floor, so stay there.',
        basedOn: last.entry,
      );
    }
    return Prescription(
      policy: rule.policy,
      kind: PrescriptionKind.hold,
      sets: rule.sets,
      reps: rule.repsMax,
      weightKg: last.weight,
      seconds: target,
      why:
          '$logged against a $target s target, miss $streak of '
          '${rule.stallLimit}: hold at $target s.',
      basedOn: last.entry,
    );
  }

  // ---------------------------------------------------------------------
  // Reading sessions
  // ---------------------------------------------------------------------

  static List<_Session> _sessions(List<LiftEntry> history) {
    final out = [
      for (final e in history)
        if (e.workSets.isNotEmpty) _Session(e),
    ];
    out.sort((a, b) {
      final byTime = a.entry.startTime.compareTo(b.entry.startTime);
      return byTime != 0 ? byTime : a.entry.id.compareTo(b.entry.id);
    });
    return out;
  }

  /// Enough sets at the session weight and every one of them at or above
  /// [target] reps.
  static bool _allHit(_Session s, int target, int sets) =>
      s.top.length >= sets && s.top.every((x) => x.reps >= target);

  /// Enough timed sets and every one held for at least [target] seconds.
  static bool _allHeld(_Session s, int target, int sets) =>
      s.work.length >= sets && s.work.every((x) => (x.seconds ?? 0) >= target);

  /// Greyskull: every straight set at the target and the final set at least
  /// at the target.
  static bool _greyskullHit(_Session s, ProgressionRule rule) {
    if (s.top.length < rule.sets) return false;
    final straight = s.top.take(s.top.length - 1);
    return straight.every((x) => x.reps >= rule.repsMax) &&
        s.top.last.reps >= rule.repsMax;
  }

  /// Best single set over the sessions before [index] at [weight].
  static int? _bestBefore(List<_Session> sessions, int index, double weight) {
    int? best;
    for (var i = 0; i < index; i++) {
      final s = sessions[i];
      if (s.weight != weight) continue;
      if (best == null || s.bestReps > best) best = s.bestReps;
    }
    return best;
  }

  static bool _isStall(ProgressionRule rule, List<_Session> sessions, int i) {
    final s = sessions[i];
    switch (rule.policy) {
      case ProgressionPolicy.off:
        return false;
      case ProgressionPolicy.linear:
        return !_allHit(s, rule.repsMax, rule.sets);
      case ProgressionPolicy.greyskull:
        return !_greyskullHit(s, rule);
      case ProgressionPolicy.double_:
      case ProgressionPolicy.triple:
        if (_allHit(s, rule.repsMax, rule.sets)) return false;
        final prior = _bestBefore(sessions, i, s.weight);
        return prior != null && s.bestReps <= prior;
      case ProgressionPolicy.time:
        return !_allHeld(s, rule.seconds, rule.sets);
    }
  }

  /// Consecutive stalled sessions counting back from the newest. For load
  /// policies the count stops where the weight changed.
  static int _streak(ProgressionRule rule, List<_Session> sessions) {
    if (sessions.isEmpty || rule.policy == ProgressionPolicy.off) return 0;
    final weight = sessions.last.weight;
    var n = 0;
    for (var i = sessions.length - 1; i >= 0; i--) {
      if (rule.policy != ProgressionPolicy.time &&
          sessions[i].weight != weight) {
        break;
      }
      if (!_isStall(rule, sessions, i)) break;
      n++;
    }
    return n;
  }

  // ---------------------------------------------------------------------
  // Building prescriptions
  // ---------------------------------------------------------------------

  static Prescription _up(
    ProgressionRule rule,
    _Session last, {
    required double weight,
    required int reps,
    required String why,
    int? repsMin,
    int? sets,
  }) => Prescription(
    policy: rule.policy,
    kind: PrescriptionKind.up,
    sets: sets ?? rule.sets,
    reps: reps,
    repsMin: repsMin != null && repsMin < reps ? repsMin : null,
    weightKg: weight,
    why: why,
    basedOn: last.entry,
  );

  static Prescription _hold(
    ProgressionRule rule,
    _Session last, {
    required int reps,
    required String why,
    int? repsMin,
    int? sets,
  }) => Prescription(
    policy: rule.policy,
    kind: PrescriptionKind.hold,
    sets: sets ?? rule.sets,
    reps: reps,
    repsMin: repsMin != null && repsMin < reps ? repsMin : null,
    weightKg: last.weight,
    why: why,
    basedOn: last.entry,
  );

  static Prescription _deload(
    ProgressionRule rule,
    _Session last,
    bool bodyweight,
    String lead, {
    bool ranged = false,
  }) {
    if (bodyweight) {
      final reps = _deloadReps(rule);
      return Prescription(
        policy: rule.policy,
        kind: PrescriptionKind.deload,
        sets: rule.sets,
        reps: reps,
        repsMin: ranged && rule.repsMin < reps ? rule.repsMin : null,
        weightKg: 0,
        why: '$lead, so ease the target ${_pct(rule)} to $reps reps.',
        basedOn: last.entry,
      );
    }
    final kg = _deloadWeight(rule, last.weight);
    return Prescription(
      policy: rule.policy,
      kind: PrescriptionKind.deload,
      sets: rule.sets,
      reps: rule.repsMax,
      repsMin: ranged && rule.repsMin < rule.repsMax ? rule.repsMin : null,
      weightKg: kg,
      why: '$lead, so deload ${_pct(rule)} to ${_kg(kg)} kg.',
      basedOn: last.entry,
    );
  }

  /// The deload load: the fraction removed, snapped down to the increment
  /// grid, at least one increment below the current weight and never below
  /// one increment (or below the current weight when that is already less).
  static double _deloadWeight(ProgressionRule rule, double weight) {
    final inc = rule.incrementKg;
    var kg = snapDown(weight * (1 - rule.deloadFraction), inc);
    final cap = snapDown(weight - inc, inc);
    if (kg > cap) kg = cap;
    final floor = math.min(inc, weight);
    if (kg < floor) kg = floor;
    return _round2(kg);
  }

  /// Bodyweight deload: the rep target eased by the deload fraction.
  static int _deloadReps(ProgressionRule rule) =>
      math.max(1, (rule.repsMax * (1 - rule.deloadFraction) + 1e-9).floor());

  // ---------------------------------------------------------------------
  // Wording
  // ---------------------------------------------------------------------

  static String _describe(
    _Session s,
    ProgressionRule rule,
    bool bodyweight, {
    int? asked,
  }) {
    final reps = s.reps;
    final sets = asked ?? rule.sets;
    final where = _at(s.weight, bodyweight);
    if (reps.length < sets) {
      return 'You logged only ${reps.length} of $sets sets $where '
          '(${_list(reps)})';
    }
    return 'You got ${_list(reps)} $where';
  }

  /// Double/triple hold: whether the best set moved at this weight.
  static String _progressNote(
    ProgressionRule rule,
    List<_Session> sessions,
    int streak,
  ) {
    final last = sessions.last;
    final prior = _bestBefore(sessions, sessions.length - 1, last.weight);
    if (prior == null) return 'your first go at this weight';
    if (last.bestReps > prior) return 'best set up from $prior';
    return 'no better than your best $prior here (stall $streak of '
        '${rule.stallLimit})';
  }

  static String _holdVerb(bool bodyweight) =>
      bodyweight ? 'hold' : 'hold the weight';

  static String _at(double weight, bool bodyweight) =>
      bodyweight ? 'at bodyweight' : 'at ${_kg(weight)} kg';

  static String _range(ProgressionRule rule) => rule.repsMin < rule.repsMax
      ? '${rule.repsMin}–${rule.repsMax}'
      : '${rule.repsMax}';

  static String _pct(ProgressionRule rule) =>
      '${_kg(rule.deloadFraction * 100)} %';

  static String _list(List<int> values) => values.join(', ');

  /// Up to two decimals with trailing zeros dropped: "60", "52.5", "61.25".
  static String _kg(double kg) {
    var s = kg.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s == '-0' ? '0' : s;
  }

  static double _round2(double v) => (v * 100).round() / 100;
}

/// One logged session as the engine reads it.
class _Session {
  _Session(this.entry) : work = entry.workSets, weight = entry.topWeight;

  final LiftEntry entry;

  /// Every work set, in logged order.
  final List<LiftSet> work;

  /// The session weight: the top work-set weight.
  final double weight;

  /// The work sets done at the session weight, in logged order.
  late final List<LiftSet> top = [
    for (final s in work)
      if (s.weightKg >= weight) s,
  ];

  late final List<int> reps = [for (final s in top) s.reps];

  /// Seconds held per work set (0 when a set carries no time).
  late final List<int> held = [for (final s in work) s.seconds ?? 0];

  int get bestReps => reps.fold(0, math.max);
}
