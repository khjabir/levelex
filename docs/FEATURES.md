# Feature guide

What each part of Levelex does. Implementation details are in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Contents

- [Camera workouts](#camera-workouts)
- [MY PT: the guided personal trainer](#my-pt-the-guided-personal-trainer)
- [Challenge mode](#challenge-mode)
- [Daily habit: challenges, goals, badges and sharing](#daily-habit-challenges-goals-badges-and-sharing)
- [Strength tracking, programmes and progress](#strength-tracking-programmes-and-progress)
- [Settings and data](#settings-and-data)

## Camera workouts

- **Thirteen camera-tracked exercises**, each with its own target: push-ups,
  squats, jumping jacks, burpees, sit-ups, lunges, glute bridges, high knees,
  mountain climbers, tricep dips, squat jumps, and timed plank and wall-sit
  holds. Pick one on the home screen; the intro shows a 3D guide, the steps
  and the common mistakes the coach fixes.
- **Flow:** face check → calibration → "3, 2, 1, Go!" → counting → set
  complete. A depth gauge shows how far into the current rep you are and a
  progress bar marks your personal best.
- **Live coaching:** corrections such as "go lower", "slow down", "hips up",
  "chest up" and "arms overhead" are spoken and shown on screen. After the
  set, the coach's notes summarise what to work on next time.
- **Voice coach:** "Look at the camera", "Ready", the countdown, every rep
  count (every 10 s and the last 3 s for holds), form cues, "New personal
  best!" and "Set complete".
- **Tolerant counting:** Settings → Coaching strictness (relaxed, balanced,
  strict) sets how deep a rep must go and how strict the form checks are.
- **Any placement:** counting works with the phone at your side, in front
  or on a diagonal, in portrait or landscape, front or back camera, and
  survives rotating the phone mid-set.
- **Interruptions:** pausing, switching camera or a mid-set identity
  re-check keeps the reps already done. Sets interrupted by the app being
  killed are recovered on the next launch.
- **Quick workout:** one tap builds a 10-minute full-body session from your
  equipment and walks you through it with auto-starting intros.
- **Face check:** after a one-time registration, each set confirms it is
  you. Skipping the check still counts and saves the set, marked
  unverified; unverified sets never extend the streak or earn XP.
- **Troubleshooting:** Settings → Camera → "Show tracking details" overlays
  the live signal; the completion screen copies a tracking report (numbers
  only).

## MY PT: the guided personal trainer

MY PT turns Levelex into a session-based trainer. The "AI" is a rule-based
planner and coach that runs on the phone, so it works offline and nothing
about you leaves the device.

- **Ask for a session:** pick a duration (10–60 min presets, or 5–180 min
  custom), a split (Push, Pull, Legs, Upper, Lower, Full body, Core, HIIT,
  Mobility) or a custom muscle focus, and your level. `WorkoutPlanner`
  builds a warm-up, main block and cool-down from 60+ movements, balancing
  the target muscles, fitting the time budget and preferring the equipment
  you own. Shuffle the plan or swap any movement for one that hits the same
  muscles.
- **Your gym:** list the equipment you have (dumbbells, barbell, bench,
  pull-up bar, bands, cable, box, cardio machines…) with an optional photo
  and location note ("blue rack by the mirror"). "Scan with camera" asks
  the on-device ML Kit image labeler what a machine is and offers ranked
  guesses, with a manual fallback. During the session the "grab this" card
  shows your own photo and note.
- **3D guides:** every movement is demonstrated by a realistic rigged body
  that you can orbit. The muscles a movement trains light up; a form
  correction flags the body part in amber.
- **Live view on every item:** the camera stays on with the skeleton
  overlay, the guide in picture-in-picture and the coach card. Rep
  movements the camera can follow (push-ups, squats, lunges, curls,
  presses, rows, raises, hinges, dips, pull-ups and more) are counted and
  corrected with the same engine as camera workouts. Timed movements run on
  the clock with the camera confirming you are in frame; reps for
  untracked movements can be logged by hand.
- **Guided flow:** intro card (guide, equipment, cues) → sets with rest
  countdowns → next movement → summary.
- **Trainer voice:** greets you, explains the plan, calls each movement and
  the equipment to grab, comments after every set, counts the rest down and
  ends with a summary and a tip.
- **Scoring:** verified sessions earn XP (8 per active minute, 2 per
  tracked rep, +40 for finishing at least 80% of the plan). Unverified
  sessions are coached but not scored.

## Challenge mode

Add friends by name (optional photo), pick an exercise and the rules (most
reps in a time limit, or first to a target), then take turns in front of
the camera. Everyone gets the same counting and coaching, a podium with the
cup at the end and a hall of fame. Challenges never touch your own streak
or XP.

## Daily habit: challenges, goals, badges and sharing

Everything here is derived from the same local history, so nothing can
drift (`lib/core/engagement/`, `lib/features/engagement/`).

- **Levels and XP:** every rep earns XP (weighted by exercise) and finishing
  a set earns a bonus; you climb from Rookie to Legend.
- **Daily challenge:** a new challenge each day, seeded from the date and
  scaled to your level: one exercise on most days, two on Tuesday, Thursday
  and Saturday. Any set that day counts towards it, finishing it banks
  +60 XP, and consecutive days build a challenge streak.
- **Achievements:** 30 bronze, silver and gold badges across consistency,
  volume, strength, coaching, MY PT, challenges, body and daily challenges,
  with progress toward each locked one. Any badge can be shared.
- **Weekly goal and report:** pick how many active days you aim for. Home
  shows Mon–Sun dots; the This week screen compares workouts, active days,
  reps, minutes, XP, records and challenges with last week.
- **Rest days and streak nudge:** chosen weekdays never break the streak. An
  evening "streak at risk" notification fires only when nothing was logged
  and it is not a rest day.
- **Reminders:** configurable reminders through the day, scheduled by the
  OS. Missed reminders can be tracked as skipped (never retroactively, and
  switchable off).
- **Intervals:** Tabata, HIIT 30/15, EMOM, AMRAP and Core presets, or your
  own work, rest and rounds with any library movement, run through the MY PT
  engine.
- **Beat your best:** personal bests per exercise, a "Beat it" shortcut that
  sets the target to best + 1, and a spoken "New personal best!".
- **Today's pick:** with no programme active, home suggests a MY PT session
  for muscle groups that are fresh.
- **Share cards:** branded 1080×1350 images for a set, a MY PT session, a
  week or a badge, through the system share sheet. Nothing is uploaded.
- **History:** a monthly calendar (intensity, rest days, challenge stars),
  per-day detail and a 7-day chart.

## Strength tracking, programmes and progress

Inspired by the open-source [openGym](https://github.com/DuarteSantos8/openGym)
tracker and reimplemented in Dart (`lib/features/strength/`).

- **Lift log:** every main-phase set of a MY PT session is logged (load,
  reps or seconds, warm-up flag, optional RPE). Loaded movements get a load
  stepper with a plate calculator; any exercise can be logged by hand.
  Loads are stored in kg and shown in kg or lb.
- **Progression rules:** per exercise, Linear, Greyskull LP, Double
  progression, Triple progression, Timed or Off. The next prescription is
  derived from the log each time, with the reason in one sentence ("All 3
  sets hit 12 at 20 kg last time, so add 2.5 kg"). Repeated stalls trigger
  a deload.
- **Records and 1RM:** heaviest set, most reps at a weight, best estimated
  1RM and most volume, detected when a session is saved and announced by
  the trainer. 1RM formulas: Epley, Brzycki, Lombardi, O'Conner, Mayhew,
  Wathan and Lander, capped at 12 reps.
- **Exercise library:** browse by muscle, equipment, "my gym" and "logged",
  with the 3D guide, cues, a history chart, records, the next prescription
  and the progression rule editor.
- **Programmes:** weekly plans on fixed weekdays or an A/B/C rotation.
  Starter templates (Push/Pull/Legs, Upper/Lower, Full Body, 5×5) are
  fitted to your equipment. Home shows today's day and starts it as a MY PT
  session.
- **Progress:** a 26-week activity heatmap, a muscle recovery map (hard sets
  per muscle decayed over 24–48 h: worked, recovering or fresh), recent
  records and weekly volume.
- **Body:** weigh-ins with a goal line, weekly means and trend, and progress
  photos with a before/after slider, kept in the app's private folder.

Not carried over from openGym: accounts and sync, the cloud AI coach, the
licensed exercise GIF library and structural-balance ratios.

## Settings and data

- **Backup:** export one JSON file (sets, MY PT sessions, lifts, weigh-ins,
  routines, rules, challenges, equipment list; never face data or photos)
  and merge it back on any phone. Restoring imports records and keeps the
  phone's own settings.
- **Import:** workout history from FitNotes, Strong or Hevy CSV exports (or
  any CSV with a date, an exercise and reps or weight) and body weight from
  an Apple Health export. Re-importing the same file never duplicates
  anything.
- **Reset:** "Clear workout history" and "Reset app" (everything, including
  lifts, photos, routines and challenge players).
- **Accessibility:** semantic labels throughout, TalkBack and Switch Access
  activation on the main controls, layouts that scroll at large text sizes.
