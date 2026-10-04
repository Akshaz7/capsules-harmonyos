# PR #14 review: `fix/list-weather` (compound task list + weather rule)

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04). Written from the code and tests of the PR branch and from the pull request's description. Nothing was built or run on a device or emulator; the branch's pure modules were executed offline, as labelled below. Line references are to the commit named in the text and will drift.

> **Update, 2026-10-04 (after this review was written):** section 4 suggested rebasing PR #13 after PR #14. Instead, PR #14's branch was merged into PR #13's branch and the `README.md` conflict was resolved there, so PR #13 merges cleanly after PR #14 and no rebase is needed.

Reviewed head `08a365d` (5 commits on `main` bfa70f5; GitHub: MERGEABLE/CLEAN). Read-only: nothing changed, pushed,
merged or built. Paths are under `entry/src/main/ets/` on the PR branch unless stated.

Evidence labels: **[code]** read from the branch; **[run]** the branch's own pure modules (`RuleParser`,
`CapsuleValidator`, `CapsuleRouter`, `TemplateLibrary` + real `library.json`, `Language`, `cloudFirst`) executed
offline with `bun`; **[inference]** reasoning, not observed.

## Verdict

**Merge as is.** The rule does what was asked, validates, and does not hijack ordinary requests. Merge #14 before
#13 (see section 4). One caveat on the claims: the PR body says "No device run in this pass", so the emulator
end-to-end check relayed to me is not recorded in the PR; I could not confirm it.

**Demo prompt (type exactly, no "make"/"create" in front):** `a task list and the weather for Kraków`
**Fallback:** `task list and weather`, then tap the weather card and pick Kraków.
Clear app data or reinstall first: the request cache is read before the rules and may hold an old model answer.

## 1. Inputs re-traced [run]

Rule order: `parseListAndWeather` is first (core/RuleParser.ets:511); definition at 165-201.

| Input | Rule | Capsule |
| --- | --- | --- |
| `a task list and the weather for Kraków` | listAndWeather | "Tasks and weather · Kraków": weather(krakow) + count + list + input + Add |
| `task list and weather` | listAndWeather | "Tasks and weather": weather (no city, tap to choose) + list parts |
| `todo list with today's weather` | listAndWeather | same, no city |
| `weather in Krakow` | parseWeather | "Weather · Kraków" |
| `weather` | parseWeather | "Weather", no city |
| `weather in Paris` | parseWeather | "Weather · Paris" |
| `a checklist: milk, eggs and the weather in Warsaw` | parseChecklist | **Still wrong**: checklist with item "The weather in warsaw", no weather |
| `weather and a task list` | listAndWeather | correct, no city |
| `to-do list and weather in Warsaw` | listAndWeather | correct, Warsaw |
| `shopping list with weather` | none | no template (0.667); `cloudFirst` true → cloud, or on-device if cloud off |
| `tasks and weather for Cracow` | none | → on-device model ("tasks" without "list" is not matched) |
| `a task list, a timer for 10 minutes and the weather` | none | → on-device model |
| `weather in Kraków and a checklist: milk, eggs` | none | → on-device model |

Phrasings to avoid in the recording [run]:
- `make a task list and the weather for Kraków`, `create a task list with the weather` → **no rule**; falls to the
  on-device model. The regex is anchored at `^` and allows only `a/an/my` before the list word (166).
- `a to do list and the weather` ("to do" with a space) → no rule; only `to-do` and `todo` match (166).
- `a task list and weather for Kraków please`, `... for Kraków today`, `... in Kraków and Warsaw` → rule fires but
  the **city is silently dropped** (trailing words become part of the city text, which is then unknown).
- `a task list and the weather in Cracow` → rule fires, no city (Cracow is still not an alias).
- `a task list and the weather for Kraków and a timer` → rule fires and **silently drops the timer** (it is absorbed
  into the city text). The only swallow case I found; low risk.

False positives: none found. `weather station checklist`, `list of weather words`, `weather checklist`,
`nice weather` → no rule. `packing list: umbrella, weather app` → normal checklist. `count weather`,
`bad weather days counter` → normal counters. `paris weather` still works; the city-first branch now requires a
bundled city (core/RuleParser.ets:140-144).

## 2. The produced capsule

- Validates; `permissions: ['weather']`; routes app-only [run]. The consent sheet builds its rows from
  `capsule.permissions`, so the Weather row with the Open-Meteo sentence appears [code, same path as #12; not seen].
- No id collisions: the capsule has no component ids at all (device, display, list, input, button are id-less);
  state names are `tasks` and `newTask` (187-188). Capsule id is the fixed `tasks-weather`; a second one is renamed by
  `uniqueCapsule` in `pages/Index.ets` [code].
- The list starts **empty**. On screen: weather card, "Tasks to do: 0", a card reading "Nothing yet"
  (renderer/CapsuleView.ets:445-450), a "New task" text input, and an "Add" button disabled until text is typed.
  Sensible, but the user must type tasks during the demo.
- **Tasks cannot be ticked off or removed**: there is only Add (189-193). It is a list you append to, not a
  checklist. If the judges expect to complete a task this will show. A "Done (remove last)" button with
  `{ pop: 'tasks' }` (as in the `homework-tracker` template) is about 4 lines; optional.
- An unknown or missing city never fetches until the user picks one [code, unchanged from #12].

## 3. Renderer change

renderer/CapsuleView.ets:214-234 [code]: in `deviceItem` the value `Text` moved out of the title `Row` to its own
full-width line below it; the title gained `maxLines(1)` with ellipsis. Nothing else.

- Affects every `device` card, so the **battery card also changes** (value under the label instead of right-aligned).
- No effect on other component types. No effect on the home-screen widget: the widget card is a separate file
  (widget/pages/HarmoniserCard.ets) and device capsules are app-only.
- No tests cover it (there are no renderer tests in the suite). Low risk; needs one look at a battery capsule.

## 4. Scope and conflicts

Outside the stated task but reasonable:
- renderer/CapsuleView.ets (flagged by the author).
- entry/src/test/WidgetModel.test.ets:114-121: an assertion changed from `contain 'motion'` to `equal 'Tap to open'`
  to match a widget-card redesign already on main; the motion reason is now asserted on `routeCapsule` instead. This
  fixes a test that the author says was failing on main; I did not run the suite.
- adapters/WeatherAdapter.ets:70: `lastFetch` now set only after a successful parse, as recommended. Side effect: on
  repeated failures every open/foreground retries with no backoff (bounded by the 6 s timeout); fine.

Not done: the weather fetch is still not written to the gatekeeper log (author skipped it, stated).

**PR #13 overlap** [run: in-memory `git merge-tree`]: both touch `README.md` and `docs/DEMO_SCRIPT.md`.
`docs/DEMO_SCRIPT.md` auto-merges; **`README.md` conflicts** (#14 edits the status paragraph at line 11 and two table
rows; #13 rewrites the same paragraph and rows). Merge **#14 first** (code, and what the demo needs), then rebase
#13 and resolve README in #13's favour, keeping #14's three facts: motion counter/triggers, battery and weather are
real.

## 5. Not determined

- The 280-test run, the build, and any emulator/phone rendering of the combined capsule (author's reports; the PR
  body itself says no device run).
- What the on-device model or Mistral returns for the phrasings that miss the rule.
- Whether the demo phone's request cache holds stale answers for these phrases.
