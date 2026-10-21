import '../../pt/models/movement.dart';
import '../../pt/models/movement_library.dart';

/// Where a logged lift came from.
enum LiftSource { pt, manual, import }

/// One set of a loaded or bodyweight exercise. Weight is the load in kg; for
/// bodyweight movements it is the *added* load (0 for plain reps).
class LiftSet {
  const LiftSet({
    required this.weightKg,
    required this.reps,
    this.rpe,
    this.warmUp = false,
    this.seconds,
  });

  final double weightKg;
  final int reps;

  /// Rate of perceived exertion 6–10 (RPE 8 == 2 reps in reserve); null when
  /// not rated.
  final double? rpe;
  final bool warmUp;

  /// Timed sets (holds) carry seconds instead of reps.
  final int? seconds;

  bool get isWork => !warmUp && (reps > 0 || (seconds ?? 0) > 0);
  double get volume => weightKg * reps;

  LiftSet copyWith({
    double? weightKg,
    int? reps,
    double? rpe,
    bool clearRpe = false,
    bool? warmUp,
    int? seconds,
  }) => LiftSet(
    weightKg: weightKg ?? this.weightKg,
    reps: reps ?? this.reps,
    rpe: clearRpe ? null : (rpe ?? this.rpe),
    warmUp: warmUp ?? this.warmUp,
    seconds: seconds ?? this.seconds,
  );

  Map<String, dynamic> toMap() => {
    'w': weightKg,
    'r': reps,
    if (rpe != null) 'rpe': rpe,
    if (warmUp) 'wu': true,
    if (seconds != null) 's': seconds,
  };

  factory LiftSet.fromMap(Map<dynamic, dynamic> map) => LiftSet(
    weightKg: (map['w'] as num?)?.toDouble() ?? 0,
    reps: (map['r'] as num?)?.toInt() ?? 0,
    rpe: (map['rpe'] as num?)?.toDouble(),
    warmUp: (map['wu'] as bool?) ?? false,
    seconds: (map['s'] as num?)?.toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is LiftSet &&
      other.weightKg == weightKg &&
      other.reps == reps &&
      other.rpe == rpe &&
      other.warmUp == warmUp &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(weightKg, reps, rpe, warmUp, seconds);
}

/// Every set of one exercise performed on one occasion.
class LiftEntry {
  const LiftEntry({
    required this.id,
    required this.movementId,
    required this.startTime,
    required this.sets,
    this.customName,
    this.note,
    this.source = LiftSource.manual,
    this.sessionId,
    this.bodyweightKg,
  });

  final String id;

  /// A `MovementLibrary` id, or `custom:<slug>` for an exercise the library
  /// does not know (imports); then [customName] is shown.
  final String movementId;
  final String? customName;
  final DateTime startTime;
  final List<LiftSet> sets;
  final String? note;
  final LiftSource source;

  /// The MY PT record this belongs to, when logged inside a session.
  final String? sessionId;

  /// Body weight on the day, when known (bodyweight-ratio stats).
  final double? bodyweightKg;

  static const customPrefix = 'custom:';

  bool get isCustom => movementId.startsWith(customPrefix);
  Movement? get movement => MovementLibrary.byId(movementId);
  String get name => movement?.name ?? customName ?? movementId;

  List<LiftSet> get workSets => [
    for (final s in sets)
      if (s.isWork) s,
  ];
  double get volume => workSets.fold(0, (sum, s) => sum + s.volume);
  int get totalReps => workSets.fold(0, (sum, s) => sum + s.reps);
  double get topWeight =>
      workSets.fold(0, (m, s) => s.weightKg > m ? s.weightKg : m);

  LiftEntry copyWith({
    List<LiftSet>? sets,
    String? note,
    DateTime? startTime,
    String? sessionId,
    double? bodyweightKg,
  }) => LiftEntry(
    id: id,
    movementId: movementId,
    customName: customName,
    startTime: startTime ?? this.startTime,
    sets: sets ?? this.sets,
    note: note ?? this.note,
    source: source,
    sessionId: sessionId ?? this.sessionId,
    bodyweightKg: bodyweightKg ?? this.bodyweightKg,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'movementId': movementId,
    if (customName != null) 'customName': customName,
    'startTime': startTime.millisecondsSinceEpoch,
    'sets': [for (final s in sets) s.toMap()],
    if (note != null) 'note': note,
    'source': source.name,
    if (sessionId != null) 'sessionId': sessionId,
    if (bodyweightKg != null) 'bodyweightKg': bodyweightKg,
  };

  factory LiftEntry.fromMap(Map<dynamic, dynamic> map) => LiftEntry(
    id: map['id'] as String,
    movementId: map['movementId'] as String,
    customName: map['customName'] as String?,
    startTime: DateTime.fromMillisecondsSinceEpoch(
      (map['startTime'] as num).toInt(),
    ),
    sets: [
      for (final raw in (map['sets'] as List? ?? const []))
        if (raw is Map) LiftSet.fromMap(raw),
    ],
    note: map['note'] as String?,
    source: LiftSource.values.firstWhere(
      (s) => s.name == map['source'],
      orElse: () => LiftSource.manual,
    ),
    sessionId: map['sessionId'] as String?,
    bodyweightKg: (map['bodyweightKg'] as num?)?.toDouble(),
  );
}

/// A weigh-in. One per calendar day; the newest write for a day wins.
class BodyWeightEntry {
  const BodyWeightEntry({required this.date, required this.kg, this.note});

  /// Local midnight.
  final DateTime date;
  final double kg;
  final String? note;

  /// Storage key: yyyy-mm-dd.
  String get key => dayKey(date);

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
    'date': date.millisecondsSinceEpoch,
    'kg': kg,
    if (note != null) 'note': note,
  };

  factory BodyWeightEntry.fromMap(Map<dynamic, dynamic> map) {
    final raw = DateTime.fromMillisecondsSinceEpoch(
      (map['date'] as num).toInt(),
    );
    return BodyWeightEntry(
      date: DateTime(raw.year, raw.month, raw.day),
      kg: (map['kg'] as num).toDouble(),
      note: map['note'] as String?,
    );
  }
}

/// Which way the user faced for a progress photo.
enum PhotoPose {
  front('Front'),
  side('Side'),
  back('Back');

  const PhotoPose(this.label);

  final String label;

  static PhotoPose fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => front);
}

/// A progress photo stored in the app's documents directory (never uploaded).
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.date,
    required this.path,
    this.pose = PhotoPose.front,
    this.note,
  });

  final String id;
  final DateTime date;
  final String path;
  final PhotoPose pose;
  final String? note;

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date.millisecondsSinceEpoch,
    'path': path,
    'pose': pose.name,
    if (note != null) 'note': note,
  };

  factory ProgressPhoto.fromMap(Map<dynamic, dynamic> map) => ProgressPhoto(
    id: map['id'] as String,
    date: DateTime.fromMillisecondsSinceEpoch((map['date'] as num).toInt()),
    path: map['path'] as String,
    pose: PhotoPose.fromName(map['pose'] as String?),
    note: map['note'] as String?,
  );
}
