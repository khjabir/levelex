import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../challenge/challenge_providers.dart';
import '../../pt/pt_providers.dart';
import '../logic/backup_codec.dart';
import '../logic/lift_importer.dart';
import '../strength_providers.dart';

/// What an import did, in words the settings screen can show.
class ImportOutcome {
  const ImportOutcome(this.message, {this.unmatched = const {}});

  final String message;

  /// Exercise names that became custom entries (name → set count).
  final Map<String, int> unmatched;
}

/// Export and import of the whole profile, plus imports from other apps.
/// Everything goes through the providers so screens update at once.
abstract final class BackupActions {
  /// Writes a JSON backup to a temporary file and opens the share sheet.
  static Future<String> export(WidgetRef ref) async {
    final bundle = BackupBundle(
      exportedAt: DateTime.now(),
      sessions: ref.read(sessionRepositoryProvider).all(),
      ptRecords: ref.read(ptRecordsProvider),
      challenges: ref.read(challengeRepositoryProvider).records(),
      players: ref.read(challengeRepositoryProvider).players(),
      lifts: ref.read(liftLogProvider),
      bodyWeights: ref.read(bodyWeightProvider),
      routines: ref.read(routinesProvider),
      rules: ref.read(progressionRulesProvider),
      gymProfile: ref.read(gymProfileProvider),
      settingsJson: ref.read(settingsProvider).toJson(),
      goalKg: ref.read(bodyGoalProvider),
      activeRoutineId: ref.read(activeRoutineIdProvider),
    );
    final json = BackupCodec.encode(bundle);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/levelex-backup-$stamp.json');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Levelex backup $stamp',
        text: 'Levelex backup: ${bundle.recordCount} records.',
      ),
    );
    return file.path;
  }

  /// Lets the user pick a file and returns its text, or null.
  static Future<String?> pickTextFile() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Choose a file');
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Merges a Levelex backup into this device: records are upserted by id,
  /// nothing is deleted, device settings are kept.
  static Future<ImportOutcome> importBackup(WidgetRef ref, String json) async {
    final bundle = BackupCodec.decode(json);
    await ref.read(sessionRepositoryProvider).upsertAll(bundle.sessions);
    ref.invalidate(sessionsProvider);
    await ref.read(ptRecordsProvider.notifier).addAll(bundle.ptRecords);
    final challenges = ref.read(challengeRepositoryProvider);
    for (final c in bundle.challenges) {
      await challenges.upsert(c);
    }
    if (bundle.players.isNotEmpty) {
      final current = challenges.players();
      final ids = {for (final p in current) p.id};
      await challenges.savePlayers([
        ...current,
        for (final p in bundle.players)
          if (!ids.contains(p.id)) p,
      ]);
    }
    ref.invalidate(challengeRecordsProvider);
    // The set-up screen's notifier read the players once; rebuild it so its
    // next edit does not save the old list over the imported players.
    ref.invalidate(challengeConfigProvider);
    await ref.read(liftLogProvider.notifier).addAll(bundle.lifts);
    await ref.read(bodyWeightProvider.notifier).addAll(bundle.bodyWeights);
    await ref.read(routinesProvider.notifier).addAll(bundle.routines);
    await ref.read(progressionRulesProvider.notifier).replaceAll(bundle.rules);
    final gym = bundle.gymProfile;
    if (gym != null) {
      var profile = ref.read(gymProfileProvider);
      for (final item in gym.items) {
        if (!profile.available.contains(item.type)) {
          profile = profile.update(item);
        }
      }
      await ref.read(gymProfileProvider.notifier).set(profile);
    }
    if (bundle.goalKg != null && ref.read(bodyGoalProvider) == null) {
      await ref.read(bodyGoalProvider.notifier).set(bundle.goalKg);
    }
    if (bundle.activeRoutineId != null &&
        ref.read(activeRoutineIdProvider) == null &&
        bundle.routines.any((r) => r.id == bundle.activeRoutineId)) {
      await ref
          .read(activeRoutineIdProvider.notifier)
          .set(bundle.activeRoutineId);
    }
    final parts = <String>[
      if (bundle.sessions.isNotEmpty) '${bundle.sessions.length} sets',
      if (bundle.ptRecords.isNotEmpty)
        '${bundle.ptRecords.length} MY PT sessions',
      if (bundle.lifts.isNotEmpty) '${bundle.lifts.length} lift entries',
      if (bundle.bodyWeights.isNotEmpty)
        '${bundle.bodyWeights.length} weigh-ins',
      if (bundle.routines.isNotEmpty) '${bundle.routines.length} routines',
      if (bundle.challenges.isNotEmpty)
        '${bundle.challenges.length} challenges',
    ];
    final skipped = bundle.skipped > 0
        ? ' ${bundle.skipped} unreadable records were skipped.'
        : '';
    return ImportOutcome(
      parts.isEmpty
          ? 'The backup was empty.$skipped'
          : 'Restored ${parts.join(', ')}.$skipped',
    );
  }

  /// Imports a CSV from FitNotes, Strong, Hevy or any app with a date,
  /// exercise and weight/reps columns, or an Apple Health export.
  static Future<ImportOutcome> importFromOtherApp(
    WidgetRef ref,
    String text,
  ) async {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('<?xml') ||
        trimmed.startsWith('<HealthData') ||
        text.contains('HKQuantityTypeIdentifierBodyMass')) {
      final weights = LiftImporter.parseAppleHealth(text);
      if (weights.isEmpty) {
        return const ImportOutcome(
          'No body-weight records found in that Health export.',
        );
      }
      await ref.read(bodyWeightProvider.notifier).addAll(weights);
      return ImportOutcome(
        'Imported ${weights.length} weigh-ins from Apple Health.',
      );
    }
    final result = LiftImporter.parseCsv(text);
    if (result.isEmpty) {
      return ImportOutcome(
        'Nothing usable found: ${result.rowsRead} rows read, '
        '${result.rowsSkipped} skipped. The file needs a date, an exercise '
        'and reps or a weight per row.',
      );
    }
    await ref.read(liftLogProvider.notifier).addAll(result.entries);
    await ref.read(bodyWeightProvider.notifier).addAll(result.bodyWeights);
    debugPrint(
      'Import (${result.source.name}): ${result.entries.length} entries, '
      '${result.unmatched.length} unmatched names',
    );
    final parts = [
      if (result.entries.isNotEmpty)
        '${result.setCount} sets in ${result.entries.length} exercise '
            'sessions',
      if (result.bodyWeights.isNotEmpty)
        '${result.bodyWeights.length} weigh-ins',
    ];
    return ImportOutcome(
      'Imported ${parts.join(' and ')} from ${_sourceName(result.source)}'
      '${result.rowsSkipped > 0 ? ' (${result.rowsSkipped} rows skipped)' : ''}.'
      '${result.unmatched.isNotEmpty ? ' ${result.unmatched.length} exercise names were kept as your own exercises.' : ''}',
      unmatched: result.unmatched,
    );
  }

  static String _sourceName(ImportSource s) => switch (s) {
    ImportSource.strong => 'Strong',
    ImportSource.hevy => 'Hevy',
    ImportSource.fitnotes => 'FitNotes',
    ImportSource.generic => 'the CSV',
  };
}
