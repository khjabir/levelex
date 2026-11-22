import 'dart:convert';

import '../models/lift_log.dart';
import 'csv_table.dart';
import 'exercise_matcher.dart';

/// Which app wrote the CSV being imported.
enum ImportSource { strong, hevy, fitnotes, generic }

/// What an import produced, plus the numbers a confirmation screen shows.
class ImportResult {
  const ImportResult({
    required this.source,
    this.entries = const [],
    this.bodyWeights = const [],
    this.rowsRead = 0,
    this.rowsSkipped = 0,
    this.unmatched = const {},
  });

  final ImportSource source;

  /// One entry per (workout, exercise), in file order.
  final List<LiftEntry> entries;

  /// Filled for a body-weight CSV (a date plus a weight column and no
  /// exercise column); one per day, the last row for a day wins.
  final List<BodyWeightEntry> bodyWeights;

  /// Data rows seen (the header excluded).
  final int rowsRead;

  /// Rows that produced nothing: no exercise, no date, or no numbers.
  final int rowsSkipped;

  /// Raw exercise names that became `custom:` ids → how many sets they hold.
  final Map<String, int> unmatched;

  bool get isEmpty => entries.isEmpty && bodyWeights.isEmpty;
  int get setCount => entries.fold(0, (sum, e) => sum + e.sets.length);
}

/// Turns Strong, Hevy, FitNotes or generic CSV exports (and an Apple Health
/// XML export) into lift and body-weight entries. Pure Dart; no I/O.
abstract final class LiftImporter {
  static const lbToKg = 0.45359237;

  /// Parses a CSV export. Never throws on bad rows: they are counted in
  /// [ImportResult.rowsSkipped].
  static ImportResult parseCsv(String text) {
    final table = CsvTable.parse(text);
    if (table.isEmpty) return const ImportResult(source: ImportSource.generic);
    final source = detect(table.normalizedHeaders);
    final cols = _Columns(table);
    // One file uses one date order. Deciding per row read MM/dd files as
    // dd/MM on every day 1-12 (03/04 became 3 April, 03/15 15 March).
    _dayFirst = _numericOrder(table, cols);
    if (cols.exercise == null && cols.date != null && cols.bodyWeight != null) {
      return _parseBodyWeights(table, cols);
    }
    if (cols.exercise == null ||
        (cols.date == null && cols.startTime == null)) {
      return ImportResult(
        source: source,
        rowsRead: table.rows.length,
        rowsSkipped: table.rows.length,
      );
    }
    final groups = <String, _Group>{};
    var skipped = 0;
    for (final row in table.rows) {
      final name = table.value(row, cols.exercise);
      final when = _when(table, cols, row);
      if (name == null || when == null) {
        skipped++;
        continue;
      }
      final key = groupKey(when, name);
      final group = groups.putIfAbsent(
        key,
        () => _Group(name: name, startTime: when),
      );
      final note = table.value(row, cols.note);
      if (note != null && group.note == null) group.note = note;

      final order = table.value(row, cols.setOrder)?.toLowerCase();
      if (order != null && !RegExp(r'^[0-9wdf]').hasMatch(order)) {
        // Strong writes "Rest Timer" / "Note" pseudo-rows with no set data.
        skipped++;
        continue;
      }
      final type = table.value(row, cols.setType)?.toLowerCase();
      final kg = _weightKg(table, cols, row);
      final reps = parseInt(table.value(row, cols.reps));
      final seconds = cols.durationSeconds != null
          ? parseInt(table.value(row, cols.durationSeconds))
          : parseDuration(table.value(row, cols.duration));
      if ((reps ?? 0) <= 0 && (seconds ?? 0) <= 0 && (kg ?? 0) <= 0) {
        skipped++;
        continue;
      }
      var rpe = parseNum(table.value(row, cols.rpe));
      final rir = parseNum(table.value(row, cols.rir));
      if (rpe == null && rir != null) rpe = (10 - rir).clamp(0, 10).toDouble();
      final warmUp =
          (type != null && type.contains('warm')) ||
          (order != null && order.startsWith('w'));
      group.sets.add(
        LiftSet(
          weightKg: kg ?? 0,
          reps: reps ?? 0,
          rpe: rpe,
          warmUp: warmUp,
          seconds: seconds != null && seconds > 0 ? seconds : null,
        ),
      );
    }
    final entries = <LiftEntry>[];
    final unmatched = <String, int>{};
    for (final e in groups.entries) {
      final g = e.value;
      if (g.sets.isEmpty) continue;
      final movementId = ExerciseMatcher.resolve(g.name);
      final custom = movementId.startsWith(LiftEntry.customPrefix);
      if (custom) {
        unmatched[g.name] = (unmatched[g.name] ?? 0) + g.sets.length;
      }
      entries.add(
        LiftEntry(
          id: entryId(source, e.key),
          movementId: movementId,
          customName: custom ? g.name : null,
          startTime: g.startTime,
          sets: List.unmodifiable(g.sets),
          note: g.note,
          source: LiftSource.import,
        ),
      );
    }
    return ImportResult(
      source: source,
      entries: entries,
      rowsRead: table.rows.length,
      rowsSkipped: skipped,
      unmatched: unmatched,
    );
  }

  /// Recognises the exporting app from normalised headers.
  static ImportSource detect(List<String> normalizedHeaders) {
    final h = normalizedHeaders.toSet();
    if (h.contains('exercise title') &&
        h.contains('set index') &&
        (h.contains('weight kg') || h.contains('weight lbs'))) {
      return ImportSource.hevy;
    }
    if (h.contains('workout name') &&
        h.contains('exercise name') &&
        h.contains('set order')) {
      return ImportSource.strong;
    }
    if (h.contains('exercise') &&
        h.contains('category') &&
        (h.contains('weight kgs') ||
            h.contains('weight lbs') ||
            h.contains('weight'))) {
      return ImportSource.fitnotes;
    }
    return ImportSource.generic;
  }

  /// Body-mass samples from an Apple Health `export.xml`, one per local day
  /// (the last sample of a day wins), sorted by date.
  static List<BodyWeightEntry> parseAppleHealth(String xml) {
    final byDay = <String, BodyWeightEntry>{};
    final record = RegExp(r'<Record\b([^>]*)>');
    final typeAttr = RegExp(r'\stype="([^"]*)"');
    final valueAttr = RegExp(r'\svalue="([^"]*)"');
    final unitAttr = RegExp(r'\sunit="([^"]*)"');
    final startAttr = RegExp(r'\sstartDate="(\d{4})-(\d{2})-(\d{2})');
    for (final m in record.allMatches(xml)) {
      final attrs = m.group(1)!;
      if (typeAttr.firstMatch(attrs)?.group(1) !=
          'HKQuantityTypeIdentifierBodyMass') {
        continue;
      }
      final value = double.tryParse(
        valueAttr.firstMatch(attrs)?.group(1) ?? '',
      );
      final start = startAttr.firstMatch(attrs);
      if (value == null || start == null) continue;
      final unit = (unitAttr.firstMatch(attrs)?.group(1) ?? 'kg').toLowerCase();
      final kg = switch (unit) {
        'lb' || 'lbs' => value * lbToKg,
        'g' => value / 1000,
        _ => value,
      };
      final date = DateTime(
        int.parse(start.group(1)!),
        int.parse(start.group(2)!),
        int.parse(start.group(3)!),
      );
      final entry = BodyWeightEntry(date: date, kg: _round(kg));
      byDay[entry.key] = entry;
    }
    return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  // ---------------------------------------------------------------------
  // Ids
  // ---------------------------------------------------------------------

  /// The grouping key for one exercise in one workout:
  /// `yyyy-MM-ddTHH:mm|<normalised exercise>`.
  static String groupKey(DateTime when, String exercise) =>
      '${BodyWeightEntry.dayKey(when)}T${_two(when.hour)}:${_two(when.minute)}'
      '|${CsvTable.normalizeHeader(exercise)}';

  /// `import:<source>:<16 hex>`; the same workout and exercise always yield
  /// the same id so a second import of the same file replaces, never
  /// duplicates.
  static String entryId(ImportSource source, String groupKey) =>
      'import:${source.name}:${fnv1a64(groupKey)}';

  /// FNV-1a 64-bit hash of the UTF-8 bytes of [input], as 16 hex digits.
  static String fnv1a64(String input) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(input)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    final hi = (h >>> 32) & 0xffffffff;
    final lo = h & 0xffffffff;
    return '${hi.toRadixString(16).padLeft(8, '0')}'
        '${lo.toRadixString(16).padLeft(8, '0')}';
  }

  // ---------------------------------------------------------------------
  // Value parsing
  // ---------------------------------------------------------------------

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static final _hevyDate = RegExp(
    r'^(\d{1,2})\s+([a-z]{3,9})\.?\s+(\d{4})'
    r'(?:,?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]m)?)?$',
  );
  static final _monthFirstDate = RegExp(
    r'^([a-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})'
    r'(?:,?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]m)?)?$',
  );
  static final _numericDate = RegExp(
    r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})'
    r'(?:[ ,t]+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]m)?)?$',
  );
  static final _yearFirstDate = RegExp(
    r'^(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})'
    r'(?:[ t]+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]m)?)?$',
  );
  static final _timeOnly = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]m)?$',
  );

  /// Local date-time from the formats the supported apps write:
  /// `yyyy-MM-dd[ HH:mm[:ss]]`, ISO 8601 (T, Z or an offset → converted to
  /// local), Hevy's `5 Jan 2024, 18:30`, `Jan 5, 2024`, `dd/MM/yyyy` and
  /// `MM/dd/yyyy` (by value; `dd/MM` when both fit), `yyyy/MM/dd`.
  static DateTime? parseDateTime(String? raw, {bool? dayFirst}) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
      final iso = DateTime.tryParse(s.toUpperCase());
      if (iso != null) return iso.isUtc ? iso.toLocal() : iso;
    }
    var m = _hevyDate.firstMatch(s);
    if (m != null) {
      final month = _month(m.group(2)!);
      if (month == null) return null;
      return _build(m.group(3), month, m.group(1), m, 4);
    }
    m = _monthFirstDate.firstMatch(s);
    if (m != null) {
      final month = _month(m.group(1)!);
      if (month == null) return null;
      return _build(m.group(3), month, m.group(2), m, 4);
    }
    m = _numericDate.firstMatch(s);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      final order = a > 12
          ? true
          : b > 12
          ? false
          : (dayFirst ?? _dayFirst ?? true);
      final day = order ? a : b;
      final month = order ? b : a;
      return _build(m.group(3), month, '$day', m, 4);
    }
    m = _yearFirstDate.firstMatch(s);
    if (m != null) {
      return _build(m.group(1), int.parse(m.group(2)!), m.group(3), m, 4);
    }
    return null;
  }

  /// The numeric date order of the file being parsed (null: unknown, so
  /// day-first), set by [parseCsv].
  static bool? _dayFirst;

  /// Day-first (true) or month-first (false) from any date in the file
  /// whose first or second number is above 12; null when none decides.
  static bool? _numericOrder(CsvTable table, _Columns cols) {
    var dayFirst = 0, monthFirst = 0;
    for (final row in table.rows) {
      for (final c in [cols.date, cols.startTime]) {
        final raw = table.value(row, c)?.trim().toLowerCase();
        if (raw == null) continue;
        final m = _numericDate.firstMatch(raw);
        if (m == null) continue;
        if (int.parse(m.group(1)!) > 12) dayFirst++;
        if (int.parse(m.group(2)!) > 12) monthFirst++;
      }
    }
    if (dayFirst == monthFirst) return null;
    return dayFirst > monthFirst;
  }

  /// Seconds from `h:mm:ss`, `mm:ss`, `45s`, `1m 30s`, `1h 5m` or a plain
  /// number of seconds.
  static int? parseDuration(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.contains(':')) {
      final parts = s.split(':');
      if (parts.length < 2 || parts.length > 3) return null;
      var total = 0.0;
      for (final p in parts) {
        final v = double.tryParse(p.trim());
        if (v == null) return null;
        total = total * 60 + v;
      }
      return total.round();
    }
    final plain = parseNum(s);
    if (plain != null) return plain.round();
    final h = RegExp(r'(\d+(?:\.\d+)?)\s*h').firstMatch(s);
    final min = RegExp(r'(\d+(?:\.\d+)?)\s*m(?!s)').firstMatch(s);
    final sec = RegExp(r'(\d+(?:\.\d+)?)\s*s').firstMatch(s);
    if (h == null && min == null && sec == null) return null;
    final total =
        (h == null ? 0 : double.parse(h.group(1)!) * 3600) +
        (min == null ? 0 : double.parse(min.group(1)!) * 60) +
        (sec == null ? 0 : double.parse(sec.group(1)!));
    return total.round();
  }

  /// A number with either decimal separator and an optional trailing unit
  /// (`82,5`, `20 kg`, `135lbs`).
  static double? parseNum(String? raw) {
    if (raw == null) return null;
    var s = raw.trim().toLowerCase().replaceAll(RegExp(r'[a-z%]+$'), '').trim();
    if (s.isEmpty || s == '-') return null;
    if (s.contains(',') && !s.contains('.')) s = s.replaceAll(',', '.');
    s = s.replaceAll(',', '');
    return double.tryParse(s);
  }

  static int? parseInt(String? raw) => parseNum(raw)?.round();

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  static ImportResult _parseBodyWeights(CsvTable table, _Columns cols) {
    final byDay = <String, BodyWeightEntry>{};
    var skipped = 0;
    for (final row in table.rows) {
      final when = parseDateTime(table.value(row, cols.date));
      var kg = parseNum(table.value(row, cols.bodyWeight));
      if (when == null || kg == null || kg <= 0) {
        skipped++;
        continue;
      }
      if (cols.bodyWeightInLb ||
          (table.value(row, cols.weightUnit)?.toLowerCase().startsWith('lb') ??
              false)) {
        kg *= lbToKg;
      }
      final entry = BodyWeightEntry(
        date: DateTime(when.year, when.month, when.day),
        kg: _round(kg),
        note: table.value(row, cols.note),
      );
      byDay[entry.key] = entry;
    }
    return ImportResult(
      source: ImportSource.generic,
      bodyWeights: byDay.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
      rowsRead: table.rows.length,
      rowsSkipped: skipped,
    );
  }

  /// The row's moment: the start-time column when it carries a date, a
  /// time-only start combined with the date column, else the date column.
  static DateTime? _when(CsvTable table, _Columns cols, List<String> row) {
    final dateRaw = table.value(row, cols.date);
    final startRaw = table.value(row, cols.startTime);
    final date = parseDateTime(dateRaw);
    if (startRaw == null) return date;
    final t = _timeOnly.firstMatch(startRaw.trim().toLowerCase());
    if (t != null) {
      if (date == null) return null;
      return DateTime(
        date.year,
        date.month,
        date.day,
        _hour(int.parse(t.group(1)!), t.group(4)),
        int.parse(t.group(2)!),
        int.tryParse(t.group(3) ?? '') ?? 0,
      );
    }
    return parseDateTime(startRaw) ?? date;
  }

  static double? _weightKg(CsvTable table, _Columns cols, List<String> row) {
    if (cols.weightKg != null) return parseNum(table.value(row, cols.weightKg));
    if (cols.weightLb != null) {
      final lb = parseNum(table.value(row, cols.weightLb));
      return lb == null ? null : _round(lb * lbToKg);
    }
    final w = parseNum(table.value(row, cols.weight));
    if (w == null) return null;
    final unit = table.value(row, cols.weightUnit)?.toLowerCase();
    return unit != null && unit.startsWith('lb') ? _round(w * lbToKg) : w;
  }

  static int? _month(String name) =>
      _months[name.length > 3 ? name.substring(0, 3) : name];

  static DateTime? _build(
    String? year,
    int month,
    String? day,
    RegExpMatch m,
    int timeGroup,
  ) {
    final y = int.tryParse(year ?? '');
    final d = int.tryParse(day ?? '');
    if (y == null || d == null || month < 1 || month > 12 || d < 1 || d > 31) {
      return null;
    }
    final hour = int.tryParse(m.group(timeGroup) ?? '');
    final minute = int.tryParse(m.group(timeGroup + 1) ?? '') ?? 0;
    final second = int.tryParse(m.group(timeGroup + 2) ?? '') ?? 0;
    final ampm = m.group(timeGroup + 3);
    return DateTime(
      y,
      month,
      d,
      hour == null ? 0 : _hour(hour, ampm),
      minute,
      second,
    );
  }

  static int _hour(int hour, String? ampm) {
    if (ampm == null) return hour;
    if (ampm == 'pm' && hour < 12) return hour + 12;
    if (ampm == 'am' && hour == 12) return 0;
    return hour;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Two decimals: enough for any scale, and keeps lb conversions tidy.
  static double _round(double v) => (v * 100).roundToDouble() / 100;
}

/// Resolved column indexes for one table.
class _Columns {
  _Columns(CsvTable t)
    : exercise = t.column(const [
        'exercise',
        'exercise name',
        'exercise title',
      ]),
      date = t.column(const ['date', 'workout date']),
      startTime = t.column(const ['start time', 'start date']),
      weightKg = t.column(const ['weight kg', 'weight kgs']),
      weightLb = t.column(const ['weight lbs', 'weight lb']),
      weight = t.column(const ['weight']),
      weightUnit = t.column(const ['weight unit', 'unit']),
      reps = t.column(const ['reps', 'repetitions']),
      rpe = t.column(const ['rpe', 'rpe rating']),
      rir = t.column(const ['rir', 'reps in reserve']),
      durationSeconds = t.column(const [
        'seconds',
        'duration seconds',
        'set duration sec',
      ]),
      duration = t.column(const ['time', 'duration']),
      setType = t.column(const ['set type']),
      setOrder = t.column(const ['set order', 'set index']),
      note = t.column(const [
        'comment',
        'comments',
        'notes',
        'note',
        'exercise notes',
      ]),
      bodyWeight = t.column(const [
        'bodyweight kg',
        'body weight kg',
        'bodyweight',
        'body weight',
        'weight kg',
        'weight kgs',
        'weight',
        'bodyweight lbs',
        'body weight lbs',
        'weight lbs',
        'weight lb',
      ]),
      bodyWeightInLb =
          t.column(const [
                'bodyweight kg',
                'body weight kg',
                'bodyweight',
                'body weight',
                'weight kg',
                'weight kgs',
                'weight',
              ]) ==
              null &&
          t.column(const [
                'bodyweight lbs',
                'body weight lbs',
                'weight lbs',
                'weight lb',
              ]) !=
              null;

  final int? exercise;
  final int? date;
  final int? startTime;
  final int? weightKg;
  final int? weightLb;
  final int? weight;
  final int? weightUnit;
  final int? reps;
  final int? rpe;
  final int? rir;
  final int? durationSeconds;
  final int? duration;
  final int? setType;
  final int? setOrder;
  final int? note;
  final int? bodyWeight;
  final bool bodyWeightInLb;
}

class _Group {
  _Group({required this.name, required this.startTime});

  final String name;
  final DateTime startTime;
  final List<LiftSet> sets = [];
  String? note;
}
