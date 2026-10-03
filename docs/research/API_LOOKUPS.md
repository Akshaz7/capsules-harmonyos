# HarmonyOS NEXT / ArkUI API lookups for tonight's UI work

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04). Looked up in an offline mirror of Huawei's documentation (`<mirror>` = github.com/liasica/harmonyos-skills, `harmonyos/references/`) and on developer.huawei.com. **No snippet here was compiled or run**: treat them as starting points for DevEco Studio to check.

Date: 2026-10-04. App read at `origin/main` `7292381` (`capsules-harmonyos`), min API 20, emulator API 24.
Produced by an AI research pass. **No snippet here was compiled or run.** Treat snippets as starting points and let DevEco's compiler have the last word.

## How to read this

Evidence tags on every fact:

- **[M path]** verified in the offline mirror. Paths are relative to `harmony-skills/liasica__harmonyos-skills/harmonyos/references/`; `refs/` = `harmonyos-references/`, `guides/` = `harmonyos-guides/`.
- **[L]** also confirmed on the live English page (fetched today).
- **[A file:line]** seen in the app's own code on `origin/main` (so it compiles there).
- **[U]** from memory, unverified. Check before relying on it.

English URL for any mirror page: `https://developer.huawei.com/consumer/en/doc/harmonyos-references/<slug>` or `.../harmonyos-guides/<slug>` (slug = file name without `.md`). Only the pages tagged [L] were actually fetched; the rest are the same slug pattern, not fetched.

Mirror and live site disagreed on nothing I checked. The mirror and the repo's `hackathon-resources/emulator-capability-comparison.md` disagree on accelerometer simulation (section 9).

## State management: what each file uses

Every UI file in `entry/src/main/ets` is **V2** (`@ComponentV2`, `@Local`, `@Param`, `@Event`): `pages/Index.ets` (2317 lines, `@Entry @ComponentV2 struct Index`), `MarketplaceView.ets`, `DevicePanel.ets`, `ConsentView.ets`, `SettingsView.ets`, `ChangeCard.ets`, `TriggerCard.ets`, `LogView.ets`, `HomeHero.ets`, `MiniPreview.ets`, `WidgetCapsulePicker.ets`, `renderer/CapsuleView.ets`, `renderer/CapsuleRuntime.ets` (`@ObservedV2`/`@Trace`), `sharing/SharingBar.ets`.
The one exception is the widget card `widget/pages/HarmoniserCard.ets`: **V1** (`@Component`, `@LocalStorageProp`). Keep it V1.
No V1 decorators anywhere else. All snippets below are V2 unless marked.

System advanced components come in two flavours; pick by decorator type:

| Component | Kind | Since | Usable from the app's V2 structs |
|---|---|---|---|
| `Chip` | `@Builder` function | API 11 | Yes (a builder, no state generation) [M refs/ohos-arkui-advanced-chip.md] |
| `ChipGroup` | V1 `@Component` (`@Prop` params) | API 12 | Probably (V1/V2 mixing loosened from API 19 [M guides/arkts-v1-v2-mixusage.md]); not compiled |
| `ChipV2`, `ChipGroupV2` | `@ComponentV2` | **26.0.0** | **No: newer than API 24** [M refs/ohos-arkui-advanced-chipv2.md] [L] |
| `ProgressButton` | V1 `@Component` | API 10 | Probably |
| `ProgressButtonV2` | `@ComponentV2` | API 18 | Yes [M refs/ohos-arkui-advanced-progressbuttonv2.md] |
| `AddFormMenuItem` | `@Builder` function | API 12 | Yes [M refs/ohos-arkui-advanced-formmenu.md] |

All of these warn: do not put universal attributes/events on them (they land on a generated `__Common__` node). Wrap in a `Row`/`Column` and style that. [M same pages]

---

## 1. Create screen with a bottom prompt bar

**Where it attaches.** `Index.inputCard()` (line ~1543) is the current input: `TextArea` with fixed `.height(96)` inside the scrolling `home()` builder (line ~1868). `create()` (842) and `createFrom()` (858) are the submit path. `inputFocused` (`@Local`) already tracks focus.

**How the existing floating bar works** [A Index.ets:2063-2118]:
`mainTabs()` is `Stack({ alignContent: Alignment.Bottom }) { Tabs(...).barHeight(0)…; this.tabBar() }`. The pill is 64 vp high with `margin({ bottom: 12 })`. Each page scrolls under it by reserving space itself:
- `home()` and `capsulesTab()`: `Scroll` > `Column` with `padding({ bottom: 120 })` [A Index.ets:1906].
- Marketplace: `List.contentEndOffset(this.embedded ? 120 : 0)` [A MarketplaceView.ets:137].
- Root `Navigation` has `.hideTitleBar(true)` and `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])` [A Index.ets:2311-2313].

A pinned prompt bar should follow the same pattern: sibling of the scroller in a bottom-aligned `Stack`, content gets bottom padding equal to bar height.

**APIs**

| API | Signature / values | Since | Evidence |
|---|---|---|---|
| `expandSafeArea` | `expandSafeArea(types?: Array<SafeAreaType>, edges?: Array<SafeAreaEdge>)`; `SafeAreaType.SYSTEM/CUTOUT/KEYBOARD`; `SafeAreaEdge.TOP/BOTTOM/START/END`. Extends drawing only, layout unchanged | 10 | [M refs/ts-universal-attributes-expand-safe-area.md] [L] |
| `setKeyboardAvoidMode` | `uiContext.setKeyboardAvoidMode(value: KeyboardAvoidMode): void`; default `OFFSET` | 11 | [M refs/arkts-apis-uicontext-uicontext.md] [L] |
| `KeyboardAvoidMode` | `OFFSET`=0, `RESIZE`=1, `OFFSET_WITH_CARET`=2 (14+), `RESIZE_WITH_CARET`=3 (14+), `NONE`=4 (14+). Import from `@kit.ArkUI` | 11 | [M refs/arkts-apis-uicontext-e.md] |
| `ignoreLayoutSafeArea` | changes layout, unlike `expandSafeArea` | 20 | [M same safe-area page] |
| Keyboard height | `windowClass.on('keyboardHeightChange', (h: number) => void)`, value in **px**; `off('keyboardHeightChange', cb?)` | 7 | [M refs/arkts-apis-window-window.md] |
| Insets | `windowClass.getWindowAvoidArea(type: window.AvoidAreaType): AvoidArea`; types `TYPE_SYSTEM`, `TYPE_CUTOUT`, `TYPE_KEYBOARD`, `TYPE_NAVIGATION_INDICATOR` (11+); `on('avoidAreaChange', …)` | 9 | [M refs/arkts-apis-window-window.md, refs/arkts-apis-window-e.md]. Field `bottomRect.height` is [U] |
| `TextArea` | `TextArea({ placeholder?, text?, controller? })`; `text` supports `$$` (10+) and `!!` (18+) two-way binding | 7 | [M refs/ts-basic-components-textarea.md] |
| `enterKeyType` | `.enterKeyType(EnterKeyType.Send)`; values `Go, Search, Send, Next, Done, PREVIOUS, NEW_LINE`; TextArea default is `NEW_LINE` | 11 | [M same + refs/ts-basic-components-textinput.md] |
| `onSubmit` | `(enterKey: EnterKeyType) => void` (11+); or `(enterKeyType: EnterKeyType, event?: SubmitEvent) => void` (14+), `event.keepEditableState()`, `event.text`. **Not fired when the key type is `NEW_LINE`** | 11/14 | [M] |
| `minLines` / `maxLines` | `.minLines(n)` (20+, height follows, bounded by `constraintSize`); `.maxLines(lines, { overflowMode: MaxLinesMode.SCROLL })` (20+); `.maxLines(n)` (10+) truncates in non-inline mode | 20 | [M textarea.md, refs/ts-text-common.md] |
| `TextAreaController` | `caretPosition(n)`, `setTextSelection(...)`, `stopEditing()` (10+, closes the keyboard) | 8/10 | [M] |
| Focus | `this.getUIContext().getFocusController().requestFocus(key: string): void` (12+, throws 150001/150002/150003), `.clearFocus()` (12+); attributes `.id('x')`, `.defaultFocus(true)` (9+), `.focusable()`, `.focusOnTouch()`; `.enableKeyboardOnFocus(false)` (10+) | 9-12 | [M refs/arkts-apis-uicontext-focuscontroller.md, refs/ts-universal-attributes-focus.md] |
| `contentEndOffset` | on `List`: `contentEndOffset(value: number)` API 11. On `Scroll` (scrollable common): **API 22+** | 11 / 22 | [M refs/ts-container-list.md, refs/ts-container-scrollable-common.md] |

**Snippet** (V2, add to `Index`; RESIZE mode set once in the ability):

```ts
// EntryAbility.onWindowStageCreate, inside the loadContent callback:
//   import { KeyboardAvoidMode, window } from '@kit.ArkUI';
//   windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);

private promptCtl: TextAreaController = new TextAreaController();

@Builder
promptBar() {
  Row({ space: 8 }) {
    TextArea({ placeholder: this.placeholderText, text: this.request, controller: this.promptCtl })
      .id('promptInput')
      .layoutWeight(1)
      .constraintSize({ minHeight: 40, maxHeight: 120 }) // grows with content, then scrolls inside
      .enterKeyType(EnterKeyType.Send)
      .onChange((value: string) => {
        this.request = value;
      })
      .onSubmit((key: EnterKeyType) => {
        this.promptCtl.stopEditing();
        this.create();
      })
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(20).fontColor([$r('sys.color.font_on_primary')])
    }
    .width(40).height(40)
    .enabled(!this.busy && this.request.trim().length > 0)
    .accessibilityText('Create')
    .onClick(() => this.create())
  }
  .padding(12)
  .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
}
```

Place it as the last child of a `Stack({ alignContent: Alignment.Bottom })` whose first child is the `Scroll`, and give the scroll content `padding({ bottom: <bar height> })`.

**Gotchas**

- Default mode is `OFFSET`: the whole page is pushed up only as far as the caret needs. With `RESIZE` the page shrinks, percentage-sized children follow, fixed-size ones do not; a bottom-aligned bar in a `'100%'`-high Stack then sits on the keyboard. [M]
- In `RESIZE` mode `expandSafeArea([SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])` has no effect. [M]
- `setKeyboardAvoidMode` is page-level. It does **not** apply to `bindSheet`, dialogs, popups, menus, toasts, overlay. The consent sheet (`Index.build()` `.bindSheet`) is unaffected. [M] [L]
- Under RESIZE the existing floating tab pill would also ride above the keyboard. Hide it while `inputFocused`, or let the prompt bar replace it. (reasoning from the layout, not tested)
- `EnterKeyType.Send` means Enter submits and cannot insert a newline. If multi-line entry matters, keep `NEW_LINE` and submit only from the button. [M]
- "TextArea grows with content when no height is set" is [U]; `minLines` docs imply auto height. The current `.height(96)` must go for auto-grow.
- `expandSafeArea` only works when the component's edge touches the safe-area edge, is not recommended inside scroll containers, and does not propagate to children. [M]
- Do not use `Scroll.contentEndOffset` (API 22) with min API 20; keep the padding approach or guard it.
- Manual alternative: `KeyboardAvoidMode.NONE` plus `keyboardHeightChange` (px, convert with `this.getUIContext().px2vp(h)` [U]) driving a bottom margin. More code, no gain here.

**Emulator API 24:** ArkUI layout and soft keyboard work; nothing in the mirror restricts these. Not tested.

---

## 2. Suggested prompts (chips)

**Where:** inside `Index.home()` directly under `this.inputCard()`; the examples already exist as `PLACEHOLDERS` (used by `typePlaceholder()`, line ~1640). `MarketplaceView.ets:96-103` already has a horizontal category row built as `Scroll` + `.scrollable(ScrollDirection.Horizontal)`; copy that.

**Options**

| Route | API | Notes |
|---|---|---|
| Plain | `Scroll() { Row({ space: 8 }) { ForEach(...) } }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)` | Full styling control. Recommended. [A MarketplaceView.ets:96] |
| List | `List({ space: 8 }) {...}.listDirection(Axis.Horizontal)` | [M refs/ts-container-list.md] |
| System chip | `import { Chip, ChipSize } from '@kit.ArkUI'`; `Chip(options: ChipOptions)` | API 11, `@Builder`. [M refs/ohos-arkui-advanced-chip.md] |
| System group | `import { ChipGroup, ChipSize } from '@kit.ArkUI'`; `ChipGroup({ items, itemStyle?, selectedIndexes?, multiple?, chipGroupSpace?, chipGroupPadding?, onChange?, suffix? })` | API 12, V1 component, selection-oriented (filters), scrolls horizontally by itself. [M refs/ohos-arkui-advanced-chipgroup.md] |

`ChipOptions` fields [M]: `label: { text, fontSize?, fontColor? }` (required), `size?: ChipSize.NORMAL | ChipSize.SMALL | SizeOptions`, `enabled?`, `activated?` (12+), `prefixIcon?`, `prefixSymbol?` (12+), `suffixIcon?`, `backgroundColor?`, `activatedBackgroundColor?` (12+), `borderRadius?`, `allowClose?` (**default true**), `onClose?`, `onClicked?: Callback<void>` (12+; undefined = not clickable).

```ts
import { Chip, ChipSize } from '@kit.ArkUI';

@Builder
suggestionRow() {
  Scroll() {
    Row({ space: 8 }) {
      ForEach(PLACEHOLDERS, (text: string) => {
        Chip({
          label: { text: text },
          size: ChipSize.SMALL,
          allowClose: false,
          onClicked: () => {
            this.request = text;      // fill; call this.create() instead to submit
          }
        })
      }, (text: string) => text)
    }
  }
  .scrollable(ScrollDirection.Horizontal)
  .scrollBar(BarState.Off)
  .width('100%')
}
```

**Gotchas**

- `allowClose` defaults to **true**: every chip shows an X unless you set `false`. [M]
- Styling limits: colours, radius, size, icons only. No universal attributes on `Chip` itself (no `.margin`, `.onClick`, `.shadow`). Font size for label+icon as one value is API 23+ (`fontSize` on `ChipOptions`). [M]
- `Chip` has no max width control beyond `SizeOptions`; long prompts need the plain `Text` + `borderRadius` route.
- Hot zone: keep each chip at least 40 vp high (DIGEST section 5).
- `ChipV2` / `ChipGroupV2` are 26.0.0 only. Do not import them. [M] [L]

**Emulator:** fine (pure ArkUI; Wearable is the only excluded device). [M]

---

## 3. Progress screen during generation

**Where:** `Index.createFrom()` sets `this.busy`; `generate()` (905) awaits `generateCapsule(text, options)` from `core/index.ets:241`, which has **no progress callback and no cancel handle today**. `GenerateResult.origin` (`'rules' | 'template' | 'on-device' | cloud origins`) says where the result came from only after the fact. The Create button already shows `LoadingProgress` and a shimmer overlay [A Index.ets:1584, 1623].

**Components**

| Component | API | Since | Evidence |
|---|---|---|---|
| `LoadingProgress` | `LoadingProgress().color(c).enableLoading(bool)`; animation stops when not visible | 8 / 10 | [M refs/ts-basic-components-loadingprogress.md] [A] |
| `Progress` | `Progress({ value, total?, type?: ProgressType })`; types `Linear, Ring, Eclipse` [M], `ScaleRing, Capsule` ([M] by section names `ScaleRingStyleOptions`, `CapsuleStyleOptions`) | 7/8 | [M refs/ts-basic-components-progress.md] |
| Indeterminate ring | `.style({ status: ProgressStatus.LOADING })` on a `Ring` progress (10+); switching back to `PROGRESSING` ends the loop | 10 | [M] |
| Scan light | `.style({ enableScanEffect: true })` on `Linear`, `Ring`, `Capsule` | 10 | [M] |
| Capsule text | `.style({ content: 'Thinking', showDefaultPercentage: false })` on `Capsule` | 10 | [M] |
| Smooth value | `enableSmoothEffect` default true | 10 | [M] |
| `ProgressButtonV2` | `import { ProgressButtonV2, LengthMetrics } from '@kit.ArkUI'`; `ProgressButtonV2({ progress, content, isEnabled, onClicked, progressButtonWidth?, colorOptions?, progressButtonRadius? })`, `progress` 0-100 | 18 | [M refs/ohos-arkui-advanced-progressbuttonv2.md] |
| `ProgressButton` (V1) | `ProgressButton({ progress, content, enable, clickCallback, ... })` | 10 | [M refs/ohos-arkui-advanced-progressbutton.md] |
| Skeleton | No system skeleton component found in the mirror. Build from rounded `Column`s plus a moving `linearGradient` (the app's `shimmer()` builder does exactly this) or an opacity pulse via `this.getUIContext().animateTo({ iterations: -1 }, …)` | - | [A Index.ets:1623]; "no system component" is absence of evidence |
| Step list | `ForEach` over a `@Local steps: StepRow[]`; per row `if (state === 'done') SymbolGlyph($r('sys.symbol.checkmark_circle')) else if (state === 'active') LoadingProgress()`; `.transition(TransitionEffect.OPACITY)` | - | symbols [A]; pattern [U] |

**Staged list, honest about where work runs** (V2):

```ts
type StepState = 'todo' | 'active' | 'done' | 'skipped';
interface StepRow { id: string; label: string; state: StepState; }

@Local steps: StepRow[] = [];

private setStep(id: string, state: StepState): void {
  this.steps = this.steps.map((s: StepRow): StepRow => {
    const next: StepRow = { id: s.id, label: s.label, state: s.id === id ? state : s.state };
    return next;
  });
}

@Builder
stepList() {
  Column({ space: 12 }) {
    ForEach(this.steps, (s: StepRow) => {
      Row({ space: 10 }) {
        if (s.state === 'active') {
          LoadingProgress().width(20).height(20).color($r('sys.color.brand'))
        } else {
          SymbolGlyph(s.state === 'done' ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.pause'))
            .fontSize(20).fontColor([$r('sys.color.icon_secondary')])
        }
        Text(s.label).fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
      }.width('100%')
    }, (s: StepRow) => s.id + s.state)
  }
}
```

Honesty rules for the labels: the real order is rules, template match, on-device model, then cloud **only if** `allowCloud` (smart mode + consent) [A Index.ets:858-918]. Show "On this phone" while the local stages run, and only show a "Cloud" row as active once a cloud request has actually started. That needs a callback added to `GenerateOptions` (e.g. `onStage?: (stage: string) => void`) and invoked in `core/CapsuleGenerator.ets`; do not fake stages with timers. Mark the cloud row `skipped` when the result's `origin` is local.

**Cancel**

- `httpRequest.destroy(): void` "terminates the HTTP request task and releases resources". [M refs/js-apis-http.md] The awaiting `request()` promise then rejects; the exact error code is [U], so treat any rejection after a cancel as "cancelled".
- Today the request object is local to `NetworkTransport.post` (`core/index.ets:66-84`, destroyed in `finally`). To cancel, keep it in a field and expose `cancel()`:

```ts
class NetworkTransport implements HttpTransport {
  private current: http.HttpRequest | null = null;

  cancel(): void {
    this.current?.destroy();
    this.current = null;
  }
  // in post(): this.current = req; ... finally { req?.destroy(); if (this.current === req) { this.current = null; } }
}
```

- On-device inference (`complete()` from the `cactus` module) has no cancel. Use a generation counter: `const run = ++this.runId; const r = await this.generate(...); if (run !== this.runId) { return; }`. DIGEST section 3 asks for this stale-result check anyway.
- Timeouts: `connectTimeout` and `readTimeout` both default to 60000 ms [M]; the app passes its own `timeoutMs`.

**UI freezes / threads**

- The Cactus NAPI wrapper already runs off the main thread: `initModel` and `complete` use `napi_create_async_work` + a promise (`cactus/src/main/cpp/napi_init.cpp:115-119, 205-209`). **No TaskPool needed for inference.** What can still jank is main-thread work around it: big `JSON.parse`, validation, prompt building.
- TaskPool basics if needed [M guides/taskpool-introduction.md, guides/serializable-overview.md, refs/js-apis-taskpool.md]: `import { taskpool } from '@kit.ArkTS'`; task function must be top-level, marked `@Concurrent`, in a `.ets` file; `taskpool.execute(func: Function, ...args: Object[]): Promise<Object>` or `new taskpool.Task(func, ...args)` + `taskpool.execute(task)`; `taskpool.cancel(task)`.
- What crosses the boundary: primitives, plain objects and arrays (copied by serialisation), `ArrayBuffer` (transferred by default; `task.setCloneList([buf])` to copy), `SharedArrayBuffer`, `@Sendable` classes. Class instances **with methods** must be `@Sendable` (API 11+). `@State`/`@Prop`/`@Link`-decorated complex values are not supported; assume the same for `@Local`/`@Trace` objects and pass plain copies ([U] for V2). 16 MB per transfer. Task CPU time limit 3 minutes (async waits not counted). [M]
- `@Concurrent` functions can only use their arguments, locals and imports ([U], the "decorator usage" table was not read).

```ts
import { taskpool } from '@kit.ArkTS';

@Concurrent
function parseBig(text: string): Object {
  return JSON.parse(text) as Object;
}

async function parseOffMain(text: string): Promise<Object> {
  return taskpool.execute(parseBig, text);
}
```

**Emulator:** UI components fine. On-device model speed on the emulator is not representative ([M guides/ide-emulator-specification.md]: emulator is not for performance testing; some AI kits need NPU).

---

## 4. QR scan to add a device, quick-scan button, deep links

**What exists** [A]: `sharing/ImportFlow.ets` `scanAndPrepare(context)` calls `scanBarcode.startScanForResult(context, { scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: false })`, handles cancel code `1000500002`, and returns `pairCode` when `pairCodeFromQr()` (`adapters/DeviceRelay.ets:69`, regex based, unit-tested in `entry/src/test/DeviceRelay.test.ets`) matches `https://<host>/pair?code=...`. `Index.pairScan()` (416) and `claimDevice()` (428) finish the pairing. `DevicePanel.ets` has `@Event onPairScan`. The Capsules tab header already has `SharingBar({ compact: true, onPairCode, onImported })`.

**Scan Kit**

| | Default UI | Custom UI |
|---|---|---|
| Module | `import { scanBarcode, scanCore } from '@kit.ScanKit'` | `import { customScan } from '@kit.ScanKit'` |
| Call | `startScanForResult(context: common.Context, options?: ScanOptions): Promise<ScanResult>` (also callback forms) | `customScan.init(options)`, `start(viewControl)` on an `XComponent`, `stop()`, `release()`, `rescan()` |
| Camera permission | **None.** Scan Kit pre-authorises the system camera | **`ohos.permission.CAMERA`** (user_grant) must be declared and requested |
| Since | 4.0.0(10); Phone 5.0.0(12)+ per live page | see page |
| Emulator | Supported from API 6.0.0(20). Camera stream is mirrored and letterboxed | Partly from API 20: `init, start, stop, release, rescan` only, 1280x720 only |
| Evidence | [M refs/scan-scanbarcode-api.md, guides/scan-scanbarcode.md] [L] | [M refs/scan-customscan-api.md, guides/scan-customscan.md, guides/scan-introduction.md] |

- `ScanOptions`: `scanTypes?: Array<scanCore.ScanType>` (default ALL; from 6.1.0(23) the title text follows this), `enableMultiMode?` (default false), `enableAlbum?` (**default true**). [M]
- `ScanResult`: `scanType`, `originalValue: string`, optional `scanCodeRect`, `cornerPoints`, `isGS1` (22+), `source` (22+, camera vs album). Default UI does not return the code position. [M]
- Errors: `401` parameter, `1000500001` internal, `1000500002` user cancelled (5.0.0(12)+). [M]
- **Deprecated:** `scanBarcode.startScan(...)` (all three overloads) since 4.1.0(11); use `startScanForResult`. [M] [L]
- Emulator has no image decode (`detectBarcode.decode` is listed as supported in its own guide, but `scan-introduction.md` says image recognition and code generation are not supported; treat album/`decodeImage` and `generateBarcode` as unavailable). The emulator camera depends on the PC webcam or the virtual camera feature [M guides/ide-emulator-specification.md]; repo table says "Real camera hardware: no".

Stick with the default UI. Nothing to add to `module.json5`.

**Quick-scan button (top right).** The app hides the system title bar and draws its own header rows, with a ready-made builder `Index.iconButton(icon: Resource, action: () => void)` (line ~1512, used in `detail()` at 2192). Add it to the header `Row` in `home()` (line ~1871) after a `Blank()`:

```ts
Row({ space: 8 }) {
  Image($r('app.media.harmoniser_mark')).width(28).height(28)
  Text('Harmoniser').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
  Blank()
  this.iconButton($r('sys.symbol.camera'), () => {
    this.pairScan();
  })
}
.width('100%')
.height(44)
```

`pairScan()` only handles pairing codes; for a general quick scan call `scanAndPrepare(this.ctx)` and branch on `outcome.pairCode` / `outcome.result` the way `SharingBar` does. A QR-specific symbol name was not found in the mirror or the app; `sys.symbol.camera` is in use already. If the system title bar is ever switched on instead: `Navigation.menus(value: Array<NavigationMenuItem> | CustomBuilder)`, `NavDestination.menus(...)` (12+); `NavigationMenuItem { value: string | Resource; icon?: string | Resource; symbolIcon?: SymbolGlyphModifier (12+); isEnabled? (12+); action?: () => void }`; text is not shown from API 10. [M refs/ts-basic-components-navigation.md, refs/ts-basic-components-navdestination.md]

**URL parsing** [M refs/js-apis-url.md]: `import { url } from '@kit.ArkTS'`; `static parseURL(url: string, base?: string | URL): URL` (API 9), throws `BusinessError` `10200002 Invalid url string`. Fields `protocol`, `host`, `hostname`, `pathname`, `params: URLParams` (9+; `params.get(name): string | null`). **Deprecated:** `new url.URL(...)` constructor, `URL.searchParams`, `URLSearchParams` (API 9); use `parseURL`, `params`, `URLParams`.

```ts
import { url } from '@kit.ArkTS';

export function pairCodeFromLink(text: string): string {
  try {
    const u: url.URL = url.URL.parseURL(text.trim());
    const isHttp = u.protocol === 'https:' || u.protocol === 'http:';
    const isCustom = u.protocol === 'harmoniser:' && u.hostname === 'pair';
    const path = u.pathname.replace(new RegExp('/+$'), '');
    if (!(isCustom || (isHttp && path === '/pair'))) {
      return '';
    }
    return u.params.get('code') ?? '';
  } catch (e) {
    return '';
  }
}
```

The existing regex `pairCodeFromQr` is covered by local unit tests; whether `@kit.ArkTS` `url` is available under the local test runner is unknown, so keep the regex in `adapters/` and use `parseURL` only in ability/UI code, or route both through `normalizePairCode()`.

**Deep link (custom scheme): doable tonight.** [M guides/deep-linking-startup.md] [L]
Add a **separate** skill object (never extend the home skill; one object per jump scenario or the config does not take effect). `actions` must not be empty.

```json5
// module.json5 -> abilities[0].skills, as a third object
{
  "actions": ["ohos.want.action.viewData"],
  "uris": [
    { "scheme": "harmoniser", "host": "pair" }
  ]
}
```

Handle it next to the existing `takeWidgetWant` / `takeShareWant` in `EntryAbility.onCreate(want, launchParam)` (cold start) and `onNewWant(want, launchParam)` (already running) [M refs/js-apis-app-ability-uiability.md]. The link is `want.uri`:

```ts
// entryability/EntryAbility.ets
private takePairWant(want: Want): void {
  const link = want.uri ?? '';
  if (link.length === 0) {
    return;
  }
  const code = pairCodeFromLink(link);
  if (code.length > 0) {
    AppStorage.setOrCreate<string>('pendingPairCode', code); // Index reads and clears it in onPageShow
  }
}
```

Match the hand-off style of `pages/WidgetLaunch.ets` / `ShareLaunch.ets` rather than `AppStorage` if those use a module-level holder (they do: `widgetLaunch()`, `shareLaunch()`). Then `Index.onPageShow()` calls `this.claimDevice(code)`.

**https links / App Linking: not realistic tonight.** [M guides/app-linking-startupapp.md]
Requirements: App Linking service enabled in AppGallery Connect; `https://<domain>/.well-known/applinking.json` listing the app's `appIdentifier` (the AGC APP ID); the domain created under AGC "Growth > App Linking" and published (re-verified every 24 h); and in `module.json5` a separate skill with `entities: ["entity.system.browsable"]`, `actions: ["ohos.want.action.viewData"]`, `uris: [{ scheme: "https", host: "<domain>", path?: "pair" }]`, `"domainVerify": true`. Phone/Tablet/PC, HarmonyOS 5.0.0(12)+. App Linking Kit says it supports the emulator [M guides/applinking-introduction.md], but it needs a real AGC app and signing.
Without domain verification, an `https` `uris` skill is only a Deep Link: another app can reach it with `context.openLink(link, { appLinkingOnly: false })` or an implicit `startAbility`, and a chooser appears if several apps match. Whether the system browser or camera would hand a plain https link to the app is not documented; assume not.
"Scan from the system scanner straight into the app" (`guides/scan-directservice.md`) is built on App Linking and is **mainland China only**. [M]
Realistic demo path: the in-app quick-scan button. The relay's `/pair` web page can additionally offer a `harmoniser://pair?code=…` link.

**Emulator:** default scan UI works from API 20 (mirrored image). Deep link can be exercised with `hdc shell aa start -U "harmoniser://pair?code=..."` ([U] flag syntax).

---

## 5. Per-capsule "Add to home screen"

**Where:** `Index.routeCard(entry)` (line 2122). Its `else if (entry.route.widget)` branch currently shows long-press instructions. `widget/WidgetService.ets:293` already has `openHarmoniserManager(bundleName)` (unused). Provider: `widget/HarmoniserFormAbility.ets`. Form: `harmoniser`, module `entry`, sizes `2*2` (default) and `2*4` [A form_config.json].

Both routes in `docs/WIDGET_RESEARCH.md` are confirmed.

**`AddFormMenuItem`** [M refs/ohos-arkui-advanced-formmenu.md] (live page timed out; not [L])
- `import { AddFormMenuItem } from '@kit.ArkUI'`; `AddFormMenuItem(want: Want, componentId: string, options?: AddFormOptions): void`; `@Builder`; API 12; not on Wearable; **no universal attributes**; must sit inside a `Menu() { }`.
- `want`: `bundleName`, `abilityName`, `parameters` with `'ohos.extra.param.key.form_dimension'` (number), `'ohos.extra.param.key.form_name'`, `'ohos.extra.param.key.module_name'`.
- `componentId`: the `.id()` of an in-app component that looks like the widget; the system snapshots it for the fly-to-home animation.
- `AddFormOptions`: `formBindingData?: formBindingData.FormBindingData` (initial card data), `callback?: AsyncCallback<string>` (`error.code === 0` success, value is the `formId`; non-zero: see form error codes), `style?: { options?: MenuItemOptions }` (`startIcon`, `content`, `endIcon`; defaults `sys.media.ic_public_add` and `sys.string.ohos_add_form_to_desktop` apply only when `style` is absent).
- The page says: from API 18, `formProvider.openFormManager` is recommended. `AddFormMenuItem` is **not** marked deprecated.

**`formProvider.openFormManager`** [M refs/js-apis-app-form-formprovider.md, guides/arkts-ui-widget-open-formmanager.md] [L both]
- `import { formProvider } from '@kit.FormKit'`; `openFormManager(want: Want): void`; API 18; synchronous, throws.
- Same three parameter keys. Incomplete parameters or an unknown form name show the default form from `form_config.json`.
- Errors: `16500050` IPC connection error, `16500100` failed to obtain configuration, `16501000` internal functional error (also what Wearable returns).
- User sees the app's widget manager page and taps "Add to home screen".

**Keys and dimension values** [M refs/js-apis-app-form-forminfo.md]: `formInfo.FormParam.IDENTITY_KEY` = `'ohos.extra.param.key.form_identity'`, `DIMENSION_KEY` = `'ohos.extra.param.key.form_dimension'`, `NAME_KEY` = `'ohos.extra.param.key.form_name'`, `MODULE_NAME_KEY` = `'ohos.extra.param.key.module_name'`, `PARAM_FORM_CUSTOMIZE_KEY` (10+) = `'ohos.extra.param.key.form_customize'` ("custom data", no further description), `ORIGINAL_FORM_KEY` (20+) = `'ohos.extra.param.key.original_form_id'`. `formInfo.FormDimension`: `Dimension_1_2`=1, `Dimension_2_2`=2, `Dimension_2_4`=3, `Dimension_4_4`=4, `DIMENSION_6_4`=7; `Dimension_2_1`=5 is **deprecated from API 20**.

**Do custom want parameters reach `onAddForm`?** Not confirmed. The `onAddForm(want)` reference only says `want.parameters` "are custom values and may include one or more `FormParam` entries". Nothing states that extra keys passed to `AddFormMenuItem` or `openFormManager` are forwarded by the launcher. Keep the "pending slot" design from `WIDGET_RESEARCH.md` section 4 as the binding mechanism, and read `want.parameters['capsuleId']` only as a bonus.

**Corrected snippet** (V2, in `Index`; typed `Record` for parameters, enum instead of magic numbers, bundle name from context):

```ts
import { AddFormMenuItem } from '@kit.ArkUI';
import { formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

private formWant(capsuleId: string, dimension: formInfo.FormDimension): Want {
  const params: Record<string, Object> = {
    'ohos.extra.param.key.form_dimension': dimension,
    'ohos.extra.param.key.form_name': 'harmoniser',
    'ohos.extra.param.key.module_name': 'entry',
    'capsuleId': capsuleId                    // may not arrive; the pending slot is the real binding
  };
  const want: Want = { bundleName: this.ctx?.abilityInfo.bundleName ?? '', abilityName: 'HarmoniserFormAbility',
    parameters: params };
  return want;
}

@Builder
addWidgetMenu(entry: CapsuleEntry) {
  Menu() {
    AddFormMenuItem(this.formWant(entry.capsule.id, formInfo.FormDimension.Dimension_2_2),
      'capsule-card-' + entry.capsule.id, {
        formBindingData: formBindingData.createFormBindingData(''),
        callback: (error: BusinessError, formId: string) => {
          this.onWidgetAdded(entry, error?.code ?? -1, formId);
        },
        style: { options: { content: 'Add small widget' } }
      })
  }
}
// Button('Add to home screen').onClick(() => putPending(...)).bindMenu(this.addWidgetMenu(entry))
```

Notes on the snippet: the official sample passes `createFormBindingData({})` and leaves the callback parameters untyped; `{}` as an untyped literal may trip strict mode, hence `''` here (the function accepts `Object | string`, [U]). Passing the real initial view (`bindingData(...)`-style JSON under key `view`) would make the card render immediately. `this.ctx` is the `UIAbilityContext` field `Index` already uses in `pairScan()`. `onWidgetAdded` is yours to write: on code 0 clear the pending slot, toast, `loadWidgets()`; otherwise fall back to `openHarmoniserManager(bundleName)`. Give the capsule preview `.id('capsule-card-' + entry.capsule.id)`. Write the pending slot **before** the menu opens (the button's `onClick` fires along with `bindMenu`; ordering is [U], so writing it when the capsule page opens is safer).

**`resizable` and `onSizeChanged`**
- `form_config.json` form field `"resizable": true` (API 20+, default false): the user can drag to resize among this form's `supportDimensions` (or those of forms sharing a `groupId`). [M guides/arkts-ui-widget-configuration.md]
- `FormExtensionAbility.onSizeChanged(formId: string, newDimension: formInfo.FormDimension, newRect: formInfo.Rect): void` (API 20+). [M refs/js-apis-app-form-formextensionability.md] Also `onFormLocationChanged` (20+).
- With `groupId` across **different** forms, a resize creates a new form and deletes the old one; the new `onAddForm` want carries the old id under `ORIGINAL_FORM_KEY`. [M] For this app (one form, two sizes) expect `onSizeChanged`, but handle `ORIGINAL_FORM_KEY` in `onAddForm` too in case the launcher takes the create-and-delete path (not confirmed which).

```ts
// widget/HarmoniserFormAbility.ets
onSizeChanged(formId: string, newDimension: formInfo.FormDimension, newRect: formInfo.Rect): void {
  const wide = newDimension === formInfo.FormDimension.Dimension_2_4;
  hilog.info(DOMAIN, TAG, 'onSizeChanged %{public}s wide=%{public}s', formId, String(wide));
  // update the stored binding's `wide`, then push a fresh view with formProvider.updateForm(formId, bindingData(...))
}
```

Other provider facts worth knowing: the FormExtensionAbility is cleaned up after 10 s idle [M]; `formProvider.getPublishedRunningFormInfos()` is API 20+; `getPublishedFormInfoById` / `getPublishedFormInfos` are **deprecated from API 20** (use the `Running` variants) [L]; `formProvider.reloadForms` / `reloadAllForms` are API 22+ [L].

**Emulator:** repo table lists widgets as supported. Whether the emulator launcher honours `AddFormMenuItem` and `openFormManager` was not found in the docs.

---

## 6. "Hide Install when already installed", publish description and tags

Nothing platform-specific. Patterns:

- Conditional button: plain `if/else` in the builder (removes the node), or `.visibility(cond ? Visibility.Visible : Visibility.None)` (keeps state), or `.enabled(false)` with a changed label. `if/else` is what the app does everywhere.
- **Where:** `MarketplaceView.card(item)` line ~62 (`Button('Install', { controlSize: ControlSize.SMALL })`). Add `@Param installedIds: string[] = []` and pass it from both call sites in `Index` (`mainTabs()` and `pageMap()`).
- Catch: `Index.installFromMarket()` runs the capsule through `uniqueCapsule()`, so the installed capsule's id is **not** `MarketItem.id`. There is a `pendingMarketItem` field; check what `decide()` stores from it (e.g. on `CapsuleEntry`) before choosing the lookup key. If nothing is stored, add a `marketId` to the stored entry.

```ts
// MarketplaceView.ets (V2)
@Param installedIds: string[] = [];

// inside card(item: MarketItem), replacing the Install button:
if (this.installedIds.includes(item.id)) {
  Text('Installed')
    .fontSize($r('sys.float.Body_M'))
    .fontColor($r('sys.color.font_tertiary'))
} else {
  Button('Install', { controlSize: ControlSize.SMALL })
    .onClick(() => this.onInstall(item))
}
```

- Tag input: `TextInput` + `onSubmit` appends, chips with a close icon remove. Replace the array rather than mutating it (matches the app's style and always triggers `@Local`).

```ts
@Local tags: string[] = [];
@Local tagDraft: string = '';

@Builder
tagEditor() {
  Column({ space: 8 }) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.tags, (t: string) => {
        Chip({ label: { text: t }, size: ChipSize.SMALL, allowClose: true,
          onClose: () => {
            this.tags = this.tags.filter((x: string) => x !== t);
          } })
      }, (t: string) => t)
    }
    TextInput({ placeholder: 'Add a tag', text: this.tagDraft })
      .maxLength(20)
      .enterKeyType(EnterKeyType.Done)
      .onChange((v: string) => {
        this.tagDraft = v;
      })
      .onSubmit((key: EnterKeyType, event: SubmitEvent) => {
        const t = this.tagDraft.trim().toLowerCase();
        if (t.length > 0 && !this.tags.includes(t) && this.tags.length < 5) {
          this.tags = this.tags.concat([t]);
        }
        this.tagDraft = '';
        event.keepEditableState();
      })
  }
}
```

`TextInput.onSubmit((enterKey, event: SubmitEvent) => void)` and `SubmitEvent.keepEditableState()`/`.text` are API 11 [M refs/ts-basic-components-textinput.md]. `maxLength` API 10, `inputFilter(regex)` API 8 exist on TextArea [M]; same on TextInput is [U]. Description field: `TextArea().maxLength(n).showCounter(true)` (10+) [M]. `Flex({ wrap: FlexWrap.Wrap })` is already used at Index.ets:1773.

**Emulator:** fine.

---

## 7. Layered app icon

**Current state** [A]: `AppScope/app.json5` `"icon": "$media:layered_image"`; `AppScope/resources/base/media/layered_image.json` = `{ "layered-image": { "background": "$media:background", "foreground": "$media:foreground" } }` with `background.png` (1024x1024 RGB) and `foreground.png` (1024x1024 RGBA). The same three files exist under `entry/src/main/resources/base/media/`, and `module.json5` has `"icon": "$media:layered_image"`, `"startWindowIcon": "$media:startIcon"` (`startIcon.png` 1024x1024), `"startWindowBackground": "$color:start_window_background"`. So the layered icon is already wired correctly; a new icon means replacing the PNGs.

**Rules** [M guides/layered-image.md] [L]

- A layered icon is a JSON file in a `media` folder with a `layered-image` object holding `background` and `foreground` media references. Referenced as `$media:<json name without extension>`.
- Two places: `AppScope/resources/base/media` + `app.json5` `icon`, or `entry/src/main/resources/base/media` + `module.json5` ability `icon`.
- Precedence: the entry UIAbility's `icon`/`label` win (the ability whose skill has `entity.system.home` + `ohos.want.action.home`); `app.json5` is used when the ability sets none.
- At build time AppScope resources are merged into the module; **on a name clash the AppScope file overwrites the module's**. Both sets here are named identically, so the AppScope PNGs are the ones that ship. Replace both copies (or at least AppScope) to avoid confusion.
- Sizes: foreground and background **1024 x 1024 px** each. Recommended by the Image Asset wizard [M guides/ide-apply-generated-icon.md]; stated as required for store review, along with "do not cut rounded corners yourself, do not add inner padding in the resource" [M guides/ide-app-analyzer-ag-policy.md]. The system applies the mask.
- DevEco: right-click module > New > Image Asset generates the layered set and the start window icon (has Trim and Resize sliders). [M]
- `startWindowIcon` is mandatory on a UIAbility; it is a plain image reference. From API 19 a `startWindow` profile can replace `startWindowIcon` + `startWindowBackground`. [M guides/module-configuration-file.md] Whether `startWindowIcon` may point at a layered-image JSON is not stated; keep a flat PNG.
- Alternate icons (`bundleManager.setAlternateIcon`) are 26.0.0+: not available. [L]

**Widget icon.** `form_config.json` has no icon field. Per-form fields are `name`, `displayName` (max 30 bytes, shown in the widget manager), `description` (max 255 bytes), `src`, `window`, `isDefault`, `supportDimensions`, `defaultDimension`, update fields, `formConfigAbility`, `previewImages` (**wearables only**), `renderingMode`, `resizable`, `groupId`, etc. [M guides/arkts-ui-widget-configuration.md] The widget manager shows the app icon and a live render of the card, so "widget icon" = app icon + what the card draws.

**Could not confirm:** the exact safe-zone / keyline measurements. They live in the design guide (`design-guides/application-icon-0000001953444009`), which is not in the mirror and was not fetched. A third-party page quotes other numbers; ignore it.

**Emulator:** fine.

---

## 8. Polish of capsule "focus" pages

**Where:** `Index.detail(entry)` (line 2190) is the focus page; it is not a `NavDestination` but an `if (this.openEntry())` swap inside the root `Stack` (`build()`, 2288). `card()` (1816) and `detail()` both carry `.geometryTransition(entry.capsule.id)` [A 1861, 2284]. `open()`/`close()` (1059/1071) flip `openId`. Sub-pages (`LOG_PAGE`, `CHOOSE_PAGE`, `MARKET_PAGE`, `SETTINGS_PAGE`) go through `this.nav.pushPath` and `pageMap`.

**Transitions**

| API | Notes | Evidence |
|---|---|---|
| `geometryTransition(id: string)` (7+), `geometryTransition(id: string, options?: { follow?: boolean })` (11+) | Same id on the outgoing and incoming component; the state change **must run inside `animateTo`** to animate. `follow: true` is for a component that stays in the tree under an `if` | [M refs/ts-transition-animation-geometrytransition.md, guides/arkts-shared-element-transition.md] |
| `this.getUIContext().animateTo(value, event)` | Global `animateTo` is deprecated from API 18; the app already uses the UIContext form | [A Index.ets:1633], DIGEST 3 |
| `.transition(TransitionEffect.OPACITY)` etc. | enter/exit of `if` branches | [A Index.ets:1918] |
| `NavDestination.systemTransition(type: NavigationSystemTransitionType)` | 14+. `DEFAULT, NONE, TITLE, CONTENT` (14), `FADE, EXPLODE, SLIDE_RIGHT` (15), more values exist | [M refs/ts-basic-components-navdestination.md] |
| `Navigation.customNavContentTransition(delegate)` | 11+, full custom push/pop animation | [M refs/ts-basic-components-navigation.md] |
| `sharedTransition` | page-router shared element; belongs to `router`, which is not the app's navigation. Skip | [M refs/ts-transition-animation-shared-elements.md exists; content not read] |

```ts
private open(id: string): void {
  if (reduceMotion()) {
    this.openId = id;
    return;
  }
  this.getUIContext().animateTo({ curve: springCurve(), duration: 350 }, () => {
    this.openId = id;     // card and detail share .geometryTransition(entry.capsule.id)
  });
}
```

(`reduceMotion()` and `springCurve()` are in `pages/Motion.ets`. Check what `open()` already does before replacing it.)

**System tokens**

Used in the app today, so they resolve in this SDK [A]:
- Colour: `sys.color.font_primary`, `font_secondary`, `font_tertiary`, `font_on_primary`, `brand`, `icon_primary`, `icon_secondary`, `background_secondary`, `comp_background_primary`, `comp_background_tertiary`, `comp_divider`.
- Float: `sys.float.Body_L`, `Body_M`, `Caption_M`, `Subtitle_M`, `Title_S`.
- Symbols: `sys.symbol.plus_circle, square_grid_2x2, bag, gearshape, camera, chevron_left, chevron_up, chevron_down, doc_text, checkmark, checkmark_circle, xmark, arrow_up, arrow_down_circle, trash, timer, alarm, bell, cloud, lock, pin, pause, play_fill, stop_circle, wand_and_stars, list_bullet, plus, watch, flag, square_and_arrow_down`.

Additionally named in official pages in the mirror (existence in this SDK not compiled) [M, grep across guides/refs]:
- Colour: `sys.color.background_primary`, `background_tertiary`, `comp_background_secondary`, `comp_background_emphasize`, `comp_background_list_card`, `comp_background_gray`, `font_emphasize`, `font_on_secondary`, `font_fourth`, `icon_emphasize`, `icon_on_primary`, `icon_tertiary`, `icon_fourth`, `mask_secondary`, `warning`, `confirm`, `interactive_pressed`, `interactive_hover`, `interactive_focus`, `multi_color_08`.
- Float: `sys.float.Body_S`, `Title_M`, `Caption_L`, `Display_L`, `padding_level1/2/4/8/12/16/24`, `corner_radius_level10`, `corner_radius_level12`.
- Older `sys.color.ohos_id_*` / `sys.float.ohos_id_*` names appear as component defaults; prefer the short names above.

**Dark mode.** `resources/dark/element/color.json` exists with `start_window_background` and `hero_top`, mirroring `base/` [A]. `EntryAbility.onCreate` sets `COLOR_MODE_NOT_SET` (follow system) [A]. Add any new app colour to both files. Not dark-safe today: literals in `inputCard()` (`'#335B8CFF'`, `'#14000000'`) and `shimmer()` (`'#55FFFFFF'`). Guide: [M guides/ui-dark-light-color-adaptation.md].

**HarmonyOS Design System (UI Design Kit).** Public: `import { HdsNavigation, HdsNavDestination, HdsTabs, HdsActionBar, HdsSnackBar, HdsListItem, … } from '@kit.UIDesignKit'`. `HdsNavigation`/`HdsNavDestination` since 5.1.0(18); `HdsTabs`, `HdsActionBar`, `HdsSnackBar`, `HdsVisualComponent` since 6.0.0(20). Emulator supported with differences. [M refs/ui-design-hdsnavigation.md and siblings, guides/ui-design-introduction.md]
**Recommendation: do not adopt tonight.** The kit's constraints section says it is "currently only supported in mainland China (excluding Hong Kong, Macao, Taiwan)" [M guides/ui-design-introduction.md]; what happens on a device or emulator image set to another region is not stated. It would also mean replacing the working `Navigation` + custom floating bar.

**Haptics.** `import { vibrator } from '@kit.SensorServiceKit'`. [M refs/js-apis-vibrator.md]
- `vibrator.startVibration(effect: VibrateEffect, attribute: VibrateAttribute): Promise<void>` (9+; callback overload too). **Needs `ohos.permission.VIBRATE`**: level normal, `system_grant`, so declaring it is enough; already in `module.json5`. [M guides/permissions-for-all.md] [A]
- Effects: `{ type: 'time', duration: ms }`; `{ type: 'preset', effectId, count?, intensity? (12+) }`; `{ type: 'file', … }`; `{ type: 'pattern', … }`.
- Preset ids seen on the page: `'haptic.clock.timer'` (EffectId), `'haptic.effect.soft'`, `'haptic.effect.hard'`, `'haptic.effect.sharp'`, `'haptic.notice.success'`, `'haptic.notice.fail'`, `'haptic.notice.warning'` (`HapticFeedback`, 12+). Check with `vibrator.isSupportEffectSync(effectId): boolean` (12+) first; presets vary by device.
- Attribute: `{ id?: number, usage: 'unknown' | 'alarm' | 'notification' | 'touch' | … }`; `usage` decides which system switch gates it.
- Stop: `vibrator.stopVibration(): Promise<void>` (10+), `stopVibrationSync()` (12+).
- The app's `successTick()` in `Motion.ets` uses `{ type: 'time', duration: 30 }`, `{ id: 0, usage: 'notification' }` and catches failures. Also available with no permission: `.enableHapticFeedback(true)` on text inputs (13+) [M textarea.md].
- **Emulator: the Vibrator module is not supported** [M guides/sensorservice-kit-intro.md]. Calls fail; keep the try/catch. Test on a real phone.

```ts
import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

export function tick(effectId: string): void {
  try {
    if (!vibrator.isSupportEffectSync(effectId)) {
      return;
    }
    const effect: vibrator.VibratePreset = { type: 'preset', effectId: effectId, count: 1 };
    const attr: vibrator.VibrateAttribute = { usage: 'touch' };
    vibrator.startVibration(effect, attr).catch((e: BusinessError) => {
      hilog.warn(0x0001, 'Motion', 'vibrate failed: %{public}d', e.code);
    });
  } catch (e) {
    hilog.warn(0x0001, 'Motion', 'vibrate unavailable');
  }
}
```

**Emulator:** transitions, tokens, dark mode fine. Vibration no.

---

## 9. Weather via Open-Meteo, and a real accelerometer

**Where:** new adapters next to `adapters/TimerAdapter.ets` / `NotificationAdapter.ets`; HTTP in the style of `adapters/MarketplaceClient.ets:185-205` and `core/index.ets:66-84` (one `http.createHttp()` per request, `req?.destroy()` in `finally`). Any capsule-facing capability must also pass the `gatekeeper/Gatekeeper.ets` permission model and `CapsuleValidator`.

**HTTP** [M refs/js-apis-http.md, guides/http-request.md]
- `import { http } from '@kit.NetworkKit'`; `http.createHttp(): HttpRequest`; `request(url: string, options?: HttpRequestOptions): Promise<HttpResponse>`; `destroy(): void`.
- Options: `method`, `header`, `extraData`, `connectTimeout` (default 60000 ms), `readTimeout` (default 60000 ms, 0 = never), `expectDataType` (9+; `OBJECT` capped at 65536 chars, so ask for `STRING` and parse), `usingCache` (9+, default **true**; set `false` for live weather), `maxLimit` (11+, default 5 MB, max 100 MB).
- `ohos.permission.INTERNET`: normal, `system_grant`; already declared. Error `2300028` = operation timeout.
- Open-Meteo itself is a third-party API; the endpoint and field names below are [U]. Verify with one curl before coding.

```ts
import { http } from '@kit.NetworkKit';

interface MeteoCurrent { temperature_2m: number; weather_code: number; }
interface MeteoReply { current?: MeteoCurrent; }
export interface Weather { ok: boolean; tempC: number; code: number; error: string; }

export async function fetchWeather(lat: number, lon: number): Promise<Weather> {
  const fail: Weather = { ok: false, tempC: 0, code: 0, error: 'Weather unavailable' };
  let req: http.HttpRequest | null = null;
  try {
    req = http.createHttp();
    const u = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weather_code`;
    const resp = await req.request(u, { method: http.RequestMethod.GET, connectTimeout: 8000, readTimeout: 8000,
      usingCache: false, expectDataType: http.HttpDataType.STRING });
    if (resp.responseCode !== 200 || typeof resp.result !== 'string') {
      return fail;
    }
    const reply = JSON.parse(resp.result) as MeteoReply;
    const cur = reply.current;
    if (cur === undefined || typeof cur.temperature_2m !== 'number' || typeof cur.weather_code !== 'number') {
      return fail;
    }
    const ok: Weather = { ok: true, tempC: cur.temperature_2m, code: cur.weather_code, error: '' };
    return ok;
  } catch (e) {
    return fail;
  } finally {
    req?.destroy();
  }
}
```

**Location** [M refs/js-apis-geolocationmanager.md, guides/location-permission-guidelines.md, guides/location-kit-intro.md]
- `import { geoLocationManager } from '@kit.LocationKit'`.
- `getCurrentLocation(request?: CurrentLocationRequest | SingleLocationRequest): Promise<Location>`; needs `ohos.permission.APPROXIMATELY_LOCATION`. Errors: `201` permission, `401` parameter, `801` not supported, `3301000` service unavailable, `3301100` **location switch off**, `3301200` failed to obtain location.
- `SingleLocationRequest` (12+): `{ locatingPriority: geoLocationManager.LocatingPriority, locatingTimeoutMs: number }` (min 1000). `LocatingPriority.PRIORITY_ACCURACY` = 0x501, `PRIORITY_LOCATING_SPEED` = 0x502 (first fix wins; right for weather).
- `isLocationEnabled(): boolean`; `getLastLocation(): Location`. `Location.latitude`, `.longitude` (WGS84).
- Permission: `ohos.permission.APPROXIMATELY_LOCATION` alone gives about **5 km** accuracy; with `ohos.permission.LOCATION` as well, metre-level; precise cannot be requested alone. Both are `user_grant` ([M] for the accuracy table; grant mode per DIGEST section 8): declare with `reason` (`$string:`) and `usedScene` like the calendar entries already in `module.json5`.
- `abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context: Context, permissionList: Array<Permissions>): Promise<PermissionRequestResult>`. [M refs/js-apis-abilityaccessctrl.md]
- `PermissionRequestResult` [M refs/js-apis-permissionrequestresult.md]: `permissions: string[]`; `authResults: number[]` with `0` granted, `-1` not granted, `2` invalid request (not declared, bad name, or special conditions unmet); `dialogShownResults?: boolean[]` (12+): `true` = the dialog was shown this time (so `-1` means the user just refused), `false` = no dialog was shown (so `-1` means it will not prompt again: send the user to Settings or call `requestPermissionOnSetting(context, permissionList): Promise<Array<GrantStatus>>`); `errorReasons?: number[]` (18+): 0 valid, 1 bad name, 2 not declared, 3 conditions unmet (location only), 4 privacy statement not agreed, 5 not requestable by dialog.

```ts
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';

export interface Fix { ok: boolean; lat: number; lon: number; reason: string; }

export async function approximateFix(ctx: common.UIAbilityContext): Promise<Fix> {
  const none: Fix = { ok: false, lat: 0, lon: 0, reason: 'denied' };
  const wanted: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION'];
  try {
    const r = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(ctx, wanted);
    if (r.authResults[0] !== 0) {
      const shown = r.dialogShownResults !== undefined && r.dialogShownResults[0];
      none.reason = r.authResults[0] === 2 ? 'not-declared' : (shown ? 'refused' : 'blocked-open-settings');
      return none;
    }
    if (!geoLocationManager.isLocationEnabled()) {
      none.reason = 'location-off';
      return none;
    }
    const req: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED, locatingTimeoutMs: 10000 };
    const loc = await geoLocationManager.getCurrentLocation(req);
    const fix: Fix = { ok: true, lat: loc.latitude, lon: loc.longitude, reason: '' };
    return fix;
  } catch (e) {
    none.reason = 'unavailable';
    return none;
  }
}
```

Always offer a manual-city fallback. Emulator: Location Kit supports the emulator; set the position from the emulator's GPS panel (manual lat/lon or city, or import a track) and read it with `geoLocationManager` [M guides/ide-emulator-more-features.md]. Repo table agrees (GPS simulated).

**Accelerometer** [M refs/js-apis-sensor.md, guides/permissions-for-all.md]
- `import { sensor } from '@kit.SensorServiceKit'`.
- `sensor.on(type: sensor.SensorId.ACCELEROMETER, callback: Callback<AccelerometerResponse>, options?: Options): void`; **needs `ohos.permission.ACCELEROMETER`** (level normal, `system_grant`: declare in `module.json5`, no prompt, no `reason`).
- `Options.interval`: number in **nanoseconds** (default 200000000 = 200 ms) or `'game'` (20 ms) / `'ui'` / `'normal'` (API 11+); clamped to the sensor's min/max period.
- `AccelerometerResponse`: `x`, `y`, `z` in m/s².
- `sensor.once(sensor.SensorId.ACCELEROMETER, callback)`; `sensor.off(sensor.SensorId.ACCELEROMETER, callback?)` (omit the callback to remove all). Unsubscribe in `aboutToDisappear` and on `onPageHide`; a live subscription keeps the sensor powered.
- Callbacks arrive on the main thread at the chosen rate: do not write `@Local`/`@Trace` state on every sample at `'game'` rate; throttle or threshold.

```ts
import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class ShakeWatcher {
  private handler: (data: sensor.AccelerometerResponse) => void = () => {};
  private active: boolean = false;

  start(onShake: () => void): boolean {
    this.handler = (data: sensor.AccelerometerResponse) => {
      const g = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z);
      if (g > 20) {
        onShake();
      }
    };
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, this.handler, { interval: 'ui' });
      this.active = true;
    } catch (e) {
      hilog.warn(0x0001, 'Shake', 'sensor.on failed: %{public}d', (e as BusinessError).code);
    }
    return this.active;
  }

  stop(): void {
    if (this.active) {
      sensor.off(sensor.SensorId.ACCELEROMETER, this.handler);
      this.active = false;
    }
  }
}
```

**Emulator, accelerometer: sources disagree.**
- Mirror: the Sensor module "supports the emulator, with differences"; the emulator's virtual-sensor panel lists only **pedometer, ambient light, heart rate**. Separately the toolbar has a **shake** button that simulates a 1-second shake, which apps observe through the accelerometer (phone and tablet only). [M guides/sensorservice-kit-intro.md, guides/ide-emulator-more-features.md]
- Repo `hackathon-resources/emulator-capability-comparison.md`: "Basic sensor simulation (accelerometer, gyroscope, GPS)" supported on the DevEco emulator.
- Working assumption: on the emulator you get accelerometer events only from the shake button, not an adjustable tilt. A shake-style demo works; a tilt/level demo needs a real phone.

---

## Emulator API 24 summary

| Item | Emulator | Source |
|---|---|---|
| 1 Prompt bar, keyboard avoidance | Yes (nothing restricts it) | no explicit statement |
| 2 Chips | Yes | [M] not Wearable only |
| 3 Progress UI, http cancel | Yes; model speed not representative | [M guides/ide-emulator-specification.md] |
| 4 Default scan UI | Yes from API 20, mirrored and letterboxed; needs webcam or virtual camera | [M guides/scan-scanbarcode.md, scan-introduction.md] |
| 4 Custom scan | Partly from API 20 (5 calls, 1280x720) | [M] |
| 4 Image decode / QR generation | No | [M guides/scan-introduction.md] |
| 4 Deep link | Yes (plain Want matching) | [M]; App Linking Kit says emulator supported |
| 5 Widgets | Yes per repo table; in-app add APIs on the emulator launcher not documented | repo table |
| 6 Conditional UI, tag input | Yes | - |
| 7 Layered icon | Yes | - |
| 8 Transitions, tokens, dark mode | Yes | - |
| 8 HDS components | Emulator supported "with differences"; kit is mainland-China only | [M guides/ui-design-introduction.md] |
| 8 Vibration | **No** | [M guides/sensorservice-kit-intro.md] |
| 9 HTTP | Yes (no VPN) | [M guides/net-mgmt-overview.md] |
| 9 Location | Yes, position from the GPS panel | [M guides/ide-emulator-more-features.md] |
| 9 Accelerometer | Shake button only per mirror; repo table says simulated | conflict, see section 9 |

## Deprecated in API 18-24 (touching these features)

| Deprecated | Since | Use instead | Evidence |
|---|---|---|---|
| Global `animateTo`, `router`, `promptAction`, `getContext()` | 18 | `this.getUIContext().animateTo / getRouter / getPromptAction / getHostContext` | DIGEST 3 (vetted) |
| `formProvider.getPublishedFormInfoById`, `getPublishedFormInfos` | 20 | `getPublishedRunningFormInfoById`, `getPublishedRunningFormInfos` | [L] |
| `formInfo.FormDimension.Dimension_2_1` | 20 | other dimensions | [M] |
| Form `colorMode` config | 20 | follows system | DIGEST 6 |
| `scanBarcode.startScan` | 4.1.0(11) | `startScanForResult` | [M] [L] |
| `new url.URL()`, `URL.searchParams`, `URLSearchParams` | 9 | `url.URL.parseURL`, `URL.params`, `URLParams` | [M] |
| `http` `on/off('headerReceive')` | old | `headersReceive` | [M] |
| `action.system.home` as the home action | 5.1.1(19) | `ohos.want.action.home` (already used) | [M guides/app-linking-startupapp.md] |

Not deprecated but superseded: `AddFormMenuItem` (docs recommend `openFormManager` from API 18).

## What I could not confirm

1. **Nothing was compiled or run.** Every snippet is unverified against DevEco's strict-mode compiler, in particular: the typed callback in `AddFormMenuItem`, `createFormBindingData('')`, `ChipOptions` literals inside a V2 struct, `{ interval: 'ui' }` as an inline `Options` literal, and the `vibrator.VibratePreset` / `VibrateAttribute` type names.
2. Whether custom `want.parameters` keys (e.g. `capsuleId`) passed to `AddFormMenuItem` / `openFormManager` reach `FormExtensionAbility.onAddForm`. Not stated anywhere I read. Purpose of `PARAM_FORM_CUSTOMIZE_KEY` is undocumented beyond "custom data".
3. Whether a single form with `resizable: true` and two `supportDimensions` resizes via `onSizeChanged` or via create-new + delete-old (`ORIGINAL_FORM_KEY`).
4. Whether the API 24 emulator launcher supports `AddFormMenuItem` and `openFormManager`.
5. The live English page for `AddFormMenuItem` (fetch timed out); mirror only.
6. Layered icon safe-zone / keyline measurements (design guide not in the mirror, not fetched).
7. Whether `startWindowIcon` accepts a layered-image JSON.
8. Whether the phone's camera/system scanner or browser will open a custom-scheme (`harmoniser://`) link from a QR code, and how https links without App Linking are routed. App Linking set-up steps are confirmed; doing them tonight was judged unrealistic, not tested.
9. `hdc shell aa start -U <uri>` syntax for testing deep links.
10. `AvoidArea.bottomRect.height`, `UIContext.px2vp`, `window.getLastWindow` (from memory).
11. That `TextArea` auto-grows when no height is set (implied by the `minLines` text, not stated outright), and how `constraintSize` + internal scrolling behave at the cap.
12. The error code a pending `http.request()` rejects with after `destroy()`.
13. `ProgressType.ScaleRing` / `Capsule` enum rows (table output was cut; inferred from the style-option section names) and that no system skeleton component exists (absence of evidence).
14. That V1 `ChipGroup` / `ProgressButton` work inside the app's `@ComponentV2` structs (the mixing guide loosens rules from API 19; not compiled).
15. V2 state objects (`@Local`, `@Trace`) across TaskPool: docs only name the V1 decorators as unsupported.
16. Open-Meteo endpoint and field names (third-party, from memory).
17. Accelerometer on the emulator beyond the shake button (mirror and repo table disagree).
18. UI Design Kit behaviour outside mainland China.
19. How an installed marketplace capsule can be matched back to its `MarketItem.id` (`pendingMarketItem` handling in `Index.decide()` was not read).
20. Additional `sys.color.*` / `sys.float.*` names listed as "named in official pages" were not compiled against this SDK; no QR/scan symbol name was found.
