/// A parsed delimiter-separated table: one header row plus data rows.
///
/// Implements RFC 4180: quoted fields, doubled quotes inside a quoted field,
/// embedded line breaks, CRLF or LF (or bare CR) record ends, an optional
/// UTF-8 byte-order mark, and auto-detection of `,` / `;` / tab from the
/// header line. Rows are kept exactly as read; use [value] to read a cell
/// safely when a row is shorter than the header.
class CsvTable {
  CsvTable({required this.headers, required this.rows})
    : normalizedHeaders = [for (final h in headers) normalizeHeader(h)];

  /// Header cells as written (trimmed).
  final List<String> headers;

  /// [headers] passed through [normalizeHeader], in the same order.
  final List<String> normalizedHeaders;

  /// Data rows (the header excluded). Blank lines are dropped.
  final List<List<String>> rows;

  bool get isEmpty => headers.isEmpty;

  /// Parses [text]. When [delimiter] is null it is detected from the header
  /// line (`,` wins ties, then `;`, then tab).
  static CsvTable parse(String text, {String? delimiter}) {
    var s = text;
    if (s.startsWith('﻿')) s = s.substring(1);
    final delim = delimiter ?? detectDelimiter(_headerLine(s));
    final records = _records(s, delim);
    final kept = [
      for (final r in records)
        if (r.length > 1 || (r.isNotEmpty && r.first.trim().isNotEmpty)) r,
    ];
    if (kept.isEmpty) return CsvTable(headers: const [], rows: const []);
    return CsvTable(
      headers: [for (final h in kept.first) h.trim()],
      rows: kept.sublist(1),
    );
  }

  /// Picks the most frequent of `,` / `;` / tab outside quotes in
  /// [headerLine]; `,` when nothing is found.
  static String detectDelimiter(String headerLine) {
    var comma = 0, semi = 0, tab = 0;
    var inQuotes = false;
    for (var i = 0; i < headerLine.length; i++) {
      final c = headerLine[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes) {
        if (c == ',') {
          comma++;
        } else if (c == ';') {
          semi++;
        } else if (c == '\t') {
          tab++;
        }
      }
    }
    if (semi > comma && semi >= tab) return ';';
    if (tab > comma && tab > semi) return '\t';
    return ',';
  }

  /// Lower-case, trimmed, punctuation replaced by spaces and whitespace
  /// collapsed: `"Weight (kgs)"` becomes `"weight kgs"`, `"set_index"`
  /// becomes `"set index"`.
  static String normalizeHeader(String header) =>
      header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Index of the first header matching any of [candidates] (candidates are
  /// tried in order and compared after [normalizeHeader]); null when none.
  int? column(List<String> candidates) {
    for (final c in candidates) {
      final i = normalizedHeaders.indexOf(normalizeHeader(c));
      if (i >= 0) return i;
    }
    return null;
  }

  /// The trimmed cell at [col] in [row], or null when [col] is null, out of
  /// range or the cell is blank.
  String? value(List<String> row, int? col) {
    if (col == null || col < 0 || col >= row.length) return null;
    final v = row[col].trim();
    return v.isEmpty ? null : v;
  }

  /// The first line of [text] (quotes respected), used for delimiter
  /// detection.
  static String _headerLine(String text) {
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && (c == '\n' || c == '\r')) {
        return text.substring(0, i);
      }
    }
    return text;
  }

  static List<List<String>> _records(String s, String delim) {
    final out = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var fieldStart = true;
    final n = s.length;
    var i = 0;
    while (i < n) {
      final c = s[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < n && s[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
        } else {
          field.write(c);
        }
        i++;
        continue;
      }
      if (c == '"' && fieldStart) {
        inQuotes = true;
        fieldStart = false;
        i++;
        continue;
      }
      if (c == delim) {
        row.add(field.toString());
        field.clear();
        fieldStart = true;
        i++;
        continue;
      }
      if (c == '\r' || c == '\n') {
        if (c == '\r' && i + 1 < n && s[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        out.add(row);
        row = <String>[];
        fieldStart = true;
        i++;
        continue;
      }
      field.write(c);
      fieldStart = false;
      i++;
    }
    if (field.isNotEmpty || row.isNotEmpty || !fieldStart) {
      row.add(field.toString());
      out.add(row);
    }
    return out;
  }
}
