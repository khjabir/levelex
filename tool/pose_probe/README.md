# ML Kit pose probe

A tiny Flutter app that runs Google ML Kit pose detection (the same plugin and
stream mode as Levelex) over rendered frame sequences and writes the landmarks,
so the rep counters can be tested against the real detector.

1. Render frames of the 3D athlete doing every camera-tracked exercise from
   six phone placements:
   `POSE_FRAMES=<dir> flutter test test/preview/pose_frames_test.dart`
2. Create the app around `lib/main.dart` and `pubspec.yaml` here
   (`flutter create --org com.levelex.probe --project-name pose_probe --platforms android <out>`,
   then copy both files in), build a debug APK and install it on an emulator.
3. Copy the frames into the app's private storage (the emulator must allow
   `adb root`), make them owned by the app, and start it:
   `adb push <dir>/<sequence> /data/data/com.levelex.probe.pose_probe/files/frames/`
   then `adb shell chown -R <app uid> ...` and
   `adb shell am start -n com.levelex.probe.pose_probe/.MainActivity`.
   A `config.json` with `{"models": ["base", "accurate"]}` picks the models.
4. Pull every `<sequence>/pose_<model>.jsonl` back next to its frames and
   replay them through the counters:
   `POSE_REPLAY=<dir> [POSE_MODEL=accurate] flutter test test/preview/pose_replay_test.dart`

`test/fixtures/mlkit_pose_sequences.json.gz` holds a compact set of these
recordings (base model) that `test/mlkit_replay_test.dart` replays on every
test run.
