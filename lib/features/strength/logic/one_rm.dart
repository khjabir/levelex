import 'dart:math' as math;

import '../models/lift_log.dart';

/// Formulas that estimate a one-rep max from one weight × reps set.
enum OneRmFormula {
  epley('Epley'),
  brzycki('Brzycki'),
  lombardi('Lombardi'),
  oconner("O'Conner"),
  mayhew('Mayhew'),
  wathan('Wathan'),
  lander('Lander');

  const OneRmFormula(this.label);

  final String label;
}

/// One-rep-max estimates. Every formula takes the weight lifted and the reps
/// completed with it; none is meaningful far from a max, so [estimate] gives
/// up above [repCap] reps.
abstract final class OneRm {
  /// Sets longer than this are too far from a max for any formula to be
  /// trusted; [estimate] returns null above it.
  static const repCap = 12;

  static double epley(double w, int r) => w * (1 + r / 30);

  static double brzycki(double w, int r) => w * 36 / (37 - r);

  static double lombardi(double w, int r) => w * math.pow(r, 0.10).toDouble();

  static double oconner(double w, int r) => w * (1 + 0.025 * r);

  static double mayhew(double w, int r) =>
      100 * w / (52.2 + 41.9 * math.exp(-0.055 * r));

  static double wathan(double w, int r) =>
      100 * w / (48.8 + 53.8 * math.exp(-0.075 * r));

  static double lander(double w, int r) => 100 * w / (101.3 - 2.67123 * r);

  /// The estimated 1RM for [reps] at [weightKg], or null when the set says
  /// nothing about a max: no reps, more than [repCap] reps, or no load. A
  /// single rep is already a max and comes back unchanged.
  static double? estimate(
    double weightKg,
    int reps, {
    OneRmFormula formula = OneRmFormula.epley,
  }) {
    if (reps <= 0 || reps > repCap || weightKg <= 0) return null;
    if (reps == 1) return weightKg;
    return switch (formula) {
      OneRmFormula.epley => epley(weightKg, reps),
      OneRmFormula.brzycki => brzycki(weightKg, reps),
      OneRmFormula.lombardi => lombardi(weightKg, reps),
      OneRmFormula.oconner => oconner(weightKg, reps),
      OneRmFormula.mayhew => mayhew(weightKg, reps),
      OneRmFormula.wathan => wathan(weightKg, reps),
      OneRmFormula.lander => lander(weightKg, reps),
    };
  }

  /// The best estimate over the entry's work sets, or null when no set
  /// qualifies.
  static double? bestForEntry(
    LiftEntry e, {
    OneRmFormula formula = OneRmFormula.epley,
  }) {
    double? best;
    for (final s in e.workSets) {
      final rm = estimate(s.weightKg, s.reps, formula: formula);
      if (rm != null && (best == null || rm > best)) best = rm;
    }
    return best;
  }

  /// The best estimate across every entry, or null when none qualifies.
  static double? bestInHistory(
    Iterable<LiftEntry> history, {
    OneRmFormula formula = OneRmFormula.epley,
  }) {
    double? best;
    for (final e in history) {
      final rm = bestForEntry(e, formula: formula);
      if (rm != null && (best == null || rm > best)) best = rm;
    }
    return best;
  }
}
