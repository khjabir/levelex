import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the camera preview scaled to cover the whole area (no letterboxing)
/// with [overlay] drawn in the preview's own coordinate space, so normalised
/// landmark positions map directly onto the picture.
class CameraPreviewFill extends StatelessWidget {
  const CameraPreviewFill({
    super.key,
    required this.controller,
    required this.overlay,
  });

  final CameraController controller;
  final Widget overlay;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (!controller.value.isInitialized || previewSize == null) {
      return const SizedBox.expand();
    }
    // Camera sizes are reported in sensor (landscape) orientation. Swap them
    // when the phone is held in portrait so the box matches what is shown.
    final orientation =
        controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    final deviceLandscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    final sensorLandscape = previewSize.width >= previewSize.height;
    final swap = sensorLandscape != deviceLandscape;
    final width = swap ? previewSize.height : previewSize.width;
    final height = swap ? previewSize.width : previewSize.height;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: width,
          height: height,
          child: CameraPreview(controller, child: overlay),
        ),
      ),
    );
  }
}
