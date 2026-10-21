import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/theme.dart';
import 'share_card.dart';

/// Rasterises the [RepaintBoundary] under [key] at 3× and returns PNG bytes,
/// or null when the key is not attached to a repaint boundary. Waits for the
/// current frame to finish so a freshly built card is fully painted.
Future<Uint8List?> captureShareCard(GlobalKey key) async {
  await WidgetsBinding.instance.endOfFrame;
  final object = key.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) return null;
  final image = await object.toImage(pixelRatio: 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Opens a bottom sheet previewing [data] as a [ShareCard] with a share
/// button. Sharing writes a PNG to the temp directory and hands it to the
/// system share sheet; [text] is the accompanying message (defaults to the
/// card title).
Future<void> showShareSheet(
  BuildContext context,
  ShareCardData data, {
  String? text,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusXl),
      ),
    ),
    builder: (_) => _ShareSheet(data: data, text: text),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.data, this.text});

  final ShareCardData data;
  final String? text;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _cardKey = GlobalKey();
  var _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final bytes = await captureShareCard(_cardKey);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Could not render the share card');
      }
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/levelex-share-$stamp.png');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: widget.text ?? widget.data.title,
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Sharing failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Share your result',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          // Flexible + scaleDown: the preview shrinks on short screens
          // instead of overflowing; the capture is always the full card.
          Flexible(
            child: Center(
              heightFactor: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: _cardKey,
                  child: ShareCard(data: widget.data),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Icon(Icons.ios_share_rounded),
            label: const Text('SHARE'),
          ),
          const SizedBox(height: 10),
          Text(
            'Choose "Save Image" in the share menu to keep it in your photos.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
