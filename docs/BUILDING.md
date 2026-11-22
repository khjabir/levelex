# Building Levelex

Toolchain requirements, platform configuration and release builds. The
short version is in the [README](../README.md#getting-started).

## Requirements

| | Version |
|---|---|
| Flutter | 3.47.x stable (verified with 3.47.6), Dart 3.13+ |
| Android | SDK platform 36 and build-tools 36, JDK 17, NDK 28.2.13676358 (downloaded by AGP if missing). minSdk 24, target/compile SDK 36 |
| iOS | macOS with Xcode 15.3+ (16 recommended) and CocoaPods. Deployment target iOS 15.5 (required by ML Kit); 64-bit devices only |

Use a physical device for anything involving the camera: pose detection
needs a real camera, and ML Kit does not run well on the iOS simulator.

## Android

Nothing beyond a standard Flutter Android toolchain. Configuration already
in the project:

- **Manifest** (`android/app/src/main/AndroidManifest.xml`): `CAMERA`,
  `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`,
  `SCHEDULE_EXACT_ALARM` and the `flutter_local_notifications` receivers, so
  reminders survive reboots. The camera plugin's `RECORD_AUDIO` and
  external-storage declarations are removed with `tools:node="remove"`.
- **Gradle** (`android/app/build.gradle.kts`): core-library desugaring
  (required by `flutter_local_notifications`), ProGuard rules, optional
  release signing, and a `resolutionStrategy` that aligns every
  `androidx.work` artifact to 2.10.5.
- **R8 full mode.** ML Kit's `acceleration` dependency pulls in WorkManager
  2.7.0 / Room 2.2.5, whose ProGuard rules predate R8 full mode; without the
  alignment above the release build crashes at launch with "Failed to
  create an instance of androidx.work.impl.WorkDatabase".
  `proguard-rules.pro` also keeps Room `*_Impl` constructors, ML Kit's
  `ComponentRegistrar` implementations and `com.google.mlkit.**`; without
  them every frame fails with `InputImageConverterError` in release builds.
  Always launch a release build once before shipping it.
- **Kotlin** (`android/gradle.properties`):
  `kotlin.jvm.target.validation.mode=warning`, because `tflite_flutter`
  0.12 compiles Java at target 11 and Kotlin at 17.
- **Notifications:** channel `levelex_reminders` (high importance) is
  created at startup. Exact alarms are used when allowed (Android 12+), otherwise
  inexact alarms.

### Why `permission_handler` is pinned to 12.x

Version 13 requires `compileSdk 37`, and Google publishes API 37 only as
minor-versioned platform packages (`android-37.0`) that the Android Gradle
Plugin bundled with this Flutter template cannot resolve. 12.x compiles
against SDK 35/36 and offers the same camera and notification API. Bump it
once Flutter's template moves to an AGP that supports API 37.

### Release signing

Create `android/key.properties`:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without this file, release builds are signed with the debug key so
`flutter build apk --release` still produces an installable APK. Never
commit the keystore or `key.properties`.

### Build

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (about 200 MB,
because it carries native libraries for three CPU types). A per-device APK
is about half that:

```bash
flutter build apk --release --split-per-abi
```

App bundle for Google Play (Play delivers per-device splits):

```bash
flutter build appbundle --release
```

Install on a connected phone:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## iOS

Configuration already in the project:

- `ios/Podfile` sets `platform :ios, '15.5'`, excludes `armv7` and enables
  only the `PERMISSION_CAMERA` and `PERMISSION_NOTIFICATIONS` macros for
  `permission_handler`.
- `ios/Runner/Info.plist` has `NSCameraUsageDescription` and allows
  portrait and landscape; the app keeps every screen except the workout
  camera in portrait.
- `ios/Runner/AppDelegate.swift` registers the `UNUserNotificationCenter`
  delegate so reminders show in the foreground.
- The Strip Style required by `tflite_flutter` for archives is set.

First build:

```bash
cd ios && pod install && cd ..
```

Open `ios/Runner.xcworkspace` in Xcode and set your Team under Runner →
Signing & Capabilities.

### Run on your own iPhone (a free Apple ID is enough)

Sign in to Xcode with your Apple ID (Settings → Accounts), connect and trust
the phone, then:

```bash
flutter run --release
```

With a free account the build is valid for 7 days; on the phone, trust the
developer certificate under Settings → General → VPN & Device Management.

### Signed IPA (needs an Apple Developer team)

```bash
flutter build ipa --release --export-method development
```

Use `--export-method ad-hoc` for registered devices or `app-store` for
TestFlight. The export lands in `build/ios/ipa/`.

### Unsigned IPA for sideloading

Tools such as Sideloadly or AltStore re-sign it with your Apple ID:

```bash
flutter build ios --release --no-codesign
cd build/ios/iphoneos && mkdir -p Payload && cp -R Runner.app Payload/ \
  && zip -qr ../ipa/Levelex-unsigned.ipa Payload && rm -rf Payload
```

## Checks before a release

```bash
dart format .
flutter analyze
flutter test
```

Then install the release build on a real phone and do one camera set: a
release build can pass every test and still fail at launch (see R8 above).
