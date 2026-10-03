# AI Workflow

This project uses AI-assisted development. Keep this document current and public-safe. Do not include credentials, tokens, personal data, private endpoints, or confidential prompts.

## Tools used

| Model, agent, MCP server, or Agent Skill | Version or source | Role in the project |
| --- | --- | --- |
| Claude Code (Claude Opus 5.5) | Anthropic | Build/run tooling, debugging |
| `deveco-cli` Agent Skill / `devecocli` | 1.3.4 | Command-line build, screenshots |
| `hmos-arkui-develop-skill`, `hmos-arkts-knowledge-retriever` Agent Skills | Local skills | ArkUI/ArkTS API and syntax lookup before writing UI code |

## Important prompts and instructions

- `AGENTS.md` — repository-wide hackathon constraints and working agreement.
- UI session brief (2026-10-03): this session owns only `pages/`, `renderer/`, `adapters/`, `gatekeeper/` under `entry/src/main/ets`; never edit `core/` or `SCHEMA.md`. Build in order: (1) renderer for any SCHEMA.md capsule, starting with a hard-coded "Pasta night" capsule (Pasta 9, Sauce 15, Bread 6 min + "Start all"); (2) timer adapter on `reminderAgentManager`; (3) gatekeeper with per-permission allow/deny, block log, log screen, Undo; (4) notifications with a "Done" action, then vibration. Look up every API with the hmos skills; build, install and check on the emulator after every step; commit after each working step.
- Git rules from the user: commit only your own paths (no `git add -A`/`.`), commit small and often, stay on the checked-out branch, never force-push, pull or rebase.
- Decisions: capsule types come only from `core/CapsuleTypes.ets` (owned by the core session). The UI session may make minimal edits to `module.json5` (permissions) and `EntryAbility.ets` (notification action hook).

## AI-assisted work log

| Date | Tool/model | Request or task | Generated or changed | Human review and validation |
| --- | --- | --- | --- | --- |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Build, install and launch the template from the command line, bypassing a DevEco IDE sync error | Added a "Build and run" section to `CLAUDE.md` | Built the unsigned debug HAP, installed it on the emulator, launched `EntryAbility`; confirmed via `aa dump` (FOREGROUND) and a screenshot showing "Hello World" |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Step 1: renderer that draws any schema v0 capsule | `renderer/CapsuleRuntime.ets` (state, `dispatch(action)`, in-app countdown), `renderer/CapsuleView.ets` (draws all six component types), `pages/Index.ets` (hard-coded "Pasta night" capsule) | Built, installed, launched; screenshot showed the three timers; tapping "Start all" logged `dispatch startAllTimers`, and a second screenshot showed all three counting down |

## Workflow

### Ideation and architecture

[Describe how AI influenced the product idea, scope, architecture, and platform-capability choice.]

### Implementation

[Describe the AI-assisted coding workflow and how generated output was reviewed before acceptance.]

### Testing and debugging

[Record builds, linting, tests, device/emulator runs, UI inspection, logs, screenshots, and manual checks.]

## Unsuccessful approaches

- [What was tried, why it failed, and what changed afterward.]

## Known limitations

- [Product, platform, model, data, testing, or tooling limitation.]

## Lessons learned

- [Concise lesson that would help reproduce or improve the work.]

## AI feature disclosure

Complete this section only if AI is part of the product itself; otherwise write "Not applicable."

- Model or service: [Name/version/provider]
- Inference flow: [On-device, remote, or hybrid; inputs and outputs]
- Data handling and privacy: [What leaves the device, retention, consent, and safeguards]
- Failure and fallback behavior: [How errors, latency, offline use, and unsafe output are handled]
- Evaluation: [Test cases, quality measures, human review, and known model limitations]
