# Demo script (about 90 seconds, edited from several takes)

**Status of this script (2026-10-04, checked against the code at `bfa70f5` by reading; nothing was run):** it is a plan, not a record. The timings add up to about 90 seconds but were not rehearsed, and the result is cut together from separate emulator and phone recordings, not one take. Not every step has been seen working: steps 2, 3 and 5 have recorded checks (step 5 as reported by Ash); step 4 will not do what it says as written; step 6 is marked "not yet verified on the emulator" in the README; step 7 rests on one phone run recorded in a commit message; step 8's "offline" was never strictly tested. The notes under the table say what to change. A reviewed rewrite with two cuts (2:55 and 2:05) and a shot list is in [`research/DEMO_REVIEW.md`](research/DEMO_REVIEW.md); prefer it for the recording.

Most of the script is on the **emulator**, the default the judges expect, with one clearly labelled **real-phone** segment. **The marketplace (Ash, 2026-10-03):** the live API answered on 2026-10-03, and Ash reports browse, Install, the "From the marketplace" consent and Run working against it. It is at `https://harmoniser.keanuc.net` (also `https://harmoniser-web.vercel.app`) and on 2026-10-04 held over 100 listings: 108 example templates made by the team plus a few examples. Do not put an exact count in a caption. Beat 5 still installs Squat counter, the listing Ash checked.

Use English only: Harmoniser rejects other languages by design. Leave out anything that isn't built or hasn't been seen working: vibration in capsules (the app's own short vibration on save is fine to show), counting steps or reps (the motion sensor counts shakes only, and no real shake is recorded yet), calendar alerts with the app closed, and scanning a capsule QR code (no device check yet). The P1 fixes have landed (timer Pause/Stop, Share on the phone, non-English requests), so they can be shown if time allows, but the 90 seconds below don't need them.

## Before recording

- [ ] Install a fresh build from the submission commit on the emulator and the phone (README "Setup, build, install, launch").
- [ ] Clear old data on both: `hdc -t <device> shell bm clean -n com.hackyeah.capsules -d` (wipes saved capsules, grants and consents, so the one-time notices appear again).
- [ ] Emulator: push a `config.local.json` with a **Mistral** key; Settings: AI mode **Smart**, **Allow non-EU providers** off. Never show the file on screen.
- [ ] Phone: run `scripts/push-model.sh` (on-device model) and launch the app once; Settings: AI mode **On-device only**. Check that the status line reads "On-device AI ready".
- [ ] Emulator `config.local.json` also sets `marketplace.baseUrl` to `https://harmoniser.keanuc.net` (without it the tab shows the bundled examples, not the live marketplace). Check that `curl 'https://harmoniser.keanuc.net/api/capsules?q=squat'` lists Squat counter just before recording.
- [ ] Use a build that includes the widget tap fix (BUG-13, `acfbaef`) and check that + on the widget updates the count before recording.
- [ ] Emulator home screen: add one blank **Harmoniser** widget (2x2) beforehand ("Tap to choose a capsule").
- [ ] Record the emulator window and the phone (its own screen recorder) separately; cut them together in editing.
- [ ] Do a dry run of the cloud step. It takes 5–20 s: trim the wait and caption it ("cloud reply, trimmed").

## Script

| # | Time | Device | Do / type | Say (voice-over or caption) |
| --- | --- | --- | --- | --- |
| 1 | 0:00 | Emulator | Home screen of the app, with the "Try: …" placeholder rotating | "Harmoniser: tiny apps, made by asking. Each one is a *capsule*: JSON, not code." |
| 2 | 0:06 | Emulator | Type `pasta 9 min, sauce 15 min, bread 6 min`, then **Create**. On the consent sheet, keep **Reminders** allowed and tap **Run capsule**. | "Common requests are built instantly by on-device rules. You decide what each capsule may use." |
| 3 | 0:16 | Emulator | Open the card (**Made by rules**), tap start, then press Home: the blank widget now shows the timers counting down | "It's a native ArkUI app, with real calendar events and a home-screen widget that stays in sync." |
| 4 | 0:26 | Emulator | Back in the app, open a `count my squats` capsule (made by rules; create it before recording) and tap **Make it smarter with Mistral**. The **Use Mistral AI (EU)?** notice appears; tap **OK**. (Trim the wait.) Then **Run capsule**. (Was: type `km to miles converter`; a built-in template now takes that request, so no notice appears. See the corrections below.) | "Logic goes to a cloud model, but EU-only by default and only after you agree. Only the request text is sent. Our own interpreter runs the result; nothing from the model executes." |
| 5 | 0:44 | Emulator | Tap the **Marketplace** tab, search `squat`, tap **Install** on **Squat counter**; the consent sheet shows "From the marketplace", then **Run** | "Or start from a capsule someone else published, still checked by the validator and behind your consent." |
| 6 | 0:56 | Emulator | Type `read my contacts and text them happy birthday`, then **Create** | "And the cloud planner refuses it: no contacts, no SMS." Show the refusal card only if the take produced it; this step is not verified on the emulator and needs cloud AI. |
| 7 | 1:02 | **Real phone** (caption: "Real device, On-device only mode") | Type a simple request that no rule, template or prompt example covers (not `track pages I read`, see the corrections below), then **Create** | "On a real phone, a 450M-parameter model runs on the device, through our HarmonyOS port of the Cactus engine." Show **Made on-device**, and only if the badge really says that. |
| 8 | 1:14 | Real phone | Open the capsule and use it once (tap +) | "No cloud call, no account." (Say "it works offline" only if airplane mode is visibly on in the take; offline use has not been strictly tested.) |
| 9 | 1:22 | End card | Repo URL. "Built at HackYeah 2026 from the Hackathon Template." | "Rules, on-device AI, an EU-first cloud, a marketplace, and a gatekeeper you control." |

**Corrections to the table above (from reading the code at `bfa70f5`, not run):**

- **Step 4:** the earlier version typed `km to miles converter`. That request matches the built-in `km-to-miles` template before any model is asked, so the consent sheet opens with "Built from a template" and the **Use Mistral AI (EU)?** notice does not appear. The row now uses **Make it smarter with Mistral** on a rules-made capsule (README, "Make it smarter"; seen on the emulator with Claude, not recorded with Mistral). Cut the beat if it does not work in a dry run. The line "Only the request text is sent" is true for a typed request; do not extend it to edits or photos.
- **Step 6:** the refusal comes from the cloud model's planning step, not from a local rule, so it needs the Mistral key and the network; without cloud AI the request goes to the on-device model and is not refused. It is not verified on the emulator, and the card's "Capsules can only use: …" list names vibration, which capsules cannot use. Say "it refuses" only if the take shows it, and do not say "by design" as if it were a local guarantee.
- **Step 7:** `track pages I read` is one of the examples inside the on-device model's own prompt, and a `reading-pages` template may take it first (badge "Made on your phone · no internet", not "Made on-device"). Use a request that no rule, template or prompt example covers, and check the badge. The only recorded phone run of the on-device model is in the message of commit `b1dd029`.
- **Step 8:** say "runs on the device, no cloud call" unless the take visibly has airplane mode on on a real phone. Offline use has not been strictly tested.
- **Step 3:** "real calendar events" is true in code, but the script never opens the Calendar app; show it or drop the words.

**If step 7 is rejected on the phone** (the small model gets about 9/15 right), do a second take with another simple request. If it is rejected again, keep the take and caption it honestly: "Small model, rejected cleanly; rules and the cloud cover the rest."

## If the marketplace is down while recording

If the live API fails, the screen falls back to the shipped examples with a note. Either re-record later, or keep the take and caption it: "Built-in examples; live marketplace offline". Don't present the fallback as the live marketplace.

## 60-second capability demo (real phone)

Status: the battery and weather cards were seen on the emulator (2026-10-04). The shake steps (1 to 3) have not been recorded as checked on a phone; run them before filming and drop them if they do not work. Step 5 is a request that is just weather, for one of the 12 bundled cities.

**A task list with the weather (on `main` since PR #14).** Type `a task list and the weather for Kraków`: a rule builds one capsule with the weather card, an empty task list, a "New task" box and **Add**. A leading "make", "create" or "build" (optionally with "me", then "a" or "an") is accepted. Fallback: `task list and weather`, then tap the weather card and choose Kraków. This is verified by unit tests; emulator run reported by the author; not re-run, so try it in a dry run before filming. Do not write "to do" with a space, add words after the city ("please", "today"), write "Cracow", add "and a timer", or start with "please" or "can you": those miss the rule, lose the city or drop the timer (README, Weather row). Tasks can be added but not ticked off, so do not promise that on camera. Clear the app data or reinstall first: the request cache is read before the rules and may hold an old answer.

1. Create `count my shakes` and allow **Motion sensor** — "The sensor only listens while the capsule is open. Nothing is recorded."
2. Shake the phone: the count climbs. Stop shaking: it stops.
3. Open Settings → Motion and switch the scope, or deny motion for the capsule and shake again: nothing moves, and the block is in the log.
4. Create `phone battery`: the card shows the level and charging state, read on the phone.
5. Create `weather in Kraków`: the card shows the city's weather with "Updated HH:MM" and "Weather data by Open-Meteo.com"; tap the link for the source. Airplane mode shows the offline state instead of a fake value.

On hardware without an accelerometer, the motion capsule says "Motion sensor unavailable on this device" — that is the honest state; never imply a count happened. (Our emulator reports a virtual accelerometer, so it shows "Shake the phone to count" instead; both states are in the app.)

## What not to claim

- Capsules that vibrate: not built. Motion counts **shakes** while a capsule is open, never steps or reps; say that on camera. Voice input: not in the app yet.
- Calendar alerts firing with the app closed: not seen working.
- On-device accuracy beyond the eval (9/15 correct).
- Publishing to the marketplace (not tested).
