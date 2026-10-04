# Hackathon Brief: Harmoniser

**Huawei Challenge: Imagine What's Next · HackYeah 2026**

**Pitch:** *Tiny apps, made by asking.* Describe a tiny app in one sentence, and Harmoniser builds it as a safe, native HarmonyOS mini-app that can only use what you allow.

## Problem

People want small single-purpose tools: a pasta timer, a squat counter, a bill split, a tennis score. Today they install a whole app (with ads, accounts and broad permissions) or do without. AI app builders generate *code*, which is risky to run on a phone and opaque about what it touches. Many AI features send requests to a cloud outside the EU by default.

## Solution

Each app Harmoniser makes is a **capsule**: JSON, not code, checked against a strict schema ([`SCHEMA.md`](SCHEMA.md)) and drawn with native ArkUI components.
- **Smart routing:** a request cache, on-device rules and 108 built-in templates first (no internet), then a small on-device LLM (LFM2-VL-450M on our HarmonyOS port of the Cactus engine), then a cloud model for logic. The cloud is EU-only by default (Mistral); Claude only if the user opts in. Each provider gets its own consent. For a typed request only the request text and our fixed prompt are sent; editing a capsule also sends its definition, a photo can send its recognised text, and with a marketplace URL configured the request text is also sent to the marketplace as a search (details in [`docs/AI_INTEGRATION.md`](docs/AI_INTEGRATION.md)).
- **Safety:** every capsule is re-validated; our own expression interpreter runs v1 logic (no `eval`); a gatekeeper consent sheet lets the user allow or deny each permission, and blocked actions are logged.
- **Marketplace:** browse and install capsules from a shared catalogue, still validated and behind the same consent sheet. It is live only when a local `config.local.json` sets `marketplace.baseUrl`; without it the app lists the 108 bundled examples. Most live listings are example templates made by the team.
- **Platform:** Core Vision Kit text recognition (photos read offline), Calendar Kit timers, Notification Kit, Form Kit home-screen widgets, Share Kit / Scan Kit sharing (file and QR), and a system share target.

## Themes

- **Intelligent Experiences (lead):** plain-language requests become working apps, with on-device AI first.
- **Human-Centric Technology: responsible tech:** no generated code runs, permissions are consented per capsule, requests for SMS, contacts, payments and similar are refused by the cloud planning step (so not when cloud AI is off), every capsule shows how it was made, and AI is EU-first and opt-in.

## Target

HarmonyOS, API 24 (minimum API 20), phone. Checked on the DevEco HarmonyOS emulator. Two real-phone runs are recorded, in commit messages only: a create with the on-device model (`b1dd029`) and Share (`45321fa`).

## Built during the event

We started from the HackYeah Hackathon Template: an empty ArkTS project, `AGENTS.md`, `AI_WORKFLOW.md` and `hackathon-resources/`. Everything else was built at HackYeah:
- the schema, validator and v1 interpreter
- the rule parser, routing and cloud providers
- the Cactus port and Node-API wrapper
- the gatekeeper, widgets, sharing and triggers
- the template library
- the ESP32 wrist companion
- the unit tests (last recorded runs: 249, then 269 on the capabilities branch; 278 cases counted at `bfa70f5`, not re-run) and the provider and photo evals

The commit history shows the progression. AI coding agents were used throughout, and [`AI_WORKFLOW.md`](AI_WORKFLOW.md) logs how.

## Real vs not yet

| Real (seen working by a team member, per the README status table) | Partial or not yet |
| --- | --- |
| Rules, EU cloud with consent, English-only gate | On-device model: 9/15 correct in our eval on the emulator; one phone run recorded in a commit message; phone speed not measured; offline use not strictly tested. Refusals: 2/2 per provider in the eval, cloud step only, not verified in the app |
| v1 capsules (tennis scoreboard, converter, bill split) | Daily triggers fire only while the app is open. Motion (shake) counters and triggers: in the code and unit-tested, no real shake recorded |
| Gatekeeper, log, widgets (incl. picker), timer pause/stop | Calendar alerts with the app closed: not seen working |
| Share on a phone, import from file, share target (text/links) | QR import and shared images: not device-checked or not built |
| Marketplace: browse, install with consent, run (reported by Ash against the live API, which needs a pushed `config.local.json`; over 100 listings, 108 of them example templates) | Marketplace publishing: not tested |
| Battery reading and a weather reading for one bundled city (emulator, per the PR author). Once PR #14 is merged, "a task list and the weather for Kraków" builds one capsule with a task list and the weather, by rule (verified by unit tests and reported on the emulator by its author; not re-run). Tasks can be added but not ticked off, and requests that start with "make" or "create" still miss the rule | Capsules that vibrate: not built; the `notify` action does nothing yet; voice input: core only |
| Editing a capsule ("Change it…", with undo) | Photo → capsule: on-phone OCR path checked on a real phone (10/10 valid, 6/10 correct, offline); Snap button in the app not yet checked |
| | Wrist companion (an ESP32 board, not a Huawei device, does not run HarmonyOS) works on its own hardware and against the live relay. The app's **Show on another device** panel exists but is hidden without a relay URL in `config.local.json`, and the app has not been run against the live relay |

No sensor data is simulated. The app contains one simulation, a simulated second device for the **Show on another device** panel (`SimulatedDeviceRelay` in `adapters/DeviceRelay.ets`): it is behind the dev flag `devices.simulate`, off by default, labelled "Simulated device" in the panel when on, and never used in the demo. Eval figures and limits are in [`docs/AI_INTEGRATION.md`](docs/AI_INTEGRATION.md).

## Team

- **Ash:** team lead, product decisions, phone testing
- **Lewis:** capsule sharing (export, import, QR) and the marketplace and relay backend ([`harmoniser-web`](https://github.com/SimpsonLWH/harmoniser-web))
- **Keanu:** ESP32 wrist companion and its relay client; research documents under `docs/`

## Links

- Repository: https://github.com/Akshaz7/capsules-harmonyos
- Setup, build and launch: [`README.md`](README.md)
- `.hap`: not yet available as of 2026-10-04 02:00 CEST. The only release is the pre-release [`test-1`](https://github.com/Akshaz7/capsules-harmonyos/releases/tag/test-1) from 2026-10-03 16:09 UTC, which is many features behind. Needed: a build from the submission commit, published as a release, and its link here.
- Demo video: not yet available as of 2026-10-04 02:00 CEST. Needed: the recording, a public link here, and the commit it was recorded at (script: [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md))
- AI: [`docs/AI_INTEGRATION.md`](docs/AI_INTEGRATION.md) · [`AI_WORKFLOW.md`](AI_WORKFLOW.md)
- Third-party components: [`docs/THIRD_PARTY.md`](docs/THIRD_PARTY.md), plus the README table
