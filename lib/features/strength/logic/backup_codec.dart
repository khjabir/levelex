import 'dart:convert';

import '../../../models/workout_session.dart';
import '../../challenge/models/challenge.dart';
import '../../pt/models/equipment.dart';
import '../../pt/models/pt_record.dart';
import '../models/lift_log.dart';
import '../models/progression_rule.dart';
import '../models/routine.dart';

/// Everything a full backup carries. Local file paths (gym and player
/// photos) are dropped on export because they do not exist on another
/// device; face data is never part of a backup.
class BackupBundle {
  const BackupBundle({
    required this.exportedAt,
    this.sessions = const [],
    this.ptRecords = const [],
    this.challenges = const [],
    this.players = const [],
    this.lifts = const [],
    this.bodyWeights = const [],
    this.routines = const [],
    this.rules = const {},
    this.gymProfile,
    this.settingsJson,
    this.goalKg,
    this.activeRoutineId,
    this.skipped = 0,
  });

  final DateTime exportedAt;
  final List<WorkoutSession> sessions;
  final List<PtRecord> ptRecords;
  final List<ChallengeRecord> challenges;
  final List<ChallengePlayer> players;
  final List<LiftEntry> lifts;
  final List<BodyWeightEntry> bodyWeights;
  final List<Routine> routines;

  /// Movement id → progression rule.
  final Map<String, ProgressionRule> rules;
  final GymProfile? gymProfile;

  /// `UserSettings.toJson()`; kept as a string so this codec does not depend
  /// on the settings model's shape.
  final String? settingsJson;
  final double? goalKg;
  final String? activeRoutineId;

  /// Records that could not be decoded (corrupt or from a newer version)
  /// and were left out. Always 0 on a bundle built for export.
  final int skipped;

  int get recordCount =>
      sessions.length +
      ptRecords.length +
      challenges.length +
      players.length +
      lifts.length +
      bodyWeights.length +
      routines.length +
      rules.length;
}

/// JSON backup format, version [version]. Decoding tolerates missing
/// sections and skips individual corrupt records instead of failing.
abstract final class BackupCodec {
  static const version = 1;
  static const app = 'levelex';

  /// Pretty JSON of [bundle].
  static String encode(BackupBundle bundle) {
    final settings = _settingsValue(bundle.settingsJson);
    final map = <String, dynamic>{
      'app': app,
      'version': version,
      'exportedAt': bundle.exportedAt.toIso8601String(),
      'sessions': [for (final s in bundle.sessions) s.toMap()],
      'ptRecords': [for (final r in bundle.ptRecords) r.toMap()],
      'challenges': [
        for (final c in bundle.challenges) _stripChallenge(c).toMap(),
      ],
      'players': [for (final p in bundle.players) _stripPlayer(p).toMap()],
      'lifts': [for (final l in bundle.lifts) l.toMap()],
      'bodyWeights': [for (final b in bundle.bodyWeights) b.toMap()],
      'routines': [for (final r in bundle.routines) r.toMap()],
      'rules': {for (final e in bundle.rules.entries) e.key: e.value.toMap()},
      'gymProfile': bundle.gymProfile == null
          ? null
          : _stripGym(bundle.gymProfile!).toMap(),
      'settings': settings,
      'goalKg': bundle.goalKg,
      'activeRoutineId': bundle.activeRoutineId,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Parses [json]. Throws [FormatException] when it is not a Levelex backup
  /// (not a JSON object, or `app` is something else). Corrupt records are
  /// counted in [BackupBundle.skipped].
  static BackupBundle decode(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('Not a Levelex backup');
    }
    if (decoded is! Map || decoded['app'] != app) {
      throw const FormatException('Not a Levelex backup');
    }
    final Map root = decoded;
    var skipped = 0;
    List<T> section<T>(String key, T Function(Map<dynamic, dynamic>) from) {
      final raw = root[key];
      if (raw is! List) return const [];
      final out = <T>[];
      for (final item in raw) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        try {
          out.add(from(item));
        } catch (_) {
          skipped++;
        }
      }
      return out;
    }

    final rules = <String, ProgressionRule>{};
    final rawRules = root['rules'];
    if (rawRules is Map) {
      for (final e in rawRules.entries) {
        if (e.value is! Map) {
          skipped++;
          continue;
        }
        try {
          rules['${e.key}'] = ProgressionRule.fromMap(e.value as Map);
        } catch (_) {
          skipped++;
        }
      }
    }
    GymProfile? gym;
    final rawGym = root['gymProfile'];
    if (rawGym is Map) {
      try {
        gym = GymProfile.fromMap(rawGym);
      } catch (_) {
        skipped++;
      }
    }
    final exportedAt = switch (root['exportedAt']) {
      final String s => DateTime.tryParse(s)?.toLocal(),
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    };
    return BackupBundle(
      exportedAt: exportedAt ?? DateTime.now(),
      sessions: section('sessions', WorkoutSession.fromMap),
      ptRecords: section('ptRecords', PtRecord.fromMap),
      challenges: section('challenges', ChallengeRecord.fromMap),
      players: section('players', ChallengePlayer.fromMap),
      lifts: section('lifts', LiftEntry.fromMap),
      bodyWeights: section('bodyWeights', BodyWeightEntry.fromMap),
      routines: section('routines', Routine.fromMap),
      rules: rules,
      gymProfile: gym,
      settingsJson: switch (root['settings']) {
        final Map m => jsonEncode(m),
        final String s => s,
        _ => null,
      },
      goalKg: (root['goalKg'] as num?)?.toDouble(),
      activeRoutineId: root['activeRoutineId'] as String?,
      skipped: skipped,
    );
  }

  /// Settings are embedded as an object when they are valid JSON so the
  /// file stays readable; anything else is kept verbatim.
  static Object? _settingsValue(String? settingsJson) {
    if (settingsJson == null) return null;
    try {
      final decoded = jsonDecode(settingsJson);
      if (decoded is Map) return decoded;
    } on FormatException {
      // Fall through: keep the raw string.
    }
    return settingsJson;
  }

  static GymProfile _stripGym(GymProfile g) => GymProfile(
    items: [for (final i in g.items) i.copyWith(clearPhoto: true)],
    gymName: g.gymName,
  );

  static ChallengePlayer _stripPlayer(ChallengePlayer p) =>
      ChallengePlayer(id: p.id, name: p.name);

  static ChallengeRecord _stripChallenge(ChallengeRecord c) => ChallengeRecord(
    id: c.id,
    date: c.date,
    exercise: c.exercise,
    mode: c.mode,
    value: c.value,
    scores: [
      for (final s in c.scores)
        ChallengeScore(
          player: _stripPlayer(s.player),
          reps: s.reps,
          seconds: s.seconds,
          formScore: s.formScore,
        ),
    ],
  );
}
