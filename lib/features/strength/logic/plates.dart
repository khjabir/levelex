/// Bars the plate calculator knows, with their own weight.
enum BarType {
  olympic(20, 'Olympic bar'),
  womens(15, "Women's bar"),
  technique(10, 'Technique bar'),
  ezBar(7.5, 'EZ bar'),
  trapBar(25, 'Trap bar'),
  smith(7, 'Smith machine'),
  none(0, 'No bar');

  const BarType(this.kg, this.label);

  final double kg;
  final String label;
}

/// What to put on each side of the bar for a target load.
class PlateLoad {
  const PlateLoad({
    required this.perSide,
    required this.achievedKg,
    required this.targetKg,
    required this.barKg,
  });

  /// Plates for one side, heaviest first.
  final List<double> perSide;

  /// Bar plus both sides; never above [targetKg] unless the bar alone is.
  final double achievedKg;
  final double targetKg;
  final double barKg;

  /// What the load falls short of the target by (negative when the bar alone
  /// already outweighs the target).
  double get remainderKg => _round2(targetKg - achievedKg);

  bool get isExact => remainderKg.abs() < 0.005;

  /// Kilograms of plates on one side.
  double get perSideKg => _round2(perSide.fold(0.0, (sum, p) => sum + p));

  /// "20 + 10 + 2.5 per side", or "Empty bar".
  String get label => perSide.isEmpty
      ? 'Empty bar'
      : '${perSide.map(PlateCalculator.formatKg).join(' + ')} per side';
}

/// Greedy plate maths: heaviest plate first, pairs only, never over target.
abstract final class PlateCalculator {
  /// The usual plates of a commercial gym, in kg.
  static const standardKg = <double>[25, 20, 15, 10, 5, 2.5, 1.25];

  /// Loads [targetKg] on a [barKg] bar from [plates] (any order), one pair at
  /// a time from the heaviest down, stopping before the target would be
  /// passed. With [pairsAvailable] (plate kg → pairs owned) a plate missing
  /// from the map counts as unavailable.
  static PlateLoad solve({
    required double targetKg,
    double barKg = 20,
    List<double> plates = standardKg,
    Map<double, int>? pairsAvailable,
  }) {
    final sizes = plates.where((p) => p > 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    var remaining = (targetKg - barKg) / 2;
    final perSide = <double>[];
    for (final p in sizes) {
      var pairs = pairsAvailable == null ? 1 << 30 : (pairsAvailable[p] ?? 0);
      while (pairs > 0 && remaining + 1e-9 >= p) {
        perSide.add(p);
        remaining -= p;
        pairs--;
      }
    }
    final loaded = perSide.fold(0.0, (sum, p) => sum + p);
    return PlateLoad(
      perSide: perSide,
      achievedKg: _round2(barKg + 2 * loaded),
      targetKg: targetKg,
      barKg: barKg,
    );
  }

  /// The loadable weight closest to [targetKg] (below or above), ties going
  /// to the lighter one. Candidates are the greedy load for the target and
  /// the greedy load for the target plus one more pair of each plate size.
  static double nearestLoadable({
    required double targetKg,
    double barKg = 20,
    List<double> plates = standardKg,
    Map<double, int>? pairsAvailable,
  }) {
    var best = solve(
      targetKg: targetKg,
      barKg: barKg,
      plates: plates,
      pairsAvailable: pairsAvailable,
    ).achievedKg;
    for (final p in plates.toSet()) {
      if (p <= 0) continue;
      final candidate = solve(
        targetKg: targetKg + 2 * p,
        barKg: barKg,
        plates: plates,
        pairsAvailable: pairsAvailable,
      ).achievedKg;
      final gap = (candidate - targetKg).abs();
      final bestGap = (best - targetKg).abs();
      if (gap < bestGap - 1e-9 ||
          ((gap - bestGap).abs() <= 1e-9 && candidate < best)) {
        best = candidate;
      }
    }
    return best;
  }

  /// The weights of a dumbbell rack: [min], [min] + [step] … up to [max].
  static List<double> dumbbellSteps({
    double min = 2,
    double max = 50,
    double step = 2,
  }) {
    if (step <= 0 || max < min) return [_round2(min)];
    final out = <double>[];
    for (var i = 0; ; i++) {
      final kg = _round2(min + i * step);
      if (kg > max + 1e-9) break;
      out.add(kg);
    }
    return out;
  }

  /// Up to two decimals with trailing zeros dropped: "20", "2.5", "1.25".
  static String formatKg(double kg) {
    var s = kg.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s == '-0' ? '0' : s;
  }
}

double _round2(double v) => (v * 100).round() / 100;
