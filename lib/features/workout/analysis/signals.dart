import 'dart:math' as math;

/// A slowly forgetting maximum: follows any rise at once (after a 3-frame
/// median, so one glitchy frame cannot inflate it) and relaxes downwards by
/// [decayPerSecond] of its value, so a user who steps further from the
/// camera is re-learned within seconds.
class DecayingMax {
  DecayingMax({this.decayPerSecond = 0.02});

  final double decayPerSecond;
  double? _value;
  DateTime? _at;
  final List<double> _recent = [];

  double? get value => _value;

  void reset() {
    _value = null;
    _at = null;
    _recent.clear();
  }

  /// Feeds a sample and returns the current maximum.
  double update(double sample, DateTime now) {
    _recent.add(sample);
    if (_recent.length > 3) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    final robust = sorted[sorted.length ~/ 2];
    final previous = _value;
    final at = _at;
    _at = now;
    if (previous == null) return _value = robust;
    final dt = at == null
        ? 0.0
        : math.max(0, now.difference(at).inMilliseconds) / 1000;
    final decayed = previous * (1 - decayPerSecond * dt).clamp(0.5, 1.0);
    return _value = math.max(decayed, robust);
  }
}

/// A height expressed as a fraction of its usual top value: 1 at the top
/// of the movement, smaller as the body drops (0.5 = half way to the
/// floor). Being relative to the person's own top position, it reads the
/// same from the side, the front or a diagonal, near or far.
class DropRatio {
  DropRatio({double decayPerSecond = 0.02})
    : _top = DecayingMax(decayPerSecond: decayPerSecond);

  final DecayingMax _top;

  /// The height the ratio is taken against (the usual top), once known.
  double? get top => _top.value;

  void reset() => _top.reset();

  double? update(double? height, DateTime now) {
    if (height == null) return null;
    final top = _top.update(height, now);
    if (top <= 1e-6) return null;
    return (height / top).clamp(-0.5, 1.5);
  }
}
