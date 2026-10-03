# Judges' feedback research: the "task list + weather" failure, routing, models and widget sizes

**Date:** 2026-10-04

**How this was produced:** AI-assisted desk research (a Claude Code sub-agent using web search and reading this repository). Nothing was run on a device or an emulator, and no code was changed. Code references are to `origin/main` at `7292381`; paths are relative to the repository root.

**What prompted it:** Huawei judges tried the app and asked for a capsule with both a task list and weather. The app produced a garbled task list and no weather display at all.

**Tags used below:** **[S]** sourced (code or URL), **[J]** judgement, **[U]** unverified.

## What to fix first for 11:00

1. **Add a `weather` component with a network permission (2–3 h).** The schema has no live-data component at all, so no model choice can produce weather.
2. **Add a deterministic compound rule (1–1.5 h).** Split on "and / with / plus", build each part by rules or templates, and merge. The judges' prompt then needs no model.
3. **Guard the router (45 min).** Compound or live-data requests skip the 450M model, and an on-device result that drops request words is treated as a failure.
4. **Teach the cloud prompts about weather and drop the `weather` tag from the Celsius template (20 min).** Today a bare "weather" request returns a Celsius-to-Fahrenheit converter.
5. **Keep LFM2-VL-450M; do widget sizing last (45–60 min).** No other small text model has a loadable bundle for Cactus 2.2.2.

---

## Part A: diagnosis

### Weather is impossible in the current schema [S]

- Component types are `text, timer, counter, checklist, number, button, display, input, list, when, row` (`entry/src/main/ets/core/CapsuleTypes.ets:5-6, 145-147`; `SCHEMA.md:8-14, 41-46`).
- The validator rejects any other type (`entry/src/main/ets/core/CapsuleValidator.ets:251-260`).
- Expressions have no clock, fetch or external names (`SCHEMA.md:32-39`).
- The `location` permission is declared (`CapsuleTypes.ets:3, 143`) but `permissionForComponent` never returns it (`CapsuleValidator.ets:146-154`).
- The app does hold `ohos.permission.INTERNET` (`entry/src/main/module.json5:15`), used only for the cloud model, marketplace and relay.

No model choice fixes this. The fix is a schema and runtime feature.

### Trace of "a task list and the weather for Kraków"

1. The English gate passes: one accented letter plus English words (`entry/src/main/ets/core/Language.ets:49-63`). [S]
2. `Index.createFrom` tries rules, then templates (`entry/src/main/ets/pages/Index.ets:875-886`). [S]
3. Rules return null: `parseChecklist` needs a colon or the word "checklist" with separators (`entry/src/main/ets/core/RuleParser.ets:383-406`), and `parseRequest` returns the first single rule that matches, so it cannot compose two (`RuleParser.ets:409-424`). [S]
4. No template reaches the 0.7 threshold; the best is `homework-tracker` at 0.5 (`entry/src/main/ets/core/templates/TemplateLibrary.ets:69, 354-386`). This is from a Python port of the scorer, not a device run, and it leaves out the built-in `CoreTemplates.ets` entries. [U]
5. `needsLogic` is false for "task list"; only `to-?do list` or `shopping list` trigger cloud-first (`entry/src/main/ets/core/CapsuleGenerator.ets:84, 97-99, 179`). [S]
6. So the request goes to the on-device model (`CapsuleGenerator.ets:200-209`). [S]

Scores from the same port for other likely wordings (all [U]):

| Request | Best template (score) | Template match | `needsLogic` |
| --- | --- | --- | --- |
| `a task list and the weather for Kraków` | `homework-tracker` (0.5) | no | false |
| `task list and weather` | `homework-tracker` (0.667) | no | false |
| `todo list with today's weather` | `homework-tracker` (0.4) | no | true |
| `to-do list and weather` | `homework-tracker` (0.667) | no | true |
| `tasks and weather` | `celsius-to-fahrenheit` (0.5) | no | false |
| `a capsule that has both a task list and weather` | `homework-tracker` (0.4) | no | false |
| `weather` | `celsius-to-fahrenheit` (1.0) | **yes** | false |
| `weather in Krakow` | `celsius-to-fahrenheit` (0.5) | no | false |

The bare `weather` row is a separate bug: the Celsius-to-Fahrenheit template carries a `weather` tag (`entry/src/main/resources/rawfile/templates/library.json`), so that request returns a temperature converter.

### Where it breaks

The slot prompt forces "Pick exactly one kind" out of eight, none of them weather (`entry/src/main/ets/core/providers/CactusProvider.ets:66-80`). The model answers something like `{"kind":"checklist","items":["task list","weather for Kraków"]}`. Grounding passes because every item shares a word with the request (`CactusProvider.ets:445-493`), `buildChecklist` emits it (`CactusProvider.ets:361-370`), and the validator accepts it. The exact reply is inferred [J]; the mechanism is in the code [S]. That matches "garbled task list, no weather".

### The cloud path fails too

"todo list with today's weather" matches `to-?do list` and goes cloud-first. `PLAN_PROMPT` says the only things capsules cannot do are SMS, calls, contacts, email, websites and payments (`entry/src/main/ets/core/CapsuleModel.ets:151-156`), so Mistral is told to plan it anyway and can only emit static text or an input. [S for the prompt, J for the outcome]

The origin badge on the judges' capsule tells you which path they hit.

### Smallest weather feature

- **Schema:** `weather { type, place }`, with `place` a city name of at most 60 characters, and a new permission `"internet"`. `SCHEMA.md` says changes are "approved by Ash", so get that approval.
- **Types and validator:** `CapsuleTypes.ets:3, 5, 143, 145`; `CapsuleValidator.ets` `fieldsFor` (`:66-93`), the component switch (`~:270-365`), and `permissionForComponent` returning `'internet'`. The missing-permission check at `:858` then works unchanged.
- **Adapter:** new `entry/src/main/ets/adapters/WeatherAdapter.ets`, using `http.createHttp()` GET like `entry/src/main/ets/core/index.ets:65-84`. Cache for 15 minutes and map WMO codes to words.
  - `https://geocoding-api.open-meteo.com/v1/search?name=<place>&count=1`
  - `https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto`
  - Both returned Kraków data from the research machine on 2026-10-04 (12.7 °C, code 1). [S]
- **Runtime and view:** a `WeatherState` with `@Trace` fields in `entry/src/main/ets/renderer/CapsuleRuntime.ets`, fetched only when the gatekeeper allows; a `weatherItem` builder and a branch in `entry/src/main/ets/renderer/CapsuleView.ets:318-350`.
- **Consent wording:** add an `internet` case in `entry/src/main/ets/pages/ConsentView.ets:15-61`, for example "Internet: fetches the weather for Kraków from open-meteo.com. Only the place name is sent." `entry/src/main/ets/gatekeeper/Gatekeeper.ets:132-136` needs no change.
- **Prompts:** `SCHEMA_TEXT`, `SYSTEM_PROMPT` and `PLAN_PROMPT` in `CapsuleModel.ets:10-57, 80-115, 143-162`.
- **Widget:** leave weather app-only tonight; `entry/src/main/ets/core/CapsuleRouter.ets:13, 76` already reports "App only" for unknown types.
- **Tests:** `entry/src/test/CapsuleValidator.test.ets`, `RuleParser.test.ets`, `CapsuleGenerator.test.ets`.
- **Open-Meteo terms:** no key, free for non-commercial use, under 10,000 calls a day, CC BY 4.0 attribution required (https://open-meteo.com/en/terms). [S] Put "Weather data by Open-Meteo.com" under the component and in `docs/THIRD_PARTY.md`.
- **Leave "weather here" for later.** It needs Location Kit plus a runtime permission grant.

**Effort:** 2–3 h for someone who knows the validator and `CapsuleRuntime`, plus an emulator check.

**Risks:**

- HTTP from the emulator is documented as supported (`hackathon-resources/emulator-capability-comparison.md`) but was not tested for this endpoint. [U]
- `esp32-companion/main/validate.c` will reject the new type on the companion device. [J]

---

## Part B: router

Put a pure `classifyRequest(request)` next to `needsLogic` in `CapsuleGenerator.ets` and widen `cloudFirst()` (`CapsuleGenerator.ets:97`). No extra model call.

### Features, all deterministic

- **Parts:** split on `and | with | plus | , | +`, and count the distinct kinds found by a small lexicon (timer, counter, list, schedule, reminder, split, score, weather).
- **Live data:** `weather|forecast|temperature outside|rain|news|stock|exchange rate|traffic`.
- **Logic:** the existing `needsLogic`.
- **Length:** more than 12 content tokens.
- **Coverage after on-device:** content tokens of the request that the built capsule does not contain. `leftovers()` at `TemplateLibrary.ets:597-605` already does this for templates.
- **Engine confidence, optional:** Cactus returns `confidence` and `confidence_threshold` in the response JSON (https://github.com/cactus-compute/cactus/blob/main/docs/cactus_engine.md) [S]. The wrapper passes the raw JSON through with `auto_handoff:false` (`cactus/src/main/cpp/napi_init.cpp:152-154`), but `EngineResponse` ignores the field (`CactusProvider.ets:172-176`). Whether it is meaningful for LFM2-VL on this build is unknown [U]; log it, do not gate on it tonight.

### Decision table

| Condition | Route |
| --- | --- |
| Cache hit, or a single rule or template match | Local, as today |
| Compound, and every part resolves by rule, template or the weather rule | New `composeCapsules()`: merge `ui`, `state`, `permissions`, de-duplicate ids. Origin `rules`. |
| Live data other than weather | Refuse as `unsupported` (the `GenerateResult.failure` path exists) |
| `needsLogic`, or compound with an unresolved part, or more than 12 tokens | Cloud first; `needsCloud` if there is no consent (`CapsuleGenerator.ets:180-190`) |
| One kind, short | On-device slot-fill |
| On-device result invalid, or two or more uncovered tokens, or a detected kind missing | Treat as failed, then cloud (insert at `CapsuleGenerator.ets:204-208`) |

### Escalation, time budget and what the user sees

- **Escalation:** validate, one repair attempt (already there: `CactusProvider.ets:42`, `CapsuleModel.ets:78`), then escalate.
- **Time budget [J]:** 8 s on-device, 25 s cloud in total. Today it is 30 s per HTTP call with up to four calls (plan, capsule, retry, self-check; `docs/AI_INTEGRATION.md:51`), so the worst case is about two minutes. Skip the self-check once 12 s have passed.
- **What the user sees:** keep the origin badges. Extend the existing cloud notice (`entry/src/main/ets/pages/Index.ets:892-899, 920-946`) with the reason, for example "This needs Cloud AI (Mistral, EU): two parts, list and score". Cloud stays opt-in and only the request text leaves the phone.

### Fixtures

For `entry/src/test/CapsuleGenerator.test.ets`, grouped by expected route:

- **Rules:** `timer eggs 7`; `count my squats`; `pomodoro 50/10`; `split 84 between 4`; `checklist keys, wallet, charger`; `water 8 glasses`.
- **Template:** `tennis scoreboard me vs Sam`; `shopping list: milk, eggs`.
- **On-device:** `track pages I read`; `remind me to call mum`; `vitamins morning and night`.
- **Compose:** `a task list and the weather for Kraków`; `task list and weather`; `todo list with today's weather in Warsaw`; `weather in Kraków`; `pasta timer 9 min and a shopping checklist: salt, oil`.
- **Must not return the Celsius converter:** `weather`.
- **Cloud:** `tip calculator with percent`; `quiz me on capitals`; `darts 501 for two players`; `habit streak with a warning if I miss a day`; `counter for coffees and tell me if over 4`.
- **Unsupported:** `show bitcoin price`; `text my mum when the timer ends`.
- **Language gate:** `minutnik 10 minut`.
- **Not an app:** `asdf`.
- **`needsCloud`:** `to-do list and weather` with cloud off, if compose cannot resolve it.

**Effort:** 45 minutes for the classifier and coverage check, plus 1–1.5 h for `composeCapsules`.

**Risk:** state-name and id collisions when merging; prefix by part index.

---

## Part C: models for Cactus on HarmonyOS

### What Cactus 2.x is

- It is Cactus's own engine and format, not GGUF or llama.cpp: CQ weights plus a serialised graph (`components/*/graph.cactus`, `components/manifest.json`), ARM NEON kernels (https://github.com/cactus-compute/cactus). [S]
- Official platforms are iOS, Android, macOS and Linux (https://cactuscompute.com/compare/best-on-device-llm-framework). HarmonyOS is the team's own port. [S]
- The port is arm64-v8a only and compiled with `-march=armv8.2-a+fp16+simd+dotprod+i8mm` (`cactus/BUILD.md`). It ran on the Apple Silicon emulator; `BUILD.md` says a physical phone is not verified, while `docs/DEMO_SCRIPT.md:29` plans a real-phone shot. Whether a Kirin CPU has i8mm is unverified. [U]
- An x86 emulator has no native library to load, since `cactus/Index.ets` imports `libcactus_napi.so` statically. Whether the app survives that is unverified. [U]
- The engine supports tool calling (`force_tools`, already wired in the wrapper), stop sequences, a confidence value and cloud handoff. The engine doc lists no JSON-schema or grammar option, although the marketing page claims "grammar-constrained generation". [S]
- `cactus convert` produces weights only: "local runtime bundle generation is unavailable while the graph builder is being rewritten" (https://github.com/cactus-compute/cactus/blob/main/docs/cactus_engine.md and https://github.com/cactus-compute/cactus/blob/main/docs/finetuning.md). [S]

### Which models can load tonight

From a listing of every `Cactus-Compute` repository and its tags on Hugging Face (https://huggingface.co/Cactus-Compute). [S]

| Model | Bundle for 2.x? | 4-bit size | Licence |
| --- | --- | --- | --- |
| LFM2-VL-450M (current) | Yes, tag `v2.0` | 383 MB zip, about 480 MB on device | LFM Open License v1.0 |
| Gemma 4 E2B | Yes, tag `v2.0.1` | 2.72 GB (2.28 GB at 2-bit) | Apache-2.0 per the card |
| Qwen3-0.6B-cq | No: weights only, no `components/` in the zip | 371 MB | Apache-2.0 (base) |
| LFM2.5-350M, LFM2-700M, LFM2.5-1.2B-Instruct, Qwen3-0.6B/1.7B, Gemma 3 270M/1B, FunctionGemma | No: latest tag `v1.14`, old `int4` format | 209 MB (LFM2.5-350M), 376 MB (Qwen3-0.6B), 643 MB (LFM2.5-1.2B) | LFM / Apache-2.0 / Gemma terms |
| LFM2-1.2B-Tool, LFM2-1.2B | No: latest tag `v1.10` | not checked | LFM |
| SmolLM2, Phi-4-mini, Llama 3.2 1B, Hammer | Not in Cactus's supported list at all | n/a | n/a |

- "No" for the v1.x weights is a reading of the evidence [J]: `CactusProvider.load` requires `components/manifest.json` (`CactusProvider.ets:611`), and Cactus says weight-format changes break older weights (https://docs.cactuscompute.com/v1.14/docs/compatibility/). Nobody tried loading one.
- Needle (26M tool-calling model) ships as its own `needle.cact` runtime with Android/iOS binaries, not as an engine bundle. Not usable tonight. [J]

### Speed

- Repo: 92–114 tokens/s decode and about 380 MB RSS on the emulator on an M4 Pro (`docs/AI_INTEGRATION.md:89`). [S]
- Cactus v1.14 docs (https://docs.cactuscompute.com/v1.14/): LFM 1.2B INT4 decodes at 37 tokens/s on a Galaxy S25 Ultra. [S]
- Cactus fine-tuning doc: Qwen3-0.6B and LFM2-1.2B at INT8 reach 13–18 tokens/s on a Pixel 6a. [S]

### HarmonyOS constraints

- HAP limit is 4 GB for phones, from a Huawei forum post rather than a primary doc (https://forums.developer.huawei.com/forumPortal/en/topic/0205201191526461058). [S, secondary]
- The model lives in the app sandbox, pushed with `hdc file send` on debug builds (`scripts/push-model.sh`). [S]
- MindSpore Lite Kit is built into HarmonyOS and open to third-party apps (`.ms` models, ArkTS and C APIs), with NNRt and CANN Kit underneath for the NPU (https://developer.huawei.com/consumer/en/doc/harmonyos-guides/mindspore-lite-kit-introduction). [S] Running an LLM on it means converting a model and writing the tokenizer and sampling loop: not tonight. [J]
- No public on-device LLM API for third-party apps outside China was found. [U]
- The app already uses Form Kit, Core Vision Kit, Core Speech Kit, Calendar and Network Kit; a Location Kit weather capsule would add more to "platform capabilities" than a model swap. [J]

### Recommendation

Keep LFM2-VL-450M for slot-filling, fix the schema and the router, and send what the rules cannot compose to Mistral. Gemma 4 E2B is the only alternative that loads, at six times the size with untested memory and speed on the team's devices. A bigger model would not have produced weather either.

---

## Part D: widget sizes

### Today [S]

- One form, sizes `2*2` and `2*4` (`entry/src/main/resources/base/profile/form_config.json`).
- The size is read once in `onAddForm` and stored as a `wide` boolean (`entry/src/main/ets/widget/HarmoniserFormAbility.ets:15-22`, `entry/src/main/ets/widget/WidgetService.ets:117-145`).
- `openHarmoniserManager` hard-codes dimension 2 and nothing calls it (`WidgetService.ets:293-308`).
- The card has two layouts only, both keyed on `wide` (`entry/src/main/ets/widget/pages/HarmoniserCard.ets:240-362`).

### Findings

- **Size at add time: yes.** Pass `'ohos.extra.param.key.form_dimension'` in the want to `openFormManager` or `AddFormMenuItem`; codes are 2 = 2*2, 3 = 2*4, 4 = 4*4 (`docs/WIDGET_RESEARCH.md:56`). [S] Whether the manager page preselects that size on the API 24 emulator is unverified. [U]
- **Resize after adding: yes in config, API 20+.** `"resizable": true` allows drag-resize among `supportDimensions`, or across forms sharing a `groupId` (https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-ui-widget-configuration). [S] The project's `compatibleSdkVersion` is 6.0.0(20), so it compiles.
- **How the provider learns the new size:** `FormExtensionAbility.onSizeChanged(formId, newDimension: formInfo.FormDimension, newRect: formInfo.Rect)`, API 20+ (https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-references/js-apis-app-form-formextensionability.md, a mirror of Huawei's Chinese reference). [S] This closes the open item in `docs/WIDGET_RESEARCH.md:220`.
- A CSDN post claims a resize destroys and re-adds the card through `onAddForm` instead (https://harmonyosdev.csdn.net/6a81a29e10ee7a33f29bc28b.html). `bindForm` already updates `wide` for a known `formId` (`WidgetService.ets:117-124`), so both cases are covered. [U]
- The app cannot resize a placed widget itself. No provider API for it was found. [U]

### Changes, in order

1. `form_config.json`: add `"resizable": true`.
2. `HarmoniserFormAbility.ets`: add `onSizeChanged` that sets `binding.wide = newDimension === Dimension_2_4` and calls `refreshCapsuleWidgets`.
3. `entry/src/main/ets/core/WidgetModel.ets`: pure `bestWidgetSize(capsule)` with tests in `entry/src/test/WidgetModel.test.ets`:
   - counter, goal or single timer: 2*2;
   - checklist with at most 2 items: 2*2, otherwise 2*4 (the card shows 2 or 4 rows, `HarmoniserCard.ets:355`);
   - two or more parts, or a logic capsule with more than one button or display line: 2*4.
4. `WidgetService.ets:293`: take the dimension as a parameter; call it from the capsule page with the best size, and offer the other as a second option.

Skip 4*4 tonight: it needs a third card layout and replacing `wide` with a size, about 1–2 h.

**Effort:** 45–60 minutes for the four steps.

**Risk:** drag-resize and `onSizeChanged` are untested on the emulator launcher; the config flag is harmless if ignored. [J]

---

## Not verified, and decisions to treat with caution

- Nothing ran on a device or emulator. The template scores come from a Python port of the scorer in `TemplateLibrary.ets`.
- The judges' exact wording is unknown, as is whether the model was installed on their device and whether cloud consent was given. The on-device explanation fits the symptom best; the cloud path fails for the same schema reason.
- The claim that v1.x weights and the weights-only `-cq` repositories will not load in 2.2.2 is inferred from file layouts and docs, not from a load attempt.
- Gemma 4 E2B memory use and speed on the team's devices; whether Kirin CPUs support i8mm; whether the app starts on an x86 emulator.
- Whether Cactus's `confidence` value is useful for LFM2-VL on this build.
- Open-Meteo reachability from the emulator, and whether a hackathon entry counts as "non-commercial" under their terms (probably yes).
- Drag-resize, `onSizeChanged` and dimension preselection on the API 24 launcher.
- The new permission name `internet` and the `weather { type, place }` shape are proposals; `SCHEMA.md` changes need Ash's approval.
- Licences and sizes not checked: Gemma 3 terms beyond "gated", LFM2-1.2B-Tool size.
- Effort figures assume someone who already knows `CapsuleRuntime` and the validator.
