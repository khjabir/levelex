import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/strength/logic/lift_importer.dart';
import 'package:levelex/features/strength/models/lift_log.dart';

const strongCsv = '''
Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
2024-01-05 18:30:00,Push Day,1h 5m,Bench Press (Barbell),W,40,10,0,0,,,
2024-01-05 18:30:00,Push Day,1h 5m,Bench Press (Barbell),1,60,8,0,0,Felt strong,,8
2024-01-05 18:30:00,Push Day,1h 5m,Bench Press (Barbell),2,60,8,0,0,,,8.5
2024-01-05 18:30:00,Push Day,1h 5m,Bench Press (Barbell),Rest Timer,0,0,0,90,,,
2024-01-05 18:30:00,Push Day,1h 5m,Plank,1,0,0,0,45,,,
2024-01-05 18:30:00,Push Day,1h 5m,Cable Woodchop,1,20,12,0,0,,,
2024-01-05 18:30:00,Push Day,1h 5m,Cable Woodchop,2,20,12,0,0,,,
2024-01-07 09:00:00,Legs,45m,Squat (Barbell),1,80,5,0,0,,,
''';

const hevyCsv = '''
title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
"Pull Day","5 Jan 2024, 18:30","5 Jan 2024, 19:20","","Lat Pulldown (Cable)","","Go slow",0,warmup,30,12,"","",""
"Pull Day","5 Jan 2024, 18:30","5 Jan 2024, 19:20","","Lat Pulldown (Cable)","","Go slow",1,normal,50,10,"","",8
"Pull Day","5 Jan 2024, 18:30","5 Jan 2024, 19:20","","Lat Pulldown (Cable)","","Go slow",2,failure,50,9,"","",9
"Pull Day","5 Jan 2024, 18:30","5 Jan 2024, 19:20","","Plank","","",0,normal,"",0,"",60,""
"Push Day","6 Jan 2024, 07:15","6 Jan 2024, 08:00","","Bench Press (Dumbbell)","","",0,normal,24,10,"","",""
''';

const fitnotesCsv = '''
Date,Exercise,Category,Weight (lbs),Reps,Distance,Distance Unit,Time,Comment
2024-01-05,Flat Barbell Bench Press,Chest,135,5,,,,
2024-01-05,Flat Barbell Bench Press,Chest,135,5,,,,PR!
2024-01-05,Plank,Abs,0,0,,,0:01:00,
2024-01-06,Running,Cardio,0,0,5,km,0:30:00,
''';

const genericCsv = '''
workout name,exercise,date,weight kg,reps
Morning,Push Up,2024-02-01,0,20
Morning,Push Up,2024-02-01,0,18
Evening,Kettlebell Swing,01/02/2024,16,15
''';

const genericSemicolonCsv = '''
Date;Exercise;Weight;Weight Unit;Reps;RIR
2024-03-01 07:00;Deadlift;100,5;kg;5;2
2024-03-01 07:00;Deadlift;225;lbs;5;1
''';

const bodyWeightCsv = '''
Date,Weight (kg),Note
2024-01-01,82.5,
2024-01-01,82.1,evening
2024-01-02,81.9,
''';

const appleHealthXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<HealthData locale="en_GB">
 <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Watch" unit="count/min" creationDate="2024-01-05 08:00:00 +0000" startDate="2024-01-05 08:00:00 +0000" endDate="2024-01-05 08:00:00 +0000" value="62"/>
 <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Health" unit="kg" creationDate="2024-01-05 07:30:00 +0000" startDate="2024-01-05 07:30:00 +0000" endDate="2024-01-05 07:30:00 +0000" value="82.5"/>
 <Record sourceName="Health" unit="kg" value="82.1" type="HKQuantityTypeIdentifierBodyMass" startDate="2024-01-05 21:00:00 +0000" endDate="2024-01-05 21:00:00 +0000" creationDate="2024-01-05 21:00:00 +0000"/>
 <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Scale" unit="lb" creationDate="2024-01-06 07:30:00 +0000" startDate="2024-01-06 07:30:00 +0000" endDate="2024-01-06 07:30:00 +0000" value="180">
  <MetadataEntry key="HKWasUserEntered" value="1"/>
 </Record>
</HealthData>
''';

final importId = RegExp(
  r'^import:(strong|hevy|fitnotes|generic):[0-9a-f]{16}$',
);

void main() {
  group('LiftImporter.detect', () {
    test('recognises each app from its headers', () {
      expect(
        LiftImporter.detect(['exercise title', 'weight kg', 'set index']),
        ImportSource.hevy,
      );
      expect(
        LiftImporter.detect(['workout name', 'exercise name', 'set order']),
        ImportSource.strong,
      );
      expect(
        LiftImporter.detect(['exercise', 'category', 'weight kgs']),
        ImportSource.fitnotes,
      );
      expect(
        LiftImporter.detect(['exercise', 'category', 'weight lbs']),
        ImportSource.fitnotes,
      );
      expect(
        LiftImporter.detect(['exercise', 'date', 'weight kg', 'reps']),
        ImportSource.generic,
      );
    });
  });

  group('Strong export', () {
    final result = LiftImporter.parseCsv(strongCsv);

    test('is detected and grouped per workout and exercise', () {
      expect(result.source, ImportSource.strong);
      expect(result.entries.map((e) => e.movementId), [
        'bb_bench_press',
        'plank',
        'custom:cable-woodchop',
        'bb_back_squat',
      ]);
      expect(result.rowsRead, 8);
      expect(result.rowsSkipped, 1, reason: 'the Rest Timer pseudo-row');
      expect(result.setCount, 7);
    });

    test('keeps set order, warm-up flags, rpe and the first note', () {
      final bench = result.entries.first;
      expect(bench.startTime, DateTime(2024, 1, 5, 18, 30));
      expect(bench.source, LiftSource.import);
      expect(bench.customName, isNull);
      expect(bench.note, 'Felt strong');
      expect(bench.sets.length, 3);
      expect(bench.sets[0].warmUp, isTrue);
      expect(bench.sets[0].weightKg, 40);
      expect(bench.sets[0].reps, 10);
      expect(bench.sets[1].warmUp, isFalse);
      expect(bench.sets[1].rpe, 8);
      expect(bench.sets[2].rpe, 8.5);
      expect(
        bench.sets.every((s) => s.seconds == null),
        isTrue,
        reason: 'the workout Duration column is not a set duration',
      );
      expect(bench.workSets.length, 2);
    });

    test('timed rows become seconds and unknown names become custom', () {
      final plank = result.entries[1];
      expect(plank.sets.single.seconds, 45);
      expect(plank.sets.single.reps, 0);

      final chop = result.entries[2];
      expect(chop.isCustom, isTrue);
      expect(chop.customName, 'Cable Woodchop');
      expect(chop.sets.length, 2);
      expect(result.unmatched, {'Cable Woodchop': 2});

      expect(result.entries[3].startTime, DateTime(2024, 1, 7, 9));
    });

    test('ids are stable across re-imports and unique per entry', () {
      for (final e in result.entries) {
        expect(e.id, matches(importId));
        expect(e.id, startsWith('import:strong:'));
      }
      final again = LiftImporter.parseCsv(strongCsv);
      expect(
        again.entries.map((e) => e.id).toList(),
        result.entries.map((e) => e.id).toList(),
      );
      expect(result.entries.map((e) => e.id).toSet().length, 4);
    });
  });

  group('Hevy export', () {
    final result = LiftImporter.parseCsv(hevyCsv);

    test('is detected, parses the Hevy date and groups by start time', () {
      expect(result.source, ImportSource.hevy);
      expect(result.entries.length, 3);
      expect(result.rowsSkipped, 0);
      final pulldown = result.entries.first;
      expect(pulldown.movementId, 'pull_up');
      expect(pulldown.startTime, DateTime(2024, 1, 5, 18, 30));
      expect(pulldown.note, 'Go slow');
      expect(pulldown.id, startsWith('import:hevy:'));
    });

    test('warmup set type flags warm-ups; failure sets stay work sets', () {
      final sets = result.entries.first.sets;
      expect(sets.length, 3);
      expect(sets[0].warmUp, isTrue);
      expect(sets[1].warmUp, isFalse);
      expect(sets[2].warmUp, isFalse);
      expect(sets[2].rpe, 9);
      expect(sets[2].reps, 9);
    });

    test('duration_seconds becomes a timed set', () {
      final plank = result.entries[1];
      expect(plank.movementId, 'plank');
      expect(plank.sets.single.seconds, 60);
    });

    test('a second workout on another day is a separate entry', () {
      final bench = result.entries[2];
      expect(bench.startTime, DateTime(2024, 1, 6, 7, 15));
      expect(bench.movementId, 'bb_bench_press');
      expect(bench.sets.single.weightKg, 24);
    });
  });

  group('FitNotes export', () {
    final result = LiftImporter.parseCsv(fitnotesCsv);

    test('is detected and converts pounds to kilograms', () {
      expect(result.source, ImportSource.fitnotes);
      expect(result.entries.length, 3);
      final bench = result.entries.first;
      expect(bench.movementId, 'bb_bench_press');
      expect(bench.startTime, DateTime(2024, 1, 5));
      expect(bench.sets.length, 2);
      expect(bench.sets.first.weightKg, closeTo(61.23, 0.01));
      expect(bench.note, 'PR!');
      expect(bench.id, startsWith('import:fitnotes:'));
    });

    test('parses h:mm:ss time columns', () {
      expect(result.entries[1].movementId, 'plank');
      expect(result.entries[1].sets.single.seconds, 60);
      expect(result.entries[2].movementId, 'treadmill');
      expect(result.entries[2].sets.single.seconds, 1800);
    });
  });

  group('generic CSV', () {
    test('minimal columns work and dd/MM dates are read', () {
      final result = LiftImporter.parseCsv(genericCsv);
      expect(result.source, ImportSource.generic);
      expect(result.entries.length, 2);
      final pushUps = result.entries.first;
      expect(pushUps.movementId, 'push_up');
      expect(pushUps.sets.map((s) => s.reps), [20, 18]);
      expect(pushUps.startTime, DateTime(2024, 2, 1));
      final swings = result.entries[1];
      expect(swings.movementId, 'kb_swing');
      expect(swings.startTime, DateTime(2024, 2, 1));
      expect(swings.sets.single.weightKg, 16);
      expect(result.unmatched, isEmpty);
    });

    test('semicolons, decimal commas, per-row units and RIR', () {
      final result = LiftImporter.parseCsv(genericSemicolonCsv);
      expect(result.entries.length, 1);
      final dl = result.entries.single;
      expect(dl.movementId, 'bb_deadlift');
      expect(dl.startTime, DateTime(2024, 3, 1, 7));
      expect(dl.sets[0].weightKg, 100.5);
      expect(dl.sets[1].weightKg, closeTo(102.06, 0.01));
      expect(dl.sets[0].rpe, 8);
      expect(dl.sets[1].rpe, 9);
    });

    test('rows without an exercise, date or numbers are skipped', () {
      final result = LiftImporter.parseCsv(
        'exercise,date,weight kg,reps\n'
        ',2024-01-01,50,5\n'
        'Squat,,50,5\n'
        'Squat,2024-01-01,,\n'
        'Squat,2024-01-01,0,0\n'
        'Squat,2024-01-01,50,5\n',
      );
      expect(result.rowsRead, 5);
      expect(result.rowsSkipped, 4);
      expect(result.entries.single.sets.length, 1);
    });

    test('a file with no usable columns imports nothing', () {
      final result = LiftImporter.parseCsv('foo,bar\n1,2\n');
      expect(result.isEmpty, isTrue);
      expect(result.rowsRead, 1);
      expect(result.rowsSkipped, 1);
      expect(LiftImporter.parseCsv('').isEmpty, isTrue);
    });
  });

  group('body weight CSV', () {
    test('one entry per day, last row wins', () {
      final result = LiftImporter.parseCsv(bodyWeightCsv);
      expect(result.entries, isEmpty);
      expect(result.bodyWeights.length, 2);
      expect(result.bodyWeights[0].date, DateTime(2024, 1, 1));
      expect(result.bodyWeights[0].kg, 82.1);
      expect(result.bodyWeights[0].note, 'evening');
      expect(result.bodyWeights[1].kg, 81.9);
      expect(result.rowsRead, 3);
    });

    test('pound columns are converted', () {
      final result = LiftImporter.parseCsv(
        'date,body weight lbs\n2024-01-03,180\n',
      );
      expect(result.bodyWeights.single.kg, closeTo(81.65, 0.01));
    });
  });

  group('Apple Health', () {
    test('reads body mass records with attributes in any order', () {
      final weights = LiftImporter.parseAppleHealth(appleHealthXml);
      expect(weights.length, 2);
      expect(weights[0].date, DateTime(2024, 1, 5));
      expect(weights[0].kg, 82.1, reason: 'last sample of the day wins');
      expect(weights[1].date, DateTime(2024, 1, 6));
      expect(weights[1].kg, closeTo(81.65, 0.01));
    });

    test('ignores text without records', () {
      expect(LiftImporter.parseAppleHealth('<HealthData/>'), isEmpty);
    });
  });

  group('value parsing', () {
    test('dates in every supported shape', () {
      expect(LiftImporter.parseDateTime('2024-01-05'), DateTime(2024, 1, 5));
      expect(
        LiftImporter.parseDateTime('2024-01-05 18:30:00'),
        DateTime(2024, 1, 5, 18, 30),
      );
      expect(
        LiftImporter.parseDateTime('2024-01-05 18:30'),
        DateTime(2024, 1, 5, 18, 30),
      );
      expect(
        LiftImporter.parseDateTime('2024-01-05T18:30:00Z'),
        DateTime.parse('2024-01-05T18:30:00Z').toLocal(),
      );
      expect(
        LiftImporter.parseDateTime('5 Jan 2024, 18:30'),
        DateTime(2024, 1, 5, 18, 30),
      );
      expect(LiftImporter.parseDateTime('5 Jan 2024'), DateTime(2024, 1, 5));
      expect(
        LiftImporter.parseDateTime('Jan 5, 2024 6:30 PM'),
        DateTime(2024, 1, 5, 18, 30),
      );
      expect(LiftImporter.parseDateTime('13/02/2024'), DateTime(2024, 2, 13));
      expect(LiftImporter.parseDateTime('02/13/2024'), DateTime(2024, 2, 13));
      expect(LiftImporter.parseDateTime('05/02/2024'), DateTime(2024, 2, 5));
      expect(
        LiftImporter.parseDateTime('05/02/2024 07:15'),
        DateTime(2024, 2, 5, 7, 15),
      );
      expect(LiftImporter.parseDateTime('2024/02/05'), DateTime(2024, 2, 5));
      expect(LiftImporter.parseDateTime('5.2.2024'), DateTime(2024, 2, 5));
      expect(LiftImporter.parseDateTime('yesterday'), isNull);
      expect(LiftImporter.parseDateTime('31/31/2024'), isNull);
      expect(LiftImporter.parseDateTime(null), isNull);
    });

    test('durations', () {
      expect(LiftImporter.parseDuration('45s'), 45);
      expect(LiftImporter.parseDuration('1:30'), 90);
      expect(LiftImporter.parseDuration('0:01:00'), 60);
      expect(LiftImporter.parseDuration('1m 30s'), 90);
      expect(LiftImporter.parseDuration('1h 5m'), 3900);
      expect(LiftImporter.parseDuration('90'), 90);
      expect(LiftImporter.parseDuration('abc'), isNull);
      expect(LiftImporter.parseDuration(''), isNull);
    });

    test('numbers with units and either decimal separator', () {
      expect(LiftImporter.parseNum('82,5'), 82.5);
      expect(LiftImporter.parseNum('20 kg'), 20);
      expect(LiftImporter.parseNum('135lbs'), 135);
      expect(LiftImporter.parseNum('1,234.5'), 1234.5);
      expect(LiftImporter.parseNum('-'), isNull);
      expect(LiftImporter.parseInt('10.0'), 10);
    });

    test('FNV-1a 64 matches the reference vector', () {
      expect(LiftImporter.fnv1a64('abc'), 'e71fa2190541574b');
      expect(LiftImporter.fnv1a64(''), 'cbf29ce484222325');
    });
  });
}
