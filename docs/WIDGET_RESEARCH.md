# Widget research: one widget per capsule, and nicer cards

**Date:** 2026-10-03

**How this was produced:** AI-assisted research (a Claude Code sub-agent using web search and reading this repository). Nothing was run on a device or an emulator, and no code was changed. Code references are to `origin/main` at `b33b0c3`; the widget files, `form_config.json` and `pages/Index.ets` are unchanged at `3c22935`.

**Summary**

1. A widget for a specific capsule can be added from inside the app with one or two taps, using public APIs (`AddFormMenuItem`, or `formProvider.openFormManager`). A silent add is system-app only.
2. The app cannot remove its own widget (only the user can) and cannot register new form types at runtime. It can blank or retarget a widget, and it already does.
3. For judging, widget reliability and touch targets are worth more than the new add flow. Suggested order: reliability, then in-app add, then visual polish.

---

## Direct answer: can widgets be added and removed "on the fly"?

**Partly.**

- **Add: yes, with a tap or two from the user.** A public API lets the app put a widget for one specific capsule on the home screen from inside the app, with no long-press on the icon. A silent add with no user action is system-app only.
- **Remove: no.** A provider cannot delete its own widget; only the user can, from the home screen. The app can blank or retarget a widget, which the code already does.
- **New widget types at runtime: no.** Forms are static in `form_config.json`. "One widget per capsule" means many instances of the one `harmoniser` form, each bound to a capsule by `formId`. The repo already stores bindings that way.

## 1. What the app does today

- **Declared forms:** one form, `harmoniser`, in `entry/src/main/resources/base/profile/form_config.json`. It has `isDynamic: true`, `updateEnabled: true`, `updateDuration: 1` (30 minutes), sizes `2*2` (default) and `2*4`, `renderingMode: fullColor`, and no `formConfigAbility`.
- **Binding:** `onAddForm` calls `bindForm`, then `bindNewForm` in `entry/src/main/ets/widget/WidgetService.ets`. A new widget takes the newest widget-suitable capsule, or goes blank if there is none. The README says a new widget is blank, which no longer matches the code.
- **Storage:** preferences store `harmoniser_widgets`, key `form:<formId>` holding `{formId, capsuleId, wide, addedAt}`, plus a `seen` list. `onRemoveForm` deletes the key.
- **Retargeting:** a blank card routes to `EntryAbility` with `{source, action:'chooseCapsule', formId}` and opens `WidgetCapsulePicker`. The capsule page has "Show on home screen widget", which fills a blank widget or replaces one.
- **Data to the card:** one string, `view` (a JSON `WidgetView`), via `formBindingData` and `formProvider.updateForm`. The card reads it with `@LocalStorageProp('view')`.
- **Interactions:** `postCardAction` `message` for start, increment, toggle and refresh, handled in `onFormEvent` and checked by the gatekeeper. `router` on the whole card opens the app. `call` is not used.
- **In-app add entry:** there is none. `openHarmoniserManager()` (which wraps `openFormManager`) exists in `WidgetService.ets` but nothing calls it. `Index.ets` `routeCard` (around lines 1293-1320) only shows text telling the user to long-press the icon.

### Likely causes of "hit-or-miss" (judgement from the code, ranked)

1. **Tap targets are too small, and a miss opens the app.** Start and + buttons are 28x24 vp, checklist rows are 20 vp high, and the root `Column` has an `onClick` router. Huawei's guide requires at least 24 vp visual size and a 40 vp hot zone ([design guide](https://developer.huawei.com/consumer/cn/doc/design-guides/system-features-service-widget-0000002087671904)).
2. **Slow first tap, then a double tap undoes it.** The form process exits 10 s after its last callback ([lifecycle guide, mirrored](https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-guides/arkts-ui-widget-lifecycle.md)), so a tap after idle cold-starts it. The card has no optimistic state, and `toggle` is not idempotent, so a second tap flips the item back.
3. **`onChangeFormVisibility` does nothing for this app.** The same lifecycle guide says it only takes effect for system apps. Nothing refreshes the card when the user returns to the home screen.
4. **A finished timer can stay stale.** `TextTimer.onTimer` does not fire on the lock screen or in the background ([TextTimer reference](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-texttimer)). "Done" depends on the card being visible at zero; otherwise it waits up to 30 minutes.
5. **Two processes share preferences.** The app writes `capsules` and `gatekeeper` with an async flush. Commit `a2d62aa` fixed the app side, but the form process still reads from disk and can miss a just-saved capsule or grant. `syncAssignments` is an unlocked read-modify-write from both processes.
6. **Background app can overwrite widget taps.** The app reloads widget state only in `onPageShow`. A runtime `onChange` while backgrounded calls `persist` and can overwrite a newer state written by a widget tap.
7. **Auto-assignment surprises.** A new capsule fills the first blank widget, and a new widget takes the newest capsule, so a widget may show something nobody picked.
8. **Dead blank card.** If `view` arrives empty, `formId` is `''` and `takeWidgetWant` ignores the tap.

## 2. Adding a widget from inside the app

| API | Public? | Since | What the user sees |
|---|---|---|---|
| `AddFormMenuItem` from `@kit.ArkUI` | Yes | API 12, not on wearables | A menu item; tapping it adds the widget. Accepts `formBindingData` and returns `formId` in a callback. |
| `formProvider.openFormManager(want)` from `@kit.FormKit` | Yes | API 18 | The system widget manager page for this app; the user taps "Add to home screen". |
| `formProvider.requestPublishForm` | **System API** | n/a | Not available to this app. |
| `FormComponent` | Host-side | n/a | Embeds a form in a host app; it does not add to the launcher (from memory, not looked up). |

Sources: [FormMenu reference, mirrored](https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-references/ohos-arkui-advanced-formmenu.md), [formProvider reference](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-app-form-formprovider), [formProvider system APIs](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-form-kit/js-apis-app-form-formProvider-sys.md), [in-app widget manager guide, mirrored](https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-guides/arkts-ui-widget-open-formmanager.md).

- The FormMenu page says that from API 18 `openFormManager` is the recommended route. `AddFormMenuItem` is not marked deprecated.
- Dimension values are 1 = 1*2, 2 = 2*2, 3 = 2*4, 4 = 4*4, 7 = 6*4 (FormMenu sample).
- If the `openFormManager` parameters are incomplete or name a form that does not exist, the default form from `form_config.json` is shown (formProvider reference).

Snippet adapted from the FormMenu sample:

```ts
import { AddFormMenuItem } from '@kit.ArkUI';
import { formBindingData } from '@kit.FormKit';

@Builder addMenu(entry: CapsuleEntry) {
  Menu() {
    AddFormMenuItem(
      { bundleName: this.bundleName, abilityName: 'HarmoniserFormAbility',
        parameters: {
          'ohos.extra.param.key.form_dimension': 2,
          'ohos.extra.param.key.form_name': 'harmoniser',
          'ohos.extra.param.key.module_name': 'entry',
          'capsuleId': entry.capsule.id          // may not reach onAddForm: unverified
        } },
      'capsule-card-' + entry.capsule.id,         // .id() of the in-app card, used for the transition
      { formBindingData: formBindingData.createFormBindingData({}),
        callback: (error, formId) => { /* error?.code === 0 means added */ },
        style: { options: { content: 'Add 2x2 widget' } } })
  }
}
```

The fallback, already written in `WidgetService.ets` as `openHarmoniserManager()`:

```ts
import { formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';

const want: Want = {
  bundleName: bundleName,
  abilityName: 'HarmoniserFormAbility',
  parameters: {
    'ohos.extra.param.key.form_dimension': 2,
    'ohos.extra.param.key.form_name': 'harmoniser',
    'ohos.extra.param.key.module_name': 'entry'
  }
};
formProvider.openFormManager(want);
```

## 3. Removing a widget

- `formHost.deleteForm` and `releaseForm` need `ohos.permission.REQUIRE_FORM` and are host/system APIs ([formHost system APIs](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-form-kit/js-apis-app-form-formHost-sys.md)).
- The public `formProvider` page lists no delete call. Removal is user-only (long-press, then Remove).
- The provider can blank or retarget with `assignCapsuleToWidget(ctx, formId, null | id)`, clean up in `onRemoveForm`, and list placed widgets with `getPublishedRunningFormInfos()` (API 20+). All three exist or are public.
- Deleting a capsule already blanks its widget.

## 4. Recommended design: "Add to home screen" on each capsule

**Flow**

1. The capsule page shows an "Add to home screen" button for widget-suitable capsules.
2. Tapping it opens a menu with two `AddFormMenuItem`s (2x2 and 2x4).
3. Just before the menu opens, the app writes a pending slot naming this capsule.
4. The launcher adds the widget and `onAddForm` binds the new `formId` to the pending capsule.
5. The callback clears the slot, toasts and reloads the widget list. On a non-zero error code it falls back to `openHarmoniserManager()`; the same pending slot makes that path bind correctly too.

The pending slot is the key choice: it does not depend on custom `want` parameters reaching `onAddForm`, which could not be confirmed.

**Storage shape** (store `harmoniser_widgets`)

- Existing, unchanged: `form:<formId>` holding `{formId, capsuleId, wide, addedAt}`.
- New: `pending` holding `{capsuleId, at}`, written with `flushSync`, valid for about 120 s, consumed once.

**Files to change**

- `entry/src/main/ets/widget/WidgetStore.ets`: add `putPending`, `takePending`, `clearPending`.
- `entry/src/main/ets/core/WidgetModel.ets`: add a pure chooser with priority want param, then fresh pending, then the current newest-suitable fallback. Tests go in `entry/src/test/WidgetModel.test.ets`.
- `entry/src/main/ets/widget/WidgetService.ets`: `bindNewForm` uses the chooser; export a want builder taking the dimension.
- `entry/src/main/ets/widget/HarmoniserFormAbility.ets`: pass `want.parameters['capsuleId']` through.
- `entry/src/main/ets/pages/Index.ets`: in `routeCard`, replace the long-press hint with the button, `.bindMenu(this.addMenu(entry), { onAppear: () => putPending(...) })` and the callback. Keep "Show on home screen widget" for retargeting, and add "Remove from widget" (assign `null`).
- `form_config.json`: no change needed.

**Effort:** about 1.5 to 2 hours including tests, plus an emulator check.

**Risks**

- `AddFormMenuItem` is documented with a long-press `bindContextMenu`; using it under a click `bindMenu`, and inside a `@ComponentV2`, is untested.
- Emulator launcher support for the menu add is unknown. The fallback is `openFormManager`, which costs one more tap.
- Whether `onAddForm`'s return value overrides the `formBindingData` passed at add time is unknown. Passing `{}` and letting `onAddForm` build the view avoids the question.
- The per-app instance limit exists (error 16501002) but the number is unknown.

**Other ways to offer "a widget for each X", and why not now**

- `formConfigAbility` (an "Edit" entry on the widget that opens an ability with `want.parameters.formId`) is real ([widget editing guide](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-ui-widget-event-formeditextensionability)). The blank-card picker already does the same job.
- More sizes: phones support 1*2, 2*2, 2*4 and 4*4; 6*4 on some models; 1*1 on the lock screen only. A config holds at most 16 forms ([configuration guide](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-ui-widget-configuration)). Adding 4*4 means replacing the `wide` boolean with a size, roughly 1 to 2 hours; skip it.

## 5. Making widgets less static

- **Interaction:** dynamic cards get click events and custom animation; static cards only `FormLink`. Swipe, drag and long-press are not allowed ([design guide](https://developer.huawei.com/consumer/cn/doc/design-guides/system-features-service-widget-0000002087671904)). `setTimeout` is not supported in cards ([overview, mirrored](https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-guides/arkts-form-overview.md)).
- **Animation:** explicit, property and transition animations work. Duration is capped at 1000 ms before API 26 (2000 ms after); `tempo`, `delay` and `iterations` are forced to defaults ([animation guide, mirrored](https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-guides/arkts-ui-widget-page-animation.md)). So no looping or idle animation.
- **Refresh:** `updateForm` any time the app or form process is alive. `updateDuration` is in 30-minute units, `setFormNextRefreshTime` has a 5-minute minimum, and timed refresh is capped at 50 per card per day ([refresh guide, mirrored](https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-guides/arkts-ui-widget-passive-refresh.md)).
- **Message events:** `postCardAction` `message` starts the `FormExtensionAbility`, which handles `onFormEvent` and exits 10 s after its last callback ([event guide, mirrored](https://github.com/liasica/harmonyos-skills/blob/master/harmonyos/references/harmonyos-guides/arkts-ui-widget-event-formextensionability.md)).
- **Per-second ticking:** `TextTimer` is card-capable since API 10 and ticks locally; the app already uses it. Judgement: its `onTimer` can also drive a card `@State`, so a progress ring can advance every second with no provider call.
- **Live View Kit (实况窗):** mainland China only, and needs rights applied for in AppGallery Connect. It has a TIMER scenario for tool apps ([Live View intro](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/liveview-introduction)). Not usable here.
- **Interactive widgets (API 20):** scene-animation cards need a `LiveFormExtensionAbility`; `requestOverflow` works on some phone models only, and the emulator does not preview interactive widgets ([ArkTS widget overview](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-form-overview)). The "fun interaction" type is quick-game only. Skip.
- **Lock-screen widgets:** 1*1 and 1*2 with `autoColor` or `singleColor` rendering. Not tried; skip.

## 6. Design guidance and visual upgrades

Official guide: [Service widgets, English](https://developer.huawei.com/consumer/en/doc/design-guides/system-features-service-widget-0000002087671904) and [Chinese](https://developer.huawei.com/consumer/cn/doc/design-guides/system-features-service-widget-0000002087671904). The Chinese page is the one that was read.

**Rules from the guide**

- Show 1 to 2 information points on a small card; one tap goes straight to the service; no multi-step flows.
- Keep content 12 vp from the edges.
- The host clips the corners: deliver a square background, preview at 18 vp (1*2, 2*2) or 22 vp (2*4, 4*4), and avoid nested rounded rectangles.
- Type: title 14 or 18 fp, secondary 12 fp, numerals 20, 32 or 40 fp.
- Buttons: round or capsule, at least 24 vp visual and 40 vp hot zone; about 30x30 vp is recommended on 2*2.
- Background: white in light mode, and dark mode must be adapted. The card currently hardcodes white and black.
- Clean backgrounds; use accent colour sparingly.

**Ranked upgrades**

| # | Upgrade | Effort |
|---|---|---|
| 1 | Bigger targets (40 vp hot zones) and optimistic tap state; send an idempotent message (`checked: true` rather than toggle). This also fixes causes 1 and 2 above. | 45 min |
| 2 | Dark mode through `$r('app.color.*')` with a `resources/dark` set. | 20 min |
| 3 | A hero layout per capsule shape on 2x2 (see patterns below). | 60-90 min |
| 4 | Press feedback (scale or opacity, 300 ms or less) and a transition when a timer flips to "Done". | 20 min |
| 5 | Drop the 9 fp "Harmoniser" label; use the 14 fp title and a small capsule glyph. | 5 min |
| 6 | Blank state: an icon and a capsule-shaped "Choose a capsule" button. | 15 min |

**Three patterns**

- **Timer:** a large `mm:ss` numeral (32 or 40 fp) inside a progress ring, with one round start button at the bottom right.
- **Counter:** a 40 fp value, a 12 fp label, and one 30 vp "+" button whose whole right half is the hot zone.
- **Checklist:** a "3/5" numeral with a thin bar, then at most 3 rows on 2x2 (6 in two columns on 2x4), each row a full-width 40 vp hot zone.

All edits are in `entry/src/main/ets/widget/pages/HarmoniserCard.ets`; `WidgetView` needs no schema change.

## 7. Judging fit

Criteria from the [challenge statement](https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/hackathon_challenge.md): originality 20, usefulness 20, technical execution 20, platform capabilities 20, demo 10, reproducibility 10.

- The app already scores on platform use with Form Kit. In-app add improves the demo and adds a little platform depth; it is a nice-to-have.
- Widget reliability matters more. "Does it actually work as described?" sits under technical execution, and the README already records an open phone bug (BUG-2).
- Which submission items are still open was not checked. The required deliverables (`.hap`, recorded demo, README, `AI_WORKFLOW.md`) come first regardless.
- Suggested order, about 3 hours in total: reliability and touch targets, then in-app add, then dark mode and the hero layout. Drop the hero layout first if time runs short.

## What will not work

- Silent add or programmatic delete (`requestPublishForm`, `formHost.deleteForm`): system-only.
- Registering a new form type per capsule at runtime: forms are static, 16 at most.
- Live View for timers: mainland China only, and needs approval.
- Interactive or "fun" widgets on the emulator.
- Looping animations, anything over 1 s, `setTimeout`, or long-press, swipe and drag in cards.
- Background ticking from the provider: the form process dies after 10 s and refresh floors at 5 minutes.
- Relying on `onChangeFormVisibility`: system apps only.

## Not verified

- **Emulator behaviour of everything in sections 2 and 4.** It is unknown whether the API 24 emulator launcher honours `AddFormMenuItem`, shows a confirmation, or returns `formId`.
- **Custom `want.parameters` reaching `onAddForm`.** Hence the pending slot.
- **`AddFormMenuItem` under a click `bindMenu` and inside `@ComponentV2`.** The docs only show a long-press context menu.
- **The "hit-or-miss" ranking.** It is inferred from code and docs, with no device logs.
- **Whether `updateForm` with an unchanged `ForEach` key resets a running `TextTimer`.** If it does not, a timer can drift after the card is frozen.
- **Card capability of `Progress`, `Gauge`, `TextClock`, `linearGradient` and `$r('sys.color.*')`.** From memory only; the card compiler will reject anything unsupported.
- **`FormComponent` being host-side.** From memory.
- **`resizable: true` (API 20) for drag-resizing between 2*2 and 2*4.** It is in the config doc, but how the provider learns the new size was not found, so it is not recommended yet.
- **Sources.** Several Huawei pages timed out, so a GitHub mirror of the Chinese docs (`liasica/harmonyos-skills`, scraped September to October 2026) was read instead, and the OpenHarmony docs were used for the system APIs. The English in-app-add guide URL returned 404.
