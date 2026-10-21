import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'data/challenge_repository.dart';
import 'models/challenge.dart';

/// Overridden at startup with the opened Hive repository.
final challengeRepositoryProvider = Provider<ChallengeRepository>(
  (ref) => InMemoryChallengeRepository(),
);

class ChallengeRecordsNotifier extends Notifier<List<ChallengeRecord>> {
  @override
  List<ChallengeRecord> build() =>
      ref.watch(challengeRepositoryProvider).records();

  Future<void> add(ChallengeRecord record) async {
    await ref.read(challengeRepositoryProvider).upsert(record);
    state = ref.read(challengeRepositoryProvider).records();
  }

  Future<void> clear() async {
    await ref.read(challengeRepositoryProvider).clear();
    state = const [];
  }
}

final challengeRecordsProvider =
    NotifierProvider<ChallengeRecordsNotifier, List<ChallengeRecord>>(
      ChallengeRecordsNotifier.new,
    );

/// The challenge being set up / played.
class ChallengeConfigNotifier extends Notifier<ChallengeConfig> {
  static const _uuid = Uuid();

  @override
  ChallengeConfig build() =>
      ChallengeConfig(players: ref.read(challengeRepositoryProvider).players());

  void update(ChallengeConfig Function(ChallengeConfig) change) {
    state = change(state);
    ref.read(challengeRepositoryProvider).savePlayers(state.players);
  }

  void addPlayer(String name, {String? photoPath}) => update(
    (c) => c.copyWith(
      players: [
        ...c.players,
        ChallengePlayer(id: _uuid.v4(), name: name, photoPath: photoPath),
      ],
    ),
  );

  void removePlayer(String id) => update(
    (c) => c.copyWith(players: c.players.where((p) => p.id != id).toList()),
  );

  void setPhoto(String id, String? photoPath) => update(
    (c) => c.copyWith(
      players: [
        for (final p in c.players)
          if (p.id == id) p.copyWith(photoPath: photoPath) else p,
      ],
    ),
  );
}

final challengeConfigProvider =
    NotifierProvider<ChallengeConfigNotifier, ChallengeConfig>(
      ChallengeConfigNotifier.new,
    );
