# Levelex

**Level up, one rep at a time.**

Levelex is an on-device workout coach. It reminds you through the day to do a
quick set of push-ups, squats, jumping jacks, burpees, sit-ups, lunges or a
plank hold; the camera counts your reps (or times your hold), corrects your
form while you move, and every rep earns XP towards the next level.
Everything is local: no backend, no account, no cloud.

## Features

- Hourly (configurable) reminders using OS-scheduled local notifications
- Thirteen exercises: push-ups, squats, jumping jacks, burpees, sit-ups,
  lunges, glute bridges, high knees, mountain climbers, tricep dips, squat
  jumps, and timed planks and wall sits, each with its own target, picked on
  the home screen with a live 3D guide
- Quick workout: one tap on the home screen builds a 10-minute full-body
  session from your equipment and walks you through it with auto-starting
  intros
- Challenge mode: add friends by name (optional photo), pick an exercise and
  the rules (most reps in a time limit, or first to a target), then take
  turns in front of the camera. Same counting and coaching for everyone, a
  podium with the cup at the end, a hall of fame, and nothing touches your
  own streak or XP
- Face check is optional: skip it before a set (or during MY PT) and the set
  is still counted, coached and saved, but marked unverified. Unverified sets
  never extend the streak or earn XP, and the app says so before you skip
- Training assistant: animated how-to demos for every exercise, a "common
  mistakes" gallery with the fix for each, live corrections during the set
  (go lower, slow down, hips up, chest up, arms overhead) spoken and shown on
  screen, and a coach's notes summary after the set with tips for next time
- Levels and XP: every rep earns XP (weighted by exercise), finishing a set
  earns a bonus, and you climb from Rookie to Legend. Derived from history,
  so nothing can drift
- Tolerant counting: push-ups count with a slightly shallow bottom and
  relaxed hand placement; "Coaching strictness" in Settings makes counting
  and form checks more relaxed or stricter
- Camera rep counting with Google ML Kit pose detection (on-device)
- One shared rep engine: a continuity tracker that locks on to one body and
  ignores hands, faces or people entering the frame, plus a hysteresis
  rest → work → rest cycle with debouncing, a minimum work duration and a
  cooldown against false positives
- Viewpoint-independent counting: 3D joint angles (ML Kit depth), thresholds
  that adapt to your range of motion, and per-exercise "what must move, what
  must stay planted" rules, so standing, walking or waving the arms never
  counts as a push-up, from the side, the front or above
- Optional live tracking overlay and a copyable tracking report after every
  set (numbers only) for troubleshooting
- Gravity from the motion sensor tells the app which way is down in the
  camera image, so posture and hips-high/low feedback are right in portrait,
  landscape, or with auto-rotate off; rotating or repositioning mid-set is fine
- Voice coach: "Look at the camera", "Ready", "Three, two, one, Go!", every
  rep count (every 10 s and the last 3 s for the plank), form cues and
  "Set complete"
- On-screen depth gauge showing how far into the current rep you are
- Front or back camera (so a friend can hold the phone), switchable mid-set
- One-time face registration: before every set the camera confirms it is the
  registered person, with spot checks during the set. Erasing the face data
  also erases the score, so identities cannot be swapped
- Friendly form feedback: good form, hips too high/low, move back, body or arm
  not visible
- Calibration phase and 3‑2‑1‑GO countdown before counting starts
- Daily totals, daily goal, streaks, per-day history with a 7‑day chart
- Skipped-session tracking that can be switched off (never retroactive)
- Set-complete chime and haptics (respecting user settings)
- Interrupted sets are recovered on next launch
- Dark, energetic UI; portrait, safe-area aware; semantic labels throughout
- Fully offline

## MY PT: the guided personal trainer

MY PT turns Levelex into a session-based trainer. Everything runs on the
device; the "AI" is a rule-based planner and coach, not a cloud model, so it
works offline and nothing about you leaves the phone.

- **Ask for a session**: duration (10–60 min, or custom), a standard split (Push, Pull,
  Legs, Upper, Lower, Full body, Core, HIIT, Mobility) or a custom muscle
  focus, and your level. `WorkoutPlanner` (`lib/features/pt/planner/`) builds
  a warm-up, main block and cool-down from a catalogue of 60+ movements
  (`MovementLibrary`), balancing the target muscles, fitting the time budget
  and preferring the equipment you own. Shuffle for a new plan or swap any
  single movement for an alternative that hits the same muscles.
- **Your gym**: tell MY PT what equipment you have (dumbbells, barbell,
  bench, pull-up bar, bands, cable, box, cardio machines…). Attach a photo
  and a note ("blue rack by the mirror") to each item; during the session
  the "grab this" card shows your own photo and location so you know what
  to pick up next. "Scan with camera" photographs a machine and asks the
  on-device ML Kit image labeler what it is (`EquipmentDetector`); it knows
  benches, bikes, rowers and treadmills well and offers ranked best guesses
  for the rest, with a one-tap manual fallback. Photos live in the app's
  private folder and never leave the phone.
- **Session length**: presets from 10 to 60 minutes or any custom length from
  5 to 180 minutes.
- **3D guides**: every movement is demonstrated by a procedural 3D mannequin
  (`Mannequin3D`, `lib/features/pt/mannequin/`): a forward-kinematics rig
  driven by joint-angle keyframes, rendered with a perspective projection,
  lit depth-sorted capsules, a torso plate, hands and feet. Poses are
  composed with a flat-back hinge helper (`MannequinClips.hinge`) so squats,
  deadlifts, rows and push-ups show safe mechanics: hips back, chest up,
  elbows tucked. Drag to orbit, double-tap to reset. No model files, so it
  stays crisp and tiny. `test/preview/mannequin_preview_test.dart` renders
  every clip to contact sheets (`MANNEQUIN_PREVIEW=<dir> flutter test
  test/preview`) for review.
- **Live view on every item**: the camera stays on for the whole session,
  with the skeleton overlay, the 3D guide picture-in-picture and the coach
  card. Rep movements are counted and corrected; the body part involved in
  a correction turns red on the skeleton and amber on the guide. Timed
  movements and stretches run on the clock with the camera confirming you
  are in frame. If the camera fails, the item falls back to the guide and
  timer only.
- **Equipment navigation**: when a movement needs equipment you photographed,
  the intro card shows the photo full width with your location note, and the
  live view shows the thumbnail under the movement name.
- **Guided flow**: intro card (guide, equipment, cues) → sets with rest
  countdowns → next movement → summary. Movements the camera can follow
  (push-ups, squats, lunges, jumping jacks, burpees, planks, sit-ups, curls,
  presses, rows, raises, hinges, dips, pull-ups, wall sits…) are counted and
  coached live with the same engine as the main app; `GenericAngleAnalyzer`
  and `GenericHoldAnalyzer` cover gym movements through a joint-angle spec.
  Timed movements and cardio machines run on a timer with the guide. Reps
  for untracked movements can be logged by hand.
- **Identity and scoring**: the first time the camera opens, the registered
  face is checked once. Verified sessions earn XP (8 per active minute, 2 per
  tracked rep, +40 for finishing ≥ 80 % of the plan); unverified sessions are
  still coached but not scored.
- **Trainer voice**: `CoachVoice` greets you, explains the plan, calls each
  movement and the equipment to grab, comments after every set, counts the
  rest down, and ends with a summary and a tip for next time; all spoken by
  the voice coach.

## Strength tracking, programmes and progress

Inspired by the open-source [openGym](https://github.com/DuarteSantos8/openGym)
tracker, Levelex also keeps a proper training log around the camera coach.
Everything is reimplemented in Dart and stays on the phone (no account, no
server); the code lives in `lib/features/strength/`.

- **Lift log**: every main-phase set of a MY PT session is written to the log
  (`LiftEntry` / `LiftSet`: load in kg, reps or seconds, warm-up flag,
  optional RPE). Loaded movements get a load stepper on the intro card
  (with a plate calculator for barbell work) so the weight is captured per
  item; any exercise can also be logged by hand from the library. Loads are
  stored in kg and shown in kg or lb (Settings → Lifting).
- **Progression rules** (`ProgressionEngine`): per exercise, choose Linear,
  Greyskull LP, Double progression, Triple progression, Timed or Off. The
  next prescription is derived from the log every time it is needed (nothing
  is stored and nothing can drift): hit every set and the load goes up,
  missed reps never add load, repeated stalls trigger a deload, and the
  reason is always shown in one sentence ("All 3 sets hit 12 at 20 kg last
  time, so add 2.5 kg"). `PlanAdvisor` writes the suggestion and rep target
  onto the MY PT plan; the plan preview and the intro card show it.
- **Records and 1RM**: `RecordBook` detects personal records (heaviest set,
  most reps at a weight, best estimated 1RM, most volume) the moment a
  session is saved; the summary lists them and the trainer announces them.
  `OneRm` offers Epley, Brzycki, Lombardi, O'Conner, Mayhew, Wathan and
  Lander, capped at 12 reps because higher rep counts say more about work
  capacity than strength.
- **Exercise library**: browse every movement by muscle, equipment, "my
  gym" and "logged", with the 3D guide, cues, history chart (estimated 1RM
  or best set), records, the next prescription and the progression rule
  editor.
- **Programmes** (`Routine`): weekly plans on fixed weekdays or an A/B/C
  rotation. Starter templates (Push/Pull/Legs, Upper/Lower, Full Body, 5×5)
  are fitted to your equipment (`StarterPlans`: missing gear is substituted
  by the closest movement for the same muscles, or dropped). The home
  screen shows today's day (or the rest day and the next one) and starts it
  as a MY PT session: the routine's exercises form the main block, wrapped
  in the planner's warm-up and cool-down, with camera coaching and loads.
- **Progress**: a 26-week activity heatmap, a muscle recovery map
  (`MuscleRecovery`: hard sets per muscle decayed with a 24–48 h half-life,
  so you can see what is worked, recovering or fresh), recent records and
  weekly volume.
- **Body**: weigh-ins with a goal line, weekly means and trend, plus
  progress photos with a before/after slider. Photos stay in the app's
  private folder.
- **Data & backup** (Settings): export one JSON backup (sets, MY PT sessions,
  lifts, weigh-ins, routines, rules, challenges, equipment list; never face
  data or photos) through the share sheet and merge it back on any phone;
  import workout history from FitNotes, Strong or Hevy CSV exports (or any
  CSV with a date, an exercise and reps/weight) and body weight from an
  Apple Health export. Imports are idempotent: re-importing the same file
  never duplicates anything, and unknown exercise names are kept as your
  own exercises.

Not carried over from openGym: accounts, passkeys and multi-device sync (Levelex
is single-device and offline), the cloud AI coach and MCP server, the licensed
exercise GIF library (the 3D mannequin stands in), and structural-balance
ratios.

## Tech stack

| Concern | Package |
| --- | --- |
| State management | `flutter_riverpod` 3 |
| Navigation | `go_router` |
| Camera | `camera` (CameraX on Android, AVFoundation on iOS) |
| Pose detection | `google_mlkit_pose_detection` (ML Kit, on-device) |
| Face verification | `google_mlkit_face_detection` + `tflite_flutter` running a bundled MobileFaceNet (`assets/models`) |
| Notifications | `flutter_local_notifications` + `timezone` + `flutter_timezone` |
| Persistence | `shared_preferences` (settings) + `hive_ce` (sessions) |
| Permissions | `permission_handler` 12.x (see note below) |
| Charts | `fl_chart` |
| Audio / haptics | `audioplayers`, `flutter_tts` (voice coach), Flutter `HapticFeedback` |
| Motion | `sensors_plus` (accelerometer → gravity direction) |
| Photos | `image_picker` + `path_provider` (equipment photos, stored privately) |

## Requirements

- **Flutter 3.47.x (stable)** with Dart 3.13+. The project was built and
  verified with Flutter 3.47.6.
- **Android:** Android SDK with platform 36 and build-tools 36, JDK 17,
  NDK 28.2.13676358 (Flutter's default; AGP will download it if missing).
  minSdk 24, targetSdk/compileSdk 36.
- **iOS:** macOS with Xcode 15.3+ (Xcode 16 recommended), CocoaPods.
  Deployment target **iOS 15.5** (required by ML Kit). ML Kit is 64-bit only.

> **Why `permission_handler` is pinned to 12.x:** version 13 requires
> `compileSdk 37`, and Google currently publishes API 37 only as
> minor-versioned platform packages (`android-37.0`) that the Android Gradle
> Plugin bundled with this Flutter template cannot resolve. 12.x compiles
> against SDK 35/36 and offers the same camera/notification permission API.
> Bump it once Flutter's template moves to an AGP that supports API 37.

## Project layout

```
lib/
  main.dart                     bootstrap: storage, notifications, DI, runApp
  app/        app.dart, theme.dart, routes.dart, providers.dart
  core/       constants (thresholds), levels (XP and titles), utils (geometry,
              dates, reminder and stats maths), permissions
  models/     UserSettings, WorkoutSession, DailyStats, PoseResult, FormStatus,
              ExerciseType (the exercise catalogue), Coaching (cue copy)
  services/   pose_detection_service (camera + ML Kit), notification_service,
              storage_service, workout_service, feedback_service, voice_coach
  features/   onboarding, home, workout (controller + UI, push_up_analyzer,
              analysis/ with the shared engine and the other exercises),
              pt (MY PT: models, planner, mannequin, analysis, session,
              screens), history, settings, notifications
  widgets/    shared UI components
test/         unit tests (engine, analyzers, geometry, gravity, face matching,
              streaks, stats, reminders, voice script)
```

Key classes:

- `ExerciseAnalyzer` (`lib/features/workout/analysis/exercise_analyzer.dart`):
  pure Dart. `processPose(PoseResult)` → `ExerciseAnalysis` (rep count, phase,
  form status, depth, tracking quality). `CycleExerciseAnalyzer` is the base
  for every rep-based exercise; `PushUpAnalyzer`, `SquatAnalyzer`,
  `LungeAnalyzer`, `SitUpAnalyzer`, `BurpeeAnalyzer`, `JumpingJackAnalyzer`
  each supply a signal (an angle or an openness measure), a position gate and
  the "what must move" vetoes. `PlankAnalyzer` is a timed hold.
  `ExerciseAnalyzerFactory` builds the right one for an `ExerciseType`.
- `BodyTracker`, `RepCycleCounter`, `TrackingDiagnostics` (same folder):
  continuity/plausibility tracking, the hysteresis cycle with adaptive
  thresholds, and the numbers behind the tracking report.
- `PushUpThresholds` (`lib/core/constants/app_constants.dart`): every tunable
  number (angles, confidence, debounce frames, cooldown, form tolerance).
- `PoseDetectionService`: owns the camera and detector, throttles inference to
  ~12 FPS, converts ML Kit landmarks into normalised `PoseResult`s,
  recomputes the frame rotation every frame (portrait/landscape), switches
  between front and back cameras, and hands low-rate raw frames to
  `FaceService`.
- `FaceService` + `FaceCropper` + `FaceMatcher`: ML Kit finds the face, the
  crop is aligned on the eyes and resized to 112×112, MobileFaceNet (TFLite,
  run in an isolate) produces a 128-d embedding, and cosine similarity
  against the stored template decides match / unknown / mismatch.
- `NotificationService`: schedules each reminder time of day as a
  daily-repeating OS notification; dense schedules fall back to the next 60
  individual occurrences (iOS caps pending notifications at 64) which are
  refreshed whenever the app opens.
- `ReminderSchedule` / `StatsCalculator`: pure reminder and streak maths.

## Setup

```bash
flutter pub get
```

### Android setup

Nothing beyond a standard Flutter Android toolchain. Notable configuration
already in the project:

- `android/app/src/main/AndroidManifest.xml`: `CAMERA`, `POST_NOTIFICATIONS`,
  `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM` and the
  `flutter_local_notifications` receivers (so reminders survive reboots).
- `android/app/build.gradle.kts`: core-library desugaring (required by
  `flutter_local_notifications`), ProGuard rules, optional release signing,
  and a `resolutionStrategy` that aligns every `androidx.work` artifact to
  2.10.5. ML Kit's `acceleration` dependency otherwise pulls in WorkManager
  2.7.0 / Room 2.2.5, whose ProGuard rules predate R8 full mode; the release
  build then crashes on launch with "Failed to create an instance of
  androidx.work.impl.WorkDatabase". `proguard-rules.pro` also keeps Room
  `*_Impl` constructors as a second line of defence, and keeps ML Kit's
  `ComponentRegistrar` implementations plus `com.google.mlkit.**`: ML Kit
  wires its internals reflectively from manifest meta-data, and without these
  rules every frame fails with `InputImageConverterError` in release builds.
- `android/gradle.properties`: `kotlin.jvm.target.validation.mode=warning`
  because `tflite_flutter` 0.12 compiles Java at target 11 and Kotlin at 17,
  which Kotlin 2.4 otherwise rejects.
- Notification channel `pushup_reminders` ("Push-Up Reminders", high
  importance) is created at startup.
- Exact alarms are used when the user allows them (Android 12+); otherwise the
  app falls back to inexact alarms automatically and offers a settings entry
  to allow exact timing.

**Release signing (optional).** Create `android/key.properties`:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

When this file is absent, release builds are signed with the debug key so
`flutter build apk --release` still produces an installable APK.

### iOS setup

- `ios/Podfile` sets `platform :ios, '15.5'`, excludes `armv7`, and enables
  only the `PERMISSION_CAMERA` / `PERMISSION_NOTIFICATIONS` macros for
  `permission_handler`.
- `ios/Runner/Info.plist` contains `NSCameraUsageDescription` and locks the
  iPhone UI to portrait.
- `ios/Runner/AppDelegate.swift` registers the `UNUserNotificationCenter`
  delegate so reminders are shown in the foreground.

First build:

```bash
cd ios && pod install && cd ..
```

Open `ios/Runner.xcworkspace` in Xcode to set your Team / signing.

## Face verification

- Registration is a one-time step from the workout intro or Settings. Five
  embeddings are averaged into a template stored in SharedPreferences; no
  photo is ever kept.
- Every set starts with a verification step (2 consecutive matches). During
  the set the face is spot-checked every ~0.7 s whenever it is visible; three
  consecutive confident mismatches pause the set until the registered user
  verifies again.
- "Erase face data" in Settings deletes the template **and** all sessions,
  totals and streak, so a different person cannot inherit the score. A new
  face can then be registered.
- Thresholds live in `FaceMatchThresholds` (`lib/models/face_template.dart`):
  match ≥ 0.62, mismatch < 0.40 cosine similarity. Tune them if your lighting
  produces false rejections.
- The model (`assets/models/mobilefacenet.tflite`, 5 MB) was converted from
  the Apache-2.0 MobileFaceNet_TF frozen graph; see `assets/models/NOTICE.txt`.

## Permissions

| Platform | Permission | When requested | Why |
| --- | --- | --- | --- |
| Android | `CAMERA` | When you tap **Open camera** | Count reps on-device |
| Android | `POST_NOTIFICATIONS` (13+) | After onboarding / when enabling reminders | Show reminders |
| Android | `SCHEDULE_EXACT_ALARM` | Optional, from Settings | Precise reminder timing |
| iOS | Camera (`NSCameraUsageDescription`) | When you tap **Open camera** | Count reps on-device |
| iOS | Notifications | After onboarding / when enabling reminders | Show reminders |

No other user-facing permissions are requested. The camera plugin's
`RECORD_AUDIO` and external-storage declarations (used only for video
recording) are explicitly removed from the merged manifest with
`tools:node="remove"`. Normal, auto-granted permissions declared by libraries
(`INTERNET` by ML Kit, `WAKE_LOCK`/`FOREGROUND_SERVICE` by WorkManager) remain;
the app itself makes no network calls.

## Running locally

```bash
flutter run
```

Use a physical device: pose detection needs a real camera, and ML Kit does
not support iOS simulators well.

## Testing

```bash
flutter test
```

Unit tests (179) cover joint-angle geometry, gravity rotation, the rep cycle
counter (one rep, multiple reps, hysteresis band, noisy frames, too-fast
movement, cooldown, target completion, shallow attempts), the body tracker,
every exercise analyzer driven with synthetic bodies from several camera
views (including false positives such as a hand in front of the lens),
coaching episodes and copy, XP and levels, face matching, daily statistics,
streaks across day/month/year boundaries, reminder slot generation, next
reminder, skipped-slot detection, the voice script and model serialisation.

Static checks:

```bash
dart format .
flutter analyze
```

## Building

### Android APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

App bundle for Play:

```bash
flutter build appbundle --release
```

### iOS IPA

**Signed IPA (needs an Apple Developer team).** In Xcode open
`ios/Runner.xcworkspace`, select the Runner target → Signing & Capabilities,
tick "Automatically manage signing" and choose your Team. Then:

```bash
flutter build ipa --release --export-method development
```

Use `--export-method ad-hoc` for devices registered in your team, or
`app-store` for TestFlight. The export lands in `build/ios/ipa/`. An IPA
cannot be signed without Apple credentials; the project already sets the
Strip Style required by `tflite_flutter` for archives.

**Quickest way onto your own iPhone (free Apple ID is enough).** Sign in to
Xcode with your Apple ID (Settings → Accounts), connect the phone, trust the
computer, then:

```bash
flutter run --release
```

Xcode registers the device and signs a development build on the fly (valid
for 7 days with a free account; on the phone enable Settings → General → VPN
& Device Management → trust your developer certificate).

**Unsigned IPA for sideloading.** The release bundle can be packaged without
a signature; tools such as Sideloadly or AltStore re-sign it with your Apple
ID when installing:

```bash
flutter build ios --release --no-codesign
cd build/ios/iphoneos && mkdir -p Payload && cp -R Runner.app Payload/ \
  && zip -qr ../ipa/Levelex-unsigned.ipa Payload && rm -rf Payload
```

To verify the project compiles without signing:

```bash
flutter build ios --release --no-codesign
```

## Orientation and cameras

The workout screen allows portrait and landscape (the rest of the app stays
portrait). Rotation is recomputed per frame from the camera plugin's device
orientation, so the skeleton overlay and the "hips high/low" direction stay
correct whichever way the phone is propped. The flip button switches between
front and back cameras; the last choice is remembered in Settings.

## How counting works

1. Camera frames (NV21 on Android, BGRA on iOS) are handed to ML Kit without
   copying, at most every 80 ms (~12 FPS), and never while a previous
   inference is still running.
2. Landmarks are converted to uniform 3D units (pixels ÷ longest frame side,
   including ML Kit's depth), so angles are undistorted and viewpoint
   independent. Joint angles are measured in the image plane and fall back to
   the 3D angle only when a limb is foreshortened or bends towards the camera.
3. Gravity: the accelerometer reading is rotated into the camera frame
   (`GravityEstimator`), giving the true "down" direction in any orientation,
   even with auto-rotate off. Without a sensor the image's y axis is used.
4. Continuity (`BodyTracker`): the skeleton must be plausible (a real torso,
   not a hand or a face), and its centre may not jump more than 0.8 body
   sizes between frames. A jump, a missing body or a change of orientation
   resets the in-flight rep so a hand waved in front of the lens or a second
   person walking through cannot produce counts.
5. Position gate per exercise: push-ups and the plank need the hands below
   the shoulders and the body within 55° of horizontal; squats, lunges,
   jumping jacks and burpees need an upright body; sit-ups need bent knees.
   This is deliberately permissive; the decisive check is per rep.
6. Signal and cycle (`RepCycleCounter`): each exercise reduces the pose to one
   number (mean elbow angle for push-ups, knee angle for squats and lunges,
   torso angle for sit-ups, body tilt for burpees, an arms-up + feet-apart
   openness for jumping jacks). Defaults such as ≥ 150° = up and ≤ 100° =
   down for push-ups use hysteresis and 2 agreeing frames; once enough range
   has been seen the thresholds adapt to your own range of motion, so partial
   lock-outs still count.
7. Vetoes: a push-up descent counts only if the shoulders travelled ≥ 0.2
   upper-arm lengths while the wrists moved less than 60 % of that (hands
   planted, body moving). Squats need the hips to drop with the feet planted;
   sit-ups need the shoulders to rise with the hips planted; burpees need the
   hands on the floor. Arm swings, elbow twitches and walking fail these.
8. A rep counts on work → rest when the work phase lasted ≥ 200 ms and
   ≥ 400 ms passed since the previous rep. A descent that got at least 40 %
   of the way down but came back up without reaching the work position is
   reported as a shallow attempt: it is not counted, the coach says "go
   lower", and it appears in the coach's notes. The plank instead accumulates
   time while the body is tracked, horizontal and supported, crediting at
   most 400 ms per frame gap, so a dropout never adds time.
9. Form: shoulder→hip→ankle angle below the straight-body threshold plus the
   hip's deviation from the shoulder–ankle line along "up" yields "hips too
   high" or "hips too low" for push-ups and the plank; squats and lunges
   flag a torso folding forward, jumping jacks flag arms that stop short of
   overhead. Posture mistakes count once per episode after persisting for
   0.7 s (`CoachingTracker`), so a single noisy frame never becomes a note.
   Strictness is configurable in Settings.

Troubleshooting: Settings → Camera → "Show tracking details" overlays the live
signal, thresholds, tilt and tracking quality on the workout screen, and the
completion screen has "Copy tracking report" (counts and numbers only, no
images) to share when a set did not count as expected.

## Known limitations

- Form feedback is a simple geometric heuristic, not medical or coaching
  advice. A side view with the whole body in frame works best.
- Counting accuracy depends on lighting, distance and the whole body being in
  frame. Very loose clothing or a cluttered background can reduce confidence.
  Jumping jacks and burpees need the most room: the hands overhead and the
  floor position must both stay inside the frame.
- Daily totals add up reps across all rep-based exercises; plank seconds are
  shown per session and on the home card but are not added to rep totals.
- Reminders rely on the OS. Some Android OEM battery optimisers delay or drop
  scheduled notifications (see https://dontkillmyapp.com). Without the exact
  alarm permission, Android may deliver reminders a few minutes late.
- iOS keeps at most 64 pending notifications; schedules denser than 60 slots
  per day are refreshed each time the app is opened.
- "Skipped" sessions are only evaluated when the app runs; they are never
  counted for times before onboarding or while tracking is disabled.
- Overnight reminder windows (end time before start time) are not supported;
  the end time must be after the start time.
- Face verification is a convenience lock, not biometric security: a good
  photo of the registered user held to the camera may pass. Low light,
  strong backlight or face coverings can cause "not recognised"; retry with
  the face well lit.
- ML Kit's depth estimate is noisier than its x/y, so extreme angles (camera
  directly above or far below the body) are less reliable than side, front
  or elevated-front placements.
- The voice coach needs a text-to-speech engine (Google TTS on Android is
  standard); without one the app simply stays silent.
- The app outside the workout screen is portrait-only.

## Roadmap

Planned, not yet implemented:

- **Multiplayer challenges:** several registered users on the same phone or
  nearby phones, each verified by face, competing for the most reps; the
  winner takes the cup for the day/week.
- **More exercises:** pull-ups, mountain climbers and wall sits. Adding one
  means a new `CycleExerciseAnalyzer` subclass (or a timed analyzer) in
  `lib/features/workout/analysis/` plus an `ExerciseType` entry; the workout
  controller, HUD, history and reminders stay the same.
- **Challenge history and leaderboards**, still local-first.

## Privacy

Levelex processes camera frames on your device to detect body
position and count push-ups. Camera footage is not uploaded or stored. Pose
landmarks are used only in memory to count reps and are discarded
immediately. The registered face is stored only as a numeric embedding on the
device and can be erased (together with the score) at any time. Workout
history and settings are stored locally on the device. There are no accounts,
no analytics and no network calls.

## Branding

The mark is a figure mid star-jump in the brand gradient. The icon and
splash are generated from vector art by `tool/logo/make_logo.swift`
(CoreGraphics) and fanned out with `flutter_launcher_icons` and
`flutter_native_splash`; the project skill `.claude/skills/logo-creator`
documents the whole loop, including how to try new variants:

```bash
cd tool/logo && swiftc -O make_logo.swift -o make_logo && ./make_logo ../../assets/icon/icon.png figure full
dart run flutter_launcher_icons && dart run flutter_native_splash:create
```

The in-app mark (`BrandMark`) is a `CustomPainter` with the same geometry,
so it stays crisp at any size. Fonts: Inter (OFL).

## Fonts & licenses

- Inter (SIL Open Font License) — `assets/fonts/OFL.txt`
- MobileFaceNet weights (Apache License 2.0) —
  `assets/models/LICENSE-MobileFaceNet_TF.txt` and `NOTICE.txt`
- Notification icon derived from Material Symbols (Apache 2.0)
