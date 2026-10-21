import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/lift_log.dart';
import '../models/progression_rule.dart';
import '../models/routine.dart';

/// Lift log, weigh-ins, progress photos, routines and progression rules.
abstract class StrengthRepository {
  List<LiftEntry> lifts();
  Future<void> upsertLift(LiftEntry entry);
  Future<void> upsertLifts(Iterable<LiftEntry> entries);
  Future<void> deleteLift(String id);

  List<BodyWeightEntry> bodyWeights();
  Future<void> upsertBodyWeight(BodyWeightEntry entry);
  Future<void> deleteBodyWeight(DateTime day);
  double? get goalKg;
  Future<void> setGoalKg(double? kg);

  List<ProgressPhoto> photos();
  Future<void> upsertPhoto(ProgressPhoto photo);
  Future<void> deletePhoto(String id);

  List<Routine> routines();
  Future<void> upsertRoutine(Routine routine);
  Future<void> deleteRoutine(String id);
  String? get activeRoutineId;
  Future<void> setActiveRoutineId(String? id);

  Map<String, ProgressionRule> rules();
  Future<void> saveRule(String movementId, ProgressionRule? rule);

  /// Removes everything in this repository.
  Future<void> clear();
}

class HiveStrengthRepository implements StrengthRepository {
  HiveStrengthRepository._(
    this._lifts,
    this._body,
    this._photos,
    this._routines,
    this._meta,
  );

  static const liftBox = 'lift_log';
  static const bodyBox = 'body_log';
  static const photoBox = 'progress_photos';
  static const routineBox = 'routines';
  static const metaBox = 'strength_meta';
  static const _goalKey = 'goalKg';
  static const _activeRoutineKey = 'activeRoutineId';
  static const _rulesKey = 'rules';

  final Box<Map> _lifts;
  final Box<Map> _body;
  final Box<Map> _photos;
  final Box<Map> _routines;
  final Box _meta;

  static Future<HiveStrengthRepository> open() async {
    await Hive.initFlutter();
    return HiveStrengthRepository._(
      await Hive.openBox<Map>(liftBox),
      await Hive.openBox<Map>(bodyBox),
      await Hive.openBox<Map>(photoBox),
      await Hive.openBox<Map>(routineBox),
      await Hive.openBox(metaBox),
    );
  }

  List<T> _read<T>(Box<Map> box, T Function(Map) parse, String what) {
    final out = <T>[];
    for (final raw in box.values) {
      try {
        out.add(parse(raw));
      } catch (e) {
        debugPrint('Corrupt $what skipped: $e');
      }
    }
    return out;
  }

  @override
  List<LiftEntry> lifts() =>
      _read(_lifts, LiftEntry.fromMap, 'lift entry')
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  @override
  Future<void> upsertLift(LiftEntry entry) =>
      _lifts.put(entry.id, entry.toMap());

  @override
  Future<void> upsertLifts(Iterable<LiftEntry> entries) =>
      _lifts.putAll({for (final e in entries) e.id: e.toMap()});

  @override
  Future<void> deleteLift(String id) => _lifts.delete(id);

  @override
  List<BodyWeightEntry> bodyWeights() =>
      _read(_body, BodyWeightEntry.fromMap, 'weigh-in')
        ..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<void> upsertBodyWeight(BodyWeightEntry entry) =>
      _body.put(entry.key, entry.toMap());

  @override
  Future<void> deleteBodyWeight(DateTime day) =>
      _body.delete(BodyWeightEntry.dayKey(day));

  @override
  double? get goalKg => (_meta.get(_goalKey) as num?)?.toDouble();

  @override
  Future<void> setGoalKg(double? kg) =>
      kg == null ? _meta.delete(_goalKey) : _meta.put(_goalKey, kg);

  @override
  List<ProgressPhoto> photos() =>
      _read(_photos, ProgressPhoto.fromMap, 'progress photo')
        ..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<void> upsertPhoto(ProgressPhoto photo) =>
      _photos.put(photo.id, photo.toMap());

  @override
  Future<void> deletePhoto(String id) => _photos.delete(id);

  @override
  List<Routine> routines() =>
      _read(_routines, Routine.fromMap, 'routine')
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> upsertRoutine(Routine routine) =>
      _routines.put(routine.id, routine.toMap());

  @override
  Future<void> deleteRoutine(String id) async {
    await _routines.delete(id);
    if (activeRoutineId == id) await setActiveRoutineId(null);
  }

  @override
  String? get activeRoutineId => _meta.get(_activeRoutineKey) as String?;

  @override
  Future<void> setActiveRoutineId(String? id) => id == null
      ? _meta.delete(_activeRoutineKey)
      : _meta.put(_activeRoutineKey, id);

  @override
  Map<String, ProgressionRule> rules() {
    final raw = _meta.get(_rulesKey);
    if (raw is! Map) return const {};
    final out = <String, ProgressionRule>{};
    for (final e in raw.entries) {
      if (e.value is Map) {
        try {
          out['${e.key}'] = ProgressionRule.fromMap(e.value as Map);
        } catch (err) {
          debugPrint('Corrupt progression rule skipped: $err');
        }
      }
    }
    return out;
  }

  @override
  Future<void> saveRule(String movementId, ProgressionRule? rule) async {
    final current = {for (final e in rules().entries) e.key: e.value.toMap()};
    if (rule == null) {
      current.remove(movementId);
    } else {
      current[movementId] = rule.toMap();
    }
    await _meta.put(_rulesKey, current);
  }

  @override
  Future<void> clear() async {
    await _lifts.clear();
    await _body.clear();
    await _photos.clear();
    await _routines.clear();
    await _meta.clear();
  }
}

class InMemoryStrengthRepository implements StrengthRepository {
  final Map<String, LiftEntry> _lifts = {};
  final Map<String, BodyWeightEntry> _body = {};
  final Map<String, ProgressPhoto> _photos = {};
  final Map<String, Routine> _routines = {};
  final Map<String, ProgressionRule> _rules = {};
  double? _goal;
  String? _active;

  @override
  List<LiftEntry> lifts() =>
      _lifts.values.toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  @override
  Future<void> upsertLift(LiftEntry entry) async => _lifts[entry.id] = entry;

  @override
  Future<void> upsertLifts(Iterable<LiftEntry> entries) async {
    for (final e in entries) {
      _lifts[e.id] = e;
    }
  }

  @override
  Future<void> deleteLift(String id) async => _lifts.remove(id);

  @override
  List<BodyWeightEntry> bodyWeights() =>
      _body.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<void> upsertBodyWeight(BodyWeightEntry entry) async =>
      _body[entry.key] = entry;

  @override
  Future<void> deleteBodyWeight(DateTime day) async =>
      _body.remove(BodyWeightEntry.dayKey(day));

  @override
  double? get goalKg => _goal;

  @override
  Future<void> setGoalKg(double? kg) async => _goal = kg;

  @override
  List<ProgressPhoto> photos() =>
      _photos.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<void> upsertPhoto(ProgressPhoto photo) async =>
      _photos[photo.id] = photo;

  @override
  Future<void> deletePhoto(String id) async => _photos.remove(id);

  @override
  List<Routine> routines() =>
      _routines.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> upsertRoutine(Routine routine) async =>
      _routines[routine.id] = routine;

  @override
  Future<void> deleteRoutine(String id) async {
    _routines.remove(id);
    if (_active == id) _active = null;
  }

  @override
  String? get activeRoutineId => _active;

  @override
  Future<void> setActiveRoutineId(String? id) async => _active = id;

  @override
  Map<String, ProgressionRule> rules() => Map.unmodifiable(_rules);

  @override
  Future<void> saveRule(String movementId, ProgressionRule? rule) async {
    if (rule == null) {
      _rules.remove(movementId);
    } else {
      _rules[movementId] = rule;
    }
  }

  @override
  Future<void> clear() async {
    _lifts.clear();
    _body.clear();
    _photos.clear();
    _routines.clear();
    _rules.clear();
    _goal = null;
    _active = null;
  }
}
