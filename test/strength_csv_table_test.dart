import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/csv_table.dart';

void main() {
  group('CsvTable.parse', () {
    test('splits a plain comma file into headers and rows', () {
      final t = CsvTable.parse('a,b,c\n1,2,3\n4,5,6\n');
      expect(t.headers, ['a', 'b', 'c']);
      expect(t.rows, [
        ['1', '2', '3'],
        ['4', '5', '6'],
      ]);
    });

    test('handles quoted fields, doubled quotes and embedded newlines', () {
      final t = CsvTable.parse(
        'name,note\n"Bench Press, flat","He said ""go""\nthen left"\n',
      );
      expect(t.rows.single, ['Bench Press, flat', 'He said "go"\nthen left']);
    });

    test('accepts CRLF endings and a UTF-8 BOM', () {
      final t = CsvTable.parse('﻿Date,Reps\r\n2024-01-05,10\r\n');
      expect(t.headers, ['Date', 'Reps']);
      expect(t.rows, [
        ['2024-01-05', '10'],
      ]);
    });

    test('keeps a last row that has no trailing newline', () {
      final t = CsvTable.parse('a,b\n1,2\n3,');
      expect(t.rows, [
        ['1', '2'],
        ['3', ''],
      ]);
    });

    test('drops blank lines', () {
      final t = CsvTable.parse('a,b\n\n1,2\n\n\n3,4\n');
      expect(t.rows.length, 2);
    });

    test('detects semicolons and tabs from the header line', () {
      final semi = CsvTable.parse('Date;Weight (kg);Reps\n2024-01-05;82,5;5\n');
      expect(semi.headers, ['Date', 'Weight (kg)', 'Reps']);
      expect(semi.rows.single, ['2024-01-05', '82,5', '5']);

      final tab = CsvTable.parse('Date\tReps\n2024-01-05\t5\n');
      expect(tab.headers, ['Date', 'Reps']);
      expect(tab.rows.single, ['2024-01-05', '5']);
    });

    test('ignores delimiters inside quotes when detecting', () {
      final t = CsvTable.parse('"a;b;c;d",x\n1,2\n');
      expect(t.headers, ['a;b;c;d', 'x']);
    });

    test('an explicit delimiter overrides detection', () {
      final t = CsvTable.parse('a|b\n1|2\n', delimiter: '|');
      expect(t.headers, ['a', 'b']);
      expect(t.rows.single, ['1', '2']);
    });

    test('empty input yields an empty table', () {
      expect(CsvTable.parse('').isEmpty, isTrue);
      expect(CsvTable.parse('\n\n').isEmpty, isTrue);
    });
  });

  group('CsvTable.normalizeHeader', () {
    test('lower-cases, strips punctuation and collapses spaces', () {
      expect(CsvTable.normalizeHeader('Weight (kgs)'), 'weight kgs');
      expect(CsvTable.normalizeHeader('  Set_Index '), 'set index');
      expect(CsvTable.normalizeHeader('Exercise   Name'), 'exercise name');
      expect(CsvTable.normalizeHeader('RPE'), 'rpe');
      expect(CsvTable.normalizeHeader('duration_seconds'), 'duration seconds');
    });
  });

  group('CsvTable.column / value', () {
    final t = CsvTable.parse(
      'Date,Exercise Name,Weight (kg),Notes,Note\n2024-01-05,Bench,60,,x\n',
    );

    test('returns the first candidate that exists', () {
      expect(t.column(['exercise', 'exercise name']), 1);
      expect(t.column(['weight kg', 'weight kgs']), 2);
      expect(t.column(['note', 'notes']), 4);
      expect(t.column(['notes', 'note']), 3);
      expect(t.column(['missing']), isNull);
    });

    test('value is null for a missing column, out of range or blank', () {
      final row = t.rows.single;
      expect(t.value(row, 1), 'Bench');
      expect(t.value(row, null), isNull);
      expect(t.value(row, 3), isNull);
      expect(t.value(row, 9), isNull);
      expect(t.value(const ['only'], 1), isNull);
    });
  });
}
