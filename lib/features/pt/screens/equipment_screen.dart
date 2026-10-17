import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/section_header.dart';
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

  Future<void> _attachPhoto(EquipmentItem item, ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 82,
      );
    } catch (e) {
      debugPrint('Image pick failed: $e');
    }
    if (file == null || !mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/equipment');
      await folder.create(recursive: true);
      final ext = file.path.split('.').last.toLowerCase();
      final target = File(
        '${folder.path}/${item.type.name}_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await File(file.path).copy(target.path);
      final old = item.photoPath;
      if (old != null && File(old).existsSync()) {
        await File(old).delete();
      }
      await ref
          .read(gymProfileProvider.notifier)
          .update(item.copyWith(photoPath: target.path));
    } catch (e) {
      debugPrint('Saving equipment photo failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the photo.')),
      );
    }
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
              onPressed: notifier.clear,
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
            const SizedBox(height: 20),
            const SectionHeader('Tap to add or remove'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
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
