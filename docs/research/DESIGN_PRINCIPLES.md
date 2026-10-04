# Harmoniser design principles: rules for generated capsules

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04, about 01:00–01:30). Read from the rules, this repository at `origin/main` and public sources. Nothing was run on a device or emulator and no code was changed. Line references are to the commit named in the text and will drift as work lands.

> **Status since writing (re-checked on 2026-10-04):** the redesign is **in progress**: tokens, shell, Create tab, capsule frame, consent sheet and Capsules tab are in the code behind per-area switches in `theme/Flags.ets`. The 13 audit changes in section D were not checked one by one; treat each as **planned** unless the code shows it.

**Date:** 2026-10-04. **How this was produced:** AI-assisted research (web search and page fetches, plus a read of `capsules-harmonyos` at `origin/main` `7292381`). No code was changed, nothing was run on a device. Line numbers refer to that commit.

**Source labels used on every rule**

| Label | Meaning |
| --- | --- |
| [P] | Platform guideline (Huawei, Apple, Google). Authoritative for that platform, not experimental evidence. |
| [R] | Research or standard (WCAG, peer-reviewed study, NN/g, regulator). |
| [Pr] | Practitioner source. Useful, not evidence. |
| [C] | Convention. Widely used number with no study behind it. |
| [J] | My judgement, derived from the above for this product. Challenge freely. |

**Units.** `vp` and `fp` on the phone and widget. The wrist board is 368x448 px at about 322 ppi (1.8 inch diagonal), which is roughly 184x224 vp-equivalent at 2 px per vp [J, computed]; wrist numbers below are in those vp-equivalents.

**The one-paragraph version.** Every capsule gets exactly one hero (a number, a time, or a tick list). Everything else is a quiet label or one action. The same hero, the same icon and the same accent colour appear on the card, the focus page, the widget and the wrist, so the capsule is recognisable anywhere. Small surfaces carry one or two facts; the focus page carries the rest.

---

## A. Principles and capsule rules

### Hierarchy and glanceability

**A1. One primary value per surface.**
- Evidence: Huawei service widget guide [P]: a small widget should show "1 to 2 information points", and widgets should present content, not a set of entry buttons (https://developer.huawei.com/consumer/cn/doc/design-guides/system-features-service-widget-0000002087671904). Apple HIG Widgets [P]: "Display only the information that's directly related to the widget's main purpose" (https://developer.apple.com/design/human-interface-guidelines/widgets). NN/g [R]: a card is a summary that links to detail (https://www.nngroup.com/articles/cards-component/).
- Rule: the renderer picks one hero per capsule (table below) and renders it at the largest type size on every surface. No second element may use the hero size.

| Capsule type | Hero | Supporting line | Primary action |
| --- | --- | --- | --- |
| Timer | remaining time `mm:ss` | timer label, or "Done" | start / pause |
| Counter | count | counter label | + |
| Goal (display of `x / y`) | `x`, with ring to `y` | "/ y" and label | + |
| Checklist | first unticked items | "3 of 5" | tick |
| Display(s) | first display value | its label | first button |
| Form | computed display (the result) | the result's label | none on card |
| List | newest items | item count | add (focus page only) |
| Weather (planned) | temperature | condition, place | none |

**A2. Glance budget: a widget or wrist screen must be readable in one glance of about 2 seconds.**
- Evidence: NHTSA visual-manual guidelines [R]: single glances away from the road of 2 seconds or less, 12 seconds in total per task (https://www.federalregister.gov/documents/2013/04/26/2013-09883/visual-manual-nhtsa-driver-distraction-guidelines-for-in-vehicle-electronic-devices). This is a driving limit, used here as a conservative ceiling, not a widget study. Wear OS tiles guidance [P]: "limited screen time (around 7 seconds)" (https://developer.android.com/design/ui/wear/guides/surfaces/tiles/bestpractices); Wear OS principles [P]: complete tasks "within seconds" (https://developer.android.com/training/wearables/principles).
- Maths [J]: silent reading is roughly 3 to 4 words per second (commonly cited 200 to 250 words per minute; not re-verified in this session). Allow about half a second to find the widget, leaving about 1.5 s, so about 5 words, or one number plus a 2-word label.
- Rule:

| Surface | Max text | Max interactive elements |
| --- | --- | --- |
| 2x2 widget | hero (up to 5 glyphs) + 1 label line (up to 16 characters) + optional 1-word status | 1 |
| 2x4 widget | hero + label + 1 secondary fact, or up to 4 short rows | 2 (3 if the capsule is "value + action") |
| Wrist | hero + label; nothing else unless the state is an error | 1 |
| Home card | title (2 lines) + hero + 1 caption line | whole card is one target |
| Focus page | everything | no limit, but see A21 |

**A3. Progressive disclosure: card and widget summarise, the focus page holds the detail.**
- Evidence: NN/g cards [R] (summary plus linked entry point, URL above). Apple HIG Widgets [P]: essential information at a glance, "additional details by taking a longer look". NN/g progressive disclosure [R] (https://www.nngroup.com/articles/progressive-disclosure/, page not re-fetched in this session).
- Rule: inputs, lists longer than 3 items, the change log, triggers, sharing and device pairing never appear on a card or widget. A widget tap outside a control opens the focus page.

### Type, space, touch

**A4. Use few type sizes, with large steps between them.**
- Evidence: Huawei widget guide [P]: 2x2 title 14 or 18 fp; numbers 20 / 32 / 40 fp; subtitles and auxiliary text 12 fp (14 allowed); button text 14 fp Medium. Apple HIG [P]: "Avoid very small font sizes", 11 pt or larger in widgets; watchOS minimum 12 pt, default 16 pt (https://developer.apple.com/design/human-interface-guidelines/typography). Refactoring UI [Pr]: pick a small hand-made scale and size by hierarchy, not by element type (https://www.refactoringui.com/).
- Rule: five roles only, see section C. Nothing under 12 fp anywhere. The hero is at least 2x the label size.

**A5. Line length and line count.**
- Evidence: 50 to 75 characters per line is the usual body-text recommendation [C/Pr] (Baymard publishes it; not re-fetched). It does not apply to widgets, where the limit is the glance budget.
- Rule [J]: `text` components on the focus page: 16 fp, line height 22 fp, maximum 6 lines then "more". Labels: 1 line on widget and wrist, 2 on card and focus page.

**A6. Spacing on a 4 vp grid; space between groups is larger than space inside a group.**
- Evidence: Gestalt proximity and common region, as summarised by NN/g [R] (cards article above). Huawei widget guide [P]: content at least 12 vp from the widget edge. Apple HIG [P]: 16 pt standard widget margins, 11 pt when tighter. The 4 / 8 grid itself is a convention [C] (Material uses 8 dp increments, https://m3.material.io/foundations/layout/understanding-layout/spacing).
- Rule: steps 4, 8, 12, 16, 24, 32. Inside a group 8; between groups 16; page side margin 16; widget padding 12 (2x2) or 16 (2x4 and up); wrist 12 with 16 at the rounded corners.

**A7. Touch targets: 48 vp, never under 40 vp, 8 vp apart.**
- Evidence: Huawei widget guide [P]: visual size at least 24 vp, hot zone at least 40 vp. DIGEST (checked against Huawei UX standard) [P]: 48 vp recommended, 40 vp minimum. Android widget quality [P]: 48x48 dp (https://developer.android.com/docs/quality-guidelines/widget-quality). WCAG 2.2 SC 2.5.8 [R]: 24 CSS px floor, or spacing so 24 px circles do not overlap (https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html). Parhi, Karlson and Bederson 2006 [R]: 9.2 mm for single taps and 9.6 mm for serial taps with one thumb (https://www.cs.umd.edu/hcil/trs/2006-11/2006-11.htm). At about 0.16 mm per vp that is 58 to 60 vp, so 48 vp is a platform compromise, not the measured optimum.
- Rule: every control has a 48 vp hit area (`responseRegion` when the visual is smaller). A 2x2 widget has room for one 48 vp control; a second control moves to 2x4. Wrist: one control, at least 56 vp-equivalent [J, from Parhi].

**A8. Density: comfortable on the phone, compact only in lists.**
- Evidence: Apple HIG Widgets [P]: "Sparse layouts can make the widget seem unnecessary, while overly dense layouts are less glanceable." IBM Carbon and Polaris both ship two or three density modes [Pr] (https://carbondesignsystem.com/, https://polaris.shopify.com/).
- Rule [J]: row height 56 vp comfortable (focus page), 48 vp compact (checklists, lists, widget rows). No third mode.

### Colour

**A9. Colour roles, not colour values; system tokens first.**
- Evidence: Huawei widget guide [P]: text maps to the system palette; background white in light and the system dark background in dark; do not use saturated colour for the whole widget background or a whole paragraph. Material 3 colour roles [P] (https://m3.material.io/styles/color/roles). DIGEST [P]: system tokens adapt to dark mode automatically.
- Rule: surfaces and text use `sys.color.*` only. A capsule owns exactly one accent colour (A10).

**A10. Accent restraint: one accent per capsule, used for the hero's progress, the primary action and the icon. Never for body text.**
- Evidence: Huawei widget guide [P] (saturated colours "please do not overuse"). WCAG 1.4.3 [R]: 4.5:1 for text, 3:1 for large text; 1.4.11 [R]: 3:1 for the parts of a control or graphic needed to understand it (https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html, https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html).
- Measured on the current palette (`WidgetModel.ets:418`), contrast against white [computed]: `#0A59F7` 5.55, `#8A5CF5` 4.26, `#E84D6E` 3.67, `#2DA44E` 3.22, `#ED6F21` 3.04, `#00A3B4` 3.04. Only the blue passes 4.5:1 as text. Against a dark card of about `#202224`, the blue drops to 2.88 and fails 3:1 even as a ring.
- Rule: accent is for fills, rings and glyphs (3:1 is enough). Text on the accent is white and at least 14 fp Medium. Accent-coloured text is not allowed; use `font_primary`. Give each palette entry a light and a dark value so each clears 3:1 on its own background.

**A11. Semantic colour is separate from accent, and never the only signal.**
- Evidence: WCAG 1.4.1 Use of Color [R] (https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html).
- Rule: done = `sys.color.confirm` + check glyph; warning or blocked = `sys.color.warning` + lock or alert glyph; error text is `font_primary` with a warning glyph beside it, not orange text.

**A12. Dark mode and AMOLED.**
- Evidence: Huawei widget guide [P]: widgets must adapt to dark mode; on the standby screen avoid large bright areas; lock-screen widgets are monochrome with `#FFFFFF` main content. Apple HIG StandBy [P]: no widget background, scaled-up text. Material dark theme [P] recommends a dark grey surface rather than black for elevation and less smearing (https://m2.material.io/design/color/dark-theme.html; the `#121212` value is quoted from memory).
- Rule: phone and widget use system surfaces (no hard-coded black). Wrist uses true black `#000000` background, no card surfaces, hero in white, accent only on the ring and the one control, nothing lit that is not information [J].

### Icons, numbers, text

**A13. A glyph replaces a label only for universal actions; otherwise glyph plus label.**
- Evidence: NN/g icon usability [R]: icons need labels except for a handful that are universally understood (https://www.nngroup.com/articles/icon-usability/, not re-fetched). Apple HIG Widgets [P]: prefer system symbols. Huawei widget guide [P]: circular and capsule buttons; show icons without a nested geometric backing plate where clipping could occur.
- Rule: glyph-only is allowed for play, pause, stop, plus, tick, and only on widget and wrist. Generated button labels are always shown as text on the focus page. One capsule icon, chosen from the hero type (timer, plus, checklist, flag, list, cloud), 20 vp on widgets, 24 vp on cards.

**A14. Numbers: tabular figures, fixed formats, units small.**
- Evidence: convention and practitioner guidance [C/Pr]; changing digits jitter without tabular figures. `fontFeature` exists in ArkUI (offline mirror) and the renderer already uses `"tnum" on` at `CapsuleView.ets:120`.
- Rule [J]: timers `m:ss` under an hour, `h:mm:ss` above, `Done` at zero. Counts: grouped thousands up to 9,999, then `12.3k`, `1.2M`. Decimals: at most 1 place on widget and wrist, 2 on the focus page. Units at label size after the number. Every changing number uses tabular figures.

**A15. Generated text has unknown length: cap lines, ellipsise, shrink only within a floor.**
- Evidence: Android widget quality [P]: "content is cropped" marks a low-quality widget. Apple HIG [P]: 11 pt floor. Huawei [P]: 12 fp auxiliary text on 2x2.
- Rule:

| Text | Max lines | Overflow | Shrink floor |
| --- | --- | --- | --- |
| Hero number | 1 | abbreviate (A14), then shrink | 28 fp on 2x2, 32 fp on 2x4 and wrist; never below |
| Title | 1 on widget and wrist, 2 on card | ellipsis | no shrink |
| Label / caption | 1 | ellipsis | no shrink, 12 fp |
| Button label | 1 | ellipsis; over 14 characters on a widget, use the glyph | no shrink |
| Checklist item | 1 on widget, 2 on focus page | ellipsis | no shrink |

### State, feedback, motion

**A16. Every component has a designed state for empty, running, done and blocked.**
- Evidence: Android widget quality WT-1 [P]: "Zero and empty states are intentional". Apple HIG Widgets [P]: realistic previews and placeholders, do not hide stale data behind placeholders. Huawei widget guide [P]: placeholder blocks at 10% (light) and 40% (dark) opacity, 4 vp radius.

| State | Timer | Counter | Checklist | Display / form | List | Weather (planned) |
| --- | --- | --- | --- | --- | --- | --- |
| Empty / idle | full time, play button | `0`, + button | all unticked | `0` or em dash, never blank | "Nothing yet" + how to add | em dash |
| Loading | n/a | n/a | n/a | placeholder block | placeholder rows | placeholder block |
| Running | countdown, ring emptying, pause | n/a | "2 of 5" | live value | n/a | "Updated 10:42" |
| Paused | time at 60% opacity, "Paused", play | n/a | n/a | n/a | n/a | n/a |
| Done | "Done" + check, `confirm` colour | goal reached: check | "All done" + check | n/a | n/a | n/a |
| Error | "Could not start" + retry | n/a | n/a | "Check the numbers" under the input | n/a | "No data" + last value |
| Offline | n/a (local) | n/a | n/a | n/a | n/a | last value + "Offline" |
| Permission denied | lock glyph, "Reminders off", Allow | lock, "Motion off", Allow (manual + still works) | n/a | n/a | n/a | lock, "Location off", Allow |

**A17. Feedback within 100 ms; motion short; none on a timer tick.**
- Evidence: Material 3 easing and duration [P]: 200 ms exits, 250 to 400 ms enters, 300 to 500 ms on-screen moves (https://m3.material.io/styles/motion/easing-and-duration). Material 1 [P]: mobile transitions about 300 ms, over 400 ms "may feel too slow" (https://m1.material.io/motion/duration-easing.html). Huawei widget guide [P]: small elements change simply or with the symbol's default effect; large areas cross-fade. ArkTS widget animation doc (offline mirror, `arkts-ui-widget-page-animation.md`) [P]: widget animations are capped at 2000 ms, 1000 ms before API version 26.0.0. Apple HIG [P]: widget animations up to 2 seconds. The 100 ms figure is Nielsen's response-time limit [R] (https://www.nngroup.com/articles/response-times-3-important-limits/, not re-fetched).
- Rule: press state on every control (opacity 0.6 or `clickEffect`), 100 ms. Value change: 150 ms fade. Card to focus page: 300 ms, `Curve.FastOutSlowIn`. Widget: no custom animation other than the glyph swap; countdowns use `TextTimer`, not per-second redraws. No looping animation anywhere. If the system reduce-motion setting is on, use fades only (the API name for reading that setting was not found in the mirror).

**A18. Error prevention before error messages.**
- Evidence: Nielsen heuristics 5 and 9 [R] (https://www.nngroup.com/articles/ten-usability-heuristics/). HAX guidelines G8 and G9 [R]: support efficient dismissal and efficient correction (Amershi et al., CHI 2019, https://dl.acm.org/doi/10.1145/3290605.3300233).
- Rule: disabled buttons say why (caption under the button from `enabledIf`, e.g. "Enter a weight first"). Destructive steps (`reset`, `pop`, `resetTimer`, `stopTimer`) get a tonal button and a 5-second Undo snackbar instead of a confirm dialog. Numeric inputs use the numeric keyboard and reject non-numbers inline. A capsule that fails validation shows "Try again" and "Edit request", never raw schema errors.

### Consistency and accessibility

**A19. Same capsule, same identity on every surface.**
- Evidence: Apple HIG Widgets [P]: each size "remains centered" on the same purpose while the range of information grows. Huawei [P]: larger sizes show richer content, not a stretched small layout. Jakob's law / consistency heuristic [R/Pr].
- Rule: icon, accent colour, title and hero are computed once per capsule and reused by card, focus header, widget and mirror. The home card must use the same `colorTag` accent as the widget.

**A20. Accessibility is generated with the UI.**
- Evidence: Huawei widget guide [P]: widget text scales to at most 1.3x; text over 20 fp does not scale. Apple HIG [P]: keep hierarchy at large sizes. ArkUI accessibility doc (offline mirror) [P]: set `accessibilityText` to the core content and do not include the state or the word "button"; group with `accessibilityGroup`. WCAG 1.4.4, 1.4.10, 1.4.12 [R].
- Rule: all text in `fp`; `maxFontScale(1.3)` on widget text; hero exempt above 20 fp. Each component is one accessibility group with generated text: timer "Pasta timer, 4 minutes 10 seconds left"; counter "Push-ups, 12"; checklist item "Buy milk" (the checked state is announced by the system). Status is always glyph plus word plus colour.

### Consent, trust, onboarding

**A21. Consent: plain purpose, default deny, ask where it is needed, easy to change.**
- Evidence: NN/g [R]: in Tan et al. (CHI 2014) users were 12% more likely to grant a request that came with a reason, and the best-worded reason beat the worst by 81%; in-context requests cause less surprise; avoid dark patterns and let people reverse the decision (https://www.nngroup.com/articles/permission-requests/). Android [P]: ask in context, do not block, degrade gracefully, do not nag after a denial (https://developer.android.com/training/permissions/requesting). Apple HIG Privacy [P]: purpose strings state how the resource is used (https://developer.apple.com/design/human-interface-guidelines/privacy).
- Rule: each row = glyph, permission name, one sentence in the form "So it can [benefit]. [Where the data goes]." Example: "So it can alert you when the timer ends. Stays on this phone." All toggles start off. The primary button states the outcome: "Run with 2 of 3 allowed". Denied features show the A16 blocked state with an inline "Allow" that reopens the sheet (just-in-time). The focus page has a "Permissions" row to revoke. Never re-prompt automatically.

**A22. Say what the AI did, where it ran, and what is simulated.**
- Evidence: HAX guidelines [R] G1 "Make clear what the system can do" (verified), G2 and G11 on how well and why (quoted from memory of the paper). People + AI Guidebook, explainability and trust chapter [P/Pr] (https://pair.withgoogle.com/guidebook/).
- Rule: one origin badge per capsule, glyph plus word, in a fixed place (focus header and card footer): "Template", "On device", "Cloud". Cloud means the request text left the phone; say so once on the consent sheet. Anything simulated (mock relay, emulator sensor) carries a "Simulated" badge in `warning` colour next to the value it affects. No badge on widgets or wrist (A2).

**A23. Onboarding by example prompts, not by tutorial.**
- Evidence: HAX G1 [R]. NN/g on prompt suggestions and empty states [R] (https://www.nngroup.com/articles/empty-state-interface-design/, not re-fetched).
- Rule [J]: empty home shows 3 or 4 tappable prompts that each exercise a different template ("5-minute tea timer", "Count my push-ups", "Packing list for a weekend", "Split a bill"). A tap fills the input, it does not submit.

### Multi-component capsules

**A24. Lay out 2 to 6 mixed components as hero, then facts, then actions. Do not stack a box per component.**
- Evidence: common region and proximity [R] (NN/g cards). Refactoring UI [Pr]: use spacing before borders; fewer borders. Hick's law [R/Pr]: more choices, slower decision (https://lawsofux.com/hicks-law/). Huawei widget guide [P]: avoid many nested rounded rectangles inside a widget.
- Rule [J]:
  1. Order on the focus page: hero block, secondary facts, inputs, actions, long content (list, text). The renderer reorders for display only when the capsule has no `when` that depends on order.
  2. One surface card per group, not per component. Consecutive components of the same kind share a card, separated by 0.5 vp dividers inset 16 vp.
  3. `text` and `button` sit directly on the page background, never in a card.
  4. `row`: 2 or 3 items only, equal width, same kind. A row of displays becomes stat tiles; a row of buttons becomes a split action bar. A row with 4 or more items, or mixed input and display, falls back to a column.
  5. At most one filled button per screen (the first non-destructive one). Others tonal. More than 3 buttons: the rest go under "More".
  6. No scrolling for capsules of 6 components or fewer on a 6.x-inch phone; budget about 560 vp of content height. Beyond that the page scrolls and the hero block stays pinned.

---

## B. Layout templates

Notation: `[ ]` control, `( )` ring, `##` hero, `..` secondary text, `|` card edge. Widget and wrist frames are to rough scale only.

### B0. Selection logic

Flatten `when` (count only currently shown children) and `row`. Ignore `text`. Evaluate top to bottom; first match wins.

| # | Condition | Template | Existing widget `layout` value |
| --- | --- | --- | --- |
| 0 | capsule missing, all components blocked, or validation failed | M0 Message | `message` |
| 1 | timers = 1, counters = 0, inputs = 0, lists = 0 | T1 Timer hero | `timer` |
| 2 | counters = 1 and timers = 0 and inputs = 0, or one display of the form `a / b` with an increment button | T2 Counter hero (ring variant when a goal exists) | `counter`, `goal` |
| 3 | checklists = 1 and it has the most items of any component | T3 Checklist | `checklist` |
| 4 | inputs + numbers >= 1 and displays >= 1 | T6 Form | `logic` (result only) |
| 5 | lists >= 1 and no weather | T7 List | `rows` |
| 6 | displays = 1 and buttons 1 to 3 | T4 Value + action | `logic` |
| 7 | displays + counters + timers between 2 and 4, inputs = 0 | T5 Dashboard | `rows` / `logic` |
| 8 | anything else (including list + weather) | T8 Mixed stack | `rows` |

### T1. Timer hero
```
CARD (home, 2 col)        2x2 WIDGET            2x4 WIDGET                        WRIST (184x224)
|(i) Pasta        |      |(i) Pasta      |     |(i) Pasta timer               |  |    Pasta     |
|                 |      |               |     |  ( ring )  ##04:10##         |  |   ( ring )   |
| ##04:10##       |      | ##04:10##     |     |            ..of 8 min..  [>] |  |  ##04:10##   |
| ..of 8 min..    |      | =====---  [>] |     |                              |  |              |
| [On device]     |      |               |                                       |     [||]     |

FOCUS PAGE
< Pasta timer                       [log]
          (   ring 200 vp   )
              ##04:10##            hero 56 fp
              ..of 8 min..
      [  Pause  ]   [  Stop  ]     48 vp, first filled, second tonal
```
Overflow: label 1 line, ellipsis. Over an hour, `h:mm:ss` at the next size down. A second and third timer in the capsule become compact rows under the hero on the focus page only; the widget shows the timer that ends soonest.

### T2. Counter hero (and goal ring)
```
CARD                      2x2 WIDGET            2x4 WIDGET                        WRIST
|(i) Push-ups     |      |(i) Push-ups   |     |(i) Push-ups                  |  |   Push-ups   |
|                 |      |               |     | ##12##         ( 12/20 )     |  |              |
| ##12##          |      | ##12##        |     | ..today..              [ + ] |  |    ##12##    |
| ..today..       |      | ..today.. [+] |                                       |   ../ 20..   |
| [Template]      |                                                              |     [ + ]    |

FOCUS PAGE
< Push-ups                          [log]
               ##12##               hero 64 fp
              ..today..
        [        +1        ]        filled, 56 vp
        [ Reset ]                   tonal, with Undo
```
Overflow: 5 digits at full size; then `12.3k`; shrink floor 28 fp. With a goal, the 2x2 swaps the number for a ring with the number inside (current `goalLayout`), but only if the number fits at 24 fp or more; otherwise number without ring.

### T3. Checklist
```
CARD                      2x2 WIDGET            2x4 WIDGET                        WRIST
|(i) Packing      |      |(i) Packing 2/5|     |(i) Packing            2 of 5 |  | Packing  2/5 |
| ##2 of 5##      |      | o Passport    |     | o Passport     o Charger     |  | o Passport   |
| o Passport      |      | o Charger     |     | o Socks        o Toothbrush  |  | o Charger    |
| o Charger       |      | ..+1 more..   |     | ..+1 more..                  |  | o Socks      |
| [Cloud]         |

FOCUS PAGE: one surface card, 48 vp rows, ticked items struck through and moved to the end, "2 of 5" in the header.
```
Overflow: widget shows unticked items first; 2 rows on 2x2, 4 on 2x4, 3 on wrist; "+N more" at 12 fp. Item text 1 line with ellipsis. All done: "All done" with a check, no list.

### T4. Value + action
```
CARD                      2x2 WIDGET            2x4 WIDGET                        WRIST
|(i) Tennis       |      |(i) Tennis     |     |(i) Tennis        [ Point A ] |  |    Tennis    |
| ##15 - 30##     |      |  ##15 - 30##  |     |   ##15 - 30##    [ Point B ] |  |  ##15 - 30## |
| ..Set 1..       |      | [ A ]  [ B ]  |     |   ..Set 1..      [ Undo ]    |  |  [ A ] [ B ] |

FOCUS PAGE: hero display centred 48 fp, label under it, then buttons as a split bar (2) or a column (3).
```
Overflow: display text over 9 characters drops to 32 fp, over 14 to 22 fp with ellipsis. 2x2 shows 2 buttons only if both labels are 6 characters or fewer; otherwise 1 button. This is the one template allowed 3 controls on 2x4.

### T5. Dashboard (2 to 4 values)
```
CARD                      2x2 WIDGET            2x4 WIDGET                        WRIST
|(i) Workout      |      |(i) Workout    |     |(i) Workout                   |  |   Workout    |
| ##12##  ..reps..|      | ##12## ..reps.|     | ##12##    ##3##     ##04:10##|  |  ##12## reps |
| 3 sets · 04:10  |      | 3 sets        |     | ..reps..  ..sets..  ..rest.. |  |  3 sets      |
                         | 04:10 rest    |                                       |  04:10 rest  |

FOCUS PAGE: stat tiles in a 2-column grid (value 28 fp over label 12 fp), then actions.
```
Overflow: the first value is the hero; the rest are secondary rows. 2x2 shows hero + 2 rows; 2x4 shows up to 3 tiles (4 if every value is 4 glyphs or fewer); wrist hero + 2. A fifth value appears on the focus page only.

### T6. Form (inputs + computed result)
```
CARD                      2x2 WIDGET            2x4 WIDGET                        WRIST
|(i) Tip split    |      |(i) Tip split  |     |(i) Tip split                 |  |  Tip split   |
| ##£14.50##      |      | ##£14.50##    |     | ##£14.50##     Bill   £52.00 |  |  ##£14.50##  |
| ..each..        |      | ..each..      |     | ..each..       People      4 |  |   ..each..   |

FOCUS PAGE
< Tip split                         [log]
            ##£14.50##              result first, pinned
              ..each..
  | Bill            [   52.00 ] |   one card, labels left, fields right, 56 vp rows
  | People          [       4 ] |
  | Tip %           [      12 ] |
```
Overflow: no inputs on card, widget or wrist; a tap opens the focus page. Labels over 18 characters move above their field. With no result yet, the hero is an em dash and the caption reads "Enter the bill".

### T7. List
```
CARD                      2x2 WIDGET            2x4 WIDGET                        WRIST
|(i) Ideas        |      |(i) Ideas    7 |     |(i) Ideas             7 items |  |  Ideas    7  |
| ##7 items##     |      | Call Anna     |     | Call Anna      Book train    |  | Call Anna    |
| Call Anna       |      | Book train    |     | Buy stamps     Fix bike      |  | Book train   |
| Book train      |      | ..+5 more..   |     | ..+3 more..                  |  | Buy stamps   |

FOCUS PAGE: input and Add button as one row at the top, list card below (48 vp rows, newest first), empty state "Nothing yet. Add your first item above."
```
Overflow: newest items first; same row limits as T3; item text 1 line.

### T8. Mixed stack (fallback, including list + weather)
```
CARD                      2x2 WIDGET            2x4 WIDGET                        WRIST
|(i) Morning      |      |(i) Morning    |     |(i) Morning                   |  |   Morning    |
| ##14°##         |      | ##14°##       |     | ##14°##        o Vitamins    |  |   ##14°##    |
| ..Rain later..  |      | ..Rain later..|     | ..Rain later.. o Stretch     |  | ..Rain later.|
| 1 of 3 done     |      | 1 of 3 done   |     |                ..+1 more..   |  |  1 of 3 done |

FOCUS PAGE: hero block, then one card per group in schema order (A24), 16 vp between groups.
```
Hero choice: first of weather, timer, counter, display, checklist. Everything else collapses to one summary line ("1 of 3 done"). Overflow: summary line 1 line, ellipsis.

### M0. Message (empty, blocked, failed)
```
2x2 / wrist: glyph 24 vp, one line of title, one line of reason, whole surface is the tap target.
"Choose a capsule" | "Reminders off - open to allow" | "Could not load - tap to retry"
```

---

## C. Design tokens

Token status: **V** = name found in the offline Huawei mirror; **A** = not in the mirror, but already used in app code on `origin/main`; **U** = unverified. Sizes of `sys.float.*` text tokens are not stated in the mirror; values given are the commonly quoted ones and are marked.

### Spacing, radius, size

| Token | Value | Justification | HarmonyOS resource |
| --- | --- | --- | --- |
| space.1 | 4 vp | 4 vp grid [C] | `sys.float.padding_level2` (U) |
| space.2 | 8 vp | inside a group [C]; Material 8 dp [P] | `sys.float.padding_level4` (U; DIGEST and mirror show `padding_level8` used, value not stated) |
| space.3 | 12 vp | Huawei widget safe margin [P] | `sys.float.padding_level6` (U) |
| space.4 | 16 vp | Apple widget margin 16 pt [P]; page margin [C] | `sys.float.padding_level8` (V name, value assumed 16) |
| space.5 | 24 vp | between sections [C] | `sys.float.padding_level12` (V name, value assumed 24) |
| space.6 | 32 vp | above a hero block [J] | `sys.float.padding_level16` (V name, value assumed 32) |
| radius.widget | host-clipped | Huawei: deliver square, host clips; preview at 18 vp (2x2) and 22 vp (2x4, 4x4) [P] | `sys.float.ohos_id_corner_radius_card` (V, in use at `HarmoniserCard.ets:590`) |
| radius.card | 20 vp | matches current app; close to host radius [J] | none verified |
| radius.inner | 12 vp | inner = outer minus padding, so nested corners look concentric [Pr] | `sys.float.corner_radius_level4`? (V name, value unknown) |
| radius.control | height / 2 | Huawei: circular and capsule buttons [P] | n/a |
| target.min | 40 vp | Huawei hot-zone minimum [P] | n/a |
| target.default | 48 vp | Huawei recommended, Android 48 dp [P] | n/a |
| target.wrist | 56 vp-eq | Parhi et al. 9.2 mm [R] | n/a |
| target.gap | 8 vp | WCAG 2.5.8 spacing logic [R], Material [P] | n/a |
| icon.widget | 20 vp | Huawei brand glyph 20 vp [P] | n/a |
| icon.card | 24 vp | [C] | n/a |
| row.compact / row.comfortable | 48 / 56 vp | A8 [J] | n/a |

### Type (system font only; all `fp`)

| Role | Size / line height / weight | Where | Justification | HarmonyOS resource |
| --- | --- | --- | --- | --- |
| hero.focus | 56 to 64 / 1.1 / Bold, tabular | focus page hero | 2x+ label size [Pr]; [J] | none |
| hero.widget | 40 (2x2 and 2x4), floor 28 / Bold, tabular | widget, card | Huawei numbers 32, 40 fp [P] | none |
| hero.wrist | 48, floor 32 / Bold, tabular | wrist | viewing distance; watchOS default 16 pt body [P]; [J] | none |
| value | 28 / 32 / Medium, tabular | stat tiles, inline values | Huawei 20 and 32 steps [P] | none |
| title | 20 / 26 / Bold | focus header | [C] | `sys.float.Title_S` (A; value assumed 20) |
| subtitle | 16 / 22 / Medium | card title, row label | Huawei widget title 14 or 18 fp [P] | `sys.float.Subtitle_M` (A; assumed 16) |
| body | 16 / 22 / Regular | text, list items | Huawei: phone body size in lists [P] | `sys.float.Body_L` (V; assumed 16) |
| body.small | 14 / 20 / Regular or Medium | widget title, button text, secondary rows | Huawei button text 14 fp Medium [P] | `sys.float.Body_M` (V; assumed 14) |
| caption | 12 / 16 / Regular | labels, units, "+N more", badges | Huawei auxiliary 12 fp [P]; Apple 11 pt floor [P] | `sys.float.Caption_L` (V; assumed 12) |
| not allowed | under 12 | anywhere | same | avoid `Caption_M`, `Caption_S` (A; assumed 10 and 8) |

### Colour roles

| Role | Light / dark | Justification | HarmonyOS resource |
| --- | --- | --- | --- |
| page background | system | [P] | `sys.color.background_secondary` (V) |
| surface (card, widget) | system | Huawei widget background rule [P] | `sys.color.comp_background_primary` (V) |
| surface.tonal (chips, tonal buttons) | system | [P] | `sys.color.comp_background_tertiary` (V) |
| text.primary | system | 4.5:1 [R] | `sys.color.font_primary` (V) |
| text.secondary | system | [P] | `sys.color.font_secondary` (V) |
| text.tertiary (placeholders, struck items only) | system | must not carry needed information; contrast unverified | `sys.color.font_tertiary` (A) |
| text.onAccent | white | [R] | `sys.color.font_on_primary` (V) |
| divider | system, 0.5 vp | [P] | `sys.color.comp_divider` (V) |
| brand (app chrome, consent) | system blue | [P] | `sys.color.brand` (V) |
| accent (per capsule) | 6 entries, each with a light and a dark value, 3:1 or better on its surface | A10 [R] | app resources `app.color.accent_N` in `base/` and `dark/` (to create) |
| accent.tint | accent at 15% | current `tint()`; fine for tracks and chips [J] | computed |
| success | system | A11 | `sys.color.confirm` (V) |
| warning | system | A11 | `sys.color.warning` (V) |
| error | system | A11 | `sys.color.alert` (U) |
| wrist background | `#000000` | A12 [P/J] | firmware constant |
| elevation | none on cards (tone difference only); one shadow level for floating bars: radius 24, y 6, 12% black | Material 3 prefers tonal elevation [P]; current tab bar value [J] | none |

### Motion

| Token | Value | Justification | HarmonyOS resource |
| --- | --- | --- | --- |
| press | 100 ms, opacity 0.6 | response-time limit [R] | `clickEffect` / `stateStyles` (`ClickEffectLevel` V) |
| change | 150 ms fade | Huawei: simple change for small elements [P] | `animation({ duration: 150 })` |
| exit | 200 ms, accelerate | Material 3 [P] | `Curve.FastOutLinearIn` (U) |
| enter | 250 ms, decelerate | Material 3 [P] | `Curve.LinearOutSlowIn` (U) |
| move / expand | 300 ms, standard | Material 3 standard 300 ms [P] | `Curve.FastOutSlowIn` (V, cubic-bezier 0.4, 0, 0.2, 1) |
| open focus page | 350 ms spring | current `geometryTransition` [J] | `curves.springMotion` (V name) |
| widget max | 1000 ms to be safe (hard cap 2000 ms, 1000 ms on older API) | ArkTS widget animation doc [P] | n/a |

---

## D. Audit of the current app: 13 changes, best visible gain per minute first

Files: `R` = `entry/src/main/ets/renderer/CapsuleView.ets`, `I` = `entry/src/main/ets/pages/Index.ets`, `W` = `entry/src/main/ets/widget/pages/HarmoniserCard.ets`, `C` = `entry/src/main/ets/pages/ConsentView.ets`.

| # | Where | Change | Principle | Min |
| --- | --- | --- | --- | --- |
| 1 | `I:1834-1838` | The live state is the smallest text on the home card (`Caption_L`, secondary). Make it the hero: `fontSize(28)`, `FontWeight.Bold`, `font_primary`, `fontFeature('"tnum" on')`, `maxLines(1)`, `minFontSize(20)`. Better: add `heroValue()` and `heroCaption()` beside `summary()` (`CapsuleRuntime.ets:291`) so the card shows "04:10" over "Pasta, left" instead of one joined string. | A1, A19 | 5 (restyle) to 25 (split) |
| 2 | `I:1840-1853` | Delete the "Add to home screen" / "In app" footer from every card. It repeats on each card and is an entry point, not content. Keep the action on the focus page (`routeCard`). Move `originPill` (`I:1833`) down to take the footer's place. | A1, A3, A22 | 4 |
| 3 | `I:1857` | Card height 236 vp leaves a large hole after change 2. Set `height(168)`; with the 2-column grid that shows 6 to 8 capsules per screen instead of 4. | A8 | 1 |
| 4 | `I:1818-1826` | Every card has the same grey disc and blue glyph, so capsules look identical. Use the capsule's widget accent (`accentFor(colorTag)`, `WidgetModel.ets:420`): disc `36x36`, background accent at 15%, glyph 20 in accent. Same colour as its widget. | A10, A19 | 10 |
| 5 | `R:116-120` | Timer value is `Title_S` (about 20 fp), half the counter's size. Set `fontSize(40)`, `FontWeight.Bold`; move the label above it at `Body_M` secondary; when the capsule matches T1, centre it at 56. | A1, A4 | 8 |
| 6 | `R:181-184` | Counter value 40 fp Medium without tabular figures. Add `.fontFeature('"tnum" on')`, `FontWeight.Bold`; for T2 capsules centre at 64 with the label above. | A1, A14 | 8 |
| 7 | `R:243-253` | Every non-reset button is full-width brand blue; three buttons make a blue wall. Filled only for the first button in the capsule; others `comp_background_tertiary` with `font_primary`. Also treat `do` steps containing `reset`, `pop`, `resetTimer:` or `stopTimer:` as secondary: `c.action` is `''` for v1 buttons, so line 249 currently never sees them. | A24, A18 | 10 |
| 8 | `R:33-38`, `R:49` | One 20-radius white box per component, 12 vp apart, reads as a form. Quick version: `Column({ space: 16 })` at `R:49`, and drop `.sectionCard()` from `displayItem` when it is the hero. Full version: group consecutive same-type components into one card with dividers. | A6, A24 | 5 to 30 |
| 9 | `W:223`, `W:291`, `W:363`, `W:376` | 11 fp text on the widget. Huawei's 2x2 minimum for auxiliary text is 12 fp. Change all four to `fontSize(12)`. Also `I:1478` and `C:155` use `Caption_S`; switch to `Caption_L`. | A4 | 3 |
| 10 | `W:192`, `W:417`, `W:649`, `W:746`, `W:758` | Accent-coloured text. Five of the six accents are below 4.5:1 on white (orange and teal 3.04). Use `$r('sys.color.font_primary')` for these texts; keep the accent for rings, discs and filled pills. In dark mode `#0A59F7` is about 2.9:1 on the card; add lighter dark-mode accent values. | A10 | 8 |
| 11 | `W:663-667` | On 2x2 the timer hero is 18 fp inside an 84 vp ring; on 2x4 the ring holds an icon. Make the time the hero: 2x2 = time at 32 to 40 fp with a 4 vp linear bar under it (or ring 96 with 24 fp inside); 2x4 = ring with the time beside it at 40 (already so). Lower `minFontSize` floors: `W:244` 28 is fine, `W:289` 14 should be 20, `W:405` 12 is fine. | A1, A15 | 15 |
| 12 | `C:32-49`, `C:185` | Purpose strings name the mechanism, not the benefit or the data path ("Use where you are"). Rewrite as "So it can ... . Stays on this phone." (only where true), and make the button state the outcome: `Run with ${n} of ${total} allowed`. Buttons at `C:181` and `C:187` to `height(48)`. | A21, A7 | 10 |
| 13 | `R:72-93`, `R:56`, `R:287` | "Blocked timer" exposes a schema type and is dimmed to 0.8 opacity. Use "Timer is off" + the reason + an inline "Allow" that reopens the consent sheet; no opacity. Error text in `sys.color.warning` (orange text, contrast unverified): use `font_primary` with a warning glyph. | A16, A21, A11 | 12 |

Also worth doing, not in the top 13: no `accessibilityText` or `accessibilityGroup` anywhere in `R`, `W` or `C` (A20); no press state on widget controls or `R` custom rows (A17); `W:239` and `W:631` lack tabular figures (check that `fontFeature` is allowed in widgets); `W:173-179` icon in a tinted disc inside a rounded widget, where Huawei suggests showing the glyph without a backing plate.

---

## E. Anti-patterns in generated UI, with fixes

| Anti-pattern | Why it fails | Fix |
| --- | --- | --- |
| A box around every component | No grouping, everything equal weight | A24: group by kind, cards only for groups |
| Everything the same size | No hero, nothing to glance at | A1, A4: one hero at 2x |
| Schema order as layout order | Inputs above the result they produce | A24 rule 1: hero first |
| Purple-blue gradients, glow, glassmorphism on content cards | Lowers contrast, reads as template; Huawei asks for clean widget backgrounds | System surfaces, accent only on the hero |
| A different colour per component | Colour stops meaning anything | A10: one accent per capsule |
| Emoji as icons | Render differently per device, no tinting, poor screen-reader names | System symbols only |
| Coloured status text only | Fails colour-blind users and WCAG 1.4.1 | Glyph + word + colour |
| Raw labels from the model ("counter_1", "Blocked timer") | Leaks implementation | Humanise at render time; fall back to type nouns |
| Shrink-to-fit until it fits | 8 fp text | A15 floors, then ellipsis or abbreviation |
| Full-width filled button for every action | Hick's law; no primary action | A24 rule 5 |
| Fake precision (`14.499999`) | Looks broken | A14 rounding |
| Spinners and skeletons that never resolve, or stale data with no timestamp | Android WT-3 "stale" | Show the last value with "Updated hh:mm" |
| Dashboard of 6 equal tiles on a 2x2 | Not glanceable | A2 budget, T5 limits |
| Confirmation dialogs for everything | Slows the common case | Undo instead (A18) |
| Buttons on widgets that only open the app | Huawei: widgets are content, not entry points | Whole widget is the tap target |
| AI sparkle badge on everything | Says nothing about origin or data flow | A22: three concrete origin labels |

---

## F. What good looks like

Only details confirmed on the linked pages are stated as fact. Everything else is marked.

| Product | What it does that applies here | Source |
| --- | --- | --- |
| Apple system widgets (Weather, Calendar, Music) | Each size keeps the same purpose and adds range, not new features; 16 pt margins; system font; StandBy drops the background and scales text up | HIG Widgets, https://developer.apple.com/design/human-interface-guidelines/widgets |
| Apple Watch Smart Stack widgets | Standard layouts, colour and iconography for glanceable, distinctive widgets | WWDC23 "Design widgets for the Smart Stack on Apple Watch", https://developer.apple.com/videos/play/wwdc2023/10309/ (title and summary only; video not watched) |
| Things 3 | List widgets you can tick from (interactive since 3.19); follows system widget styles (dark, tinted, clear); added an extra-tall size for longer lists | https://culturedcode.com/things/blog/2023/09/interactive-widgets-and-more/, https://culturedcode.com/things/blog/index.html, https://culturedcode.com/things/support/articles/2803567/ |
| Fantastical | A named family where each widget does one thing at several sizes: Date, Calendar, Up Next ("the next item in your list, including details"), Event List; small, medium, large, extra large | https://flexibits.com/fantastical/help/widgets-and-extensions |
| Streaks | Apple Design Award winner; watch complications and widgets show which tasks remain and let you mark one complete; hard cap of 24 tasks | https://streaksapp.com/ (visual details such as its ring grid are not described there; unverified) |
| Wear OS tiles | One task per tile, about 7 seconds of attention, no decorative containers, glanceable graphs, app icon supplied by the system | https://developer.android.com/design/ui/wear/guides/surfaces/tiles/bestpractices |
| Android "differentiated" widgets | Fill the grid, system corner radius, light and dark, intentional empty state, updates after an in-widget action | https://developer.android.com/docs/quality-guidelines/widget-quality |
| Huawei service widgets | Title top-left at 14 or 18 fp, numbers at 32 or 40 fp, 12 vp safe margin, round or capsule buttons, no app name inside the widget | https://developer.huawei.com/consumer/cn/doc/design-guides/system-features-service-widget-0000002087671904; component library at https://developer.huawei.com/consumer/cn/design/resource/ |
| CARROT Weather | Widely praised for many configurable widget layouts built from one data source. Not verified in this session. | https://www.meetcarrot.com/weather/ (not fetched) |
| Google Pixel At a Glance | One contextual line that changes with relevance. Not verified in this session. | https://support.google.com/pixelphone/ (specific article not located) |
| Nothing OS widgets | Monochrome dot-matrix type, one value per widget, suited to AMOLED. Not verified in this session. | https://nothing.tech/ (not fetched) |

---

## G. Open questions to search on social sources

1. Search X and Reddit r/HarmonyOS for "服务卡片 设计" or "HarmonyOS widget design" posts with screenshots of third-party widgets that Huawei featured; collect 10 and note hero size and padding.
2. Search Mobbin and Dribbble for "timer widget", "habit widget", "counter widget"; record how many use a ring versus a bar on the smallest size.
3. Search r/UXDesign and Hacker News for "generative UI" and "LLM generated interface" critiques; list complaints that repeat (spacing, hierarchy, sameness).
4. Search X for posts by designers at Linear, Things or Flighty on widget design trade-offs ("widget", "Live Activity", "glanceable").
5. Search r/userexperience and r/privacy for reactions to permission sheets with per-item toggles versus one-by-one prompts; look for cited studies.
6. Search Hacker News for "permission fatigue" and "just-in-time permission" threads; extract any measured grant rates.
7. Search Reddit r/WearOS, r/AppleWatch and r/GarminWatches for "can't read" or "too small" complaints about third-party tiles; note the font sizes involved.
8. Search X and Behance for "AMOLED true black UI smearing" to check whether pure black is still a problem on small panels at low brightness.
9. Search r/UI_Design for "card inside card" and "too many cards" threads; collect the fixes people recommend.
10. Search X for "AI badge" or "generated by AI label" user research (NN/g, Google PAIR staff) on whether origin labels change trust.
11. Search Huawei developer forum and Zhihu for the actual vp sizes of 2x2, 2x4 and 4x4 widgets on current phones, and for the values of `sys.float.Body_L`, `Caption_M`, `padding_level8`.
12. Search Dribbble and Mobbin for consent or "review permissions" sheets in automation apps (Shortcuts, IFTTT, Tasker) and note how they show what leaves the device.

---

## What I could not verify

- **Widget sizes in vp.** 2x2 = 150x150, 2x4 = 316x150, 4x4 = 316x344 come from one forum answer (https://bbs.itying.com/topic/680324df687c4e0048a9e891), not from Huawei. The character counts in A2 and A15 depend on them.
- **System text token sizes.** The mirror confirms the names `Body_L`, `Body_M`, `Title_M`, `Caption_L` but not their sizes. `Body_S`, `Title_S`, `Subtitle_M`, `Subtitle_L`, `Caption_M`, `Caption_S`, `font_tertiary`, `font_emphasize`, `icon_secondary` do not appear in the mirror at all; the app uses them and presumably compiles. `sys.color.alert`, the `padding_level` to vp mapping and `corner_radius_level` values are unverified. Check in DevEco before relying on section C.
- **Contrast of system colours.** I did not have the hex values of `sys.color.warning`, `font_tertiary` or the dark card surface. The dark-surface figure in A10 assumes about `#202224`.
- **Reduce-motion API.** No ArkUI API for reading a reduced-motion setting was found in the mirror.
- **`fontFeature` and `maxFontScale` inside widgets.** Both exist in ArkUI; whether each is allowed in an ArkTS widget page was not checked.
- **Reading speed** (200 to 250 words per minute) and **Nielsen's 100 ms limit** are quoted from memory; the NN/g pages for progressive disclosure, icon usability, empty states, response times and heuristics were not re-fetched. The MIT Touch Lab fingertip study named in the brief was not found and is not cited.
- **HAX guidelines** other than G1 are quoted from memory of the paper.
- **Material dark theme `#121212`**: page located, value from memory.
- **Refactoring UI, Laws of UX, Carbon, Polaris**: cited as practitioner sources by home page; specific chapters not fetched.
- **Reference products**: CARROT Weather, Pixel At a Glance and Nothing OS rows are reputation only. The English version of the Huawei widget guide timed out; the Chinese page was read and the translations are mine.
- **Wrist density.** The 2 px per vp conversion is arithmetic from the panel size, not a measured legibility test. Wrist type sizes need checking on the board.
- **Nothing was rendered.** Every wireframe and size is untested on a device; the 2x2 layouts in particular need a check at 1.3x font scale.
