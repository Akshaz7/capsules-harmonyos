# Compliance audit

Checked against the official [`hackathon_challenge.md`](https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/hackathon_challenge.md) on 2026-10-03 at about 20:00, at commit `a9d853e` (main, local). Owners: **Ash** (team lead), **T1** (coordination, builds, phones), **T2** (docs), **T3** (app UI), **T4** (core), **T5** (Cactus).

Status key: ✅ met · ⚠️ partly met or at risk · ❌ missing.

## Technical requirements

| Requirement | Status | Evidence | Gap and owner |
| --- | --- | --- | --- |
| Native ArkTS/ArkUI or C/C++ | ✅ | ArkTS/ArkUI app; C++ Node-API wrapper for Cactus | – |
| Targets HarmonyOS/OpenHarmony/Oniro | ✅ | `build-profile.json5`: `runtimeOS: HarmonyOS` | – |
| API 20+, with API 20 as the minimum | ✅ | `compatibleSdkVersion: 6.0.0(20)`, `targetSdkVersion: 6.1.1(24)` | – |
| Compatible SDK and dev environment | ✅ | DevEco Studio 6.1.1, SDK API 24, hvigor, hdc | – |
| Runs on an emulator or a compatible device | ✅ emulator / ⚠️ device | Emulator runs are recorded throughout `AI_WORKFLOW.md` | Physical device: no run is recorded in the repo yet. **T1**: once the phones are flashed, add one line to `AI_WORKFLOW.md` (device model, build, what was checked). Calendar alerts with the app closed have never been seen working (they don't fire on the emulator). |
| Reproducible setup, build and launch instructions | ✅ | README "Setup, build, install, launch" | `CLAUDE.md` still says to use `devecocli signature generate`, which is mainland-China only (README already corrected). **T1/Ash**: fix `CLAUDE.md`. |
| Uses or improves a platform capability | ✅ | Calendar Kit, Notification Kit, Form Kit widget, Share Kit, Scan Kit, Core File Kit, Preferences, on-device inference through Node-API | – |

## Required deliverables

| # | Deliverable | Status | Evidence | Gap and owner |
| --- | --- | --- | --- | --- |
| 1 | Public source repository | ⚠️ | https://github.com/Akshaz7/capsules-harmonyos is public | 5 commits on local `main` are not pushed yet (task protocol says don't push). **T1**: push before the deadline. |
| 2 | Setup, build, install and launch instructions | ✅ | README | See the `CLAUDE.md` signing note above |
| 3 | Working `.hap` | ⚠️ | Pre-release `test-1` has `harmoniser-test-1.hap`, which I byte-scanned: no API key (the only match is the error string `"apiKey" is missing`) | It was built from `e493911`, which is many features behind, and it is unsigned, so emulator only. **T1**: publish a final release from the submission commit. Keep an unsigned emulator HAP, because judges default to the emulator, and add a signed one if it is meant for real devices. Byte-scan both for keys before uploading. |
| 4 | Brief recorded demonstration | ❌ | None in the repo or releases | **Ash/T1**: record it following `docs/DEMO_SCRIPT.md` (T2-2), then link it from the README |
| 5 | Architecture and implementation description | ✅ | README "Architecture", stage table, Mermaid diagram, Cactus port section | – |
| 6 | `AI_WORKFLOW.md` | ⚠️ | Tools table, prompts, detailed work log, and some unsuccessful approaches and lessons | The template placeholders are still there: "Ideation and architecture", "Implementation" and "Testing and debugging" are `[Describe …]`, and there are placeholder bullets under Unsuccessful approaches, Known limitations and Lessons learned. The challenge explicitly asks for the workflow "from ideation and architecture through implementation, testing and debugging" and for how output was reviewed. **T1** (or whoever owns `AI_WORKFLOW.md`): fill these in from the work log and delete the placeholders. |
| 7 | AI integration documentation (the product has AI features) | ❌ | The `AI_WORKFLOW.md` "AI feature disclosure" section is still all placeholders (`[Name/version/provider]` …). README and `docs/THIRD_PARTY.md` cover parts. | The challenge requires the model or service, inference flow, data handling, limitations, validation approach and privacy. **T2** can write `docs/AI_INTEGRATION.md` (docs/ is T2's) from the existing material if T1 assigns it. `AI_WORKFLOW.md` should then link to it instead of the placeholders. |

## Use of AI rules

| Rule | Status | Notes and owner |
| --- | --- | --- |
| List all models, agents, MCP servers, skills and tools | ⚠️ | The tools table lists Claude Code (Opus 5.5), a Sonnet subagent, `deveco-cli` and the hmos skills. Not listed: the product's own runtime models (LFM2-VL-450M with Cactus, Mistral `ministral-14b-latest`, Claude `claude-sonnet-5-5`), and `GEMINI.md` exists without saying whether Gemini was used. **T1**: add rows, or state that Gemini was not used. |
| Main prompts and reusable instructions | ✅ | Session briefs and `AGENTS.md` are summarised; the product prompt is in `core/CapsuleModel.ets` | – |
| How output was reviewed and tested | ⚠️ | Covered row by row in the work log, but the "Implementation" and "Testing and debugging" sections are placeholders | Same owner as deliverable 6 |
| No keys, credentials or personal data | ✅ | History scan for key patterns (`sk-ant-…`, long `apiKey` values, private keys, signing passwords) found nothing. `config.local.json`, `*.p12`, `*.cer`, `*.p7b` and `local.properties` are git-ignored and untracked. The release HAP is clean. | Commit author emails include a university address and a contributor noreply address (public, not secret). Re-run the scan before the final push. |

## Evaluation risks (claims vs code)

The jury checks that "claims should be backed by the code, the demo, logs or test results". These claims currently aren't:

| Issue | Where | Owner |
| --- | --- | --- |
| The UI says capsules can use "vibration and the motion sensor", but neither is built: there is no vibrator or sensor code and no sensor permission | `pages/Index.ets` `CAPSULE_ABILITIES` | **T3**: remove the words, or build the features |
| The cloud prompt tells the model "steps and reps can use the motion sensor" and that capsules can use "vibration, the motion sensor, location and a home [widget]". A user asking for automatic step counting gets a tap counter. | `core/CapsuleModel.ets` lines 135–137 | **T4**: align the prompt with what is built |
| The schema has `location` and `widget` permissions that nothing uses | `SCHEMA.md` | **Ash** decides (SCHEMA is the contract). The README already says so. |
| `HACKATHON_BRIEF.md` is still the empty template | repo root | **Ash**: fill in or delete. Judges may read it. |
| No screenshots | README | **Ash**: `docs/screenshots/` (widget, gatekeeper sheet, dark mode, Calendar, tennis); T2 adds the section |
| The README doesn't say what was built during the hackathon versus the template | README | **T2**: add a short "Built at HackYeah" note (doing it under T2-4) |

## Reproducibility

| Item | Status | Notes and owner |
| --- | --- | --- |
| Tool versions | ✅ | DevEco Studio 6.1.1, SDK API 24 (min API 20), `devecocli` 1.3.4, Node 18+ for the eval |
| Unit tests | ✅ | 156 pass (`hvigorw … test`; the README gives the exact command, including `DEVECO_SDK_HOME`) |
| On-device model | ✅ | URL, tag and sha256 in `docs/THIRD_PARTY.md`; `scripts/push-model.sh` |
| Rebuilding `libcactus_engine.so` | ⚠️ | The repo has the prebuilt `.so` and `cactus/cactus-ohos.patch`, but the cross-compile commands live only in `cactus-spike/SPIKE_LOG.md`, outside the repo. **T5**: add a `cactus/BUILD.md` or script with the exact CMake/NDK commands. |
| Untracked `.cache/` folder | ⚠️ | **T1**: add it to `.gitignore` so it is never committed by accident |
