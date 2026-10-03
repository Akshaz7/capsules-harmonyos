# PR #12 review: `codex/ark-kits` (motion, battery, Open-Meteo weather)

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04, about 01:30–01:50). Written from the code, tests and documents of both repositories. Nothing was built or run. Line references are to the commits named in the text and will drift. Where it says a document contradicts the code, the code is what was read.

Reviewed head `52450b0` (6 commits on `main` 7292381, GitHub says MERGEABLE/CLEAN, no CI checks). Read-only: nothing
changed, pushed, merged or built. Paths are under `entry/src/main/ets/` on the PR branch unless stated.

Evidence labels: **[code]** read from the branch; **[run]** the PR's own pure modules (`RuleParser`, `Language`,
`TemplateLibrary` + the real `library.json`, `CapsuleValidator`, `CapsuleRouter`, `cloudFirst`) copied out of the
branch and executed offline with `bun` (no HarmonyOS build); **[inference]** my reasoning, not observed.

## Verdict

**Merge only after fixes 1 and 2 below (about 45 minutes), otherwise hold.** The single-intent weather path is
sound and well gated. But the PR does **not** make the judges' request work: nothing composes two intents, the router
is untouched, and it adds a new bug where `task list and weather` returns a weather-only capsule with the task list
silently dropped.

## 1. The judges' request, traced

Pipeline on the branch [code]: `Index.createFrom` (pages/Index.ets:1159) → if `parseRequest(text) === null`, try
`matchTemplate` (1176) → else `generateCapsule` → `generateCapsuleWith` (core/CapsuleGenerator.ets:126): language gate
(132) → request cache (156) → rules (161) → template (171, threshold 0.7) → `cloudFirst` (179) → cloud if logic (193) →
on-device (201) → cloud (214). `CapsuleGenerator.ets` is **not changed by this PR**.

| Input | Stage that answers | Result | Looks right? |
| --- | --- | --- | --- |
| `a task list and the weather for Kraków` | Passes language gate; rules null; best template `homework-tracker` 0.5 < 0.7; `cloudFirst` false → **on-device 450M model**, then cloud only if that fails [run] | One-kind slot fill, most likely a checklist with the words as items. Same failure the judges saw [inference; model not run] | **No** |
| `task list and weather` | **Rule `parseWeather`** [run] | `{device weather}` only, no city, name "Weather". Task list dropped | **No, new regression** |
| `todo list with today's weather` | Rules null; template 0.4; `cloudFirst` **true** (`to-?do list`, CapsuleGenerator.ets:84) → cloud first if consented, else `needsCloud` notice; cloud off/unconfigured → on-device [run] | Depends on Mistral; cloud-off gives the garbled one-kind capsule | Unreliable |
| `weather in Krakow` | Rule `parseWeather` | `Weather · Kraków`, city `krakow`, permission `weather`, app-only | Yes |
| `weather` | Rule `parseWeather` (rules now run before the Celsius template) | Weather card, no city: "Tap to choose a city" | Yes |
| `weather in Paris` | Rule | `Weather · Paris` (Paris is bundled) | Yes |
| `a checklist: milk, eggs and the weather in Warsaw` | Rule `parseChecklist` (runs before weather, RuleParser.ets:461) | Checklist with items `Milk`, `Eggs`, `The weather in warsaw`. No weather component | **No** |

Other phrasings [run]: `weather app` → still the Celsius-to-Fahrenheit template (score 1.0). `weather today`,
`what's the weather`, `show me the weather in Warsaw` → no rule, no template → on-device model. `to-do list` →
"Cleaning chores" template. `task list` / `todo list` → "Homework tracker" template (labels say "Homework").

**Why input 2 breaks** [code]: the city-first branch `^([a-zÀ-ɏ -]+?)\s+(?:weather|forecast)$`
(core/RuleParser.ets:133) accepts any words before "weather" as the city text; an unknown city is then ignored
(140-145) and a bare weather capsule is returned. Any request ending in "weather" is swallowed this way.

**What is missing:** no compound rule, no merge, no router guard. The research recommendations other than the weather
component itself are not in this PR.

### Smallest change that makes inputs 1 and 2 (and 3) work: about 40 lines, `core/RuleParser.ets` only

I ran this candidate against the PR's validator and router: all of `a task list and the weather for Kraków`,
`task list and weather`, `todo list with today's weather`, `weather in Warsaw and a to-do list` validate, the first
gets `city: "krakow"`, all route app-only [run].

1. Add `parseListAndWeather(req)` and put it **first** in the `rules` array (RuleParser.ets:460-463), before
   `parseChecklist` and `parseWeather`:

```ts
/** "a task list and the weather for Kraków", "todo list with today's weather", "weather in Warsaw and a to-do list". */
function parseListAndWeather(req: string): Capsule | null {
  const LIST = "(?:an?\\s+|my\\s+)?(?:task|to-?do|todo|check)\\s*list";
  const WX = "(?:the\\s+|today'?s\\s+)?(?:weather|forecast)(?:\\s+(?:in|for|at)\\s+([a-z\\u00c0-\\u024f -]+))?";
  const JOIN = "\\s+(?:and|with|plus|&)\\s+";
  let m = req.match(new RegExp(`^${LIST}${JOIN}${WX}$`));
  if (m === null) {
    m = req.match(new RegExp(`^${WX}${JOIN}${LIST}$`));
  }
  if (m === null) {
    return null;
  }
  const city: string = m[1] !== undefined ? cityIdFromText(m[1].trim()) : '';
  const reading: DeviceComponent = { type: 'device', bind: 'weather' };
  if (city.length > 0) {
    reading.city = city;
  }
  const state: Record<string, StateVar> = {};
  state['tasks'] = { type: 'list', initial: [] };
  state['newTask'] = { type: 'text', initial: '' };
  const add: ButtonComponent = { type: 'button', label: 'Add', action: '', enabledIf: 'len(newTask) > 0',
    do: [{ push: 'tasks', value: 'newTask' }, { set: 'newTask', to: "''" }] };
  const ui: CapsuleComponent[] = [reading, display('Tasks to do: {len(tasks)}'),
    { type: 'list', source: 'tasks' }, { type: 'input', bind: 'newTask', kind: 'text', label: 'New task' }, add];
  return { schemaVersion: 1, id: 'tasks-weather',
    name: city.length > 0 ? `Tasks and weather · ${cityName(city)}` : 'Tasks and weather',
    permissions: ['weather'], state: state, ui: ui };
}
```

   The list/state/button shapes are copied from the shipped `homework-tracker` template, which the validator accepts;
   the implementer must adjust the literal types to what ArkTS strict mode wants (`StateVar`, `ListComponent`,
   `StepObject` typed locals, as the neighbouring `goalCapsule` does at RuleParser.ets:363-379). Add a "Done (remove
   last)" button with `{ pop: 'tasks' }` if wanted.

2. Fix the swallow bug in `parseWeather` (RuleParser.ets:133-138): in the city-first branch return `null` unless
   `cityIdFromText(before[1])` is non-empty. Two lines. `paris weather` keeps working; `task list and weather` no
   longer becomes weather-only.

3. Add three test cases to `entry/src/test/Weather.test.ets` (the four inputs above, plus `nice weather` → null).

This is a narrow special case, not general composition. A general "split on and/with/plus, build each part, merge"
rule is larger (ids, state-name collisions, v0/v1 mixing) and I would not start it nine hours out.

## 2. Router

- **Nothing stops compound or weather requests reaching the 450M model** [code]. `cloudFirst` is still only
  `needsLogic` (CapsuleGenerator.ets:97-99); no pattern mentions weather, "and", or two intents. Only requests that
  happen to hit a logic word (e.g. `todo list`, line 84) go cloud-first.
- **No coverage check** [code]. On-device grounding only checks that each slot shares one word with the request
  (core/providers/CactusProvider.ets `checkGrounding`), never that the request's words are covered. A checklist with
  items "Task list" and "Weather for Kraków" passes.
- **Cloud off / on-device-only** [code]: rules → template → on-device → failure card. For input 1 that means the
  on-device capsule or "could not make this". With cloud configured but not yet consented, logic requests return
  `needsCloud` (180-190); non-logic ones (input 1) go straight to on-device.
- **Cloud on**: the prompt now advertises the device readings (core/CapsuleModel.ets:88, 157), so Mistral could
  compose list + weather. But the prompt says "one of the bundled city ids" without listing the ids
  (capabilities/CapabilityRegistry.ets:94-95), so the model must guess `krakow`; `"Kraków"` is rejected by the
  validator [run]. `SCHEMA_TEXT` in the prompt has no `device` entry. Not evaluated by the author.
- **Stale cache hazard** [code]: the request cache is checked before the rules (CapsuleGenerator.ets:156) and stores
  model-made capsules in Preferences (core/index.ets:245-247). If the demo phone already answered
  `task list and weather` (or any phrase a new rule now covers) through a model, the old garbled capsule is returned
  even after the fix. Clear app data before the demo, or reinstall.

## 3. Gatekeeper

Weather:
- Declares permission `weather`; validator rejects a weather component without it: `device "" needs permission
  "weather"` [run] (core/CapsuleValidator.ets:163). Unknown fields (`url`), unknown city ids, v0 use, >1 weather,
  >2 readings are rejected [run] (322-347, 880-888).
- Consent sheet row: title "Weather", reason "Send the chosen city's coordinates to Open-Meteo (open-meteo.com) to
  show its weather" (pages/ConsentView.ets:27, 50). Accurate: coordinates are sent, not the place name
  (adapters/WeatherAdapter.ets:74-77). It does not mention that the phone's IP address is visible to Open-Meteo
  [inference: true of any request].
- Before consent: the capsule is not an entry until `decide` (pages/Index.ets:1289), and `refreshWeather` returns
  unless `gate.isAllowed(capsule,'weather')` (667-675). After a deny: same guard, and the component renders the
  blocked card (renderer/CapsuleView.ets:462). The grant is re-checked when the fetch returns (700-705). No fetch path
  bypasses the gate [code].
- **Not logged**: a successful or failed fetch writes nothing to the gatekeeper log; only the allow/deny decision and
  blocked components are logged (gatekeeper/Gatekeeper.ets:73-104). Failures go to hilog only. If the pitch says
  "everything that leaves the phone is in the log", weather is an exception. Fix: one `gate.logDeviceSend(capsule.id,
  true, 'weather: sent <city> coordinates to open-meteo.com')` in `refreshWeather` before `weather.refresh` (3 lines;
  the method exists at Gatekeeper.ets:118).

Accelerometer: permission `motion`, consent text "React to shaking the phone while the capsule is open. It does not
count steps or reps" (ConsentView.ets:45). Subscription only when a granted consumer exists and the app is in front
(Index.ets:828-841); grant re-checked per event (847-862). Shakes are not logged (reasonable). Battery: permission
`battery`, read only when allowed (620-645), not logged, nothing sent.

## 4. Cities

Bundled (capabilities/WeatherData.ets:17-30): Kraków, Warsaw, Wrocław, Gdańsk, Poznań, Łódź, Katowice, Berlin,
Prague, Vienna, London, Paris.

- `Kraków`, `krakow`, `Krakow`, `KRAKÓW` → `krakow` [run]. **`Cracow` does not match** (returns ''), nor `Warszawa`,
  `Praha`, `Wien` [run]. Only Polish diacritics are folded (47-58).
- City not in the list (`weather in Lisbon`, `weather in new york`, `weather for Cracow`): the rule still returns a
  weather capsule with **no city and no message**; the name is plain "Weather" and the card says "Tap to choose a
  city", which opens the 12-city picker (Index.ets:676-684) [run + code]. The user is not told Lisbon is unsupported.
- If the capsule names a city, the picker is still offered on tap but has no effect: `weatherCityFor` prefers the
  capsule's city over the stored pick (Index.ets:655-661) [code].

## 5. Correctness and safety of the new code

Open-Meteo request (adapters/WeatherAdapter.ets) [code]:
- `https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto`
  (74-77). Parameter names are the current API's; default units are °C and km/h, which is what the card prints. I did
  not re-confirm against the live docs.
- 6 s connect and read timeouts, string body, non-200 → null, exception → null, `req.destroy()` in `finally` (79-100).
- Parsing (capabilities/WeatherData.ets:139-172): `JSON.parse` in try/catch, typed as `Record<string, Object|null>`,
  every field type- and range-checked, >8192 chars rejected. Safe under strict mode [inference from reading; it
  compiled per the author].
- Cache: in memory only, 15 min per city (48-56); lost on app restart. Stale reading shown with "· stale".
- Offline with no cache → "Unavailable / No connection"; bad body → "The weather service did not answer".
- **Cooldown bug**: `lastFetch` is set before the request (58), so a *failed* fetch blocks retries for 60 s, and the
  cooldown branch with no cache returns `empty` (51-53), which the page shows as "The weather service did not
  answer" (Index.ets:710-725). There is no refresh button; a fetch only happens on open, on return to the foreground,
  or on a city pick. On flaky venue Wi-Fi the card can sit on "Unavailable" for a minute. Fix: set `lastFetch` only
  on success (move one line), about 2 minutes.
- `usingCache` is not set on the HTTP request, so the platform default applies [not determined whether that matters].

Attribution: "Weather data by Open-Meteo.com" is shown under every reading and opens `https://open-meteo.com/`
(WeatherData.ets:32-33, Index.ets:717, CapsuleView.ets:244-250, 286). `docs/THIRD_PARTY.md` has an Open-Meteo section
with the CC BY 4.0 note. It is not shown while the card is in an error state (no data, so nothing to attribute).

Accelerometer [code]:
- One subscription, `sensor.on(ACCELEROMETER, cb, { interval: 'ui' })` (adapters/MotionAdapter.ets:62-70). `'ui'` is
  60 ms per the offline Huawei reference (`js-apis-sensor.md`, SensorFrequency), about 17 Hz.
- Unsubscribed with the same callback on `onPageHide` (Index.ets:1115), `aboutToDisappear` (1036), when no consumer
  remains (828-835), and on a subscribe failure. Foreground-only holds as far as `onPageShow/onPageHide` fire on
  background/foreground [inference; the author lists "backgrounding stops counting" as unverified].
- Missing sensor: `probe()` catches everything and reports `unsupported`/`error`; `start()` is a no-op unless
  `available` (31-47, 58-61). No startup crash path that I can see.
- Thresholds (capabilities/ShakeDetector.ets:19-27): |magnitude − 9.81| ≥ 6 m/s², 3 high samples in 300 ms, 150 ms
  debounce, burst ends after 800 ms quiet. At 60 ms sampling the count rises about every 180 ms **for as long as the
  phone keeps shaking**, so the number tracks shaking duration more than discrete shakes [inference]. Untested on
  hardware.
- Each counted shake calls `runtime.dispatch`, which persists state and refreshes widgets (Index.ets:1083-1098), up
  to about 6 times a second while shaking [code]; cost on the phone unknown.

`module.json5`: `ohos.permission.INTERNET` was already declared; `ohos.permission.ACCELEROMETER` is added (lines
15-19). Battery needs none.

Widgets: any capsule using motion or a `device` reading is routed app-only (core/CapsuleRouter.ets:64-77), so the
widget never draws them. Side effect: the proposed list + weather capsule cannot be a widget, and motion counters
that used to be widget-eligible no longer are (WidgetModel test changed accordingly).

ESP32: the app never sends capsule JSON to the board; `payloadFor` sends only the first timer or counter and returns
null otherwise (adapters/DeviceRelay.ets:113-134). A weather or battery capsule cannot be sent; the board never sees
`device`. `capsule_json.c:113-117` accepts only `timer` and `counter`. No change needed.

Follow-up commit `52450b0` [code]: confirmed. There is now exactly one `bindSheet` on the root Stack
(Index.ets:2617-2630) whose builder branches on `cityPickerId` (sheetBody); the only other `bindSheet` in the app is
on a different node (sharing/SharingBar.ets:217). The battery guard now checks `bind === 'battery'` (Index.ets:627)
and weather checks `bind === 'weather'` (650). I found no other place that treats every `device` as one bind: the
router and validator count readings generically on purpose. `DeviceReadout` is keyed by bind, which is safe only
because the validator caps weather at one.

## 6. Schema and docs

- `CLAUDE.md:7`: "SCHEMA.md is the contract. Never change it without asking me." Every earlier section is headed
  "approved by Ash". The new section is headed "Proposed ... for Ash's review", yet the validator, types, rule parser
  and prompt already implement it. Merging ships an unapproved schema change. **Needs Ash's explicit yes.**
- Versioning: called "v1.2" but `schemaVersion` stays `1`. A capsule with `device` therefore claims v1 and is
  rejected by any v1 validator that predates this PR.
- Validator and tests updated in step: yes (`DeviceComponents.test.ets`, `Weather.test.ets`). `SCHEMA_TEXT` in
  `core/CapsuleModel.ets` ("Copy of SCHEMA.md ... Keep in sync") was not updated; the device component reaches the
  model only through the capability lines.
- **Web parity**: `harmoniser-web` `origin/main` pins `452777e8…` in `vendor/upstream/PIN.json`; its
  `lib/validator/types.ts` has `V1_COMPONENT_TYPES = ['display','input','list','when','row']` and no `battery`/
  `weather` permission. Publishing a weather, battery or list-plus-weather capsule to the marketplace **will be
  rejected** until the port is re-vendored. `npm run parity` will also warn that upstream moved. Do not demo
  "publish" with a capsule from this PR. Sharing by QR/file to a phone with an older build fails the same way.
- Docs vs code:
  - `README.md` now has two contradictory rows: the new one says motion is "Real (phone check pending)", while the
    untouched Triggers row (line 245) still says "Motion triggers: not working ... no motion sensor code ... coming
    soon". Update line 245.
  - `README.md` weather row says "Real on the emulator" and the second `AI_WORKFLOW.md` entry supports that
    (author's emulator check after `52450b0`). The **PR body is stale**: it still lists the weather card as not
    verified. The motion row is correctly labelled as pending. The link tap is labelled unchecked.
  - `docs/DEMO_SCRIPT.md` says the default emulator shows "Motion sensor unavailable", while `AI_WORKFLOW.md` says the
    emulator showed "Shake the phone to count". One of them is wrong.
  - `AI_WORKFLOW.md` and `docs/THIRD_PARTY.md` are updated and match the code.

## 7. Risk of merging nine hours before the deadline

What can regress in existing behaviour [code unless marked]:
- **Create flow**: the PR already broke Create once (two `bindSheet`s) and shipped a weather path that never fetched;
  both were found by a teammate, not by the 269 tests. `pages/Index.ets` gained 356 lines with no test coverage. This
  is the main risk signal.
- **Rule parser**: the weather city-first regex swallows any request ending in "weather"/"forecast" (see section 1).
  `count my squats/steps/reps` now build manual counters instead of motion counters (intended).
- **Widgets**: motion-counter capsules that were widget-eligible become app-only; an existing home-screen widget for
  one would stop drawing [inference; depends on whether any exist on the demo phone].
- **Template library**: `walking-step-counter` is now a shake counter with different tags; "step counter" requests go
  to the manual counter rule [run].
- **Prompts**: both cloud prompts changed (capability lines, "List only permissions from this list"). No eval was
  re-run; the last eval numbers in the README predate this.
- **Validator**: additive; every existing fixture still validates per the author's test and the unchanged code paths.
- Startup: one extra async sensor probe in `aboutToAppear` (Index.ets:337), fully caught.

Test coverage: the 14 new tests cover the shake detector, consumer policy, validator rules, parsing of the Open-Meteo
body and the two rule phrasings. **Not covered**: `WeatherAdapter` (HTTP, cache, cooldown), `MotionAdapter`,
`BatteryAdapter`, everything in `Index.ets`, the consent/sheet flow, compound requests. I did not run the suite; "269
pass" is the author's report.

Conflicts: GitHub reports the branch mergeable. PR #8 also edits `README.md`; #9-#11 touch only new docs files. A
textual conflict with #8 is possible depending on merge order.

Kill switch: **there is none.** No setting or flag disables weather, battery or motion. The only mitigations are
per-capsule deny on the consent sheet, and not typing those prompts. Motion scope in Settings only narrows which
capsules listen. If something misbehaves on the phone the fallback is reverting the merge and rebuilding.

## 8. Ordered fixes before merge

1. Add `parseListAndWeather` first in the rule list, and make the city-first branch of `parseWeather` require a known
   city (section 1). About 40 lines + 3 tests, 30 minutes. Without this the PR does not answer the judges.
2. Get Ash's approval of the `SCHEMA.md` section (minutes, but blocking under the repo rule).
3. `WeatherAdapter.refresh`: set `lastFetch` only after a successful fetch. 2 minutes.
4. Log the weather fetch through `gate.logDeviceSend`. 3 lines, 5 minutes.
5. README line 245 and the DEMO_SCRIPT emulator sentence; refresh the PR body. 5 minutes.
6. On the real phone, before the demo: clear app data (stale request cache), then check a shake count, revoke-then-
   shake, background-stops-counting, and the weather card on venue Wi-Fi.
7. After the deadline or if time allows: re-vendor `harmoniser-web`; add `cracow` and other aliases; list the city
   ids in the generator prompt; router guard for compound/live-data requests.

## Demo prompts

With fix 1 merged: **`a task list and the weather for Kraków`** (rule, no model, no cloud; consent sheet shows
Weather with the Open-Meteo sentence; card shows the list and the Kraków reading). Fallback: `task list and weather`,
then tap the weather card and pick Kraków.

Without fix 1 (PR as is): there is no single prompt that gives both. Use two capsules: `weather in Kraków`, then
`checklist: milk, eggs, bread`. Do not type `task list and weather` (weather only) or the judges' full sentence
(on-device model).

## What I could not determine without running it

- What the 450M model and Mistral actually return for the compound inputs on this branch.
- Whether the app builds and the 269 tests pass at `52450b0` (author's report only).
- Real-phone behaviour: shake counts per physical shake, sensor stop on background/lock, jank from persisting on
  every shake, battery cost.
- Weather card rendering and the attribution link tap on the phone; behaviour on the venue network; whether the
  platform HTTP cache affects repeated fetches.
- Whether the demo phone's request cache holds stale model answers for the judge phrases.
- Whether the `sys.symbol.*` glyphs used for weather and battery exist on the phone's OS version (they compiled
  against the SDK per the author).
- That the Open-Meteo parameter names and default units are unchanged today (not re-fetched).
