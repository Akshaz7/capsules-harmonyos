# AI Workflow

This project uses AI-assisted development. Keep this document current and public-safe. Do not include credentials, tokens, personal data, private endpoints, or confidential prompts.

## Tools used

| Model, agent, MCP server, or Agent Skill | Version or source | Role in the project |
| --- | --- | --- |
| Claude Code (Claude Opus 5.5) | Anthropic | Build/run tooling, debugging |
| `deveco-cli` Agent Skill / `devecocli` | 1.3.4 | Command-line build, screenshots |
| `hmos-arkui-develop-skill`, `hmos-arkts-knowledge-retriever` Agent Skills | Local skills | ArkUI/ArkTS API and syntax lookup before writing UI code; `devecocli docs` for Kit API and error-code lookup |

## Important prompts and instructions

- `AGENTS.md` — repository-wide hackathon constraints and working agreement.
- UI session brief (2026-10-03): this session owns only `pages/`, `renderer/`, `adapters/`, `gatekeeper/` under `entry/src/main/ets`; never edit `core/` or `SCHEMA.md`. Build in order: (1) renderer for any SCHEMA.md capsule, starting with a hard-coded "Pasta night" capsule (Pasta 9, Sauce 15, Bread 6 min + "Start all"); (2) timer adapter on `reminderAgentManager`; (3) gatekeeper with per-permission allow/deny, block log, log screen, Undo; (4) notifications with a "Done" action, then vibration. Look up every API with the hmos skills; build, install and check on the emulator after every step; commit after each working step.
- Git rules from the user: commit only your own paths (no `git add -A`/`.`), commit small and often, stay on the checked-out branch, never force-push, pull or rebase.
- Core session brief (2026-10-03): this session owns only `entry/src/main/ets/core/` and its unit tests (`entry/src/test/`); never edit pages, renderer, adapters, gatekeeper or `SCHEMA.md`. Build pure ArkTS logic in order: (1) capsule types and a strict validator with unit tests; (2) an on-device rule parser for common requests; (3) a provider-swappable model module that sends the request plus the schema and always validates the reply, with the API key read from the git-ignored `rawfile/config.local.json`; (4) `generateCapsule(request)`: rules first, model as fallback. Commit after each working step.
- Decisions: capsule types come only from `core/CapsuleTypes.ets` (owned by the core session). The UI session may make minimal edits to `module.json5` (permissions) and `EntryAbility.ets` (notification action hook).

## AI-assisted work log

| Date | Tool/model | Request or task | Generated or changed | Human review and validation |
| --- | --- | --- | --- | --- |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Build, install and launch the template from the command line, bypassing a DevEco IDE sync error | Added a "Build and run" section to `CLAUDE.md` | Built the unsigned debug HAP, installed it on the emulator, launched `EntryAbility`; confirmed via `aa dump` (FOREGROUND) and a screenshot showing "Hello World" |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Step 1: renderer that draws any schema v0 capsule | `renderer/CapsuleRuntime.ets` (state, `dispatch(action)`, in-app countdown), `renderer/CapsuleView.ets` (draws all six component types), `pages/Index.ets` (hard-coded "Pasta night" capsule) | Built, installed, launched; screenshot showed the three timers; tapping "Start all" logged `dispatch startAllTimers`, and a second screenshot showed all three counting down |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Core steps 1–4: validator, rule parser, model module, `generateCapsule` | `core/CapsuleTypes.ets` (added constants and result types to the shared types), `core/CapsuleValidator.ets`, `core/RuleParser.ets`, `core/ModelProvider.ets`, `core/CapsuleModel.ets`, `core/CapsuleGenerator.ets`, `core/index.ets`; local unit tests in `entry/src/test/` | 33 local unit tests pass (`hvigorw test`), including bad JSON, unknown component, unknown action and missing-permission cases, and a check that every rule output passes the validator. Deliberately broken assertions (sync and async) confirmed failures are reported. Model calls tested only with a fake HTTP transport, not a real provider. `devecocli check arkts` is clean on all core files |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Step 2: timers that fire with the app closed | `adapters/TimerAdapter.ets` on Calendar Kit (one event per timer, reminder at start, tagged `capsules:<capsuleId>:<timerId>`); READ/WRITE_CALENDAR permissions | `reminderAgentManager.publishReminder` failed with 1700002 (log: `VerifyCloudCapability failed … reminder_capability`, limit 0): phones need an AppGallery Connect grant. The user chose Calendar Kit. Events were created (logged ids 1–4), but the 1-minute reminder did not show with the app force-stopped. The system Calendar app was still on its first-run privacy screen. Firing is pending the user's test |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Follow-ups from the user | `initCapsuleModel(context)` in `EntryAbility.onCreate`, INTERNET permission, ability label "Capsules" | Startup log `initCapsuleModel ready=true` |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Step 3: gatekeeper | `gatekeeper/Gatekeeper.ets` (per-capsule grants and log in Preferences; a permission counts only if declared AND allowed; blocks and logs components and actions using core `permissionForComponent`/`permissionForAction`), `pages/ConsentView.ets` (allow/deny switch per permission), `pages/LogView.ets`, Undo in `pages/Index.ets` (cancels the capsule's calendar events, forgets grants, marks it removed) | On the emulator: with reminders denied, all four timers and "Start all" rendered as blocked, with matching log lines. A manual run on the emulator logged Undo "cancelled 4 calendar reminder(s)" and a re-consent with reminders allowed |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | User: stop working on calendar alerts. Notify when a timer ends while the app runs. Add a README note. Top priority: wire the main screen to `generateCapsule` | `adapters/NotificationAdapter.ets` (`notificationManager.publish`, basic text), `TimerAlert` hook in the runtime, `pages/CapsuleStore.ets` (active capsule in Preferences), `pages/Index.ets` (text box, then Create, then `generateCapsule`, then consent, then render; Undo deletes the stored capsule); removed the hard-coded Pasta night capsule; README note and status rows | Built and installed; the create screen renders. Found and fixed a race: `initCapsuleModel` finishes after the first render, so the screen showed "not configured" while the log said `ready=true`; it now re-reads the status. Typing was not exercised: the emulator keyboard asked for its own first-run consent, which was left to the user. The generate-to-render path and the timer-end notification are unverified on device |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Harmoniser home-screen widget (Form Kit) and widget routing | `core/CapsuleRouter.ets` (`routeCapsule`), `core/WidgetModel.ets`, a checklist rule in `core/RuleParser.ets`, `widget/` (FormExtensionAbility, preferences storage, card page), `form_config.json`, the form entry in `module.json5` | Form Kit APIs looked up in local DevEco docs first (TextTimer is widget-capable since API 10; `requestPublishForm` is not in the public SDK, `openFormManager` is). 52 unit tests pass. On the emulator: added 2x2 and 2x4 widgets from the picker; timers count down, + updates every widget showing that capsule, checklist items tick and untick, widgets keep their capsule after reinstall |

## Workflow

### Ideation and architecture

[Describe how AI influenced the product idea, scope, architecture, and platform-capability choice.]

### Implementation

[Describe the AI-assisted coding workflow and how generated output was reviewed before acceptance.]

### Testing and debugging

[Record builds, linting, tests, device/emulator runs, UI inspection, logs, screenshots, and manual checks.]

## Unsuccessful approaches

- [What was tried, why it failed, and what changed afterward.]
- Core and UI sessions shared one checkout. The core session made a `feat/core` branch, which switched the branch for the UI session too, and the UI session's commit replaced the core session's uncommitted `CapsuleTypes.ets`. Fix: fast-forwarded `main`, deleted the branch, and both sessions now work on `main` and `git add` only their own paths. The core session added its exports to the UI session's version so existing imports keep working.

## Known limitations

- [Product, platform, model, data, testing, or tooling limitation.]
- Schema v0 has no time-of-day reminder or computed values, so the rule parser turns "medication 8am and 8pm" into a dose checklist and works out bill splits as static text.
- `CapsuleModel.ets` holds a copy of `SCHEMA.md` for the prompt. It must be updated by hand if the schema changes.
- Local unit tests can't call system APIs, so the network transport and rawfile loading in `core/index.ets` are type-checked but not unit-tested.

## Lessons learned

- [Concise lesson that would help reproduce or improve the work.]
- In an ArkTS widget, a tap handler inside a `@Builder`'s `ForEach` sent another item's index on the device. Putting each item in its own `@Component` with `@Prop` fixed it. The widget compiler also rejects non-widget APIs such as `hitTestBehavior`, so check the "widget capability" note in the docs.
- After an app update the launcher calls `onAddForm` again with the existing formId, so keep stored widget bindings instead of treating every call as a new widget.
- hvigor only compiles `.ets` files that something imports. Use `devecocli check arkts <files>` to type-check files nothing imports yet. Local unit tests run with `hvigorw --mode module -p module=entry@default -p product=default test`, and results land in `entry/.test/default/intermediates/test/coverage_data/test_result.txt`.

## AI feature disclosure

Complete this section only if AI is part of the product itself; otherwise write "Not applicable."

- Model or service: [Name/version/provider]
- Inference flow: [On-device, remote, or hybrid; inputs and outputs]
- Data handling and privacy: [What leaves the device, retention, consent, and safeguards]
- Failure and fallback behavior: [How errors, latency, offline use, and unsafe output are handled]
- Evaluation: [Test cases, quality measures, human review, and known model limitations]
