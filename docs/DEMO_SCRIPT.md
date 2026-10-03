# Demo script (90 seconds)

One take of about 90 seconds. Most of it is on the **emulator**, the default the judges expect, with one clearly labelled **real-phone** segment. Every step shows something that is built and has been seen working. The marketplace appears only as "coming next" on the end card, unless it works end to end by 03:00 (then see [Marketplace swap](#marketplace-swap-only-if-it-works-end-to-end-by-0300)).

Leave out anything with an open P1 bug or that isn't built: the Share button on the phone (T3-7), stopping a running timer (T3-6), photo or Chinese-language requests (T3-5/T4-6), vibration, motion counting, and calendar alerts with the app closed.

## Before recording

- [ ] Install a fresh build from the submission commit on the emulator and the phone (README "Setup, build, install, launch").
- [ ] Clear old data on both: `hdc -t <device> shell bm clean -n com.hackyeah.capsules -d` (wipes saved capsules, grants and consents, so the one-time notices appear again).
- [ ] Emulator: push a `config.local.json` with a **Mistral** key; Settings: AI mode **Smart**, **Allow non-EU providers** off. Never show the file on screen.
- [ ] Phone: run `scripts/push-model.sh` (on-device model) and launch the app once; Settings: AI mode **On-device only**. Check that the status line reads "On-device AI ready".
- [ ] Emulator home screen: add one blank **Harmoniser** widget (2x2) beforehand ("Tap to choose a capsule").
- [ ] Record the emulator window and the phone (its own screen recorder) separately; cut them together in editing.
- [ ] Do a dry run of the cloud step. It takes 5–20 s: trim the wait and caption it ("cloud reply, trimmed").

## Script

| # | Time | Device | Do / type | Say (voice-over or caption) |
| --- | --- | --- | --- | --- |
| 1 | 0:00 | Emulator | Home screen of the app, with the "Try: …" placeholder rotating | "Harmoniser: tiny apps, made by asking. Each one is a *capsule*: JSON, not code." |
| 2 | 0:06 | Emulator | Type `pasta 9 min, sauce 15 min, bread 6 min`, then **Create**. On the consent sheet, keep **Reminders** allowed and tap **Run capsule**. | "Common requests are built instantly by on-device rules. You decide what each capsule may use." |
| 3 | 0:18 | Emulator | Open the card (**Made by rules**), tap start, then press Home: the blank widget now shows the timers counting down | "It's a native ArkUI app, with real calendar events and a home-screen widget that stays in sync." |
| 4 | 0:30 | Emulator | Back in the app, type `km to miles converter`, then **Create**. The **Use Mistral AI (EU)?** notice appears; tap **OK**. (Trim the wait.) Then **Run capsule**, and type `10`. | "Logic goes to a cloud model, but EU-only by default and only after you agree. Only the request text is sent. Our own interpreter runs the result; nothing from the model executes." |
| 5 | 0:50 | Emulator | Type `read my contacts and text them happy birthday`, then **Create** | "And it refuses by design: no contacts, no SMS." Show the "can't do … by design" card. |
| 6 | 0:58 | **Real phone** (caption: "Real device, On-device only mode") | Type a simple request no rule covers, e.g. `track pages I read`, then **Create** | "On a real phone, a 450M-parameter model runs fully on-device, through our HarmonyOS port of the Cactus engine." Show **Made on-device**. |
| 7 | 1:12 | Real phone | Open the capsule and use it once (tap +) | "No network, no account. It works offline." |
| 8 | 1:20 | End card | Repo URL. "Coming next: a capsule marketplace." "Built at HackYeah 2026 from the Hackathon Template." | "Rules, on-device AI, an EU-first cloud, and a gatekeeper you control." |

**If step 6 is rejected on the phone** (the small model gets about 9/15 right), do a second take with another simple request. If it is rejected again, keep the take and caption it honestly: "Small model, rejected cleanly; rules and the cloud cover the rest."

## Marketplace swap (only if it works end to end by 03:00)

"End to end" means search, then **Install**, then the consent sheet labelled "From the marketplace", then a running capsule, seen working on the emulator. If so, replace step 5 (the refusal) with:

| 5 | 0:50 | Emulator | Open the marketplace, search `pomodoro`, tap **Install**; the consent sheet shows "From the marketplace", then **Run** | "Or start from a capsule someone else published, still behind your consent." |

and remove "Coming next: a capsule marketplace" from the end card. Otherwise keep the script as it is.

## What not to claim

- Vibration and automatic motion/step counting: not built.
- Calendar alerts firing with the app closed: not seen working.
- On-device accuracy beyond the eval (9/15 correct).
- Anything about the marketplace, unless the swap above applies.
