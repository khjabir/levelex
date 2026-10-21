import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so reminders are shown (and
    // taps are delivered) while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Tells Dart how much memory the device has so the 3D guide can pick
  /// the detailed body or the lite mannequin.
  private func registerDeviceChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "LevelexDevice") else { return }
    let channel = FlutterMethodChannel(name: "levelex/device", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "memoryInfo":
        let totalMb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        result([
          "totalMb": totalMb,
          "lowRamDevice": totalMb < 3072,
          "memoryClassMb": totalMb / 4,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerDeviceChannel(engineBridge.pluginRegistry)
  }
}
