# Roadmap

What to build next, in priority order. The November 2026 audit and
everything it fixed is in [AUDIT.md](AUDIT.md).

Each item says why it matters, where the work is, and when it counts as
done.

## Decisions needed

These are product calls to make before the related work starts.

1. **Should unverified sets count towards the daily challenge?** Today a set
   that skipped the face check still counts towards the challenge and its
   +60 XP bonus, although unverified sets earn no XP anywhere else. Tests
   pin the current rule (`test/daily_challenge_test.dart`); changing it is
   small.
2. **Should restoring a backup bring the settings across?** Today a restore
   imports records only and keeps the phone's goal, rest days, targets,
   unit and seen badges.
3. **Should camera sets work without registering a face?** The face check
   can be skipped per set, but the home-screen camera sets still require a
   one-time registration first (`workout_intro_screen.dart` shows only
   "Register face" until then). MY PT does not require it.
4. **Which license?** The repository has no `LICENSE` file, so by default
   nobody else may use the code. Third-party assets are already compatible
   with common open-source licenses (CC0 body mesh, Apache-2.0 face model,
   OFL font).

## Next fixes

### Before a public release

1. **Field-test the new counting on real people.**
   - Why: the rep-counting rework was measured with Google ML Kit on
     rendered videos of the 3D athlete, run on an emulator. It has not yet
     been tried on a real phone with a real person, real clothing and real
     lighting.
   - Where: record sets on the Samsung and the iPhone, 13 exercises × side,
     front and diagonal placements, two or three people. Copy the tracking
     report after each set; convert the misses into replay fixtures
     (`test/fixtures/`, `test/support/pose_replay.dart`).
   - Done when: every exercise counts within one rep from its recommended
     placements, and the real recordings run in `flutter test`.
2. **Verify the iOS build on a device.**
   - Why: the audit changed iOS-specific behaviour (the completion chime's
     audio session, app lifecycle handling, wakelock) and the iPhone was
     unavailable, so none of it has run on iOS.
   - Done when: a camera set, a MY PT session and a challenge round complete
     on the iPhone with the voice coach audible in silent mode.
3. **Progress heatmap counts empty MY PT sessions.**
   - Why: a MY PT session ended before any work still lights up a day on
     the Progress heatmap. The routine logic already ignores such sessions.
     The screen can also read "3 active days" next to "longest streak 0",
     because the heatmap counts unverified sets and hand-logged lifts while
     the streak counts verified work only.
   - Where: `lib/features/strength/screens/progress_screen.dart` (the
     `r.items.isNotEmpty` check); use the same rule as `routineRunsProvider`
     (`!i.skipped && i.setsDone > 0`), and label the streak as "verified".
   - Done when: an empty session leaves the heatmap unchanged, with a test.
4. **3D guide floor grid draws outside its card.**
   - Why: the grid lines run past the card's rounded border into the card
     below (visible on exercise intros and the library detail screen).
   - Where: clip `FigurePainter` and `MannequinPainter` (or the `Guide3D`
     card) to the card's rounded rectangle.
5. **Cut the Android download size.**
   - Why: the release APK is 199 MB because it carries native libraries for
     three CPU types, including x86_64, which only emulators use.
   - Where: publish an app bundle for Play, and per-ABI APKs
     (`flutter build apk --split-per-abi`) for direct installs; leave x86_64
     out of release builds.
   - Done when: an arm64 install is about 100 MB or less.
6. **Floor exercises filmed end-on.**
   - Why: 7 of the 78 measured sequences still miss reps: glute bridges and
     sit-ups filmed from the head or feet, and mountain climbers from the
     front, far away or a diagonal. The tips tell people to film from the
     side, but nothing checks it.
   - Where: see the placement assistant below; then try the accurate ML Kit
     model for floor exercises (73 of 78 right against the base model's 71).

### Soon after

7. **End-to-end test of a camera set.**
   - Why: no automated test drives intro → camera → counting → summary. The
     camera screen cannot even be reached on an emulator without a
     registered face.
   - Where: a debug-only fake pose source fed from the replay fixtures, and a
     debug face bypass, used by a new `integration_test/` suite.
8. **Continuous integration.**
   - Why: format, analyze and the 695 tests only run when someone remembers.
   - Where: a GitHub Actions workflow for `dart format --set-exit-if-changed`,
     `flutter analyze`, `flutter test` and a release build. Add a layout
     test that opens every screen on a small phone at 2× text and fails on
     overflow (the audit's sweep ran outside the test suite).
9. **Reminder gaps.**
   - Overnight reminder windows (end time before start time) are not
     supported.
   - Skipped sessions are only evaluated when the app runs.
   - Some Android makers' battery optimisers delay or drop reminders; add
     in-app guidance for the detected manufacturer.
10. **Liveness for the face check.**
    - Why: a good photo of the registered user can pass verification.
    - Where: ask for a blink or a head turn using ML Kit face
      classification (eye-open probability, head angles) in `FaceService`.
11. **Upgrade `permission_handler` to 13.x** once Flutter's Android template
    supports compile SDK 37 (see [docs/BUILDING.md](docs/BUILDING.md)).

## Next features

1. **Placement assistant.** During calibration, read the camera angle from
   the pose (side, front, diagonal, end-on) and tell the user when it is a
   poor angle for the chosen exercise ("turn the phone to your side").
   Fixes most of the remaining end-on misses at the source.
2. **Accurate pose model on capable phones.** The accurate model counted 73
   of 78 sequences against the base model's 71. Benchmark its frame rate on
   mid-range phones and offer Auto, Fast and Accurate in Settings.
3. **Rep quality timeline.** On the summary screen, show each rep's depth
   and tempo, with shallow attempts marked, so people see where a set
   started to slip.
4. **More camera-tracked exercises.** Candidates: pike push-ups, side
   plank, calf raises, step-ups, bicycle crunches. Each needs an
   `ExerciseType` entry, an analyzer, a 3D clip, and replay recordings from
   the six placements before it ships.
5. **Health Connect and Apple Health export.** Opt-in, on-device writing of
   workouts and active minutes. Today only body weight is imported, from an
   Apple Health export file.
6. **Home-screen widget.** Streak, today's progress and the daily challenge,
   with one tap to start a set.
7. **Challenges across nearby phones.** Each player on their own phone,
   results merged over the local network with no server. Challenge mode
   today runs on one phone.
8. **Localisation.** The app is English-only with strings in the widgets.
   Move them to ARB files and add `flutter_localizations`.
9. **Automatic local backups.** A scheduled JSON export to a folder the user
   picks, so a lost phone does not mean lost history.
10. **Light theme.** The app is dark-only (`ThemeMode.dark` in
    `lib/app/app.dart`).
