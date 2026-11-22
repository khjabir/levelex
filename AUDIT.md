# App audit, November 2026

Every issue found in the audit and what was done about it. "Fixed" items
are covered by the test suite (695 tests) unless noted.

## 1. Rep detection: workouts not identified

Measured with the real detector: Google ML Kit (base and accurate models,
stream mode, as in the app) on rendered videos of the 3D athlete doing all
13 camera-tracked exercises from six phone placements. Correctly counted
sequences went from 40 of 78 to 71 (base) and 73 (accurate). See
`tool/pose_probe/README.md`; 35 recordings are replayed by
`test/mlkit_replay_test.dart` on every test run.

| Issue | Effect | Fix |
|---|---|---|
| Joint angles switched to ML Kit's noisy depth whenever it disagreed with the 2D angle by 25° | A straight arm seen from the side read ~140°, so side-view push-ups never counted (stuck waiting for the "top") | Depth is used only when a limb points straight at the camera |
| One missing or "jumped" frame reset the rep in progress | Fast moves (burpees, jumps) lost reps | Short dropouts (≤0.9 s) keep the rep; the jump check scales with the time between frames; a body that reappears in place resumes immediately |
| Push-ups measured by elbow angle | From the front or a diagonal the bend is hidden | Shoulders' height above the hands relative to the top of the rep; balanced counts from ~105° of elbow bend, relaxed ~115°, strict ~85° |
| Squats, squat jumps, lunges measured by knee angle | Front view: knees bend towards the camera, nothing counted | Hips' height above the (planted) ankles relative to standing |
| Burpees measured by body tilt | A plank pointing at the camera read 40-55°, so front-view burpees were missed | Shoulders' height above the feet, with the hands near the floor (a squat is not a burpee) |
| High knees and mountain climbers took the most-flexed leg | The signal never returned to "rest" while the legs alternate: almost nothing counted | New alternating counter: every knee drive counts |
| Glute bridge rest threshold 120° | Lying with knees bent is already ~135°: bridges could never count | Hips' rise above the shoulders |
| Sit-ups: 2D shoulder-travel check | Filmed from the feet or head, sitting up was vetoed | Shoulders' rise above the hips in torso lengths |
| Jumping jacks seen side-on | Hips overlap, the feet-apart measure divided by ~0 and read "open"; never counted | Feet only judged when facing the camera; thresholds adapt to the visible range |
| Tricep dips by elbow angle | Front/far views failed | Shoulders' height above the hands |
| Wall sit seen from the front | Knee angle reads straight, hold never started | Also recognised by thighs level over upright shins |
| Pause, camera switch or identity re-check mid-set | Reset the counter to 0 and asked for the full target again | Reps carry over; the set resumes |

Still weak: floor exercises filmed end-on (glute bridges, mountain
climbers, partly sit-ups from the head or feet). The placement tips now say
to film those from the side or a diagonal.

## 2. 3D guide animations

| Issue | Fix |
|---|---|
| Push-up showed a shallow rep and the hands slid ~25 cm each rep | Arms solved so the hands stay planted; full-depth bottom |
| Bench dip was a quarter rep | Deeper, hands stay on the bench |
| Lying poses (sit-ups, crunches, bridges) had the feet floating 26 cm with toes pointing up | Feet flat on the floor |
| Glute bridge top lifted the feet into the air | Feet and shoulders stay down while the hips rise |
| Burpee crouch never put the hands on the floor | Hands planted; the feet jump back |
| Hands and feet slid as the rig re-centred every pose | Planted contacts keep their place between keyframes |
| Mountain climbers: driven foot on the floor, extended leg floating | Swapped |
| Bench press floated the whole body 40 cm up | Feet on the floor, back at bench height |
| Non-ping-pong loops (burpee, squat jump, lunge, circles) rewound through every keyframe in half a second at the end of each loop | A closing keyframe returns straight to the start |

## 3. Session controllers

| Issue | Fix |
|---|---|
| Teardown read `ref` in `onDispose`, which throws, so the camera, pose detector, face model and wakelock were never released (workout, MY PT, challenge) | Voice coach captured at build time |
| Backgrounding during the face check skipped verification | The check is repeated on resume |
| MY PT saved the last item twice (sessions marked incomplete, lifts logged twice) | Fixed |
| MY PT / challenge "finish" could run twice on a double tap | Guarded |
| Challenge had no wakelock; auto-lock ended rounds | Screen stays on during rounds |
| Backgrounding during "get in position" left the challenge with no camera | Returns to "ready" |
| Wakelock not restored after resume | Restored |
| TRY AGAIN switched a daily-challenge set to the default exercise | Launch kept for retries |
| Interrupted sets recovered as verified | Draft stores verification; never overwrites a saved set |
| TRY AGAIN after a camera error reused the broken camera | Camera released on error |
| MY PT identity timer ran while paused | Paused with the session |
| iOS: the completion chime switched audio to "ambient", muting the voice coach in silent mode | Same playback category as the coach |
| Challenge "see results" double tap saved twice | Guarded |
| Camera switch had no in-progress guard (MY PT, challenge) | Guarded |
| Switching camera during the face check removed its timeout | Restarted |
| Face errors left the camera and keep-awake running | Stopped |
| Challenge countdown could not restart after an error | Fixed |
| Permission granted in Settings: screens offered only "Open settings" | Retry on return (workout, challenge, face registration) |
| MY PT after-set coaching line cut off on Android | Speech queued instead of flushed |
| The camera permission prompt paused MY PT | Only a real move to the background pauses |
| Backgrounding while the camera reopened left it open | Release waits for the opening camera |
| Face model could be left half-built or outlive a disposed service | Fixed |
| Challenge exit dialog let the round clock run | Clock stopped while deciding |
| MY PT "Keep going" overrode a pause you set yourself | Respected |

## 4. Data, logic and scheduling

| Issue | Fix |
|---|---|
| Muscle recovery counted every MY PT session twice | Lift-log copies skipped |
| Swapping a loaded or previously logged exercise did nothing (but said it did) | Swaps match the plan's own item |
| Timed holds and bodyweight reps stopped progressing after one step | Targets replayed over the history |
| Turning reminders on recorded the earlier part of the day as skipped | Missed reminders settled under the old rules first |
| "Reset app" kept lifts, weigh-ins, photos, routines and challenge players | Cleared (photos deleted) |
| After a reset the app still thought a face was registered | Face state rebuilt |
| Level badges ignored the daily-challenge bonus XP | Included |
| Streak badges and the progress screen ignored rest days | Same streak rules as home |
| A reminder tap opened the last-picked exercise, not the reminder's | Opens the reminder's exercise and target |
| A daily-challenge or "beat it" launch stuck to the next ordinary set | Cleared on START/close, expires after 10 minutes |
| Today's routine day stale after midnight | Follows the app clock |
| Ending an empty MY PT session used up the routine day | Only sessions with work count |
| CSV import guessed the date order per row (MM/dd dates on days 1-12 swapped) | One order per file |
| First logs counted as personal records ("Record Breaker" on day one) | Baselines are not records |
| Imported challenge players lost on the next edit | Set-up state refreshed after import |
| Tomorrow's streak nudge claimed a streak that would have broken | Its own text |
| Weigh-ins moved a day after changing time zone (undeletable, duplicates) | The calendar day is stored |
| Backup import parsed every MY PT record once per record | Batched |

## 5. Screens and navigation

| Issue | Fix |
|---|---|
| START, GET STARTED, exercise cards, mode cards, badges and calendar days could not be activated with TalkBack / Switch Access | Tap actions on the semantics nodes |
| A reminder tap during MY PT or a challenge destroyed the session unsaved | Ignored while a session runs; otherwise opens over home |
| Challenge round-over and up-next screens did not scroll; the button fell off small phones | Middle scrolls, button fixed |
| "New badge" sections vanished one frame after appearing | Snapshotted per screen |
| Camera panels overflowed in landscape, hiding their buttons | Scroll |
| Face-registration intro and onboarding pages overflowed at large text or on short phones | Scroll |
| "Another set" switched back to the default exercise | Same exercise and target |
| Overflows: intro target pill, level card, MY PT mode grid and title, plan chips, achievement tiles, history day sheet, settings dropdown at 2× text, muscle-map legend, routine week, equipment tiles | Wrap, flex, scale or taller cells |
| Imported exercises in the routine/interval picker were dropped or left hidden entries | Not offered when picking |
| Weigh-in accepted any number ("800" for "80.0") | 20-400 kg (45-880 lb) |
| "Bodyweight only" wiped the gym with one tap | Confirmation; photos deleted |
| Cold start from a reminder had no home underneath (back closed the app) | Opens over home |

## 6. Left as designed (your call)

- Unverified sets (face check skipped) still count towards the daily
  challenge and its 60 XP bonus, like the daily totals. Tests pin this as a
  deliberate rule; making the challenge require verified sets is a small
  change if you prefer it.
- Restoring a backup keeps the device's settings (weekly goal, rest days,
  targets, unit, seen badges); only records are imported.
