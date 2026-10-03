# AI Workflow

This project uses AI-assisted development. Keep this document current and public-safe. Do not include credentials, tokens, personal data, private endpoints, or confidential prompts.

## Tools used

| Model, agent, MCP server, or Agent Skill | Version or source | Role in the project |
| --- | --- | --- |
| Claude Code (Claude Opus 5.5) | Anthropic | Build/run tooling, debugging |
| `deveco-cli` Agent Skill / `devecocli` | 1.3.4 | Command-line build, screenshots |
| `hmos-arkui-develop-skill`, `hmos-arkts-knowledge-retriever` Agent Skills | Local skills | ArkUI/ArkTS API and syntax lookup before writing UI code; `devecocli docs` for Kit API and error-code lookup |
| Claude Code general-purpose subagent (Claude Sonnet) | Anthropic | Read-only research of the Cactus-Compute Hugging Face models compatible with Cactus v2.2.2 (sizes, licences, formats); results checked by hand before any download |

## Important prompts and instructions

- `AGENTS.md` — repository-wide hackathon constraints and working agreement.
- UI session brief (2026-10-03): this session owns only `pages/`, `renderer/`, `adapters/`, `gatekeeper/` under `entry/src/main/ets`; never edit `core/` or `SCHEMA.md`. Build in order: (1) renderer for any SCHEMA.md capsule, starting with a hard-coded "Pasta night" capsule (Pasta 9, Sauce 15, Bread 6 min + "Start all"); (2) timer adapter on `reminderAgentManager`; (3) gatekeeper with per-permission allow/deny, block log, log screen, Undo; (4) notifications with a "Done" action, then vibration. Look up every API with the hmos skills; build, install and check on the emulator after every step; commit after each working step.
- Git rules from the user: commit only your own paths (no `git add -A`/`.`), commit small and often, stay on the checked-out branch, never force-push, pull or rebase.
- Core session brief (2026-10-03): this session owns only `entry/src/main/ets/core/` and its unit tests (`entry/src/test/`); never edit pages, renderer, adapters, gatekeeper or `SCHEMA.md`. Build pure ArkTS logic in order: (1) capsule types and a strict validator with unit tests; (2) an on-device rule parser for common requests; (3) a provider-swappable model module that sends the request plus the schema and always validates the reply, with the API key read from the git-ignored `rawfile/config.local.json`; (4) `generateCapsule(request)`: rules first, model as fallback. Commit after each working step.
- Decisions: capsule types come only from `core/CapsuleTypes.ets` (owned by the core session). The UI session may make minimal edits to `module.json5` (permissions) and `EntryAbility.ets` (notification action hook).
- On-device AI session brief (2026-10-03): make Cactus on-device inference the default AI provider for the European digital sovereignty and offline pitch. May edit only a new `cactus/` HAR, the module and dependency registration, the new `core/providers/CactusProvider.ets`, and the minimal core change to chain it. Never edit pages, renderer, adapters, gatekeeper, widget, `module.json5` or `SCHEMA.md`. Provider order: rules, then on-device, then cloud only if enabled. Export `getOnDeviceStatus()`, `generateCapsule(request, { allowCloud })` and origins `'rules' | 'on-device' | 'cloud'`. The model stays out of the .hap. A separate spike folder (outside this repo) proved the engine first.

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
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Spike, outside this repo: run Cactus on the emulator from ArkTS, then evaluate capsule generation on 10 requests | Cactus v2.2.2 cross-compiled for arm64-v8a with the OHOS toolchain (3 patches); a Node-API wrapper with async work; an eval harness and validator | On the emulator: LFM2-VL-450M decodes 92–113 tok/s, first token 0.27–0.39 s, about 380 MB RAM. Full-capsule generation: LFM2 6/10 schema-valid but 3/10 correct; gemma-4-E2B cq2 0/10 correct. Slot-filling with grounding (the model picks a kind and fills slots, code builds the capsule): 5/10 correct, 0 wrong-but-valid. Tool calling (`force_tools`): 2/10. User chose slot-filling |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Make on-device Cactus the default provider | `cactus/` HAR (prebuilt `.so`, Node-API wrapper, minimal FFI header, licence, patch), `core/providers/CactusProvider.ets`, chain and API in `core/CapsuleGenerator.ets`, `core/index.ets`, `core/CapsuleTypes.ets` (origins) and `core/CapsuleModel.ets` (`'cloud'`), `scripts/push-model.sh`, `docs/THIRD_PARTY.md` | `devecocli check arkts` clean and the entry build passes; the HAP contains `libcactus_engine.so`, `libcactus_napi.so` and `libc++_shared.so`. Unit tests: 50/52 pass; the 2 failures assert the old origin `'model'`, which this change renamed to `'cloud'` (tests are owned by the core session). On the emulator the app logs `cactus_init ok in 310.7 ms`. Not yet shown in the UI: with cloud AI off, `pages/Index.ets` calls `generateCapsuleWith(text, null, ...)` directly, which skips on-device, until the app session switches to `generateCapsule(text, { allowCloud })`. Emulator airplane mode does not cut the emulator's network, so "offline" was not strictly tested |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Keep app and home-screen widget state in sync both ways | `CapsuleRuntime.exportState()/applyState()` and an `onChange` hook, mapped to core's `WidgetModel.CapsuleState`; `Index.ets` loads state from the widget store on create and on `onPageShow`, saves it and calls `refreshCapsuleWidgets(ctx, id)` on every change; checklist ticks go through `setChecked` | Built and installed on the emulator. Widget to app: widget had Water 3 and Leaving home 2/3, app showed the same after returning (log: reloaded widget state for 6 capsules). App to widget: ticked Keys in the app, the home-screen widget showed 3/3. Timers started from a widget do not create calendar events (not addressed) |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Friendly create failure: no internal error text for users | `Index.ets`: on a failed `generateCapsule` (or a thrown error) show a fixed message, three suggestion chips that the offline rules can build, and a link to Settings when cloud AI is off; the real error and validator details go to hilog | On the emulator with cloud off: "zxqv blorp" showed the card and the logged error; the "Eggs timer 10 min" chip built "Eggs timers" (made by rules). The Settings link was not tapped |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Schema v1 in core: state, computed values, expressions, display/input/list/when/row, button steps | `SCHEMA.md` (v1 section, approved by Ash), `core/CapsuleTypes.ets`, `core/Expr.ets` (own lexer and parser, static types, step budget; never eval), `core/CapsuleProgram.ets` (pure interpreter: `applyActions` all-or-nothing, `setInput`, `renderTemplate`), `core/CapsuleValidator.ets` (v1 checks and limits), `core/CapsuleModel.ets` (prompt teaches v1 with two examples), `core/V1Fixtures.ets` (tennis and bill-split capsules), `core/CapsuleRouter.ets` (v1 capsules are app-only) | 39 new unit tests, including a full tennis scoreboard (15/30/40, deuce, advantage, games), a live bill split, all-or-nothing steps, computed cycles and limits; every v0 test still passes. Not yet tested with a real cloud model generating v1 |
| 2026-10-03 | Claude Code (Claude Opus 5.5) | Mistral as a cloud provider, multi-provider config, provider eval | `core/ModelProvider.ets` (provider `mistral`: OpenAI-compatible chat completions with JSON output mode; config with several providers and a `default`, old format still read), `scripts/eval-providers.mjs` (bundles the core prompt, providers and validator with esbuild; 15 requests per provider), `CLAUDE.md` | Model choice checked against Mistral's docs, then against the key: `mistral-large-latest` returned 403 `tier_not_allowed`, and Medium and Small allow 0 requests a minute on this tier, so the config uses `ministral-14b-latest`. 7 new unit tests with a fake transport (118 pass). Real calls, same 15 requests: Anthropic `claude-sonnet-5-5` 15/15 valid, 15/15 correct; Mistral `ministral-14b-latest` 13/15 valid, 13/15 correct (the validator caught an invalid computed expression and hyphenated state names). The key lives only in the git-ignored root `config.local.json`, pushed to the emulator's files dir, where the app logged `initCapsuleModel ready=true`; an in-app cloud request was not exercised |

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
- On-device full-capsule generation: LFM2-VL-450M and gemma-4-E2B cq2 were given the compact schema plus examples. LFM2 copied the example (most requests became a timer) and printed placeholders such as `<number>`; Gemma at 2-bit was worse and 4 times slower. We switched to slot-filling with a deterministic capsule builder.
- Cactus tool calling (one tool per capsule kind, `force_tools`): the model over-picked `make_timers` and merged list items. It scored 2/10 against 5/10 for slot-filling, so it was not adopted.
- An example-free retry prompt (no example values the model could copy) broke the output format and did not raise the score.

## Known limitations

- [Product, platform, model, data, testing, or tooling limitation.]
- Schema v0 has no time-of-day reminder or computed values, so the rule parser turns "medication 8am and 8pm" into a dose checklist and works out bill splits as static text.
- `CapsuleModel.ets` holds a copy of `SCHEMA.md` for the prompt. It must be updated by hand if the schema changes.
- Local unit tests can't call system APIs, so the network transport and rawfile loading in `core/index.ets` are type-checked but not unit-tested.
- On-device AI handles 5 of the 10 eval requests correctly and rejects the other 5 cleanly. Slot grounding stops it returning a valid but wrong capsule, but multi-item requests (3 timers, a 3-item checklist) often fail. Rules run first, so the model only sees the requests rules miss.
- `RuleParser`'s goal pattern turns "laundry done in 55 minutes" into a 55-minute goal counter before the on-device model sees it.
- The on-device model must be pushed separately (`scripts/push-model.sh`, debug builds only); without it the status reads "On-device model not installed" and the app falls back cleanly. A release or AppGallery build would need an in-app download.
- Cactus only ships arm64-v8a. Performance was measured on the emulator, which runs on the host's Apple M4 Pro cores; a phone will be slower and was not measured.

## Lessons learned

- [Concise lesson that would help reproduce or improve the work.]
- In an ArkTS widget, a tap handler inside a `@Builder`'s `ForEach` sent another item's index on the device. Putting each item in its own `@Component` with `@Prop` fixed it. The widget compiler also rejects non-widget APIs such as `hitTestBehavior`, so check the "widget capability" note in the docs.
- After an app update the launcher calls `onAddForm` again with the existing formId, so keep stored widget bindings instead of treating every call as a new widget.
- hvigor only compiles `.ets` files that something imports. Use `devecocli check arkts <files>` to type-check files nothing imports yet. Local unit tests run with `hvigorw --mode module -p module=entry@default -p product=default test`, and results land in `entry/.test/default/intermediates/test/coverage_data/test_result.txt`.
- `hdc file send` as the shell user can't write into an app's sandbox (`permission denied`). `hdc file send -b <bundle> <local> data/storage/el2/base/haps/entry/files/...` writes as the app's own uid, on debuggable builds only.
- The OHOS NDK's Clang 15 lacks C++20 parenthesised aggregate init (`emplace_back` on an aggregate). Brace-init with `push_back(T{...})` fixes it.
- Small models copy prompt examples verbatim. Rejecting slots whose words or numbers are not in the request, then retrying once, turned wrong answers into clean failures.
- Several sessions share one emulator. Drive automated runs with `aa start ... --ps key value` and read result files over hdc, rather than with foreground UI clicks that another session can steal.

## AI feature disclosure

Complete this section only if AI is part of the product itself; otherwise write "Not applicable."

- Model or service: [Name/version/provider]
- Inference flow: [On-device, remote, or hybrid; inputs and outputs]
- Data handling and privacy: [What leaves the device, retention, consent, and safeguards]
- Failure and fallback behavior: [How errors, latency, offline use, and unsafe output are handled]
- Evaluation: [Test cases, quality measures, human review, and known model limitations]
