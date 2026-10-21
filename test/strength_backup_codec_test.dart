import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/challenge/models/challenge.dart';
import 'package:levelex/features/pt/models/equipment.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/strength/logic/backup_codec.dart';
import 'package:levelex/features/strength/models/lift_log.dart';
import 'package:levelex/features/strength/models/progression_rule.dart';
import 'package:levelex/features/strength/models/routine.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/form_status.dart';
import 'package:levelex/models/user_settings.dart';
import 'package:levelex/models/workout_session.dart';

const ana = ChallengePlayer(id: 'p1', name: 'Ana', photoPath: '/tmp/ana.jpg');
const ben = ChallengePlayer(id: 'p2', name: 'Ben');

BackupBundle sample() => BackupBundle(
  exportedAt: DateTime(2026, 10, 21, 9, 30),
  sessions: [
    WorkoutSession(
      id: 's1',
      startTime: DateTime(2026, 10, 14, 7),
      endTime: DateTime(2026, 10, 14, 7, 2),
      targetReps: 20,
      completedReps: 20,
      status: SessionStatus.completed,
      formScore: 0.9,
      exercise: ExerciseType.squat,
      mistakes: const {FormStatus.goDeeper: 1},
    ),
  ],
  ptRecords: [
    PtRecord(
      id: 'pt1',
      startTime: DateTime(2026, 10, 14, 8),
      endTime: DateTime(2026, 10, 14, 8, 30),
      mode: WorkoutMode.push,
      plannedMinutes: 30,
      items: const [
        PtItemResult(
          movementId: 'push_up',
          phase: PlanPhase.main,
          setsPlanned: 3,
          setsDone: 3,
          reps: 30,
          seconds: 0,
          skipped: false,
          mistakes: {FormStatus.goDeeper: 2},
        ),
      ],
      verified: true,
      plannedItems: 4,
      activeSeconds: 1500,
      routineId: 'r1',
      routineDayId: 'd1',
    ),
  ],
  challenges: [
    ChallengeRecord(
      id: 'c1',
      date: DateTime(2026, 10, 10),
      exercise: ExerciseType.pushUp,
      mode: ChallengeMode.timed,
      value: 30,
      scores: const [
        ChallengeScore(player: ana, reps: 25, seconds: 30, formScore: 0.8),
        ChallengeScore(player: ben, reps: 20, seconds: 30),
      ],
    ),
  ],
  players: const [ana, ben],
  lifts: [
    LiftEntry(
      id: 'import:strong:0123456789abcdef',
      movementId: 'bb_bench_press',
      startTime: DateTime(2026, 10, 12, 18, 30),
      sets: const [
        LiftSet(weightKg: 40, reps: 10, warmUp: true),
        LiftSet(weightKg: 60, reps: 8, rpe: 8),
        LiftSet(weightKg: 0, reps: 0, seconds: 45),
      ],
      note: 'Felt strong',
      source: LiftSource.import,
      bodyweightKg: 82.5,
    ),
    LiftEntry(
      id: 'm1',
      movementId: 'custom:cable-woodchop',
      customName: 'Cable Woodchop',
      startTime: DateTime(2026, 10, 13, 18, 30),
      sets: const [LiftSet(weightKg: 20, reps: 12)],
    ),
  ],
  bodyWeights: [BodyWeightEntry(date: DateTime(2026, 10, 1), kg: 82.5)],
  routines: [
    Routine(
      id: 'r1',
      name: 'PPL',
      description: 'Push pull legs',
      days: const [
        RoutineDay(
          id: 'd1',
          name: 'Push',
          mode: WorkoutMode.push,
          minutes: 50,
          exercises: [
            RoutineExercise(
              movementId: 'bb_bench_press',
              sets: 5,
              repsMin: 5,
              repsMax: 5,
              policy: ProgressionPolicy.linear,
            ),
          ],
        ),
      ],
      schedule: RoutineSchedule.rotation,
      weekdays: const {1: 'd1', 3: 'd1'},
      starterId: 'ppl',
      createdAt: DateTime(2026, 9, 1),
    ),
  ],
  rules: const {
    'bb_bench_press': ProgressionRule(
      policy: ProgressionPolicy.linear,
      incrementKg: 2.5,
      repsMin: 5,
      repsMax: 5,
      sets: 5,
      stallLimit: 2,
    ),
  },
  gymProfile: const GymProfile(
    items: [
      EquipmentItem(
        type: Equipment.barbell,
        photoPath: '/tmp/rack.jpg',
        location: 'by the mirror',
      ),
      EquipmentItem(type: Equipment.dumbbells),
    ],
    gymName: 'Home',
  ),
  settingsJson: const UserSettings(
    pushUpsPerSession: 25,
    voiceEnabled: false,
  ).toJson(),
  goalKg: 78,
  activeRoutineId: 'r1',
);

void main() {
  group('BackupCodec round trip', () {
    final json = BackupCodec.encode(sample());
    final back = BackupCodec.decode(json);
    final raw = jsonDecode(json) as Map<String, dynamic>;

    test('writes the envelope', () {
      expect(raw['app'], 'levelex');
      expect(raw['version'], BackupCodec.version);
      expect(raw['exportedAt'], isA<String>());
      expect(json, contains('\n  "sessions"'), reason: 'pretty printed');
      expect(back.exportedAt, DateTime(2026, 10, 21, 9, 30));
      expect(back.skipped, 0);
      expect(back.recordCount, 10);
    });

    test('sessions', () {
      final s = back.sessions.single;
      expect(s.id, 's1');
      expect(s.startTime, DateTime(2026, 10, 14, 7));
      expect(s.endTime, DateTime(2026, 10, 14, 7, 2));
      expect(s.exercise, ExerciseType.squat);
      expect(s.status, SessionStatus.completed);
      expect(s.formScore, 0.9);
      expect(s.mistakes, {FormStatus.goDeeper: 1});
    });

    test('PT records', () {
      final r = back.ptRecords.single;
      expect(r.id, 'pt1');
      expect(r.mode, WorkoutMode.push);
      expect(r.items.single.movementId, 'push_up');
      expect(r.items.single.mistakes[FormStatus.goDeeper], 2);
      expect(r.plannedItems, 4);
      expect(r.activeSeconds, 1500);
      expect(r.routineId, 'r1');
      expect(r.routineDayId, 'd1');
      expect(r.verified, isTrue);
    });

    test('challenges and players (photos dropped)', () {
      final c = back.challenges.single;
      expect(c.id, 'c1');
      expect(c.exercise, ExerciseType.pushUp);
      expect(c.mode, ChallengeMode.timed);
      expect(c.value, 30);
      expect(c.scores.map((s) => s.reps), [25, 20]);
      expect(c.scores.first.formScore, 0.8);
      expect(c.scores.first.player.name, 'Ana');
      expect(c.scores.first.player.photoPath, isNull);
      expect(back.players.map((p) => p.id), ['p1', 'p2']);
      expect(back.players.first.photoPath, isNull);
    });

    test('lifts and body weights', () {
      final bench = back.lifts.first;
      expect(bench.id, 'import:strong:0123456789abcdef');
      expect(bench.movementId, 'bb_bench_press');
      expect(bench.source, LiftSource.import);
      expect(bench.note, 'Felt strong');
      expect(bench.bodyweightKg, 82.5);
      expect(bench.sets, sample().lifts.first.sets);
      final chop = back.lifts[1];
      expect(chop.customName, 'Cable Woodchop');
      expect(chop.source, LiftSource.manual);
      expect(back.bodyWeights.single.date, DateTime(2026, 10, 1));
      expect(back.bodyWeights.single.kg, 82.5);
    });

    test('routines, rules and the active routine', () {
      final r = back.routines.single;
      expect(r.id, 'r1');
      expect(r.schedule, RoutineSchedule.rotation);
      expect(r.weekdays, {1: 'd1', 3: 'd1'});
      expect(r.starterId, 'ppl');
      expect(r.createdAt, DateTime(2026, 9, 1));
      final day = r.days.single;
      expect(day.mode, WorkoutMode.push);
      expect(day.minutes, 50);
      expect(day.exercises.single.policy, ProgressionPolicy.linear);
      expect(day.exercises.single.sets, 5);
      expect(back.rules['bb_bench_press'], sample().rules['bb_bench_press']);
      expect(back.activeRoutineId, 'r1');
      expect(back.goalKg, 78);
    });

    test('gym profile keeps locations but never photo paths', () {
      final g = back.gymProfile!;
      expect(g.gymName, 'Home');
      expect(g.available, {Equipment.barbell, Equipment.dumbbells});
      expect(g.item(Equipment.barbell)!.location, 'by the mirror');
      expect(g.item(Equipment.barbell)!.photoPath, isNull);
      expect(json, isNot(contains('/tmp/')));
    });

    test('settings survive as an embedded object', () {
      expect(raw['settings'], isA<Map<String, dynamic>>());
      final settings = UserSettings.fromJson(back.settingsJson!);
      expect(settings.pushUpsPerSession, 25);
      expect(settings.voiceEnabled, isFalse);
    });
  });

  group('BackupCodec.decode', () {
    test('rejects JSON that is not a Levelex backup', () {
      expect(
        () => BackupCodec.decode('{"app":"other","version":1}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BackupCodec.decode('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BackupCodec.decode('"levelex"'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BackupCodec.decode('not json at all'),
        throwsA(isA<FormatException>()),
      );
    });

    test('tolerates missing sections', () {
      final b = BackupCodec.decode('{"app":"levelex"}');
      expect(b.sessions, isEmpty);
      expect(b.lifts, isEmpty);
      expect(b.rules, isEmpty);
      expect(b.gymProfile, isNull);
      expect(b.settingsJson, isNull);
      expect(b.goalKg, isNull);
      expect(b.skipped, 0);
    });

    test('skips and counts corrupt records, keeping the good ones', () {
      final map =
          jsonDecode(BackupCodec.encode(sample())) as Map<String, dynamic>;
      (map['sessions'] as List).insert(0, {'id': 42});
      (map['lifts'] as List).add('garbage');
      (map['rules'] as Map)['db_curl'] = 'not a rule';
      (map['bodyWeights'] as List).add({'date': 'nope', 'kg': 1});
      map['gymProfile'] = 'nope';
      map['exportedAt'] = 'not a date';
      final b = BackupCodec.decode(jsonEncode(map));
      expect(b.sessions.length, 1);
      expect(b.lifts.length, 2);
      expect(b.rules.keys, ['bb_bench_press']);
      expect(b.bodyWeights.length, 1);
      expect(b.gymProfile, isNull);
      expect(b.skipped, 4);
      expect(b.exportedAt, isNotNull);
    });

    test('accepts settings stored as a raw string', () {
      final b = BackupCodec.decode(
        '{"app":"levelex","settings":"{\\"x\\":1}"}',
      );
      expect(b.settingsJson, '{"x":1}');
    });
  });
}
