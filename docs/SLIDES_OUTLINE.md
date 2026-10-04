# Pitch deck outline (6 slides)

Every number here comes from the README, `docs/COMPLIANCE.md` or `AI_WORKFLOW.md`. Don't add claims the code doesn't back. In particular, don't claim vibration, step or rep counting (the motion sensor counts shakes only, and no real shake is recorded), offline use, alerts firing with the app closed, marketplace publishing, or the Snap button working in the app (the photo path was checked headless on a phone; the button itself hasn't been).

## 1. Problem

**Title:** Small needs, big apps

- People want tiny, single-purpose tools: a pasta timer, a squat counter, a bill split, a tennis score. Today they install a whole app (ads, accounts, permissions) or do without.
- AI app builders generate *code*, which is unsafe to run on a phone and opaque about what it touches.
- Many AI features send requests to a cloud outside the EU by default.

*Visual:* a phone home screen crowded with single-use apps, next to one Harmoniser card.

## 2. Solution

**Title:** Harmoniser: tiny apps, made by asking

- Describe it in one sentence, and get a working native mini-app (a *capsule*) in seconds.
- A capsule is JSON, not code. A strict schema plus our own expression interpreter means nothing from a model ever executes.
- Change a capsule later in plain words ("make it 1 minute"), see the change before applying it, and undo it.
- You decide what each capsule may use, on a consent sheet. Denied actions are blocked and logged.
- Simple capsules live on the home screen as widgets. Any capsule can be shared as a file or QR code, or installed from a marketplace (still validated, still behind consent).

*Visual:* request, then consent sheet, then running capsule, then widget (four screenshots).

## 3. Demo flow

**Title:** What you'll see (or: live demo)

1. `pasta 9 min, sauce 15 min, bread 6 min`: made by rules, instantly and offline, with calendar events and a widget.
2. `km to miles converter`: built at once from a built-in template, as a live v1 capsule, with no cloud call. To show the EU cloud model and its one-time consent, use **Make it smarter with Mistral** on a rules-made capsule.
3. `demo tennis`: a full scoreboard (deuce, advantage) run by the safe interpreter.
4. Marketplace: search `squat`, Install, consent "From the marketplace", Run.
5. `read my contacts and text them…`: refused by the cloud planning step (needs cloud AI; not verified in the app on the emulator; without cloud AI it is not refused).
6. Real phone: the on-device LLM, with no cloud call. Say "offline" only if airplane mode was on in the recording; offline use was not strictly tested.

*Visual:* the step list beside a QR code to the recorded demo.

## 4. Architecture

**Title:** Cache, rules, templates, then on-device, then EU cloud, then validator, then gatekeeper

- Paste the README's Mermaid diagram (rendered).
- **Every source is re-validated:** the validator type-checks every expression, rejects unknown fields, actions and permissions, and enforces limits.
- **Smart routing:** a cache hit, rule match or template match (108 templates, filled on the phone) returns at once; simple requests go on-device; logic requests go to the cloud; requests for capabilities capsules don't have are refused.
- **Two-step cloud generation:** plan, then capsule, then validate, then self-check. A revision is kept only if it is still valid.
- **Unit tests** (last recorded runs: 249, then 269 on the capabilities branch; 278 cases counted at `bfa70f5`, not re-run), plus a provider eval with held-out and refusal sets.

## 5. Platform capabilities used

**Title:** Built on HarmonyOS, not just running on it

| Capability | Used for |
| --- | --- |
| **Cactus ported to HarmonyOS** (Node-API, arm64-v8a) | On-device LLM (LFM2-VL-450M): 92–114 tok/s decode, about 380 MB; first token in about 0.3 s for a 29-token prompt and 1.2–1.6 s for a 350–600-token prompt (emulator figures on an Apple M4 Pro host; phone speed not measured; 9 of 15 correct in our eval) |
| **Form Kit** | Home-screen widgets (2x2 and 2x4), synced both ways with the app |
| **Core Vision Kit** (`textRecognition`) | Photo → capsule: reads the text on the phone, offline (10/10 valid, 6/10 correct on a real phone) |
| **Calendar Kit** | Capsule timers become system calendar events |
| **Notification Kit** | Timer-finished notifications |
| **Share Kit / Scan Kit / Document picker** | Share capsules as files or QR codes |
| **ArkUI + ArkData Preferences** | Native rendering, saved capsules, grants and the block log |

*Note for the speaker:* the Cactus port is original work: 3 patches, telemetry stubbed out, our own Node-API wrapper.

## 6. AI and privacy

**Title:** Intelligent, and on your side

- **Local first:** rules and the on-device model need no network. In **On-device only** mode no request is sent to an AI provider. Two things can still leave the phone when they are configured: the marketplace search (the request text; on `main` at `bfa70f5` this happens in On-device only mode too, and PR #16 stops it there) and a send to another device.
- **EU-first cloud:** used automatically only with Mistral (EU). Claude or OpenAI only if you enable non-EU providers. Each provider gets its own consent. For a typed request, only the request text and our fixed prompt are sent.
- **Honest trade-off:** Mistral 14/15 tuning and 4/5 held-out; Claude 14/15 and 5/5. On hard logic requests Claude led 4/4 to 2/4. We default to EU anyway, and the validator catches the failures.
- **Transparency:** every capsule shows how it was made: rules, on your phone (template), on-device, Mistral (EU), Claude, or from someone else.
- **Built openly with AI:** coding agents throughout, with the full log in `AI_WORKFLOW.md`.

*Closing line:* "Rules, on-device AI, an EU-first cloud, and a gatekeeper you control."
