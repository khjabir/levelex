import '../../pt/models/equipment.dart';
import '../../pt/models/movement.dart';
import 'lift_log.dart';

/// How the next load is chosen from what was logged. Inspired by openGym's
/// named policies: the rule is always visible with the reason it fired.
enum ProgressionPolicy {
  off('Off', 'Same prescription every time; you decide the load.'),
  linear(
    'Linear',
    'Hit every rep in every set and the weight goes up. Repeated misses '
        'trigger a deload.',
  ),
  greyskull(
    'Greyskull LP',
    'Two straight sets plus a final set taken as far as you can. Beat the '
        'target on that set and the weight goes up (twice as much when you '
        'double it). One miss resets 10 %.',
  ),
  double_(
    'Double progression',
    'Work up through a rep range at the same weight. Reach the top of the '
        'range in every set and the weight goes up, reps back to the bottom.',
  ),
  triple(
    'Triple progression',
    'Reps climb to the top of the range, then a set is added, up to your '
        'most sets. All of them at the top and the weight goes up.',
  ),
  time('Timed', 'Hold the full time in every set and the hold gets longer.');

  const ProgressionPolicy(this.label, this.description);

  final String label;
  final String description;

  static ProgressionPolicy fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => double_);
}

/// Per-exercise progression settings.
class ProgressionRule {
  const ProgressionRule({
    this.policy = ProgressionPolicy.double_,
    this.incrementKg = 2.5,
    this.repsMin = 8,
    this.repsMax = 12,
    this.sets = 3,
    this.setsMax,
    this.deloadFraction = 0.10,
    this.stallLimit = 3,
    this.seconds = 30,
    this.secondsStep = 5,
  });

  final ProgressionPolicy policy;

  /// Smallest load step for this exercise (2.5 kg on a bar, 2 kg per
  /// dumbbell, 4 kg between kettlebells).
  final double incrementKg;

  /// Rep range (double/triple); [repsMax] is the target for linear and
  /// greyskull.
  final int repsMin;
  final int repsMax;
  final int sets;

  /// Triple progression adds sets up to this many.
  final int? setsMax;

  /// Fraction removed on a deload (0.10 = 10 %).
  final double deloadFraction;

  /// Consecutive missed sessions before a deload (greyskull deloads at 1).
  final int stallLimit;

  /// Timed policy: hold length and the step it grows by.
  final int seconds;
  final int secondsStep;

  /// The increment that suits the equipment used.
  static double incrementFor(Set<Equipment> equipment) {
    if (equipment.contains(Equipment.kettlebell)) return 4;
    if (equipment.contains(Equipment.dumbbells)) return 2;
    if (equipment.contains(Equipment.cableMachine)) return 2.5;
    return 2.5;
  }

  /// Sensible defaults for a movement: timed holds progress by time,
  /// compound barbell lifts linearly in a 5×5 style, everything else by
  /// double progression.
  factory ProgressionRule.defaultsFor(
    Movement movement, {
    Set<Equipment> equipment = const {},
    int sets = 3,
  }) {
    if (movement.isTimed) {
      return ProgressionRule(
        policy: ProgressionPolicy.time,
        sets: sets,
        seconds: movement.baseSeconds,
      );
    }
    final inc = incrementFor(equipment);
    if (movement.compound && equipment.contains(Equipment.barbell)) {
      return ProgressionRule(
        policy: ProgressionPolicy.linear,
        incrementKg: inc,
        repsMin: 5,
        repsMax: 5,
        sets: sets,
      );
    }
    return ProgressionRule(
      policy: ProgressionPolicy.double_,
      incrementKg: inc,
      repsMin: 8,
      repsMax: 12,
      sets: sets,
    );
  }

  ProgressionRule copyWith({
    ProgressionPolicy? policy,
    double? incrementKg,
    int? repsMin,
    int? repsMax,
    int? sets,
    int? setsMax,
    bool clearSetsMax = false,
    double? deloadFraction,
    int? stallLimit,
    int? seconds,
    int? secondsStep,
  }) => ProgressionRule(
    policy: policy ?? this.policy,
    incrementKg: incrementKg ?? this.incrementKg,
    repsMin: repsMin ?? this.repsMin,
    repsMax: repsMax ?? this.repsMax,
    sets: sets ?? this.sets,
    setsMax: clearSetsMax ? null : (setsMax ?? this.setsMax),
    deloadFraction: deloadFraction ?? this.deloadFraction,
    stallLimit: stallLimit ?? this.stallLimit,
    seconds: seconds ?? this.seconds,
    secondsStep: secondsStep ?? this.secondsStep,
  );

  Map<String, dynamic> toMap() => {
    'policy': policy.name,
    'incrementKg': incrementKg,
    'repsMin': repsMin,
    'repsMax': repsMax,
    'sets': sets,
    if (setsMax != null) 'setsMax': setsMax,
    'deloadFraction': deloadFraction,
    'stallLimit': stallLimit,
    'seconds': seconds,
    'secondsStep': secondsStep,
  };

  factory ProgressionRule.fromMap(Map<dynamic, dynamic> map) => ProgressionRule(
    policy: ProgressionPolicy.fromName(map['policy'] as String?),
    incrementKg: (map['incrementKg'] as num?)?.toDouble() ?? 2.5,
    repsMin: (map['repsMin'] as num?)?.toInt() ?? 8,
    repsMax: (map['repsMax'] as num?)?.toInt() ?? 12,
    sets: (map['sets'] as num?)?.toInt() ?? 3,
    setsMax: (map['setsMax'] as num?)?.toInt(),
    deloadFraction: (map['deloadFraction'] as num?)?.toDouble() ?? 0.10,
    stallLimit: (map['stallLimit'] as num?)?.toInt() ?? 3,
    seconds: (map['seconds'] as num?)?.toInt() ?? 30,
    secondsStep: (map['secondsStep'] as num?)?.toInt() ?? 5,
  );

  @override
  bool operator ==(Object other) =>
      other is ProgressionRule &&
      other.policy == policy &&
      other.incrementKg == incrementKg &&
      other.repsMin == repsMin &&
      other.repsMax == repsMax &&
      other.sets == sets &&
      other.setsMax == setsMax &&
      other.deloadFraction == deloadFraction &&
      other.stallLimit == stallLimit &&
      other.seconds == seconds &&
      other.secondsStep == secondsStep;

  @override
  int get hashCode => Object.hash(
    policy,
    incrementKg,
    repsMin,
    repsMax,
    sets,
    setsMax,
    deloadFraction,
    stallLimit,
    seconds,
    secondsStep,
  );
}

/// What the rule decided for the next session.
enum PrescriptionKind {
  /// Nothing logged yet: this session sets the baseline.
  first,
  up,
  hold,
  deload,
  off,
}

/// The next target for one exercise, with the reason in plain words.
class Prescription {
  const Prescription({
    required this.policy,
    required this.kind,
    required this.sets,
    required this.reps,
    this.weightKg,
    this.repsMin,
    this.seconds,
    required this.why,
    this.basedOn,
  });

  final ProgressionPolicy policy;
  final PrescriptionKind kind;
  final int sets;

  /// Target reps per set (the top of the range under double/triple).
  final int reps;

  /// Bottom of the rep range when one applies.
  final int? repsMin;

  /// Null when the exercise has no load yet (first session) or is timed.
  final double? weightKg;

  /// Timed policy target.
  final int? seconds;

  /// One sentence a user can audit ("All 3 sets hit 12 at 20 kg").
  final String why;

  /// The most recent entry the decision read.
  final LiftEntry? basedOn;

  String get repLabel =>
      repsMin != null && repsMin != reps ? '$repsMin–$reps' : '$reps';
}
