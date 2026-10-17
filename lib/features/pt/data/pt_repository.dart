import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/equipment.dart';
import '../models/pt_record.dart';

/// Stores the gym profile and completed MY PT sessions.
abstract class PtRepository {
  GymProfile get profile;
  Future<void> saveProfile(GymProfile profile);
  List<PtRecord> records();
  Future<void> upsertRecord(PtRecord record);
  Future<void> clearRecords();
}

class HivePtRepository implements PtRepository {
  HivePtRepository._(this._profileBox, this._recordBox);

  static const _profileBoxName = 'pt_profile';
  static const _recordBoxName = 'pt_records';
  static const _profileKey = 'profile';

  final Box<Map> _profileBox;
  final Box<Map> _recordBox;

  static Future<HivePtRepository> open() async {
    await Hive.initFlutter();
    final profiles = await Hive.openBox<Map>(_profileBoxName);
    final records = await Hive.openBox<Map>(_recordBoxName);
    return HivePtRepository._(profiles, records);
  }

  @override
  GymProfile get profile {
    final raw = _profileBox.get(_profileKey);
    if (raw == null) return const GymProfile();
    try {
      return GymProfile.fromMap(raw);
    } catch (e) {
      debugPrint('Corrupt gym profile ignored: $e');
      return const GymProfile();
    }
  }

  @override
  Future<void> saveProfile(GymProfile profile) =>
      _profileBox.put(_profileKey, profile.toMap());

  @override
  List<PtRecord> records() {
    final list = <PtRecord>[];
    for (final raw in _recordBox.values) {
      try {
        list.add(PtRecord.fromMap(raw));
      } catch (e) {
        debugPrint('Corrupt PT record skipped: $e');
      }
    }
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  @override
  Future<void> upsertRecord(PtRecord record) =>
      _recordBox.put(record.id, record.toMap());

  @override
  Future<void> clearRecords() => _recordBox.clear();
}

class InMemoryPtRepository implements PtRepository {
  GymProfile _profile = const GymProfile();
  final Map<String, PtRecord> _records = {};

  @override
  GymProfile get profile => _profile;

  @override
  Future<void> saveProfile(GymProfile profile) async => _profile = profile;

  @override
  List<PtRecord> records() =>
      _records.values.toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  @override
  Future<void> upsertRecord(PtRecord record) async =>
      _records[record.id] = record;

  @override
  Future<void> clearRecords() async => _records.clear();
}
