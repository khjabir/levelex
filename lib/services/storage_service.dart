import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/exercise.dart';
import '../models/face_template.dart';
import '../models/user_settings.dart';
import '../features/challenge/data/challenge_repository.dart';
import '../features/pt/data/pt_repository.dart';
import '../models/workout_session.dart';

/// An in-progress set that is persisted so it can be recovered if the app
/// is killed mid-workout.
class WorkoutDraft {
  const WorkoutDraft({
    required this.id,
    required this.startTime,
    required this.targetReps,
    required this.reps,
    this.exercise = ExerciseType.pushUp,
  });

  final String id;
  final DateTime startTime;
  final int targetReps;
  final int reps;
  final ExerciseType exercise;

  Map<String, dynamic> toMap() => {
    'id': id,
    'startTime': startTime.millisecondsSinceEpoch,
    'targetReps': targetReps,
    'reps': reps,
    'exercise': exercise.id,
  };

  factory WorkoutDraft.fromMap(Map<String, dynamic> map) => WorkoutDraft(
    id: map['id'] as String,
    startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
    targetReps: map['targetReps'] as int,
    reps: map['reps'] as int,
    exercise: ExerciseType.fromId(map['exercise'] as String?),
  );
}

/// Stores [UserSettings] plus a few small pieces of app state.
abstract class SettingsRepository {
  UserSettings get settings;
  Future<void> save(UserSettings settings);

  /// Reminder windows ending at or before this instant have already been
  /// evaluated for "skipped" sessions.
  DateTime? get skipEvaluatedUntil;
  Future<void> setSkipEvaluatedUntil(DateTime? value);

  WorkoutDraft? get draft;
  Future<void> saveDraft(WorkoutDraft? draft);

  /// The registered user's face embedding, or null when none is enrolled.
  FaceTemplate? get faceTemplate;
  Future<void> saveFaceTemplate(FaceTemplate? template);

  /// Removes everything, restoring factory defaults.
  Future<void> clear();
}

/// Stores workout sessions.
abstract class SessionRepository {
  List<WorkoutSession> all();
  Future<void> upsert(WorkoutSession session);
  Future<void> upsertAll(Iterable<WorkoutSession> sessions);
  Future<void> delete(String id);
  Future<void> clear();
}

// -----------------------------------------------------------------------------
// SharedPreferences-backed settings
// -----------------------------------------------------------------------------

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository._(
    this._prefs,
    this._settings,
    this._until,
    this._draft,
    this._face,
  );

  static const _settingsKey = 'user_settings';
  static const _skipKey = 'skip_evaluated_until';
  static const _draftKey = 'workout_draft';
  static const _faceKey = 'face_template';

  final SharedPreferencesAsync _prefs;
  UserSettings _settings;
  DateTime? _until;
  WorkoutDraft? _draft;
  FaceTemplate? _face;

  static Future<PrefsSettingsRepository> load() async {
    final prefs = SharedPreferencesAsync();
    var settings = const UserSettings();
    DateTime? until;
    WorkoutDraft? draft;
    FaceTemplate? face;
    try {
      final json = await prefs.getString(_settingsKey);
      if (json != null) settings = UserSettings.fromJson(json);
      final untilMs = await prefs.getInt(_skipKey);
      if (untilMs != null) until = DateTime.fromMillisecondsSinceEpoch(untilMs);
      final draftJson = await prefs.getString(_draftKey);
      if (draftJson != null) {
        draft = WorkoutDraft.fromMap(
          jsonDecode(draftJson) as Map<String, dynamic>,
        );
      }
      final faceJson = await prefs.getString(_faceKey);
      if (faceJson != null) {
        face = FaceTemplate.fromMap(
          jsonDecode(faceJson) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      // Corrupt preferences should never block app start.
      debugPrint('Settings load failed, using defaults: $e');
    }
    return PrefsSettingsRepository._(prefs, settings, until, draft, face);
  }

  @override
  UserSettings get settings => _settings;

  @override
  Future<void> save(UserSettings settings) async {
    _settings = settings;
    await _prefs.setString(_settingsKey, settings.toJson());
  }

  @override
  DateTime? get skipEvaluatedUntil => _until;

  @override
  Future<void> setSkipEvaluatedUntil(DateTime? value) async {
    _until = value;
    if (value == null) {
      await _prefs.remove(_skipKey);
    } else {
      await _prefs.setInt(_skipKey, value.millisecondsSinceEpoch);
    }
  }

  @override
  WorkoutDraft? get draft => _draft;

  @override
  Future<void> saveDraft(WorkoutDraft? draft) async {
    _draft = draft;
    if (draft == null) {
      await _prefs.remove(_draftKey);
    } else {
      await _prefs.setString(_draftKey, jsonEncode(draft.toMap()));
    }
  }

  @override
  FaceTemplate? get faceTemplate => _face;

  @override
  Future<void> saveFaceTemplate(FaceTemplate? template) async {
    _face = template;
    if (template == null) {
      await _prefs.remove(_faceKey);
    } else {
      await _prefs.setString(_faceKey, jsonEncode(template.toMap()));
    }
  }

  @override
  Future<void> clear() async {
    _settings = const UserSettings();
    _until = null;
    _draft = null;
    _face = null;
    await _prefs.clear();
  }
}

// -----------------------------------------------------------------------------
// Hive-backed sessions
// -----------------------------------------------------------------------------

class HiveSessionRepository implements SessionRepository {
  HiveSessionRepository._(this._box);

  static const boxName = 'workout_sessions';

  final Box<Map> _box;

  static Future<HiveSessionRepository> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<Map>(boxName);
    return HiveSessionRepository._(box);
  }

  @override
  List<WorkoutSession> all() {
    final result = <WorkoutSession>[];
    for (final raw in _box.values) {
      try {
        result.add(WorkoutSession.fromMap(raw));
      } catch (e) {
        debugPrint('Skipping corrupt session record: $e');
      }
    }
    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  @override
  Future<void> upsert(WorkoutSession session) =>
      _box.put(session.id, session.toMap());

  @override
  Future<void> upsertAll(Iterable<WorkoutSession> sessions) =>
      _box.putAll({for (final s in sessions) s.id: s.toMap()});

  @override
  Future<void> delete(String id) => _box.delete(id);

  @override
  Future<void> clear() => _box.clear();
}

// -----------------------------------------------------------------------------
// In-memory fallbacks (tests, and a safety net if storage fails to open)
// -----------------------------------------------------------------------------

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this._settings = const UserSettings()]);

  UserSettings _settings;
  DateTime? _until;
  WorkoutDraft? _draft;
  FaceTemplate? _face;

  @override
  UserSettings get settings => _settings;

  @override
  Future<void> save(UserSettings settings) async => _settings = settings;

  @override
  FaceTemplate? get faceTemplate => _face;

  @override
  Future<void> saveFaceTemplate(FaceTemplate? template) async =>
      _face = template;

  @override
  DateTime? get skipEvaluatedUntil => _until;

  @override
  Future<void> setSkipEvaluatedUntil(DateTime? value) async => _until = value;

  @override
  WorkoutDraft? get draft => _draft;

  @override
  Future<void> saveDraft(WorkoutDraft? draft) async => _draft = draft;

  @override
  Future<void> clear() async {
    _settings = const UserSettings();
    _until = null;
    _draft = null;
    _face = null;
  }
}

class InMemorySessionRepository implements SessionRepository {
  final Map<String, WorkoutSession> _items = {};

  @override
  List<WorkoutSession> all() =>
      _items.values.toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  @override
  Future<void> upsert(WorkoutSession session) async =>
      _items[session.id] = session;

  @override
  Future<void> upsertAll(Iterable<WorkoutSession> sessions) async {
    for (final s in sessions) {
      _items[s.id] = s;
    }
  }

  @override
  Future<void> delete(String id) async => _items.remove(id);

  @override
  Future<void> clear() async => _items.clear();
}

/// Opens all local storage. Falls back to in-memory storage if the device
/// storage cannot be opened so the app still runs.
class StorageService {
  StorageService({
    required this.settings,
    required this.sessions,
    required this.pt,
    required this.challenges,
  });

  final SettingsRepository settings;
  final SessionRepository sessions;
  final PtRepository pt;
  final ChallengeRepository challenges;

  static Future<StorageService> initialize() async {
    SettingsRepository settingsRepo;
    SessionRepository sessionRepo;
    PtRepository ptRepo;
    ChallengeRepository challengeRepo;
    try {
      settingsRepo = await PrefsSettingsRepository.load();
    } catch (e) {
      debugPrint('Preferences unavailable, using in-memory settings: $e');
      settingsRepo = InMemorySettingsRepository();
    }
    try {
      sessionRepo = await HiveSessionRepository.open();
    } catch (e) {
      debugPrint('Hive unavailable, using in-memory sessions: $e');
      sessionRepo = InMemorySessionRepository();
    }
    try {
      ptRepo = await HivePtRepository.open();
    } catch (e) {
      debugPrint('Hive unavailable, using in-memory PT storage: $e');
      ptRepo = InMemoryPtRepository();
    }
    try {
      challengeRepo = await HiveChallengeRepository.open();
    } catch (e) {
      debugPrint('Hive unavailable, using in-memory challenges: $e');
      challengeRepo = InMemoryChallengeRepository();
    }
    return StorageService(
      settings: settingsRepo,
      sessions: sessionRepo,
      pt: ptRepo,
      challenges: challengeRepo,
    );
  }
}
