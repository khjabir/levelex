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

1. **Create the Android release key, then publish the first release.**
   - Why: the website's download buttons point at GitHub's latest release,
     and there is none yet. Without `android/key.properties`, release builds
     are signed with the build machine's debug key, and Android installs an
     update only over an app signed with the same key: everyone would have
     to uninstall, losing their history, to move to a properly signed build.
   - Where: [docs/RELEASING.md](docs/RELEASING.md) (keystore, then
     `tool/release/build_release.sh --ios`, then a GitHub release tagged
     `v1.0.0`).
   - Done when: the website shows the version and its download buttons
     install the app on a phone.
2. **Deploy the website on Vercel.**
   - Where: import the repository in Vercel and keep the defaults;
     `vercel.json` serves `website/`. Optionally add a custom domain.
3. **Field-test the new counting on real people.**
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
4. **Verify the iOS build on a device.**
   - Why: the audit changed iOS-specific behaviour (the completion chime's
     audio session, app lifecycle handling, wakelock) and the iPhone was
     unavailable, so none of it has run on iOS. The sideloading steps on the
     website also need one run-through.
   - Done when: the unsigned IPA installs through Sideloadly, and a camera
     set, a MY PT session and a challenge round complete with the voice
     coach audible in silent mode.
5. **Floor exercises filmed end-on.**
   - Why: 7 of the 78 measured sequences still miss reps: glute bridges and
     sit-ups filmed from the head or feet, and mountain climbers from the
     front, far away or a diagonal. The tips tell people to film from the
     side, but nothing checks it.
   - Where: see the placement assistant below; then try the accurate ML Kit
     model for floor exercises (73 of 78 right against the base model's 71).

Done since the audit: the Progress heatmap and History calendar no longer
count a MY PT session ended before any work, the Progress streak is labelled
as counting verified workouts, the 3D guide's floor grid stays inside its
card, and releases ship per-device APKs (86 MB for 64-bit phones instead of
the 199 MB all-in-one APK).
See [AUDIT.md](AUDIT.md).

### Soon after

6. **End-to-end test of a camera set.**
   - Why: no automated test drives intro → camera → counting → summary. The
     camera screen cannot even be reached on an emulator without a
     registered face.
   - Where: a debug-only fake pose source fed from the replay fixtures, and a
     debug face bypass, used by a new `integration_test/` suite.
7. **Continuous integration.**
   - Why: format, analyze and the 701 tests only run when someone remembers.
   - Where: a GitHub Actions workflow for `dart format --set-exit-if-changed`,
     `flutter analyze`, `flutter test` and a release build. Add a layout
     test that opens every screen on a small phone at 2× text and fails on
     overflow (the audit's sweep ran outside the test suite).
8. **Reminder gaps.**
   - Overnight reminder windows (end time before start time) are not
     supported.
   - Skipped sessions are only evaluated when the app runs.
   - Some Android makers' battery optimisers delay or drop reminders; add
     in-app guidance for the detected manufacturer.
9. **Liveness for the face check.**
    - Why: a good photo of the registered user can pass verification.
    - Where: ask for a blink or a head turn using ML Kit face
      classification (eye-open probability, head angles) in `FaceService`.
10. **Upgrade `permission_handler` to 13.x** once Flutter's Android template
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
