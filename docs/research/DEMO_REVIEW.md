# Demo review: Harmoniser recorded demo

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04, about 01:00–01:30). Read from the rules, this repository at `origin/main` and public sources. Nothing was run on a device or emulator and no code was changed. Line references are to the commit named in the text and will drift as work lands.

> **Status since writing (re-checked against the code on 2026-10-04):** findings 3 and 4 still hold and are now flagged in `docs/DEMO_SCRIPT.md` (beat 4 hits the `km-to-miles` template; `track pages I read` is a prompt example). Finding 8 is out of date: a weather component exists now (PR #12), but no compound "task list and weather" rule. Live listing counts change; check before quoting them.

**Written:** Sunday 2026-10-04, about 01:30. Submission 11:00. Finalist pitches about 16:00.

**How this was produced:** AI-assisted desk review (Claude Code). I read `origin/main` of the app repo at `7292381` (last commit 2026-10-03 22:36; a fetch at 01:15 brought nothing newer), the branches `docs/judges-feedback-research` and `feat/esp32-relay-live`, the Huawei rules and criteria PDFs, the public challenge repo, and made read-only HTTP GETs against the live site. **Nothing was run on an emulator, a phone or the board. No repository was changed.**

**Tags:** **[RULE]** quoted from the rules. **[CODE]** read in the code, with file:line on `origin/main`. **[LIVE]** seen on the live site at about 01:20. **[J]** my judgement. **[U]** unverified.

---

## 0. The ten things that matter most

1. **No length, format or host is set for the video.** The only wording is "a brief recorded demonstration". The general guide says "Jurors only have a few minutes per project". [RULE] Target 2:00 to 2:55, and make the first 60 seconds stand alone. [J]
2. **The current script never shows the gatekeeper denying anything.** Beat 2 keeps Reminders allowed and moves on. The original idea is said, not shown. [J]
3. **Beat 4 of the current script will not do what it says.** `km to miles converter` now matches the built-in `km-to-miles` template before any cloud call, so the "Use Mistral AI (EU)?" notice will not appear. [CODE, not run]
4. **Beat 7 shows the on-device model answering one of its own prompt examples.** `track pages I read` is a few-shot example inside the model prompt. It may also be taken by the `reading-pages` template first. [CODE]
5. **Beat 6 (refusal) depends on Mistral and the network,** is marked "not yet verified on the emulator" in the README, failed in Lewis's 18:41 test, and its card prints "vibration and the motion sensor", which are not built. [CODE] Cut it.
6. **The Marketplace tab opens on "Tasks with weather".** It is the newest listing, so it is first in the default order. Its first line reads "Weather is typed in by you, it is not looked up." That is the failure the judges saw. [LIVE] Search before the tab is on screen, or remove the listing.
7. **The live marketplace has 115 listings, not 113** (108 templates plus 7). [LIVE] Do not burn a number into a caption. Say "over 100".
8. **None of the fixes for the judges' request is on `origin/main`.** There is no weather component, no compound rule and no router guard in the code I read. [CODE] The weather beat must stay optional.
9. **Scan Kit cannot be shown on the emulator.** The scan call sets `enableAlbum: false` and the emulator has no camera. [CODE, RULE] It needs a real phone, where QR scanning has no recorded check and a camera crash was reported.
10. **"Show on another device" is hidden** unless `config.local.json` sets `devices.relayBaseUrl`. [CODE] The app has not been run against the live relay. It is a full-cut beat only.

---

## 1. What the rules say

### 1.1 Criteria and weights

From `CRITERIA Imagine What_s Next.pdf` and the identical text in `hackathon_challenge.md` in the public repo (one commit, 2026-10-01). [RULE]

> **Originality - 20%**
> Is this a new idea, or a fresh take on a known problem?
> A port of an existing app can be original too, if it solves something non-obvious along the way.
> Ideas that combine more than one challenge area (for example on-device AI that makes a spatial interface accessible) are a plus, as long as the combination serves a purpose.

> **Demonstrated usefulness of the proposed solution - 20%**
> Who would use it, and what problem does it solve for them?
> Which challenge area does it address: Intelligent Experiences, Spatial Experiences or Human-Centric Technology? The connection should be visible in what the solution does, not only in how it is described.
> We value a working, narrow solution to a real problem over a broad concept that only exists on slides.

> **Technical execution - 20%**
> Does it actually work as described? Claims should be backed by the code, the demo, logs or test results.
> Is the architecture sensible: are the components, data flows and integrations justified, not added for show?
> Is the code readable and modular, with reasonable error handling?
> How does it behave when things go wrong: API errors, timeouts, missing data, unexpected input or, if you use AI models, incorrect model output?
> Are there tests covering the key scenarios? Full coverage is not expected, but some evidence that you checked your own work is.
> Basic hygiene matters: no secrets in the repo, input validation, no unnecessary permissions or risky dependencies.

> **Use or enhancement of platform capabilities - 20%**
> Does the solution make real use of the platform, for example its system services, APIs or distributed features? An app that would run unchanged on any other OS, without touching anything platform-specific, scores lower here. Cross-platform frameworks are fine, as long as the solution also uses what the platform itself provides.
> Depending on the area, this may mean on-device AI and agent frameworks, sensors, positioning and 3D rendering, or accessibility and system services.

> **Quality of the demonstration - 10%**
> Can we see the solution actually running, not just mockups? The emulator is the expected default.
> Is it clear what we are looking at and what part was built during the hackathon?
> Show the core interaction as realistically as you can. If part of it can't run on the emulator (sensors, positioning, physical context), explain clearly how it would work. Mentors have devices on site if you want to try it on real hardware.

> **Reproducibility and transparency of the development workflow - 10%**
> Can someone else build and run it from the README and the repository alone?
> Are dependencies and environment setup documented (versions, SDKs, configuration)?
> Does the commit history show how the work progressed? If you used AI tools, describe how. That's fine, we just want to see it.

Scoring, from `RULES Imagine What_s Next.pdf` section 5: "Each Jury member assesses each submission on a scale of 1 to 10 under each of the criteria listed below. The final score of a submission is the weighted average". Also: "Repositories may undergo an automated technical pre-review; the final assessment is made by the jury." [RULE]

### 1.2 The video

- Deliverable 4: "a brief recorded demonstration". [RULE]
- FAQ: "Who records the demo video? **You do.**" [RULE]
- Rules section 4: "All submissions, presentations, demonstrations and project documentation submitted for evaluation must be prepared in English." [RULE]
- Rules section 8: Huawei may disqualify a team that "provides false or misleading information". [RULE]
- General guide: "Submit **only through HackTribe**." and "Jurors only have a few minutes per project". [RULE]
- **No length limit, file format, resolution or hosting site is stated** in the two Huawei PDFs, `hackathon_challenge.md`, `FAQ.md`, the challenge README or the general guide. I could not see the HackTribe form; it may have its own field or size limit. [U]

### 1.3 Advice from Huawei's workshop deck

From `presentation/Huawei Hackathon Challenge Workshop.pdf`, slide "Scoping Advice". The PDF has no text layer; these are OCR readings, so check the slide before quoting them. [RULE, via OCR]

- "Pick one capability and make it work end to end. Breadth reads as unfinished."
- "Say plainly what is real and what is faked. Simul[ated se]nsor data is fine if you declare it."
- "Record the demo before you are out of time"
- "Pick the category your project leads with and make that choice explicit in your submission."

### 1.4 The emulator

From `hackathon-resources/emulator-capability-comparison.md`, DevEco Studio Emulator column: push notifications, internet access and widgets are supported; "Real camera hardware", "Distributed feature testing", "Bluetooth pairing with real devices" and NFC are not. [RULE]

---

## 2. Scorecard of the current script (`docs/DEMO_SCRIPT.md`)

Scores are my estimate of what the video alone would earn, on the jury's 1 to 10 scale. [J]

| Criterion | Weight | Earns points | Loses points | Missing | Est. |
| --- | --- | --- | --- | --- | --- |
| **Originality** | 20% | "JSON, not code" (beat 1). "You decide what each capsule may use" (beat 2). Two themes combined. | The gatekeeper is on screen for about 3 seconds with everything allowed. Nothing is denied, blocked or logged. The video reads as "AI app builder", which is a known idea. | A deny, a blocked component, the log. The line that nothing from a model runs is said in beat 4 but never shown. | 5 |
| **Usefulness** | 20% | Pasta timers are a real, narrow need. The marketplace suggests reuse. | No user and no problem are named. Six features in 90 seconds: the deck says "Breadth reads as unfinished". | "Who would use it". The theme named on screen. | 5 |
| **Technical execution** | 20% | Rules, validator and consent are real. Honest "What not to claim" list. | Beat 4 will not show the cloud notice (section 6, F1). Beat 6 can produce a capsule instead of a refusal. Beat 7 uses a prompt example. A wrong beat on video is a claim the demo does not back. | Any failure handling. Any test evidence (243 tests exist). | 5 |
| **Platform capabilities** | 20% | Widget (beat 3). On-device model through the Cactus port (beat 7). Calendar is mentioned. | No kit is named on screen. The Calendar app is never opened. The log is never opened. Scan Kit is excluded. | Form Kit, Calendar Kit, Scan Kit and Node-API named in captions. | 5 |
| **Demo quality** | 10% | Emulator first. Real-phone segment labelled. End card says built at HackYeah from the template. | Says "one take" and also "cut them together in editing". Opens on a tagline, not a result. | Real versus simulated. Where to try it. What was built during the event, said early. | 5 |
| **Reproducibility** | 10% | Repo URL on the end card. | Nothing else. | The `.hap` release link, the live site, `AI_WORKFLOW.md`. | 4 |

### Timing of the current script

There is no limit in the rules. The script sets its own target of 90 seconds. "Realistic" is my estimate at normal typing speed, before any speed-up. [J]

| Beat | Slot | Allotted | Realistic | Voice-over words | Note |
| --- | --- | --- | --- | --- | --- |
| 1 Home, tagline | 0:00 | 6 s | 6 s | 12 | Fine. |
| 2 Pasta, consent, Run | 0:06 | 10 s | 14 to 16 s | 19 | 38 characters to type. |
| 3 Start, Home, widget | 0:16 | 10 s | 12 s | 22 | Three claims in one line. |
| 4 km to miles, Mistral | 0:26 | 18 s | 20 to 25 s after trimming | 40 | Will not hit the cloud (F1). |
| 5 Marketplace install | 0:44 | 12 s | 14 s | 21 | Tab opens on "Tasks with weather". |
| 6 Refusal | 0:56 | 6 s | 12 to 15 s | 9 | 45 characters to type, then a cloud round trip. |
| 7 Phone, on-device | 1:02 | 12 s | 12 to 20 s | 26 | Phone speed is not measured. |
| 8 Phone, use it | 1:14 | 8 s | 8 s | 7 | "It works offline" is untested. |
| 9 End card | 1:22 | 8 s | 8 s | 12 | Fine. |
| **Total** | | **90 s** | **about 110 to 125 s** | 168 | Needs speed-ups to fit 90 s. |

---

## 3. Risk per beat of the current script

| Beat | Depends on | Status | Safe fallback |
| --- | --- | --- | --- |
| 1 Home | Nothing | Safe. | Keep, but open on a result instead (section 4). |
| 2 Pasta by rules | Rule parser | Unit-tested, and checked on the emulator (README:216). Re-shootable. | None needed. |
| 3 Widget | Form Kit on the emulator; BUG-13 fix `acfbaef` | Checked on the emulator earlier. A tester says widgets are unreliable. Widget sizing is being changed tonight. | Re-shoot until clean. If it stays flaky, show the widget already bound and running, and do not tap it. |
| 3 "real calendar events" | Calendar Kit permission | README:229 says real. README:226 says the emulator's calendar permission was denied in one check. The script never opens Calendar. | Grant the permission on first launch and open the Calendar app. If no event appears, drop the word "calendar" from the voice-over. |
| 4 Mistral | Network, API key, model output | Will be taken by a template instead (F1). | Use **Make it smarter with Mistral** on `count my squats` (cloud-only path, README:287). Or cut. |
| 5 Marketplace | Network, live API | API is up: HTTP 200, `q=squat` returns Gym workout, Squats: goal 100, Squat counter. [LIVE] In-app install reported working by Ash. | Type the search before cutting to the tab. If the API is down, re-record later; do not show the fallback as live. |
| 6 Refusal | Mistral plan step | Not verified on the emulator (README:290). Lewis saw a capsule instead. Card text claims unbuilt features. | **Cut.** Use the gatekeeper deny for "responsible tech". |
| 7 On-device on a phone | Signed build, model pushed, Kirin CPU support | A phone run is recorded in commit `b1dd029`. `cactus/BUILD.md:50` says "not yet verified on a physical phone". These conflict. | Record on the emulator (Apple Silicon), caption it so. Use a request that is not a prompt example. |
| 8 "works offline" | Airplane mode | Not strictly tested (README:214). | Say "no cloud call" and show On-device only mode. Say "offline" only if airplane mode is visible on a real phone. |
| 9 End card | Nothing | Safe. | Add real versus not shown. |

Reported broken tonight, so keep off camera unless fixed and shown working: the camera prompt (Snap), Pomodoro stop, Share on the capsule view on the emulator (Lewis, 18:41: "Share writes JSON but no panel"), bare `weather` (returns a Celsius converter), and the judges' request.

---

## 4. Rewritten script

**Length:** no rule. Cut A is 2:55. Cut B is 2:05. [J]

**Spine:** one idea, shown end to end. *You ask for a tiny app. It can only do what you allow.* Every other beat is evidence for that line. This follows "Pick one capability and make it work end to end." [J]

**Voice-over style:** short sentences, present tense, no adjectives. About 2.5 words per second.

**Criterion codes:** O originality, U usefulness, T technical execution, P platform capabilities, D demo quality, R reproducibility.

**Persistent caption, top left, whole video:** `DevEco emulator · HarmonyOS API 24` (swap to `Real phone` or `Browser` or `ESP32 board` when the picture changes).

### Cut A: "everything landed" (2:55)

Use only if every beat has passed three clean dry runs on the recording build.

| # | Time | On screen | Exact prompt or action | Voice-over | Burned-in caption | Serves |
| --- | --- | --- | --- | --- | --- | --- |
| A1 | 0:00–0:10 | Emulator home screen. A Harmoniser widget shows three timers counting down. Cut to the request box with the sentence typed. | Pre-recorded result first. Then the box showing `pasta 9 min, sauce 15 min, bread 6 min`. | "You want three kitchen timers. You don't want another app with ads and an account. I typed one sentence. This is what I got." | `Harmoniser · tiny apps you don't need to download · built at HackYeah 2026` | U, D |
| A2 | 0:10–0:26 | Create tab. | Type `pasta 9 min, sauce 15 min, bread 6 min`. Tap **Create**. The consent sheet opens. | "The app is a capsule. It is JSON, not code. Common requests are built by rules on the phone. No model, no network." | `Made by rules · on the phone` | U, T |
| A3 | 0:26–0:54 | Consent sheet, then the capsule, then the log. | Leave **Reminders** off. Tap **Run capsule**. The timers show "Blocked timer · needs reminders (denied by user)". Tap the blocked start button. Open the log from the capsule header. Then remove the capsule, create it again, switch **Reminders** on, **Run capsule**. | "This is the gatekeeper. Every capsule must declare what it uses. Everything starts denied. I say no. The timers are blocked, and each attempt is logged. I ask again and allow it. Now it runs." | `Gatekeeper · consent per permission` then `Permission log` | **O**, T |
| A4 | 0:54–1:12 | Capsule, then system Calendar, then home screen. | Tap start. Open the Calendar app: today shows "Pasta is done" in the "Harmoniser" calendar. Press Home: the widget counts down. Tap the widget's start or + once. | "Allowed means real system services. The timers are events in the system calendar. The same capsule runs as a home-screen widget, and stays in step with the app." | `Calendar Kit` then `Form Kit widget` | **P**, T |
| A5 | 1:12–1:30 | Settings, then Create tab. | Settings: AI mode **On-device only**. Type the request chosen in the dry run (section 5.4). **Create**, **Run capsule**. The card reads **Made on-device**. | "When no rule fits, a small model on the device fills in the blanks. It is a 450-million-parameter model. We ported its engine to HarmonyOS. The model only picks from fixed parts. It never writes code." | `On-device model · LFM2-VL-450M · Cactus engine, our HarmonyOS port (Node-API)` | **P**, O, T |
| A6 | 1:30–1:48 | **OPTIONAL. The judges' request.** Create tab, consent sheet, capsule. | Smart mode. Type `a task list and the weather for Kraków`. **Create**. The consent sheet lists the new network permission with its reason. Allow, **Run capsule**. A task list and live weather appear. Tick one task. | "Last night you asked for a task list with the weather. It failed. Capsules could not fetch live data. Now they can, and the gatekeeper asks first. Only the place name leaves the phone." | `Added overnight · weather data by Open-Meteo.com` | T, U |
| A7 | 1:48–2:02 | Marketplace tab, search already typed. | Search `squat`. Tap **Install** on **Squat counter**. Consent sheet reads "From the marketplace". **Run capsule**. | "You can start from a capsule someone else made. It goes through the same validator and the same consent sheet." | `Live marketplace · harmoniser.keanuc.net` | U, T |
| A8 | 2:02–2:28 | Split screen: emulator left, a browser at `harmoniser.keanuc.net/device` right. | Browser shows a QR code and three words. In the app, open the pasta capsule, **Show on another device**, **Type its 3 words**, type them, **Pair**. Tap **Show on Browser**. The dialog reads `Only this leaves your phone: timer "Pasta", 540 seconds`. Tap **Send**. The browser counts down. Open the log: "sent to …". | "A capsule can show on a second screen. Any browser can be one. It pairs with three words or a QR code. The gatekeeper asks before anything leaves the phone, and shows exactly what is sent. The send is in the log." | `Device relay · live · pairs by QR (Scan Kit) or three words` | **O**, P, T |
| A9 | 2:28–2:38 | Phone-camera shot of the ESP32 wrist board showing the same timer. | Board already paired. Send the timer; it counts down on the board. | "The same message reaches this board. It stands in for a watch. The wrist is a permission, not a product." | `ESP32 stand-in for a watch. It does not run HarmonyOS.` | O, D |
| A10 | 2:38–2:55 | End card, three columns (section 5.6). | Static card. | "Real and shown: rules, the gatekeeper and its log, calendar events, widgets, the on-device model, the marketplace, the relay. Not shown or not built is listed here and in the README. The code, the app package and the tests are at this address." | See section 5.6 | D, R, T |

**Scan Kit in Cut A.** If a signed build is on a real phone and the camera scan has passed three dry runs, shoot A8 on the phone: tap **Scan its QR code**, scan the QR in the browser, caption `Scan Kit · real phone`. Otherwise keep the typed three words and leave Scan Kit on the end card under "in the code, not shown". Do not caption Scan Kit over a beat that does not use it. [J]

**A6 fallback, in order:**
1. The fix is merged and the exact prompt passes three dry runs: shoot A6 as written.
2. Weather works alone but the compound request does not: shoot `weather in Kraków` only. Change the voice-over to "You asked for the weather. Capsules could not fetch live data. Now they can, and the gatekeeper asks first." Do not mention the task list.
3. Anything else: **cut A6 completely.** Do not mention weather. Do not type any wording close to the judges' request. Move A7 up. The video is then 2:37.

### Cut B: "safe cut, only what is verified today" (2:05)

Every beat here is either checked on the emulator according to the README, or backed by a unit test and re-shootable. No beat needs the cloud model, a real phone, the relay or tonight's fixes. Only B6 needs the network.

| # | Time | On screen | Exact prompt or action | Voice-over | Burned-in caption | Serves |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | 0:00–0:10 | As A1. | As A1. | As A1. | As A1. | U, D |
| B2 | 0:10–0:26 | As A2. | `pasta 9 min, sauce 15 min, bread 6 min` | As A2. | `Made by rules · on the phone` | U, T |
| B3 | 0:26–0:54 | As A3. | As A3. | As A3. | `Gatekeeper · consent per permission` then `Permission log` | **O**, T |
| B4 | 0:54–1:12 | As A4. | As A4. | As A4. | `Calendar Kit` then `Form Kit widget` | **P**, T |
| B5 | 1:12–1:30 | Create tab, consent sheet, capsule. | Type `tennis scoreboard me vs Sam`. **Create**. The sheet reads "Built from a template". **Run capsule**. Tap points to 40–40, then once more: "Advantage". | "Some apps need logic. A tennis score has deuce and advantage. The capsule is still JSON. Our own interpreter runs it. Nothing a model wrote is executed." | `Made on your phone · no internet · our interpreter, no eval` | T, O |
| B6 | 1:30–1:44 | As A7. | Search `squat`, **Install** on **Squat counter**, **Run capsule**. | As A7. | `Live marketplace · harmoniser.keanuc.net` | U, T |
| B7 | 1:44–2:05 | End card (section 5.6), with a 3-second terminal inset of the unit-test result line. | Static card. | "Real and shown: rules, the gatekeeper and its log, calendar events, widgets, the interpreter, the marketplace. In the code but not shown here: the on-device model, a cloud model that is opt-in and in the EU, QR sharing, and a second-screen relay. They are listed in the README with their status. The code, the app package and the tests are at this address." | See section 5.6 | D, R, T |

**Conditional inserts for Cut B**, each only after three clean dry runs:

- **On-device model** (A5), between B4 and B5. Fallback if it is unreliable: a 4-second terminal inset of `hilog | grep cactus_init` showing `cactus_init ok in … ms`, with the app's status line "On-device AI ready", captioned `Engine loads on the emulator. Generation not shown.`
- **Second device** (A8, then A9), between B6 and B7.

### Optional swap-ins, if a beat above fails

| Beat | Prompt or action | Evidence | Use it for |
| --- | --- | --- | --- |
| Change it | Create `tea 4 min`. On the capsule page type `make it 1 minute` in **Change it…**, **Apply**, then **Undo last change**. | Checked on the emulator (README:236). | Usefulness. Replaces B5. |
| Cloud, opt-in | Create `count my squats`, open it, tap **Make it smarter with Mistral**. The notice "Use Mistral AI (EU)?" appears. **OK**. Trim the wait. | Checked on the emulator with Claude, not Mistral (README:222). Needs a key and the network. [U] | The consent story: nothing leaves the phone without a named notice. Caption `cloud reply, trimmed`. |
| Template | `mood tracker` | Checked on the emulator (README:218). | Replaces B5 if tennis misbehaves. |

---

## 5. Shot list and recording checklist

### 5.1 Build and data

- [ ] Decide the recording commit and write its hash on the end card. If fixes merge after recording, the video shows an older build: say so in the README ("video recorded at `<hash>`").
- [ ] Fresh build from that commit on the emulator: `devecocli build --modules entry`, then `hdc install -r`.
- [ ] Clear data so the consent sheet and notices are in their first-run state: `hdc -t 127.0.0.1:5555 shell bm clean -n com.hackyeah.capsules -d`. This also clears cloud consent.
- [ ] Push `config.local.json` to the app's files directory. For Cut B it needs only `marketplace.baseUrl` (`https://harmoniser.keanuc.net`). For Cut A add a Mistral key and `devices.relayBaseUrl` (`https://harmoniser.keanuc.net`). Without `relayBaseUrl` the device panel does not exist (`Index.ets:343-346`). **Never show this file or a terminal that prints it.**
- [ ] Do **not** set `devices.simulate`. It shows a simulated device, and the video would then contain a simulation.
- [ ] Cut A only: `scripts/push-model.sh`, relaunch, and check the status line reads "On-device AI ready".
- [ ] First launch: **allow** the system calendar permission. Then start one timer and confirm an event appears in the Calendar app, in the "Harmoniser" calendar. One earlier emulator check had this permission denied (README:226).

### 5.2 Emulator settings

- [ ] DevEco emulator on an Apple Silicon Mac. The on-device engine is arm64-v8a only.
- [ ] Phone profile, portrait, 100% zoom. Do not resize the window during a take.
- [ ] Pick light or dark once and keep it. The judges said "make the cards look nicer": choose the mode in which the polished cards look best, and check the consent sheet in that mode. [J]
- [ ] Clean status bar: dismiss notifications, close other apps. Emulator clock at a normal daytime hour if it can be set.
- [ ] Home screen: only Harmoniser's widget and icon on the page that is filmed.
- [ ] System language English.

### 5.3 What to pre-create, and what to clear

| For beat | Pre-create | Clear |
| --- | --- | --- |
| A1 / B1 hook | A separate short take: one pasta capsule with Reminders allowed, bound to a 2x4 widget, timers running. | Nothing. This take is recorded last, from the state left by A4. |
| A2–A4 | A blank Harmoniser widget on the home screen ("Tap to choose a capsule"). | All capsules. Calendar events from earlier runs. |
| A3 | Nothing. | The log, so only this capsule's blocks show (the data clean does it). |
| A7 / B6 | The search text `squat` typed before the cut, so the default list is never on screen. | Any earlier install of Squat counter. |
| A8 | Browser tab at `/device`, zoomed so the three words are readable. A fresh code: a code works once and for 10 minutes (`esp32-companion/RELAY.md:245`). | Old pairings in the app. |
| A9 | Board on, on Wi-Fi, paired, on a plain dark surface. | Any old capsule on the board. |

Ask the listing's owner to remove "Tasks with weather" and "Daily motivation" from the marketplace, or replace the first with a working weather capsule if the fix lands. They are the first two listings in the default order. [LIVE]

### 5.4 Prompts

**Routed by rules** (no model, no network; re-shootable):

| Prompt | Evidence |
| --- | --- |
| `pasta 9 min, sauce 15 min, bread 6 min` | `RuleParser.test.ets` (9 uses); checked on the emulator (README:216). **Use this.** |
| `count my squats` | `RuleParser.test.ets`, `CapsuleGenerator.test.ets`. |
| `split 84 between 4` | `RuleParser.test.ets`. Live v1 bill split. |
| `water 8 glasses` | `RuleParser.test.ets`. README:289 says not yet verified on the emulator. |
| `timer eggs 3` | Checked on the emulator for Pause, Resume, Stop (README:292). |
| `checklist for leaving home: keys, wallet, charger` | Listed in the rule parser's own header (`RuleParser.ets:11`). The shorter `checklist keys, wallet, charger` from the research doc is not in any test. [U] |

**Routed by a template** (on the phone, no network):

| Prompt | Evidence |
| --- | --- |
| `tennis scoreboard me vs Sam` | `Templates.test.ets:42`. |
| `mood tracker` | Checked on the emulator (README:218). |

**On-device model.** Pick one in a dry run. It must end with the badge **Made on-device**, not "Made by rules" and not "Made on your phone · no internet". Do **not** use any of these, because they are the examples inside the model's own prompt (`CactusProvider.ets:83-95`): `eggs 7 and toast 3`, `track pages I read`, `drink 2 litres`, `chess me vs dad`, `volleyball score`, `jumping jacks and burpees`, `gym bag: towel bottle shoes`, `vitamins morning and night`, `remind me to call mum`, `share 90 by 3`. Candidates to try, none verified [U]: `remind me to water the plants`, `packing for the beach towel sunscreen hat`, `badminton me vs Ola`.

**Do not type on camera:**

| Prompt | Why |
| --- | --- |
| `weather` | Returns a Celsius-to-Fahrenheit converter (template tag). |
| `km to miles converter` | Template, not cloud (F1). Fine as a template demo; wrong as a cloud demo. |
| `demo tennis`, `demo bill split` | Hidden fixtures. They are badged "Made by rules" (`Index.ets:869`), which is not how they were made. |
| `read my contacts and text them happy birthday` | Cloud-dependent, unverified, and the card names unbuilt features. |
| `pomodoro` | Stop was reported broken. |
| Anything in Polish | English-only gate. A fair design choice, but not one to show a Polish jury. [J] |
| Snap (camera) | Crash reported. The emulator has no camera. |
| Share on the emulator | Reported to do nothing. |

### 5.5 Screen recording on macOS

- Record the emulator window with macOS screen capture: Cmd+Shift+5, "Record Selected Portion", drawn tightly around the device screen. Turn on "Show Mouse Clicks" in Options so taps are visible.
- Record at full resolution. Do not scale the emulator window down to fit.
- Turn on Do Not Disturb. Quit chat apps. Hide the Dock and the menu bar clock if the selection touches them.
- Record each beat as its own take, three to five times. Keep the best. Join them in the editor. This is a cut video; do not call it "one take".
- Type at normal speed and speed the typing up by 2 to 3 times in the editor. Do not speed up the app's own response, except a cloud wait, which is cut and captioned `cloud reply, trimmed`.
- Record the voice-over separately, after the picture is locked. Read it against a timer.
- A8: record the browser and the emulator in one capture, side by side, so the judges see cause and effect in one frame.
- A9: film the board with a phone, landscape, steady, no glare on the AMOLED. Ten seconds is enough.
- Export H.264 MP4, 1080p, 30 fps. Watch the export once with the sound off: every beat should still make sense from the captions alone. Judges may watch muted. [J]
- If your DevEco emulator toolbar has its own record button, it may be simpler. I did not check this. [U]

### 5.6 Captions to burn in

Per beat: as in the tables in section 4. Kit names are captions, in the same place each time, shown only while that kit is doing the thing on screen.

**End card, three columns.** Fill it from what is true on the recording build.

| Real, shown in this video | Real, not shown here | Not built, or not verified |
| --- | --- | --- |
| Rule parser, validator, interpreter | Cloud model, opt-in, EU provider first (Mistral) | Calendar alerts with the app closed |
| Gatekeeper consent and log | QR sharing and import (Scan Kit): no emulator camera | Capsules that vibrate; motion counting |
| Calendar Kit events | Photo to capsule (Core Vision Kit OCR) | Voice input (core only) |
| Form Kit widget | (Cut B) On-device model; second-device relay | On-device model speed on a phone |
| (Cut A) On-device model: LFM2-VL-450M, Cactus port | | The wrist board does not run HarmonyOS |
| Marketplace, live | | |
| (Cut A) Device relay, live | | |

Footer of the end card:

```
Built at HackYeah 2026 from the Hackathon Template. Nothing in this video is simulated.
Code, .hap and tests: github.com/Akshaz7/capsules-harmonyos
Try the marketplace and a virtual second screen: harmoniser.keanuc.net
Recorded on the DevEco emulator at commit <hash>. Theme: Intelligent Experiences + Human-Centric Technology.
```

Use "Nothing in this video is simulated" only if `devices.simulate` was off and no fixture prompt was typed.

### 5.7 Where to host

The rules name no host. [RULE] My advice [J]:

1. Upload the MP4 as an asset on the same GitHub Release as the final `.hap`. It then sits with the repository the jury already opens, and needs no account.
2. Also upload it unlisted to YouTube, for a link that plays in a browser.
3. Put both links in the README, at the top, and in `HACKATHON_BRIEF.md` in place of "Demo video: TBD".
4. Put the link in whatever field HackTribe offers. Check that form for a size or length limit before exporting. Open every link in a private window before 10:30.

---

## 6. Honesty: the README, and claims the code does not back

### 6.1 Claims in the current script that the code does not back

| # | Claim in `docs/DEMO_SCRIPT.md` | What the code says | Confidence |
| --- | --- | --- | --- |
| F1 | Line 26: `km to miles converter` shows "Use Mistral AI (EU)?" and goes to the cloud. | The app tries templates before any model: `entry/src/main/ets/pages/Index.ets:875-886`. The library has a `km-to-miles` template whose tags include "km to miles", "km", "miles", "converter" (`entry/src/main/resources/rawfile/templates/library.json`). Threshold 0.7: `core/templates/TemplateLibrary.ets:69`. The request goes to the consent sheet as "Built from a template". The same stale claim is in `README.md:280` and `docs/SLIDES_OUTLINE.md:32`. | High, from reading the scorer (`TemplateLibrary.ets:354-386`). Not run. |
| F2 | Line 29: `track pages I read` is "a simple request no rule covers", built by the on-device model. | It is example 2 in the model's few-shot prompt: `core/providers/CactusProvider.ets:85`. The comment at line 82 says "None of them is an eval request", so the team already treats these as off-limits for measurement. A `reading-pages` template (tags "reading", "pages", "read") may also take it first, giving the badge "Made on your phone · no internet". | Prompt example: certain. Template match: likely, not run. |
| F3 | Line 29: "On a real phone, a 450M-parameter model runs fully on-device". | `cactus/BUILD.md:50`: "Verified on the HarmonyOS emulator on Apple Silicon; not yet verified on a physical phone." Commit `b1dd029` records a phone run with the on-device model. The two documents disagree. | Fix one of them. |
| F4 | Line 30: "No network, no account. It works offline." | `README.md:214`: "offline use was not strictly tested". | Certain. |
| F5 | Line 28: the refusal is "by design". | There is no local refusal. The request is sent cloud-first by a pattern (`core/CapsuleGenerator.ets:89`) and the refusal is whatever the cloud plan step returns (`core/CapsuleModel.ets:159`, `CapsuleGenerator.ets:193-196`). With no cloud it falls through to the on-device model (`CapsuleGenerator.ets:200-209`). `README.md:290` marks it "not yet verified on the emulator". | Certain. |
| F6 | Line 28: show the "can't do … by design" card. | The card lists "vibration and the motion sensor" (`pages/Index.ets:147-148`). Neither is built (`README.md:239-241`). The cloud prompt has the same claim (`core/CapsuleModel.ets:148, 151`). `docs/COMPLIANCE.md` raised this; it is still on `origin/main`. | Certain. |
| F7 | Line 25: "real calendar events and a home-screen widget that stays in sync". | Calendar events are real in code (`adapters/TimerAdapter.ets:49-85`), but the script never shows the Calendar app. Two-way widget sync landed in `d36455d` with no emulator check recorded (`README.md:232`). | Show it or do not say it. |
| F8 | Line 3: "One take of about 90 seconds", and line 18: "cut them together in editing". | Self-contradiction. | Certain. |
| F9 | Line 5: leave out "scanning a capsule QR code (no device check yet)". | Still true. Scan needs a camera: `sharing/ImportFlow.ets:83-89` sets `enableAlbum: false`. | Certain. |

Also check on the consent sheet, in any cloud-made capsule: the sheet has reasons for `vibration`, `motion` and `location` (`pages/ConsentView.ets:38-45`) although nothing uses them. If a cloud capsule declares one, the video would show "Count reps or steps with the motion sensor". Do not keep such a take.

### 6.2 What the README must say for the demo to be honest

Stale or wrong on `origin/main` today:

| Where | Says | Should say |
| --- | --- | --- |
| `README.md:135` | The relay routes are "**not deployed**"; "no app code talks to the companion yet"; "It has not been tested against the mock relay or a live relay." | The relay is live at `https://harmoniser.keanuc.net` (PR #8, not merged). Whether the app has run against it: state the result of tonight's check, or "not yet". |
| `README.md:11` | Status stamp "2026-10-03, commit `37e5c5d`". | The submission commit and the commit the video was recorded at. |
| `README.md:280`, `docs/SLIDES_OUTLINE.md:32` | `km to miles converter` shows the Mistral notice. | It is built from a template. Give a request that really reaches the cloud, or describe **Make it smarter**. |
| `README.md:219` | Marketplace at `harmoniser-web.vercel.app` with 5 example listings. | Also at `harmoniser.keanuc.net`; 115 listings at 01:20 on 2026-10-04, of which 108 are example templates. |
| `HACKATHON_BRIEF.md:54` | "Nothing is simulated in the app." | True only with `devices.simulate` off. The code contains a labelled in-app simulated device (`adapters/DeviceRelay.ets:324-326, 416-419`). Say so. |
| `HACKATHON_BRIEF.md:52` | "Wrist companion works on its own hardware; not connected to the app". | Current state after tonight. |
| `HACKATHON_BRIEF.md:66-67` | "`.hap`: GitHub Releases (final release TBD)", "Demo video: TBD". | Links. The only release is `test-1` from 16:09, many features behind. |

Real versus simulated table to put in the README, next to the video link. Fill the last column from the recording build.

| Feature | In the video | Status to state |
| --- | --- | --- |
| Rules, validator, interpreter | Shown | Real. Unit-tested. |
| Gatekeeper consent, block, log | Shown | Real. |
| Calendar Kit events | Shown | Real. Alerts with the app closed: not working on the emulator. |
| Form Kit widget | Shown | Real on the emulator. Reported unreliable on a phone. |
| On-device model | Cut A | Real on the emulator (Apple Silicon host). 9 of 15 correct in the team's eval. Phone speed not measured. Offline not strictly tested. |
| Cloud model (Mistral, EU) | Not shown, or swap-in | Real, opt-in. Only the request text is sent. |
| Marketplace | Shown | Real, live. Most listings are example templates generated by the team, not user uploads. |
| Device relay and `/device` browser screen | Cut A | Relay live. App against the live relay: state what was checked, and when. |
| ESP32 wrist board | Cut A, 10 s | Real hardware. **It does not run HarmonyOS.** It stands in for a watch. Not part of the `.hap`. |
| Scan Kit (QR import, QR pairing) | Not shown | In the code, unit-tested. No device check recorded. Needs a real camera. |
| Photo to capsule (Snap) | Not shown | Photo path checked headless on a phone. The button was reported to crash. |
| Weather / live data | A6 only if fixed | Say plainly: before the fix, capsules had no live-data component, and the judges' request failed. |
| Vibration in capsules, motion counting, voice input | Not shown | Not built (voice: core only). |
| The video itself | | Edited from several takes. Typing sped up. Any cloud wait trimmed and captioned. Recorded at commit `<hash>`. |

---

## 7. What I could not verify

- **Nothing was run.** Every statement about app behaviour comes from reading code, tests and the team's own notes.
- **F1 and the template half of F2** are from reading the scorer, not from executing it. One dry run settles both: type the prompt and read the badge.
- **Whether any of tonight's fixes work.** None is on `origin/main` as of 01:15: no weather component, no compound rule, no router guard, no widget resizing. I did not look at unpushed work on other machines.
- **The app against the live relay.** I confirmed only that `/device`, `/pair` and `/api/capsules` on `harmoniser.keanuc.net` return 200. I did not register, pair or send, because those are writes.
- **The tester's four bugs** (camera crash, widgets, Pomodoro stop, Share). I found no fix commits and no reproduction.
- **Which on-device prompt works.** My three candidates are guesses. A rule or a template may take them.
- **The Calendar event on the emulator.** One recorded check had the permission denied.
- **Whether "Tasks with weather" on the marketplace is the judges' capsule.** It was created at 22:49 local time and installed once at 00:39. Either way it is the first listing.
- **The HackTribe form:** its fields, and any limit on video length, size or host.
- **The workshop deck quotes** are OCR of an image-only PDF.
- **The estimated scores** in section 2 are my opinion, not a model of this jury.
- **macOS and DevEco recording details** come from general knowledge, not from this team's machine.
- **Open-Meteo attribution.** If A6 is shown, their terms need "Weather data by Open-Meteo.com" (per the judges research doc; I did not re-read the terms).

## 8. Decisions I'm not confident about

- **Cutting the refusal beat.** It is the clearest "responsible tech" moment in the old script. I cut it because it is cloud-dependent, unverified and prints a false ability list. If someone fixes the card text and it passes three dry runs, it could return as a swap-in.
- **Putting the on-device model outside the safe cut.** It is the strongest platform point (the Cactus port). I left it out of Cut B because its only recorded UI success is one line on the team board. If it passes three dry runs with a non-example prompt, add it; it is worth more than B5.
- **Naming last night's failure in A6.** I think owning it reads well to judges who saw it. The team may prefer to show the fix without comment. The neutral line is: "Capsules can now fetch live data. The gatekeeper asks first."
- **Opening on a pre-recorded result.** It gives a result in the first 10 seconds, as asked, but it is a flash-forward. The caption must not imply it happened before the typing.
- **2:55 for Cut A.** With "a few minutes per project", a juror may stop at 90 seconds. The gatekeeper and the platform beats are therefore in the first 72 seconds of both cuts. The second device comes late and may not be seen.
- **Scan Kit on the end card only.** The brief asked for it by name on screen. On the emulator that is not possible without implying something untrue, so in the default path it appears as "in the code, not shown".
- **`tennis scoreboard me vs Sam` in the safe cut.** It is unit-tested as a template match, but I found no record of this exact prompt on the emulator. `mood tracker` is the checked fallback.
- **Remove-and-recreate in A3.** I did not find a way to change a capsule's grants after Run, so the script removes the capsule and asks again. If the app has a simpler path, use it.
