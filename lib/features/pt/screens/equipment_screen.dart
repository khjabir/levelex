import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme.dart';
import '../../../widgets/primary_button.dart';
import '../data/equipment_detector.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/section_header.dart';
import '../../settings/widgets/settings_widgets.dart' show confirmAction;
import '../models/equipment.dart';
import '../pt_providers.dart';
import 'pt_widgets.dart';

/// Tell MY PT what equipment you have; attach a photo and a note per item
/// so it can point you to the right rack or machine.
class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key});

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  final _picker = ImagePicker();
  EquipmentDetector? _detector;
  bool _scanning = false;

  @override
  void dispose() {
    _detector?.dispose();
    super.dispose();
  }

  Future<XFile?> _pick(ImageSource source) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 82,
      );
    } catch (e) {
      debugPrint('Image pick failed: $e');
      return null;
    }
  }

  /// Copies a picked photo into the app's private folder for [type].
  Future<String?> _store(XFile file, Equipment type) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/equipment');
      await folder.create(recursive: true);
      final ext = file.path.split('.').last.toLowerCase();
      final target = File(
        '${folder.path}/${type.name}_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await File(file.path).copy(target.path);
      return target.path;
    } catch (e) {
      debugPrint('Saving equipment photo failed: $e');
      return null;
    }
  }

  Future<void> _attachPhoto(EquipmentItem item, ImageSource source) async {
    final file = await _pick(source);
    if (file == null || !mounted) return;
    final path = await _store(file, item.type);
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the photo.')),
      );
      return;
    }
    final old = item.photoPath;
    if (old != null && File(old).existsSync()) {
      await File(old).delete();
    }
    await ref
        .read(gymProfileProvider.notifier)
        .update(item.copyWith(photoPath: path));
  }

  /// Photograph a piece of equipment, let the on-device labeler guess what
  /// it is, confirm, and add it with the photo attached.
  Future<void> _scan(ImageSource source) async {
    final file = await _pick(source);
    if (file == null || !mounted) return;
    setState(() => _scanning = true);
    final guesses = await (_detector ??= EquipmentDetector()).detect(file.path);
    if (!mounted) return;
    setState(() => _scanning = false);
    final chosen = await showModalBottomSheet<Equipment>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _GuessSheet(photoPath: file.path, guesses: guesses),
    );
    if (chosen == null || !mounted) return;
    final path = await _store(file, chosen);
    final profile = ref.read(gymProfileProvider);
    final existing = profile.item(chosen) ?? EquipmentItem(type: chosen);
    await ref
        .read(gymProfileProvider.notifier)
        .update(existing.copyWith(photoPath: path ?? existing.photoPath));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${chosen.label} added to your gym.')),
    );
  }

  Future<void> _editItem(EquipmentItem item) async {
    final profile = ref.read(gymProfileProvider);
    final current = profile.item(item.type) ?? item;
    final controller = TextEditingController(text: current.location ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Consumer(
          builder: (context, ref, _) {
            final live =
                ref.watch(gymProfileProvider).item(item.type) ?? current;
            final photo = live.photoPath;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(equipmentIcon(live.type), color: AppColors.secondary),
                    const SizedBox(width: 10),
                    Text(
                      live.type.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    color: AppColors.cardElevated,
                    child: photo != null && File(photo).existsSync()
                        ? Image.file(File(photo), fit: BoxFit.cover)
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.add_a_photo_outlined,
                                  color: AppColors.textMuted,
                                  size: 32,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No photo yet',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _attachPhoto(live, ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('TAKE PHOTO'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _attachPhoto(live, ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('GALLERY'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Where is it? (optional)',
                    hintText: live.type.whereHint,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (v) => ref
                      .read(gymProfileProvider.notifier)
                      .update(live.copyWith(location: v.trim())),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () {
                    ref
                        .read(gymProfileProvider.notifier)
                        .update(
                          live.copyWith(location: controller.text.trim()),
                        );
                    Navigator.of(context).pop();
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        ),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(gymProfileProvider);
    final notifier = ref.read(gymProfileProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your gym'),
        actions: [
          if (!profile.bodyweightOnly)
            TextButton(
              onPressed: () async {
                // One tap used to wipe every item, location and photo.
                final ok = await confirmAction(
                  context,
                  title: 'Switch to bodyweight only?',
                  message:
                      'This removes all your equipment, its locations and '
                      'photos from MY PT.',
                  confirmLabel: 'Remove all',
                  destructive: true,
                );
                if (!ok) return;
                for (final item in profile.items) {
                  final path = item.photoPath;
                  if (path == null) continue;
                  try {
                    final f = File(path);
                    if (f.existsSync()) await f.delete();
                  } catch (_) {}
                }
                await notifier.clear();
              },
              child: const Text('Bodyweight only'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            TrainerBubble(
              text: profile.bodyweightOnly
                  ? 'Tap what you have. Add a photo of each item and I will '
                        'show it when it is time to grab it. Nothing leaves '
                        'your phone.'
                  : 'Got it: ${profile.items.length} items. Tap an item to add '
                        'a photo or a note about where it is.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: _scanning ? 'SCANNING…' : 'SCAN WITH CAMERA',
                    icon: Icons.center_focus_strong_rounded,
                    height: 54,
                    loading: _scanning,
                    onPressed: _scanning
                        ? null
                        : () => _scan(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _scanning
                        ? null
                        : () => _scan(ImageSource.gallery),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Icon(Icons.photo_library_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Point the camera at a machine or weight and I will try to '
              'recognise it on-device. You always get the final say.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            const SectionHeader('Tap to add or remove'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // Taller tiles as the text grows (two-line names clipped at
              // the largest sizes).
              childAspectRatio:
                  1.35 /
                  MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
              children: [
                for (final type in Equipment.values)
                  _EquipmentTile(
                    type: type,
                    item: profile.item(type),
                    selected: profile.available.contains(type),
                    onToggle: () => notifier.toggle(type),
                    onEdit: () => _editItem(
                      profile.item(type) ?? EquipmentItem(type: type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Equipment photos are stored in the app\'s private folder '
                      'on this device and are only shown back to you during a '
                      'session.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EquipmentTile extends StatelessWidget {
  const _EquipmentTile({
    required this.type,
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onEdit,
  });

  final Equipment type;
  final EquipmentItem? item;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = item?.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();
    return Semantics(
      button: true,
      selected: selected,
      label: '${type.label}${selected ? ', available' : ''}',
      excludeSemantics: true,
      onTap: onToggle,
      onLongPress: selected ? onEdit : null,
      child: GestureDetector(
        onTap: onToggle,
        onLongPress: selected ? onEdit : null,
        child: AnimatedContainer(
          duration: AppTokens.normal,
          curve: AppTokens.curve,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                Opacity(
                  opacity: 0.35,
                  child: Image.file(File(photo), fit: BoxFit.cover),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          equipmentIcon(type),
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const Spacer(),
                        if (selected)
                          IconButton(
                            tooltip: 'Photo and location',
                            onPressed: onEdit,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              hasPhoto
                                  ? Icons.photo_rounded
                                  : Icons.add_a_photo_outlined,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      type.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (item?.location?.isNotEmpty == true)
                      Text(
                        item!.location!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the detector's best guesses and a manual fallback.
class _GuessSheet extends StatelessWidget {
  const _GuessSheet({required this.photoPath, required this.guesses});

  final String photoPath;
  final List<EquipmentGuess> guesses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(photoPath),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    guesses.isEmpty
                        ? 'I could not recognise this one. Pick it below and '
                              'I will keep the photo.'
                        : 'My best guess. Tap the right one.',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final g in guesses)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(equipmentIcon(g.type), color: AppColors.primary),
                ),
                title: Text(g.type.label),
                subtitle: Text(
                  'Confidence ${(g.confidence * 100).round()}% · ${g.evidence}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).pop(g.type),
              ),
            if (guesses.isNotEmpty) const Divider(height: 20),
            Text('Something else', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in Equipment.values)
                  if (!guesses.any((g) => g.type == e))
                    ActionChip(
                      avatar: Icon(equipmentIcon(e), size: 16),
                      label: Text(e.label),
                      onPressed: () => Navigator.of(context).pop(e),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
