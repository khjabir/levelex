import '../models/lift_log.dart';
import 'one_rm.dart';

/// What kind of personal record a session set.
enum PrKind {
  weight('Heaviest set'),
  reps('Most reps at a weight'),
  oneRm('Best estimated 1RM'),
  volume('Most volume in a session');

  const PrKind(this.label);

  final String label;
}

/// A personal record and what it beat.
class PersonalRecord {
  const PersonalRecord({
    required this.movementId,
    required this.kind,
    required this.value,
    this.previous,
    required this.date,
    required this.entryId,
    this.weightKg,
  });

  final String movementId;
  final PrKind kind;

  /// Kilograms for weight, 1RM and volume records; a rep count for reps.
  final double value;

  /// The best before this one, or null for a first-ever record.
  final double? previous;
  final DateTime date;
  final String entryId;

  /// Reps records only: the weight the reps were done at (0 = bodyweight).
  final double? weightKg;

  /// How much the record moved, or null when there was nothing to beat.
  double? get gain => previous == null ? null : value - previous!;

  /// "22.5 kg", "12 reps @ 20 kg", "e1RM 60 kg", "1,200 kg volume".
  String get label => switch (kind) {
    PrKind.weight => '${formatKg(value)} kg',
    PrKind.reps =>
      '${value.round()} reps @ '
          '${(weightKg ?? 0) > 0 ? '${formatKg(weightKg!)} kg' : 'bodyweight'}',
    PrKind.oneRm => 'e1RM ${formatKg(value)} kg',
    PrKind.volume => '${formatKg(value)} kg volume',
  };

  /// Kilograms with up to one decimal ("22.5", "60", "1,200").
  static String formatKg(double kg) {
    var s = kg.toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    final dot = s.indexOf('.');
    final whole = dot < 0 ? s : s.substring(0, dot);
    final frac = dot < 0 ? '' : s.substring(dot);
    final negative = whole.startsWith('-');
    final digits = negative ? whole.substring(1) : whole;
    final grouped = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
      grouped.write(digits[i]);
    }
    return '${negative ? '-' : ''}$grouped$frac';
  }
}

/// The best numbers a movement has reached so far.
class MovementBests {
  const MovementBests({
    this.weight,
    this.oneRm,
    this.volume,
    this.repsAtWeight = const {},
  });

  /// Heaviest work set with a load (> 0 kg).
  final double? weight;

  /// Best estimated 1RM over sets that qualify for an estimate.
  final double? oneRm;

  /// Most volume (kg × reps) in one session, when above 0.
  final double? volume;

  /// Weight (0 = bodyweight) → most reps done in one set at that weight.
  final Map<double, int> repsAtWeight;

  bool get isEmpty =>
      weight == null && oneRm == null && volume == null && repsAtWeight.isEmpty;
}

/// Personal records read from the lift log.
abstract final class RecordBook {
  /// The bests of [movementId] across [history] (other movements ignored).
  static MovementBests bestsFor(
    String movementId,
    Iterable<LiftEntry> history,
  ) {
    final acc = _Bests();
    for (final e in history) {
      if (e.movementId == movementId) acc.add(e);
    }
    return acc.snapshot();
  }

  /// Records [entry] set against the strictly earlier entries of the same
  /// movement in [history]. The entry itself (by id) and anything logged at
  /// the same instant or later are ignored. A tie is not a record. On a
  /// first-ever entry the weight, 1RM and volume records have no `previous`
  /// and only exist when a work set carries a load; a reps record needs an
  /// earlier set at exactly that weight to beat.
  static List<PersonalRecord> detect(
    LiftEntry entry,
    Iterable<LiftEntry> history,
  ) {
    final acc = _Bests();
    for (final h in history) {
      if (h.movementId == entry.movementId &&
          h.id != entry.id &&
          h.startTime.isBefore(entry.startTime)) {
        acc.add(h);
      }
    }
    return _compare(entry, acc.snapshot());
  }

  /// Every record in [history], newest first, at most [limit] of them. The
  /// log is replayed in time order so each entry is judged only against what
  /// came strictly before it.
  static List<PersonalRecord> recent(
    Iterable<LiftEntry> history, {
    int limit = 20,
  }) {
    if (limit <= 0) return const [];
    final sorted = history.toList()..sort(_chronological);
    final bests = <String, _Bests>{};
    final perEntry = <List<PersonalRecord>>[];
    var i = 0;
    while (i < sorted.length) {
      var j = i + 1;
      while (j < sorted.length &&
          sorted[j].startTime.isAtSameMomentAs(sorted[i].startTime)) {
        j++;
      }
      final batch = sorted.sublist(i, j);
      for (final e in batch) {
        final acc = bests[e.movementId];
        perEntry.add(
          _compare(e, acc == null ? const MovementBests() : acc.snapshot()),
        );
      }
      for (final e in batch) {
        bests.putIfAbsent(e.movementId, _Bests.new).add(e);
      }
      i = j;
    }
    final out = <PersonalRecord>[];
    for (var k = perEntry.length - 1; k >= 0 && out.length < limit; k--) {
      out.addAll(perEntry[k]);
    }
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  static int _chronological(LiftEntry a, LiftEntry b) {
    final byTime = a.startTime.compareTo(b.startTime);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  static List<PersonalRecord> _compare(LiftEntry entry, MovementBests bests) {
    final work = entry.workSets;
    if (work.isEmpty) return const [];
    final out = <PersonalRecord>[];

    PersonalRecord pr(
      PrKind kind,
      double value,
      double? previous, {
      double? weightKg,
    }) => PersonalRecord(
      movementId: entry.movementId,
      kind: kind,
      value: value,
      previous: previous,
      date: entry.startTime,
      entryId: entry.id,
      weightKg: weightKg,
    );

    final top = entry.topWeight;
    if (top > 0 && (bests.weight == null || top > bests.weight!)) {
      out.add(pr(PrKind.weight, top, bests.weight));
    }

    final repsHere = <double, int>{};
    for (final s in work) {
      if (s.reps <= 0) continue;
      final cur = repsHere[s.weightKg];
      if (cur == null || s.reps > cur) repsHere[s.weightKg] = s.reps;
    }
    final weights = repsHere.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final w in weights) {
      final prior = bests.repsAtWeight[w];
      final reps = repsHere[w]!;
      if (prior != null && reps > prior) {
        out.add(
          pr(PrKind.reps, reps.toDouble(), prior.toDouble(), weightKg: w),
        );
      }
    }

    final rm = OneRm.bestForEntry(entry);
    if (rm != null && (bests.oneRm == null || rm > bests.oneRm!)) {
      out.add(pr(PrKind.oneRm, rm, bests.oneRm));
    }

    final vol = entry.volume;
    if (vol > 0 && (bests.volume == null || vol > bests.volume!)) {
      out.add(pr(PrKind.volume, vol, bests.volume));
    }
    return out;
  }
}

/// Mutable accumulator behind [MovementBests].
class _Bests {
  double? weight;
  double? oneRm;
  double? volume;
  final repsAtWeight = <double, int>{};

  void add(LiftEntry e) {
    final work = e.workSets;
    if (work.isEmpty) return;
    final top = e.topWeight;
    if (top > 0 && (weight == null || top > weight!)) weight = top;
    final rm = OneRm.bestForEntry(e);
    if (rm != null && (oneRm == null || rm > oneRm!)) oneRm = rm;
    final vol = e.volume;
    if (vol > 0 && (volume == null || vol > volume!)) volume = vol;
    for (final s in work) {
      if (s.reps <= 0) continue;
      final cur = repsAtWeight[s.weightKg];
      if (cur == null || s.reps > cur) repsAtWeight[s.weightKg] = s.reps;
    }
  }

  MovementBests snapshot() => MovementBests(
    weight: weight,
    oneRm: oneRm,
    volume: volume,
    repsAtWeight: Map.unmodifiable(repsAtWeight),
  );
}
