# Demo script (90 seconds)

One take of about 90 seconds. Most of it is on the **emulator**, the default the judges expect, with one clearly labelled **real-phone** segment. Every step shows something that is built and has been seen working. **The marketplace is in (Ash, 2026-10-03):** the live API (`harmoniser-web.vercel.app`) answered with 5 example listings on 2026-10-03, and Ash reports browse, Install, the "From the marketplace" consent and Run working against it. The **template catalogue is live too**: `/api/capsules?tag=template` returned all 108 templates on 2026-10-03 (T1 note, re-checked). Beat 5 still installs Squat counter, the listing Ash checked.

Use English only: Harmoniser rejects other languages by design. Leave out anything that isn't built or hasn't been seen working: vibration in capsules (the app's own short vibration on save is fine to show), motion counting on the emulator (it has no accelerometer; see the phone capability demo below), calendar alerts with the app closed, and scanning a capsule QR code (no device check yet). The P1 fixes have landed (timer Pause/Stop, Share on the phone, non-English requests), so they can be shown if time allows, but the 90 seconds below don't need them.

## Before recording

- [ ] Install a fresh build from the submission commit on the emulator and the phone (README "Setup, build, install, launch").
- [ ] Clear old data on both: `hdc -t <device> shell bm clean -n com.hackyeah.capsules -d` (wipes saved capsules, grants and consents, so the one-time notices appear again).
- [ ] Emulator: push a `config.local.json` with a **Mistral** key; Settings: AI mode **Smart**, **Allow non-EU providers** off. Never show the file on screen.
- [ ] Phone: run `scripts/push-model.sh` (on-device model) and launch the app once; Settings: AI mode **On-device only**. Check that the status line reads "On-device AI ready".
- [ ] Emulator `config.local.json` also sets `marketplace.baseUrl` to `https://harmoniser-web.vercel.app`. Check that `curl https://harmoniser-web.vercel.app/api/capsules` lists Squat counter just before recording.
- [ ] Use a build that includes the widget tap fix (BUG-13) and check that + on the widget updates the count before recording.
- [ ] Emulator home screen: add one blank **Harmoniser** widget (2x2) beforehand ("Tap to choose a capsule").
- [ ] Record the emulator window and the phone (its own screen recorder) separately; cut them together in editing.
- [ ] Do a dry run of the cloud step. It takes 5–20 s: trim the wait and caption it ("cloud reply, trimmed").

## Script

| # | Time | Device | Do / type | Say (voice-over or caption) |
| --- | --- | --- | --- | --- |
| 1 | 0:00 | Emulator | The **Create** tab, with the "Try: …" placeholder typing out examples | "Harmoniser: tiny apps, made by asking. Each one is a *capsule*: JSON, not code." |
| 2 | 0:06 | Emulator | Type `pasta 9 min, sauce 15 min, bread 6 min`, then **Create**. On the consent sheet, keep **Reminders** allowed and tap **Run capsule**. | "Common requests are built instantly by on-device rules. You decide what each capsule may use." |
| 3 | 0:16 | Emulator | Open the card (**Made by rules**), tap start, then press Home: the blank widget now shows the timers counting down | "It's a native ArkUI app, with real calendar events and a home-screen widget that stays in sync." |
| 4 | 0:26 | Emulator | Back in the app, type `km to miles converter`, then **Create**. The **Use Mistral AI (EU)?** notice appears; tap **OK**. (Trim the wait.) Then **Run capsule**, and type `10`. | "Logic goes to a cloud model, but EU-only by default and only after you agree. Only the request text is sent. Our own interpreter runs the result; nothing from the model executes." |
| 5 | 0:44 | Emulator | Tap the **Marketplace** tab, search `squat`, tap **Install** on **Squat counter**; the consent sheet shows "From the marketplace", then **Run** | "Or start from a capsule someone else published, still checked by the validator and behind your consent." |
| 6 | 0:56 | Emulator | Type `read my contacts and text them happy birthday`, then **Create** | "And it refuses by design: no contacts, no SMS." Show the "can't do … by design" card. |
| 7 | 1:02 | **Real phone** (caption: "Real device, On-device only mode") | Type a simple request no rule covers, e.g. `track pages I read`, then **Create** | "On a real phone, a 450M-parameter model runs fully on-device, through our HarmonyOS port of the Cactus engine." Show **Made on-device**. |
| 8 | 1:14 | Real phone | Open the capsule and use it once (tap +) | "No network, no account. It works offline." |
| 9 | 1:22 | End card | Repo URL. "Built at HackYeah 2026 from the Hackathon Template." | "Rules, on-device AI, an EU-first cloud, a marketplace, and a gatekeeper you control." |

> **⚠ Two beats need Ash's decision before recording (checked against the code, not run):**
> - **Beat 4:** `km to miles converter` now matches the built-in `km-to-miles` template, so the app builds it on the phone and the **Use Mistral AI (EU)?** notice does not appear. To show the EU cloud step, use a logic request that neither the rules nor a template covers, and dry-run it first.
> - **Beat 7:** `track pages I read` is one of the on-device model's own prompt examples, and the `reading-pages` template may answer it before the model runs. Pick a different simple request and dry-run it on the phone.

**If step 7 is rejected on the phone** (the small model gets about 9/15 right), do a second take with another simple request. If it is rejected again, keep the take and caption it honestly: "Small model, rejected cleanly; rules and the cloud cover the rest."

## If the marketplace is down while recording

If the live API fails, the screen falls back to the shipped examples with a note. Either re-record later, or keep the take and caption it: "Built-in examples; live marketplace offline". Don't present the fallback as the live marketplace.

## 60-second capability demo (real phone)

1. Create `count my shakes` and allow **Motion sensor** — "The sensor only listens while the capsule is open. Nothing is recorded."
2. Shake the phone: the count climbs. Stop shaking: it stops.
3. Open Settings → Motion and switch the scope, or deny motion for the capsule and shake again: nothing moves, and the block is in the log.
4. Create `phone battery`: the card shows the level and charging state, read on the phone.
5. Create `weather in Kraków`: the card shows the city's weather with "Updated HH:MM" and "Weather data by Open-Meteo.com"; tap the link for the source. Airplane mode shows the offline state instead of a fake value.

On a device without an accelerometer (the default emulator), the motion capsule says "Motion sensor unavailable on this device" — that is the honest state; never imply a count happened.

## What not to claim

- Capsules that vibrate: not built. Motion counts **shakes** while a capsule is open, never steps or reps; say that on camera. Voice input: not in the app yet.
- Calendar alerts firing with the app closed: not seen working.
- On-device accuracy beyond the eval (9/15 correct).
- Publishing to the marketplace (not tested).
