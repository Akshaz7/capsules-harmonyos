# Hackathon Brief: Harmoniser

**Huawei Challenge: Imagine What's Next · HackYeah 2026**

**Pitch:** *Tiny apps you don't need to download.* Describe a tiny app in one sentence, and Harmoniser builds it as a safe, native HarmonyOS mini-app that can only use what you allow.

## Problem

People want small single-purpose tools: a pasta timer, a squat counter, a bill split, a tennis score. Today they install a whole app (with ads, accounts and broad permissions) or do without. AI app builders generate *code*, which is risky to run on a phone and opaque about what it touches. Most AI features also send everything to a non-EU cloud by default.

## Solution

Each app Harmoniser makes is a **capsule**: JSON, not code, checked against a strict schema ([`SCHEMA.md`](SCHEMA.md)) and drawn with native ArkUI components.
- **Smart routing:** a request cache, on-device rules and 108 built-in templates first (no internet), then a small on-device LLM (LFM2-VL-450M on our HarmonyOS port of the Cactus engine), then a cloud model for logic. You choose where requests go: by default Mistral (EU) builds logic capsules and Claude (outside the EU) builds live capsules with a weather forecast or web search; one switch makes it EU-only, another keeps everything on the phone. Each provider gets its own consent, and only the request text (plus a forecast line) is sent.
- **Safety:** every capsule is re-validated; our own expression interpreter runs v1 logic (no `eval`); a gatekeeper consent sheet lets the user allow or deny each permission, and blocked actions are logged.
- **Marketplace:** browse and install capsules other people published, still validated and behind the same consent sheet.
- **Platform:** Core Vision Kit text recognition (photos read offline), the accelerometer (shake counting), battery and live weather readings, Calendar Kit timers, Notification Kit, Form Kit home-screen widgets, Share Kit / Scan Kit sharing (file and QR), and a system share target.

## Themes

- **Intelligent Experiences (lead):** plain-language requests become working apps, with on-device AI first.
- **Human-Centric Technology: responsible tech:** no generated code runs, permissions are consented per capsule, refusals are by design (SMS, contacts, payments…), every capsule shows how it was made, and the user decides where AI requests go (EU-only and On-device only are one switch away).

## Target

HarmonyOS, API 24 (minimum API 20), phone. Checked on the DevEco HarmonyOS emulator throughout. On real phones: Share, and the photo path (10 photos read by on-device OCR and built on the phone, one by the on-device model).

## Built during the event

We started from the HackYeah Hackathon Template: an empty ArkTS project, `AGENTS.md`, `AI_WORKFLOW.md` and `hackathon-resources/`. Everything else was built at HackYeah:
- the schema, validator and v1 interpreter
- the rule parser, routing and cloud providers
- the Cactus port and Node-API wrapper
- the gatekeeper, widgets, sharing and triggers
- the template library
- the ESP32 wrist companion
- 361 unit tests and the provider and photo evals

The commit history shows the progression. AI coding agents were used throughout, and [`AI_WORKFLOW.md`](AI_WORKFLOW.md) logs how.

## Real vs not yet

| Real (seen working) | Partial or not yet |
| --- | --- |
| Rules, EU cloud with consent, refusals, English-only gate | On-device model: 9/15 correct in the emulator eval, not yet shown through the main screen; phone speed not measured |
| v1 capsules (tennis scoreboard, converter, bill split) | Daily reminders with the app closed: built, not yet checked |
| Gatekeeper, log, widgets (incl. picker), timer pause/stop | Calendar alerts with the app closed: not seen working |
| Share on a phone, import from file, share target (text/links) | QR import and shared images: not device-checked or not built |
| Marketplace: browse, install with consent, run (live API, 108 templates listed) | Marketplace publishing: not tested |
| Battery and weather readings (emulator) | Shake counting: built, not yet checked on a phone; capsules that vibrate: not built; voice dictation: built, not yet checked on a device |
| Editing a capsule ("Change it…", with undo) | Photo → capsule: on-phone OCR path checked on a real phone (10/10 valid, 6/10 correct, offline); the Snap button is switched off for now, so photos come in as shared images |
| | Wrist companion: works against the live relay; the app's side isn't tested against it yet |

No sensor or device data is simulated in normal use. A labelled, dev-only device-relay simulation exists behind a config flag (`devices.simulate`). Eval figures and limits are in [`docs/AI_INTEGRATION.md`](docs/AI_INTEGRATION.md).

## Team

- **Ash:** team lead, product decisions, phone testing
- **Lewis:** capsule sharing (export, import, QR)
- **Keanu:** ESP32 wrist companion

## Links

- Repository: https://github.com/Akshaz7/capsules-harmonyos
- Setup, build and launch: [`README.md`](README.md)
- `.hap`: GitHub Releases (final release TBD)
- Demo video: TBD (script: [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md))
- AI: [`docs/AI_INTEGRATION.md`](docs/AI_INTEGRATION.md) · [`AI_WORKFLOW.md`](AI_WORKFLOW.md)
- Third-party components: [`docs/THIRD_PARTY.md`](docs/THIRD_PARTY.md), plus the README table
