import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/challenge.dart';

/// Stores finished challenges and the last set of players.
abstract class ChallengeRepository {
  List<ChallengeRecord> records();
  Future<void> upsert(ChallengeRecord record);
  List<ChallengePlayer> players();
  Future<void> savePlayers(List<ChallengePlayer> players);
  Future<void> clear();
}

class HiveChallengeRepository implements ChallengeRepository {
  HiveChallengeRepository._(this._records, this._meta);

  static const _recordsBox = 'challenge_records';
  static const _metaBox = 'challenge_meta';
  static const _playersKey = 'players';

  final Box<Map> _records;
  final Box<Map> _meta;

  static Future<HiveChallengeRepository> open() async {
    await Hive.initFlutter();
    final records = await Hive.openBox<Map>(_recordsBox);
    final meta = await Hive.openBox<Map>(_metaBox);
    return HiveChallengeRepository._(records, meta);
  }

  @override
  List<ChallengeRecord> records() {
    final list = <ChallengeRecord>[];
    for (final raw in _records.values) {
      try {
        list.add(ChallengeRecord.fromMap(raw));
      } catch (e) {
        debugPrint('Corrupt challenge skipped: $e');
      }
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  @override
  Future<void> upsert(ChallengeRecord record) =>
      _records.put(record.id, record.toMap());

  @override
  List<ChallengePlayer> players() {
    final raw = _meta.get(_playersKey);
    if (raw == null) return const [];
    try {
      return [
        for (final p in (raw['players'] as List? ?? const []))
          if (p is Map) ChallengePlayer.fromMap(p),
      ];
    } catch (e) {
      debugPrint('Corrupt players ignored: $e');
      return const [];
    }
  }

  @override
  Future<void> savePlayers(List<ChallengePlayer> players) =>
      _meta.put(_playersKey, {
        'players': [for (final p in players) p.toMap()],
      });

  @override
  Future<void> clear() async {
    await _records.clear();
    await _meta.clear();
  }
}

class InMemoryChallengeRepository implements ChallengeRepository {
  final Map<String, ChallengeRecord> _records = {};
  List<ChallengePlayer> _players = const [];

  @override
  List<ChallengeRecord> records() =>
      _records.values.toList()..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<void> upsert(ChallengeRecord record) async =>
      _records[record.id] = record;

  @override
  List<ChallengePlayer> players() => _players;

  @override
  Future<void> savePlayers(List<ChallengePlayer> players) async =>
      _players = List.of(players);

  @override
  Future<void> clear() async {
    _records.clear();
    _players = const [];
  }
}
