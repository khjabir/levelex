import '../../../models/exercise.dart';

/// How a challenge is scored.
enum ChallengeMode {
  /// Most reps (or seconds held) inside a fixed time.
  timed('Most in a time limit'),

  /// Fastest to a rep target (or longest hold up to a cap).
  target('First to a target');

  const ChallengeMode(this.label);

  final String label;

  static ChallengeMode fromName(String? n) =>
      values.firstWhere((m) => m.name == n, orElse: () => timed);
}

/// Somebody taking part. Photos stay on the device.
class ChallengePlayer {
  const ChallengePlayer({required this.id, required this.name, this.photoPath});

  final String id;
  final String name;
  final String? photoPath;

  ChallengePlayer copyWith({String? name, String? photoPath}) =>
      ChallengePlayer(
        id: id,
        name: name ?? this.name,
        photoPath: photoPath ?? this.photoPath,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'photoPath': photoPath,
  };

  factory ChallengePlayer.fromMap(Map<dynamic, dynamic> m) => ChallengePlayer(
    id: m['id'] as String,
    name: m['name'] as String,
    photoPath: m['photoPath'] as String?,
  );
}

/// What is being played.
class ChallengeConfig {
  const ChallengeConfig({
    this.exercise = ExerciseType.pushUp,
    this.mode = ChallengeMode.timed,
    this.value = 30,
    this.players = const [],
  });

  final ExerciseType exercise;
  final ChallengeMode mode;

  /// Seconds for [ChallengeMode.timed]; reps (or seconds for holds) for
  /// [ChallengeMode.target].
  final int value;
  final List<ChallengePlayer> players;

  bool get ready => players.length >= 2;

  String get describe => mode == ChallengeMode.timed
      ? 'Most ${exercise.label.toLowerCase()} in $value seconds'
      : exercise.isTimed
      ? 'Longest ${exercise.singular} (up to $value s)'
      : 'First to $value ${exercise.label.toLowerCase()}';

  ChallengeConfig copyWith({
    ExerciseType? exercise,
    ChallengeMode? mode,
    int? value,
    List<ChallengePlayer>? players,
  }) => ChallengeConfig(
    exercise: exercise ?? this.exercise,
    mode: mode ?? this.mode,
    value: value ?? this.value,
    players: players ?? this.players,
  );
}

/// One player's round.
class ChallengeScore {
  const ChallengeScore({
    required this.player,
    required this.reps,
    required this.seconds,
    this.formScore,
  });

  final ChallengePlayer player;

  /// Reps counted (or seconds held for timed exercises).
  final int reps;

  /// Round duration in seconds (time taken to hit a target, or the limit).
  final double seconds;
  final double? formScore;

  Map<String, dynamic> toMap() => {
    'player': player.toMap(),
    'reps': reps,
    'seconds': seconds,
    'formScore': formScore,
  };

  factory ChallengeScore.fromMap(Map<dynamic, dynamic> m) => ChallengeScore(
    player: ChallengePlayer.fromMap(m['player'] as Map),
    reps: (m['reps'] as int?) ?? 0,
    seconds: ((m['seconds'] as num?) ?? 0).toDouble(),
    formScore: (m['formScore'] as num?)?.toDouble(),
  );
}

/// A finished challenge.
class ChallengeRecord {
  const ChallengeRecord({
    required this.id,
    required this.date,
    required this.exercise,
    required this.mode,
    required this.value,
    required this.scores,
  });

  final String id;
  final DateTime date;
  final ExerciseType exercise;
  final ChallengeMode mode;
  final int value;

  /// Best first.
  final List<ChallengeScore> scores;

  ChallengeScore? get winner => scores.isEmpty ? null : scores.first;

  /// True when the top two are level (shared cup).
  bool get tie =>
      scores.length >= 2 && _compare(scores[0], scores[1], mode) == 0;

  static int _compare(ChallengeScore a, ChallengeScore b, ChallengeMode mode) {
    if (a.reps != b.reps) return b.reps.compareTo(a.reps);
    if (mode == ChallengeMode.target) return a.seconds.compareTo(b.seconds);
    return 0;
  }

  /// Orders scores: more reps first; for target mode, faster first.
  static List<ChallengeScore> ranked(
    Iterable<ChallengeScore> scores,
    ChallengeMode mode,
  ) => scores.toList()..sort((a, b) => _compare(a, b, mode));

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date.millisecondsSinceEpoch,
    'exercise': exercise.id,
    'mode': mode.name,
    'value': value,
    'scores': [for (final s in scores) s.toMap()],
  };

  factory ChallengeRecord.fromMap(Map<dynamic, dynamic> m) => ChallengeRecord(
    id: m['id'] as String,
    date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
    exercise: ExerciseType.fromId(m['exercise'] as String?),
    mode: ChallengeMode.fromName(m['mode'] as String?),
    value: (m['value'] as int?) ?? 0,
    scores: [
      for (final raw in (m['scores'] as List? ?? const []))
        if (raw is Map) ChallengeScore.fromMap(raw),
    ],
  );
}
