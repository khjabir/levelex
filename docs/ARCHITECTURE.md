# Architecture

How Levelex is put together: the code layout, the camera and rep-counting
pipeline, face verification, reminders and the 3D guide. For setting up a
machine and building release binaries see [BUILDING.md](BUILDING.md); for
what each screen does see [FEATURES.md](FEATURES.md).

## Contents

- [Code layout](#code-layout)
- [Key classes](#key-classes)
- [How counting works](#how-counting-works)
- [Measuring the counters](#measuring-the-counters)
- [Face verification](#face-verification)
- [Orientation and cameras](#orientation-and-cameras)
- [Reminders](#reminders)
- [The 3D guide](#the-3d-guide)
- [Branding assets](#branding-assets)

## Code layout

```
lib/
  main.dart            bootstrap: storage, notifications, providers, runApp
  app/                 app shell, theme, routes, top-level providers
  core/
    constants/         every tunable threshold (PushUpThresholds, …)
    device/            device capability checks (low-RAM detection)
    engagement/        daily challenges, achievements, weekly report, XP
    levels/            levels and titles
    permissions/       camera and notification permission flows
    utils/             geometry, dates, stats and reminder maths
  models/              ExerciseType catalogue, PoseResult, WorkoutSession,
                       UserSettings, FormStatus, coaching copy
  services/            camera + ML Kit pose detection, face verification,
                       notifications, storage, voice coach, feedback
  features/
    workout/           camera set: controller, screens, analyzers
      analysis/        the shared rep engine and every exercise analyzer
    pt/                MY PT: planner, movement library, session, 3D guide
      figure/          realistic body (GLB loader, CPU skinning, painter)
      mannequin/       rig, pose clips and the lite capsule mannequin
    challenge/         multi-person challenge mode on one phone
    engagement/        achievements, weekly report, intervals screens
    strength/          lift log, progression, records, routines, body,
                       import/backup
    history/           calendar and per-day history
    home/ onboarding/ settings/ notifications/ face/
  widgets/             shared UI components
test/                  unit and widget tests, replay fixtures, previews
tool/
  figure/              Blender build script for the 3D body
  pose_probe/          ML Kit probe app for measuring the counters
  logo/                CoreGraphics generator for the icon and splash
```

State is managed with Riverpod 3 and navigation with go_router. Analyzers,
planners and calculators are plain Dart with no Flutter dependency, so most
of the logic is unit-tested without a device.

## Key classes

| Class | Where | Role |
|---|---|---|
| `PoseDetectionService` | `lib/services/pose_detection_service.dart` | Owns the camera and the ML Kit detector, throttles inference to ~12 FPS, converts landmarks to normalised `PoseResult`s, recomputes the frame rotation every frame, switches cameras and hands low-rate frames to `FaceService` |
| `PoseResult` | `lib/models/pose_result.dart` | One frame's landmarks with geometry helpers: joint angles, planar heights along "up", distances |
| `GravityEstimator` | `lib/core/utils/gravity.dart` | Rotates the accelerometer reading into the camera frame so "down" is known in any orientation |
| `ExerciseAnalyzer` | `lib/features/workout/analysis/exercise_analyzer.dart` | `processPose(PoseResult)` → `ExerciseAnalysis` (reps, phase, form, depth, tracking quality). `CycleExerciseAnalyzer` is the base for rep exercises |
| `ExerciseAnalyzerFactory` | `analysis/analyzer_factory.dart` | Picks the analyzer for an `ExerciseType` |
| `BodyTracker` | `analysis/body_tracker.dart` | Locks on to one plausible body and rejects impossible jumps between frames |
| `RepCycleCounter` | `analysis/rep_cycle_counter.dart` | Rest → work → rest hysteresis with debouncing, adaptive thresholds, cooldown and dropout handling |
| `DecayingMax`, `DropRatio` | `analysis/signals.dart` | A slowly forgetting maximum, and a height expressed as a fraction of the user's own top position |
| `CoachingTracker` | `analysis/coaching_tracker.dart` | Turns persistent posture faults into one coaching episode each |
| `TrackingDiagnostics` | `analysis/tracking_diagnostics.dart` | The numbers behind the live overlay and the copyable tracking report |
| `WorkoutController` | `lib/features/workout/workout_controller.dart` | Runs a camera set: permissions, face check, calibration, countdown, counting, pause/resume, saving |
| `FaceService`, `FaceCropper`, `FaceMatcher` | `lib/services/face_service.dart`, `lib/core/utils/face_crop.dart`, `lib/models/face_template.dart` | Face detection, alignment, MobileFaceNet embedding and matching |
| `NotificationService`, `ReminderSchedule` | `lib/services/notification_service.dart`, `lib/core/utils/reminder_calculator.dart` | Reminder scheduling and its maths |
| `StatsCalculator` | `lib/core/utils/stats_calculator.dart` | Daily totals and streaks (rest days bridge a streak) |
| `WorkoutPlanner`, `MovementLibrary` | `lib/features/pt/planner/`, `lib/features/pt/models/` | MY PT session building from 60+ movements |
| `ProgressionEngine`, `RecordBook`, `PlanAdvisor` | `lib/features/strength/logic/` | Load progression, records and the next prescription |

Analyzer per exercise:

| Exercise | Analyzer | File |
|---|---|---|
| Push-ups | `PushUpAnalyzer` | `lib/features/workout/push_up_analyzer.dart` |
| Squats, squat jumps, lunges | `SquatAnalyzer`, `SquatJumpAnalyzer`, `LungeAnalyzer` | `analysis/leg_analyzers.dart` |
| Sit-ups, glute bridges, burpees, jumping jacks | `SitUpAnalyzer`, `GluteBridgeAnalyzer`, `BurpeeAnalyzer`, `JumpingJackAnalyzer` | `analysis/floor_analyzers.dart` |
| High knees, mountain climbers | `AlternatingKneeAnalyzer` | `analysis/alternating_analyzer.dart` |
| Tricep dips | `TricepDipAnalyzer` | `analysis/generic_analyzers.dart` |
| Plank | `PlankAnalyzer` | `analysis/plank_analyzer.dart` |
| Wall sit | `GenericHoldAnalyzer` | `analysis/generic_analyzers.dart` |
| MY PT gym movements | `GenericAngleAnalyzer`, `GenericHoldAnalyzer` driven by a `TrackingSpec` | `analysis/generic_analyzers.dart`, `analysis/tracking_spec.dart` |

Every tunable number (confidence floors, thresholds per strictness level,
debounce frames, cooldowns, form tolerances) lives in `PushUpThresholds`
(`lib/core/constants/app_constants.dart`).

## How counting works

1. **Frames.** Camera frames (NV21 on Android, BGRA on iOS) go to ML Kit
   without copying, at most every 80 ms (~12 FPS) and never while a previous
   inference is still running.
2. **Units.** Landmarks are converted to uniform units (pixels ÷ the longest
   frame side). Heights and angles are measured in the image plane. ML Kit's
   depth estimate carries tens of pixels of noise, so a joint angle uses the
   3D angle only when a limb points straight at the camera. (Preferring the
   3D angle whenever it disagreed turned a straight arm seen from the side
   into a 140° "bend", and side-view push-ups never counted.)
3. **Gravity.** `GravityEstimator` rotates the accelerometer reading into the
   camera frame, giving the true "down" in any orientation, even with
   auto-rotate off. Without a sensor the image's y axis is used.
4. **Continuity.** `BodyTracker` requires a plausible skeleton (a real torso,
   not a hand or a face) whose centre does not move further between frames
   than a body can, scaled by the time since the last frame, so a dropped
   frame during a burpee is not a "jump". A frame or two without a body
   keeps the rep in progress. Only a gap of ~0.9 s, a jump or an
   orientation change starts over, and a body that reappears where it was
   resumes without warming up again.
5. **Position gate.** Push-ups and the plank need the hands below the
   shoulders and, with a motion sensor, the body within 65° of horizontal;
   squats, lunges, jumping jacks and high knees need an upright body;
   sit-ups need bent knees. The gate is deliberately permissive. The
   decisive check is per rep.
6. **Signal and cycle.** Each exercise reduces the pose to one number,
   relative to the person's own top position (`DropRatio`):

   | Exercise | Signal |
   |---|---|
   | Push-ups, tricep dips | Shoulders' height above the hands (1 at the top, ≈0.8 with the elbows at 105°, ≈0.45 with the chest at the floor) |
   | Squats, squat jumps, lunges | Hips' height above the (planted) ankles |
   | Burpees | Shoulders' height above the feet |
   | Sit-ups | Shoulders' rise above the hips, in torso lengths |
   | Glute bridges | Hips' rise above the shoulders, in torso lengths |
   | Jumping jacks | Arms-up plus feet-apart openness (feet only when the camera faces them) |
   | High knees, mountain climbers | Left knee's lead minus the right's along the body axis, centred on its recent range; each arrival on the other side is a rep |

   `RepCycleCounter` switches phase after two agreeing frames. Once enough
   range has been seen, the thresholds adapt to the user's own range of
   motion, within a cap so habitual quarter reps never count.
7. **Vetoes** ("what must move, what must stay planted"). A push-up descent
   counts only if the shoulders travelled while the wrists stayed planted;
   squats need the hips to drop with the feet planted; sit-ups need the
   shoulders to rise with the hips planted; burpees need the hands near the
   floor (a squat is not a burpee); jumping jacks filmed from the front need
   the feet apart. Arm swings, elbow twitches and walking fail these.
8. **Counting.** A rep counts on work → rest when the work phase lasted at
   least 200 ms and 400 ms have passed since the previous rep. A descent that
   got at least 40% of the way down but came back up early is a shallow
   attempt: not counted, the coach says "go lower", and it appears in the
   coach's notes. The plank and the wall sit accumulate time while the body
   is tracked in position, crediting at most 400 ms per frame gap. A wall
   sit filmed from the front is recognised by thighs level over upright
   shins.
9. **Form.** The shoulder → hip → ankle angle plus the hip's deviation from
   the shoulder–ankle line yields "hips too high" or "hips too low" for
   push-ups and the plank; squats and lunges flag a torso folding forward;
   jumping jacks flag arms that stop short of overhead. A fault counts once
   per episode after persisting for 0.7 s (`CoachingTracker`), so one noisy
   frame never becomes a note.
10. **Strictness.** Settings → Coaching strictness sets the depth: push-ups
    count from about 105° of elbow bend (balanced), 115° (relaxed) or 85°
    (strict).
11. **Interruptions.** Pause, a camera switch or an identity re-check
    mid-set keep the reps already done; the set resumes from there.

Troubleshooting: Settings → Camera → "Show tracking details" overlays the
live signal, thresholds, tilt and tracking quality on the workout screen.
The completion screen has "Copy tracking report" (counts and numbers only,
no images).

## Measuring the counters

The counters are measured against the real detector rather than only
synthetic poses:

1. `test/preview/pose_frames_test.dart` renders the 3D athlete doing every
   camera-tracked exercise from six phone placements: side (landscape and
   portrait), phone on its side with the app in portrait, front, diagonal
   and far away.
2. `tool/pose_probe/` is a small Flutter app that runs Google ML Kit (base
   and accurate models, stream mode, the same plugin as the app) over those
   frames on an Android emulator and writes the landmarks.
3. `test/preview/pose_replay_test.dart` replays the landmarks through the
   analyzers and reports how many reps each sequence counted.

Result of the November 2026 rework: 40 of 78 sequences counted correctly
before, 71 (base model) and 73 (accurate model) after. The remaining misses
are floor exercises filmed end-on, from the head or the feet: glute bridges,
mountain climbers and some sit-ups. 35 of the recordings ship in
`test/fixtures/mlkit_pose_sequences.json.gz` and are replayed by
`test/mlkit_replay_test.dart` on every test run. Step-by-step instructions
are in [`tool/pose_probe/README.md`](../tool/pose_probe/README.md).

## Face verification

- Registration is a one-time step from the workout intro or Settings. Five
  embeddings are averaged into a template stored in SharedPreferences; no
  photo is kept.
- Pipeline: ML Kit finds the face, `FaceCropper` aligns it on the eyes and
  resizes it to 112×112, MobileFaceNet (TFLite, run in an isolate) produces
  a 128-d embedding, and cosine similarity against the template decides
  match, unknown or mismatch.
- Every set starts with a verification step (two consecutive matches).
  During the set the face is spot-checked every ~0.7 s whenever it is
  visible; three consecutive confident mismatches pause the set until the
  registered user verifies again.
- The check can be skipped per set: the set is still counted, coached and
  saved, but marked unverified, and unverified sets never extend the streak
  or earn XP.
- "Erase face data" in Settings deletes the template and all sessions,
  totals and streak, so a different person cannot inherit the score.
- Thresholds live in `FaceMatchThresholds` (`lib/models/face_template.dart`):
  match ≥ 0.62, mismatch < 0.40 cosine similarity.
- The model (`assets/models/mobilefacenet.tflite`, 5 MB) was converted from
  the Apache-2.0 MobileFaceNet_TF frozen graph; see
  `assets/models/NOTICE.txt`.

This is a convenience lock, not biometric security: a good photo of the
registered user may pass.

## Orientation and cameras

The workout screen allows portrait and landscape; the rest of the app is
portrait. Rotation is recomputed per frame from the camera plugin's device
orientation, so the skeleton overlay and the "hips high/low" direction stay
right however the phone is propped. The flip button switches between front
and back cameras mid-set; the last choice is remembered.

## Reminders

`NotificationService` schedules each reminder time of day as a
daily-repeating OS notification. Dense schedules fall back to the next 60
individual occurrences (iOS caps pending notifications at 64), refreshed
whenever the app opens. Android uses exact alarms when the user allows
them and falls back to inexact alarms otherwise. The evening streak nudge
(`StreakNudge`) is rescheduled on every app open and after every saved set,
so a finished day stays silent.

## The 3D guide

Every movement is demonstrated by a rigged human body (`Guide3D`,
`lib/features/pt/figure/`), with the capsule mannequin (`Mannequin3D`) as
the lite fallback.

**The body asset.** The body is the male realistic figure from Blender
Studio's CC0 [Human Base
Meshes](https://www.blender.org/download/demo-files/#asset-bundles) bundle
(v1.4.1), prepared by `tool/figure/build_figure.py` in Blender:

- The sculpt's face sets place the joints; the spine has two segments so
  the trunk bends through the back.
- The mesh is scaled to the rig's hip height, simplified to about 36k
  triangles and weighted with bone heat to a 21-bone armature.
- Clothing edges (neckline, sleeves, hems, hairline) are cut as smooth
  curves, and every face gets a material: skin, hair, eyes, shirt, shorts,
  or a muscle (`biceps`, `quads`, `shirt.chest`, `shorts.glutes`, …) so the
  working muscles can light up through the cloth.
- Ambient occlusion is baked with Cycles into the red vertex-colour channel
  and a skin-warmth weight into the green one.
- One animation per movement is keyed from the same joint poses as the rig
  (`tool/figure/poses.json`, exported by
  `test/preview/figure_poses_export_test.dart`).

The result ships as a 1.6 MB GLB (`assets/figure/athlete.glb`). It is
committed, so normal builds do not need Blender.

**Rendering.** `FigureModel` parses the GLB and does CPU skinning;
`FigurePainter` lights the vertices (key, fill, rim, specular, hemisphere
ambient, baked occlusion and warmth), sorts triangles far to near and draws
them with `Canvas.drawVertices`. There is no GPU scene library: it works on
any device and costs two to three milliseconds of CPU per frame on a laptop.
The feet are clamped to the floor and the silhouette is projected as a
shadow. Idle motion (breathing, weight shift, arm drift, the head turning
toward the camera) keeps the figure from looking frozen.

**Motion.** Poses are composed with a flat-back hinge helper
(`MannequinClips.hinge`). Hands, feet, hips and the back stay planted
between keyframes; push-ups and dips solve their arm angles so the hands
stay put at full depth; lying poses keep the feet flat; loops that do not
ping-pong close on a copy of their first keyframe instead of rewinding.
Reps use a smootherstep ease with a natural tempo (the lowering phase 15%
longer), and a change of movement cross-fades over 0.4 s. Drag to orbit,
double-tap to reset.

**Settings → 3D guide** offers Auto, Detailed and Lite. Auto uses the
detailed body unless the phone reports low RAM.

**Previews and rebuilds.**

```bash
FIGURE_PREVIEW=<dir> flutter test test/preview/figure_preview_test.dart      # body, all clips
FIGURE_HEAD=<dir> flutter test test/preview/figure_head_preview_test.dart    # head close-up
MANNEQUIN_PREVIEW=<dir> flutter test test/preview/mannequin_preview_test.dart
FIGURE_BENCH=1 flutter test test/preview/figure_benchmark_test.dart          # frame timing
```

To rebuild the body after changing the script or the poses, download
`human-base-meshes-bundle-v1.4.1.zip` from the Blender demo-files page
(50 MB, not vendored), export the poses and run Blender:

```bash
FIGURE_POSES=$PWD/tool/figure/poses.json flutter test test/preview/figure_poses_export_test.dart
blender -b -P tool/figure/build_figure.py -- \
  --poses tool/figure/poses.json --out assets/figure/athlete.glb \
  --base <unzipped>/human_base_meshes_bundle.blend \
  --base-object GEO-body_male_realistic --base-tris 36000
```

## Branding assets

The mark is a figure mid star-jump in the brand gradient. The icon and
splash are generated from vector art by `tool/logo/make_logo.swift` and
fanned out with `flutter_launcher_icons` and `flutter_native_splash`:

```bash
cd tool/logo && swiftc -O make_logo.swift -o make_logo && ./make_logo ../../assets/icon/icon.png figure full
cd ../.. && dart run flutter_launcher_icons && dart run flutter_native_splash:create
```

The in-app mark (`BrandMark`) is a `CustomPainter` with the same geometry.
The project skill `.claude/skills/logo-creator` documents the loop.
