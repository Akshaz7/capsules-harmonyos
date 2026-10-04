# Compliance audit

Checked against the official [`hackathon_challenge.md`](https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/hackathon_challenge.md) first on 2026-10-03; re-checked against the code on 2026-10-04 (main, local, up to `318de85`). Owners: **Ash** (team lead), **T1** (coordination, builds, phones), **T2** (docs), **T3** (app UI), **T4** (core), **T5** (Cactus).

Status key: ✅ met · ⚠️ partly met or at risk · ❌ missing. Still missing: the recorded demo and a final release `.hap`.

## Technical requirements

| Requirement | Status | Evidence | Gap and owner |
| --- | --- | --- | --- |
| Native ArkTS/ArkUI or C/C++ | ✅ | ArkTS/ArkUI app; C++ Node-API wrapper for Cactus | – |
| Targets HarmonyOS/OpenHarmony/Oniro | ✅ | `build-profile.json5`: `runtimeOS: HarmonyOS` | – |
| API 20+, with API 20 as the minimum | ✅ | `compatibleSdkVersion: 6.0.0(20)`, `targetSdkVersion: 6.1.1(24)` | – |
| Compatible SDK and dev environment | ✅ | DevEco Studio 6.1.1, SDK API 24, hvigor, hdc | – |
| Runs on an emulator or a compatible device | ✅ emulator / ⚠️ device | Emulator runs throughout `AI_WORKFLOW.md`. On real phones: Share, and the photo path (10 photos through on-device OCR, all built on the phone). `AI_WORKFLOW.md` says Ash tested on two phones, without a per-run log. | **T1**: add one `AI_WORKFLOW.md` line per phone run (device, build, what was checked). Not yet checked on a phone: shake counting, widget taps after the fix, calendar alerts with the app closed. |
| Reproducible setup, build and launch instructions | ✅ | README "Setup, build, install, launch" | Fixed: `CLAUDE.md` now points to DevEco Signing Configs (T2-7). |
| Uses or improves a platform capability | ✅ | Calendar Kit, Notification Kit, Form Kit widget, Share Kit, Scan Kit, Core File Kit, Core Vision Kit (OCR), Sensor Service Kit (accelerometer, vibrator), Basic Services Kit (battery), Network Kit, Preferences, on-device inference through Node-API | – |

## Required deliverables

| # | Deliverable | Status | Evidence | Gap and owner |
| --- | --- | --- | --- | --- |
| 1 | Public source repository | ⚠️ | https://github.com/Akshaz7/capsules-harmonyos is public | 8 commits on local `main` were not pushed at the time of this check (the task protocol says don't push). **T1**: push before the deadline. |
| 2 | Setup, build, install and launch instructions | ✅ | README | – |
| 3 | Working `.hap` | ⚠️ | Releases: pre-release `test-1` (byte-scanned: no API key) and a draft "Test builds for Lewis (not for judging)". | `test-1` is many features behind and unsigned, so emulator only. **T1**: publish a final release from the submission commit. Keep an unsigned emulator HAP, because judges default to the emulator, and add a signed one if it is meant for real devices. Byte-scan both for keys before uploading. |
| 4 | Brief recorded demonstration | ❌ | None in the repo or releases | **Ash/T1**: record it following `docs/DEMO_SCRIPT.md` (now with the marketplace beat), on a build with the widget tap fix, then link it from the README. Two beats need fixing first (see the warning in the demo script) |
| 5 | Architecture and implementation description | ✅ | README "Architecture", stage table, Mermaid diagram, Cactus port section | – |
| 6 | `AI_WORKFLOW.md` | ✅ | Tools table (including the product's runtime models and Codex), prompts, work log, workflow sections, unsuccessful approaches, limitations and lessons | Keep the work log current until submission. |
| 7 | AI integration documentation (the product has AI features) | ✅ | [`docs/AI_INTEGRATION.md`](AI_INTEGRATION.md): models, inference flow, data handling, validation, results and limitations; `AI_WORKFLOW.md` links to it | – |

## Use of AI rules

| Rule | Status | Notes and owner |
| --- | --- | --- |
| List all models, agents, MCP servers, skills and tools | ✅ | The tools table lists the coding agents (Claude Code, Codex), skills, and the product's runtime models, and states that Gemini was not used. | – |
| Main prompts and reusable instructions | ✅ | Session briefs and `AGENTS.md` are summarised; the product prompt is in `core/CapsuleModel.ets` | – |
| How output was reviewed and tested | ✅ | Covered in the work log and the "Testing and debugging" section | – |
| No keys, credentials or personal data | ✅ | History scan for key patterns (`sk-ant-…`, long `apiKey` values, private keys, signing passwords) found nothing. `config.local.json`, `*.p12`, `*.cer`, `*.p7b` and `local.properties` are git-ignored and untracked. The release HAP is clean. | Commit author emails include a university address and a contributor noreply address (public, not secret). Re-run the scan before the final push. |

## Evaluation risks (claims vs code)

The jury checks that "claims should be backed by the code, the demo, logs or test results". These claims currently aren't:

| Issue | Where | Owner |
| --- | --- | --- |
| The UI and the cloud prompt say capsules can use **vibration**, but no capsule action vibrates (the app's own save vibration is not a capsule ability). The motion sensor, battery and weather claims are now backed by code. | `pages/Index.ets` `CAPSULE_ABILITIES`; `core/CapsuleModel.ets` ("Capsules can only use timers and reminders, notifications, vibration …") | **T3/T4**: remove "vibration", or build it |
| Reminders (`notify:<text>` and daily time triggers ringing with the app closed) are now built (notification adapter, recurring daily Calendar Kit events) but not yet checked on the emulator or a phone. Until Ash's check, say "built", not "works". | `renderer/CapsuleRuntime.ets`, `core/Reminders.ets`, `adapters/NotificationAdapter.ets` | **Ash**: run the reminder check in the README |
| The schema has `location` and `widget` permissions that nothing uses | `SCHEMA.md` | **Ash** decides (SCHEMA is the contract). The README already says so. |
| No screenshots | README | **Ash**: `docs/screenshots/` (widget, gatekeeper sheet, Calendar, tennis; dark mode is off while the redesign locks light mode); T2 adds the section |
| The live marketplace search sends the request text to the marketplace server with no consent notice in **Smart** mode. **Fixed for On-device only:** the search is skipped in that mode, and the Marketplace tab then shows only the shipped examples and sends nothing (both unit-tested) | `core/CapsuleGenerator.ets`, `core/templates/MarketMatch.ets` | **Ash**: a consent notice for Smart mode, if wanted |

## Reproducibility

| Item | Status | Notes and owner |
| --- | --- | --- |
| Tool versions | ✅ | DevEco Studio 6.1.1, SDK API 24 (min API 20), `devecocli` 1.3.4, Node 18+ for the eval |
| Unit tests | ✅ | 344 pass (`hvigorw … test`; the README gives the exact command, including `DEVECO_SDK_HOME`) |
| On-device model | ✅ | URL, tag and sha256 in `docs/THIRD_PARTY.md`; `scripts/push-model.sh` |
| Rebuilding `libcactus_engine.so` | ✅ | `cactus/BUILD.md` and `cactus/build-engine.sh`; a clean rebuild matches the committed `.so` apart from the build ID |
| Untracked `.cache/` folder | ✅ | Ignored in `.gitignore` |
