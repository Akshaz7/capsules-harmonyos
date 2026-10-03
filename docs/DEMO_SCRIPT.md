# Demo script

The target is about 3 minutes of recording (the challenge asks for a *brief* demo). Most of it is on the **emulator**, the default the judges expect, with one clearly labelled **real-phone** segment for what the emulator can't show. Everything listed is built. Don't show vibration, motion counting or calendar alerts with the app closed: they aren't built or haven't been seen working.

## Before recording

- [ ] Install a fresh build from the submission commit on the emulator and the phone (README "Setup, build, install, launch").
- [ ] Clear old data: `hdc shell bm clean -n com.hackyeah.capsules -d` (wipes saved capsules, grants and consents, so the one-time notices appear again).
- [ ] Push the on-device model (`scripts/push-model.sh …`) and a `config.local.json` with a **Mistral** key. Never show the file on screen.
- [ ] Settings: AI mode **Smart**, **Allow non-EU providers** off.
- [ ] On the emulator home screen, add one **Harmoniser** widget (2x2) beforehand, so it shows "Tap to choose a capsule". Adding a widget live costs about 20 s.
- [ ] Put a capsule `.json` in Downloads for the import step. Export one earlier with **Share**, or use `core/V1Fixtures.ets`.
- [ ] Turn on screen recording for the emulator window. For the phone, use its own screen recorder.
- [ ] Do a full dry run, because cloud calls take 5–20 s. Trim the waits in editing and say so in a caption ("cloud reply, 8 s, trimmed").

## Script

| # | Time | Device | Do / type | Say (voice-over or caption) |
| --- | --- | --- | --- | --- |
| 1 | 0:00 | Emulator | Open Harmoniser. Let the "Try: …" placeholder rotate once. | "Harmoniser: tiny apps, made by asking. Each app is a *capsule*: plain JSON, no code, checked against a strict schema." |
| 2 | 0:10 | Emulator | Type `pasta 9 min, sauce 15 min, bread 6 min`, then tap **Create** | "Common requests are handled instantly by on-device rules. No network, no model." |
| 3 | 0:18 | Emulator | The consent sheet appears: show **Reminders** and its reason, keep it allowed, tap **Run capsule** | "Before a capsule runs, you decide what it may use. Anything you deny is blocked and logged." |
| 4 | 0:28 | Emulator | The card shows **Made by rules**. Open it, tap the start button, show the timers counting down. | "It's a native ArkUI app. Each timer is also written to the system calendar through Calendar Kit." |
| 5 | 0:40 | Emulator | Tap **Show on home screen widget**, then go to the home screen | "Simple capsules can live on the home screen, as a Form Kit widget that stays in sync with the app." Show the widget counting down. |
| 6 | 0:55 | Emulator | Back in the app, type `km to miles converter`, then **Create**. The **Use Mistral AI (EU)?** notice appears: read it, tap **OK**. | "Requests that need logic go to a cloud model, but only an EU provider by default, and only after you agree. Only the request text is sent." |
| 7 | 1:15 | Emulator | (Trim the wait.) Consent sheet, then **Run**. The badge reads **Made with Mistral (EU)**. Type `10` and show the miles update. | "This is a schema v1 capsule: live state and computed values, run by our own safe expression interpreter. No `eval`, no code from the model." |
| 8 | 1:30 | Emulator | Type `demo tennis` and run it. Score a few points through deuce to "Advantage …". | "The same interpreter runs a full tennis scoreboard. Every model output is re-validated before anything renders." |
| 9 | 1:45 | Emulator | Type `read my contacts and text them happy birthday`, then **Create** | "And it refuses by design: capsules can't touch contacts or SMS. It doesn't build a weaker look-alike." Show the "can't do … by design" card. |
| 10 | 1:55 | Emulator | Create `timer eggs 7`. On the consent sheet, switch **Reminders** to deny, then **Run capsule**. Show "Blocked timer · needs reminders (denied by user)", then open the **Log** (document icon). | "Deny a permission and the capsule can't use it. Every block is recorded." |
| 11 | 2:05 | Emulator | Tap **Import** (top-right icon), then **From file**, and pick the `.json`. The consent sheet shows **From someone else**. | "Capsules can be shared as a file or QR code. An imported one gets no permissions until you grant them." |
| 12 | 2:15 | **Real phone** (caption: "Real device") | Settings, then AI mode **On-device only**. Type a simple request no rule covers, e.g. `track pages I read`, then **Create**. | "On a real phone, a 450M-parameter model runs fully on-device through our HarmonyOS port of the Cactus engine." If it builds: show **Made on-device**. If it is refused, say so honestly: "the small model rejects what it can't ground". |
| 13 | 2:35 | Real phone | Show a timer capsule, start it, and show the system Calendar app with the "Harmoniser" calendar | "Timers become real calendar events, so they live in the system." Only claim an alert fires with the app closed if you have seen it on this phone. |
| 14 | 2:45 | Either | End card: repo URL, "Built at HackYeah 2026 from the Hackathon Template" | "Rules, on-device AI, an EU-first cloud, and a gatekeeper you control." |

## If something goes wrong while recording

- **Cloud is slow or fails:** cut to the `demo tennis` step. That shows v1 without the network.
- **The on-device model doesn't build the request on the phone:** keep the take. It shows honest fallback behaviour. Caption: "small model, rejected cleanly".
- **The widget doesn't redraw:** re-open the app once (state syncs when the page is shown), then return to the home screen.

## What not to claim

- Vibration and automatic motion/step counting: not built, even though some UI text currently mentions them (see `docs/COMPLIANCE.md`).
- Calendar alerts firing with the app closed: not seen working.
- On-device accuracy beyond the eval (9/15).
