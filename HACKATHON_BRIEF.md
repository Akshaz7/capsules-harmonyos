# Hackathon Brief: Harmoniser

**Huawei Challenge: Imagine What's Next · HackYeah 2026**

**Pitch:** *Tiny apps, made by asking.* Describe a tiny app in one sentence, and Harmoniser builds it as a safe, native HarmonyOS mini-app that can only use what you allow.

## Problem

People want small single-purpose tools: a pasta timer, a squat counter, a bill split, a tennis score. Today they install a whole app (with ads, accounts and broad permissions) or do without. AI app builders generate *code*, which is risky to run on a phone and opaque about what it touches. Most AI features also send everything to a non-EU cloud by default.

## Solution

Each app Harmoniser makes is a **capsule**: JSON, not code, checked against a strict schema ([`SCHEMA.md`](SCHEMA.md)) and drawn with native ArkUI components.
- **Smart routing:** a request cache, on-device rules and 108 built-in templates first (no internet), then a small on-device LLM (LFM2-VL-450M on our HarmonyOS port of the Cactus engine), then a cloud model for logic. The cloud is EU-only by default (Mistral); Claude only if the user opts in. Each provider gets its own consent, and only the request text is sent.
- **Safety:** every capsule is re-validated; our own expression interpreter runs v1 logic (no `eval`); a gatekeeper consent sheet lets the user allow or deny each permission, and blocked actions are logged.
- **Marketplace:** browse and install capsules other people published, still validated and behind the same consent sheet.
- **Platform:** Calendar Kit timers, Notification Kit, Form Kit home-screen widgets, Share Kit / Scan Kit sharing (file and QR), and a system share target.

## Themes

- **Intelligent Experiences (lead):** plain-language requests become working apps, with on-device AI first.
- **Human-Centric Technology: responsible tech:** no generated code runs, permissions are consented per capsule, refusals are by design (SMS, contacts, payments…), every capsule shows how it was made, and AI is EU-first and opt-in.

## Target

HarmonyOS, API 24 (minimum API 20), phone. Validated on the DevEco HarmonyOS emulator and on real phones (on-device model, Share).

## Built during the event

We started from the HackYeah Hackathon Template: an empty ArkTS project, `AGENTS.md`, `AI_WORKFLOW.md` and `hackathon-resources/`. Everything else was built at HackYeah:
- the schema, validator and v1 interpreter
- the rule parser, routing and cloud providers
- the Cactus port and Node-API wrapper
- the gatekeeper, widgets, sharing and triggers
- the template library
- the ESP32 wrist companion
- 243 unit tests and the provider and photo evals

The commit history shows the progression. AI coding agents were used throughout, and [`AI_WORKFLOW.md`](AI_WORKFLOW.md) logs how.

## Real vs not yet

| Real (seen working) | Partial or not yet |
| --- | --- |
| Rules, on-device LLM, EU cloud with consent, refusals, English-only gate | On-device model: 9/15 correct in our eval; phone speed not measured |
| v1 capsules (tennis scoreboard, converter, bill split) | Daily triggers fire only while the app is open; motion triggers don't fire |
| Gatekeeper, log, widgets (incl. picker), timer pause/stop | Calendar alerts with the app closed: not seen working |
| Share on a phone, import from file, share target (text/links) | QR import and shared images: not device-checked or not built |
| Marketplace: browse, install with consent, run (live API) | Marketplace publishing: not tested; template catalogue being re-seeded |
| | Vibration and motion counting: not built |
| | Photo → capsule and capsule editing: in core and unit-tested, not in the app yet |
| | Wrist companion works on its own hardware; not connected to the app |

Nothing is simulated in the app. Eval figures and limits are in [`docs/AI_INTEGRATION.md`](docs/AI_INTEGRATION.md).

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
