import 'package:permission_handler/permission_handler.dart';

/// Outcome of a camera permission request.
enum CameraPermissionResult {
  granted,

  /// Denied this time; the user can be asked again.
  denied,

  /// Denied permanently (or restricted); only the system settings can fix it.
  permanentlyDenied,
}

/// Thin wrapper around `permission_handler` so UI code never touches the
/// plugin directly. Camera permission is requested lazily, only when the user
/// starts a workout.
class PermissionService {
  const PermissionService();

  Future<CameraPermissionResult> requestCamera() async {
    final status = await Permission.camera.request();
    return _map(status);
  }

  Future<CameraPermissionResult> cameraStatus() async {
    final status = await Permission.camera.status;
    return _map(status);
  }

  /// Opens the app's page in the system settings.
  Future<bool> openSettings() => openAppSettings();

  CameraPermissionResult _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return CameraPermissionResult.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionResult.permanentlyDenied;
    }
    return CameraPermissionResult.denied;
  }
}
