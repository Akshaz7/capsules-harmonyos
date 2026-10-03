# HarmonyOS NEXT / ArkTS cheat sheet for assistants

> AI-assisted (a Claude Code sub-agent, 2026-10-04). Distilled from public community skill documents; only items checked against Huawei's documentation are stated as fact. Not Huawei-certified. Nothing here was run on a device.

Read this before touching the app. It is a digest of community skill documents, kept only where the content was checked against Huawei's documentation (URL beside each checked item). It is **not Huawei-certified**. If it disagrees with developer.huawei.com or with the compiler in DevEco Studio, they win. Items marked "(convention)" are sensible community practice that I could not tie to an official page.

App context: native HarmonyOS NEXT, ArkTS + ArkUI, Stage model, minimum API 20, emulator API 24 (HarmonyOS 6.1.1), DevEco Studio + hvigor, `@kit.*` imports, state management V2 in places, Form Kit widgets, Scan Kit, Network Kit http, Preferences.

Docs base: `https://developer.huawei.com/consumer/cn/doc/` (swap `/cn/` for `/en/` for English). Shortened below as `guides/<slug>` = `.../harmonyos-guides/<slug>` and `refs/<slug>` = `.../harmonyos-references/<slug>`.

## 1. First habits

- Read the project's `build-profile.json5`, `AppScope/app.json5`, each `module.json5` and `oh-package.json5` before choosing an API. They fix the SDK range, permissions and abilities.
- Copy the style of neighbouring files: import style, V1 or V2 state, logging, resource naming.
- Never invent an API name, property or decorator. Look it up. Web/React/CSS habits do not carry over.
- Import from kits: `import { http } from '@kit.NetworkKit'`, `import { preferences } from '@kit.ArkData'`, `import { common, abilityAccessCtrl } from '@kit.AbilityKit'`, `import { BusinessError } from '@kit.BasicServicesKit'`, `import { scanBarcode } from '@kit.ScanKit'`, `import { hilog } from '@kit.PerformanceAnalysisKit'`. Older `@ohos.*` default imports still appear in community samples; follow the project.
- Check each API's "since API version N" note against the minimum of 20, and its deprecation note.

## 2. ArkTS strict-mode gotchas

Source for the whole section: `guides/typescript-to-arkts-migration-guide`. Rule names are what the compiler prints.

| Do not write | Rule | Write instead |
|---|---|---|
| `any`, `unknown` | `arkts-no-any-unknown` | A named class/interface, a union, or `Object` plus `instanceof`/`typeof` checks |
| Untyped object literal: `const u = { name: 'a' }` | `arkts-no-untyped-obj-literals` | `const u: User = { name: 'a' }` where `User` is a declared interface or class |
| Object literal as a type: `let p: { x: number }` | `arkts-no-obj-literals-as-types` | Declare an `interface` or `class` |
| Object literal for a class that has methods, a constructor with parameters, or `readonly` fields | same family | `new TheClass(...)` |
| `obj['key']`, adding fields at runtime | `arkts-no-props-by-index` | Declared fields and `obj.key`; for dynamic keys use `Map<K, V>` or `Record<string, V>` |
| Index signatures `[k: string]: T` | `arkts-no-indexed-signatures` | `Record<string, T>` or `Map` |
| Destructuring: `const {a, b} = o`, `function f({a}: P)` | `arkts-no-destruct-params` and related | `const a = o.a`; take the whole parameter |
| Object spread `{...a, ...b}` | `arkts-no-spread` | Assign fields one by one. Spread is only for arrays into arrays or rest parameters |
| `constructor(private x: T)` | `arkts-no-ctor-prop-decls` | Declare the field in the class body, assign in the constructor |
| Relying on shape compatibility (structural typing) | `arkts-no-structural-typing` | `implements` / `extends` |
| `throw 'text'`, `throw someUnknown` | `arkts-limited-throw` | `throw new Error(...)` or a subclass |
| `catch (e: any)` | `arkts-no-types-in-catch` | `catch (e)` then `const err = e as BusinessError` |
| `function () {}` expressions, nested functions | `arkts-no-func-expressions` | Arrow functions |
| `'k' in obj`, `for..in`, `delete`, `with`, `var`, `#private` | `arkts-no-in` etc. | `instanceof`; `for..of` or index loops; set to `undefined`/`null`; `let`/`const`; `private` |
| `<T>value` casts, `as const` | `arkts-as-casts` | `value as T` only |
| `let v!: T` | `arkts-no-definite-assignment` (warning) | Initialise at declaration |
| `Pick`, `Omit`, mapped, conditional, intersection types, `typeof x` as a type, `this` as a type | `arkts-no-utility-types` etc. | Only `Partial`, `Required`, `Readonly`, `Record` are allowed. `Record` lookups are `V | undefined` |
| `Function.bind/call/apply`, `globalThis`, `require`, `Symbol()` | various | Plain methods, module exports, `import` |

More:

- Every class field needs an initial value or constructor assignment. `null` and `undefined` are different types: declare `T | null` or `T | undefined` to match what you assign.
- Give functions an explicit return type when they return another function's result; inference is limited.
- All `import` lines come before any other statement.
- `.ets` may import `.ts`; `.ts` must not import `.ets`.
- `JSON.parse` gives an untyped value: cast with `as` to a declared interface, then validate fields before trusting them.

## 3. ArkUI structure and layout

- A page is `@Entry` + `@Component` (or `@ComponentV2`) `struct` with one `build()` that has a single root container. Keep `build()` free of I/O, parsing, sorting and object creation.
- Containers: `Column`, `Row`, `Stack`, `Flex`, `RelativeContainer`, `List`, `Grid`, `Scroll`, `Tabs`. Be explicit about who scrolls. Source: `guides/arkts-layout-development-overview`.
- Use `layoutWeight`, percentages and `constraintSize` instead of fixed pixel widths. Units: `vp` for sizes, `fp` for text (follows the user's font scale).
- `ForEach(array, itemBuilder, keyGenerator)`: always pass a key generator that returns a stable unique id. The default key is `index + '__' + JSON.stringify(item)`, which causes needless rebuilds. If the item builder uses `index`, the key generator must declare it too. Source: `guides/arkts-rendering-control-foreach`.
- Long lists: `LazyForEach` with a data source, or keep the list short.
- Reuse UI with `@Builder` functions and small child components instead of copy-paste.
- Navigation: Huawei recommends the `Navigation` component with `NavPathStack`; `@ohos.router` is marked "not recommended". Global `router.pushUrl`, `promptAction.showToast` and `getContext()` are deprecated from API 18. Use `this.getUIContext().getRouter()`, `this.getUIContext().getPromptAction()` and `this.getUIContext().getHostContext()`. Follow whichever the app already uses; do not mix both in one flow. Sources: `guides/arkts-routing`, `refs/js-apis-router`, `refs/js-apis-promptaction`, `refs/js-apis-getcontext`.
- Lifecycle: `aboutToAppear` (set up), `aboutToDisappear` (cancel timers, unsubscribe, destroy handles). `onPageShow`/`onPageHide` exist only on `@Entry` pages.
- After an `await`, check the result still belongs to the current screen and request before writing state (stale responses overwrite newer ones).

## 4. State management

Sources: `guides/arkts-new-local`, `guides/arkts-new-param`, `guides/arkts-new-observedv2-and-trace`, `guides/arkts-v1-v2-mixusage`, `refs/ts-custom-component-decorator-componentv2`.

| Need | V1 (`@Component`) | V2 (`@ComponentV2`, API 12+) |
|---|---|---|
| Private component state | `@State` | `@Local` (must be initialised inside; cannot be passed in) |
| Parent to child | `@Prop` | `@Param` (read-only in the child; needs a default, or `@Require @Param`) |
| Child asks parent to change | `@Link` (two-way) | `@Event` callback |
| Observable class fields | `@Observed` class + `@ObjectLink` | `@ObservedV2` class + `@Trace` on each field that drives UI |
| Across the tree | `@Provide` / `@Consume` | `@Provider()` / `@Consumer()` |
| Derived value / watcher | `@Watch` | `@Computed` getter / `@Monitor` |

Rules:

- Stay in the generation the component already uses. Do not put `@State`, `@Prop`, `@Link` in a `@ComponentV2` struct, and do not use `@Local`/`@Param` in a `@Component` struct.
- `@Trace` only works inside an `@ObservedV2` class, never in a struct. An untraced field changes silently with no UI update. `@ObservedV2`/`@Trace` cannot be combined with `@Observed`/`@Track` or handed to V1 decorators such as `@State` (compile error).
- Mixing V1 and V2 components was loosened from API 19; check the mixing guide before passing data across the boundary.
- `JSON.stringify` on an `@ObservedV2` object produces keys prefixed `__ob_`. Serialise from a plain data object instead, and remember a parsed object is no longer observable.
- "Data changed but UI did not": find the exact field the UI reads, confirm that field is decorated, confirm the mutation hit the same instance (not a copy), then check parent/child direction.

## 5. Design conventions

- **Colours, strings, sizes come from resources, not literals.** Put values in `resources/base/element/color.json`, `string.json`, `float.json` and reference them with `$r('app.color.name')`, `$r('app.string.name')`, `$r('app.float.name')`. Source: `guides/resource-categories-and-access`.
- **Dark mode:** add `resources/dark/element/color.json` with the same names; the system picks the right one. `base/` must define every name. System tokens adapt automatically: `$r('sys.color.font_primary')`, `sys.color.font_secondary`, `sys.color.background_primary`, `sys.color.background_secondary`, `sys.color.comp_background_primary`, `sys.color.comp_background_list_card`, `sys.color.icon_primary`, `sys.color.brand`, `sys.color.warning`. Check every screen in both modes. Source: `guides/ui-dark-light-color-adaptation`.
- **Touch targets:** tappable area at least 48 vp x 48 vp (recommended), never under 40 vp x 40 vp. A small icon can keep its size and get a larger hit area with `responseRegion`. Sources: `.../design-guides/ux-guidelines-general-0000001760708152`, `refs/ts-universal-attributes-touch-target`.
- **Contrast:** body text at least 4.5:1 against its background; icons and titles at least 3:1. Interface icons at least 12 vp (8 vp hard minimum). Text at least 8 fp per the linter; in practice keep readable text at 12 fp or more. Sources: same UX standard page; `guides/ide_font-size`.
- **Typography:** use the system font; do not ship custom typefaces for ordinary UI. Use `fp` so text follows the user's font-size setting, and test with large font. System text tokens exist (`sys.float.Body_L`, `Body_M`, `Title_M`, `Caption_L`).
- **Spacing and radii:** system tokens exist (`sys.float.padding_level8`, `padding_level12`, `padding_level16`, `corner_radius_level4` ...). (convention) Many teams use a 4 vp grid: 4/8/12/16/24/32 spacing, 16 vp page side margins, 8 vp radius for buttons and inputs, 12 to 16 vp for cards, capsule buttons 40 to 48 vp high, one text scale such as 12/14/16/20/24 fp. Pick one scale, store it in `float.json`, and use only those values.
- Avoid pure hard-coded hex in components, mixed radii on sibling cards, and one-off margins to "nudge" alignment. Fix the shared container or the token.
- Icon-only buttons need an accessibility label. Do not signal state by colour alone.
- Every data screen needs explicit loading, empty, error and (where relevant) no-permission or offline states.
- Keep content clear of the status bar and bottom navigation indicator; if drawing edge to edge use `expandSafeArea` deliberately. Source: `guides/arkts-develop-apply-immersive-effects`.
- Motion: change state and let ArkUI animate; do not animate `width`/`height`/`padding` on complex subtrees.

## 6. Form Kit widget (service card) rules

Sources: `guides/arkts-form-overview`, `guides/arkts-ui-widget-configuration`, `guides/arkts-ui-widget-passive-refresh`, `guides/arkts-ui-widget-lifecycle`, `refs/js-apis-app-form-formprovider`.

- Two halves. The **provider** is a `FormExtensionAbility` (declared under `extensionAbilities` with `type: "form"` and metadata `ohos.extension.form` pointing at `$profile:form_config`). The **card page** is a separate `.ets` file rendered in a shared system process, not in the app.
- Card page limits: only modules and APIs marked "supported in ArkTS widgets" may be imported; HAR is allowed, HSP is not; no native code; no `setTimeout`; no horizontally swipeable components; no breakpoint debugging or hot reload. So no http, Preferences or app singletons inside the card page. An unsupported API makes the card fail to load.
- Data flows one way: provider builds `formBindingData.createFormBindingData({...})`, returns it from `onAddForm(want)` or pushes it with `formProvider.updateForm(formId, data)`. The card reads it with `@LocalStorageProp('key')` on an `@Entry(storage)` component where `storage = new LocalStorage()`.
- Use V1 decorators in card pages. Official pages disagree on when `@ComponentV2` became usable in cards (API 12 on one page, API 23 on another); with a minimum of API 20, V1 is the safe choice.
- Lifecycle callbacks: `onAddForm`, `onUpdateForm`, `onFormEvent`, `onRemoveForm`. Save the `formId` on add (for example in Preferences) and remove it on remove, or the app cannot push updates later. Keep callbacks short; the extension is not a long-running service.
- Interaction from a dynamic card: `postCardAction(this, { action: 'router' | 'message' | 'call', ... })`, only inside a click handler. `router` opens a UIAbility, `message` triggers `onFormEvent` in the provider, `call` starts the UIAbility in the background. Static cards use `FormLink`.
- `form_config.json`: `uiSyntax: "arkts"` (default is the old `hml`), `isDynamic` defaults to `true`, `supportDimensions` from `1*2`, `2*2`, `2*4`, `4*4` (also `1*1`, `2*3`, `3*3`, `6*4` on some devices) with `defaultDimension` among them. Do not rename `name`, ability or module casually: changing the identity tuple removes users' placed cards on upgrade.
- Refresh: `updateEnabled: true` plus either `updateDuration` (units of 30 minutes, 0 = off, wins if both set) or `scheduledUpdateTime` ("10:30"). Timed refresh is capped at 50 per card per day; `setFormNextRefreshTime` minimum is 5 minutes.
- `colorMode` is deprecated from API 20; cards follow the system colour mode. Use resource or system colours so both modes work.
- Card design: glanceable, one main message, generous padding, text and colours from resources, layout that adapts to each declared size, sensible content before data arrives.

## 7. HTTP (Network Kit)

Sources: `guides/http-request`, `refs/js-apis-http`, `guides/permissions-for-all`.

- Declare `ohos.permission.INTERNET` in `module.json5` `requestPermissions`. It is `system_grant`: declaration is enough, no runtime prompt.
- `const req = http.createHttp()` makes a single-use object: one object per request. Call `req.destroy()` in `finally`.
- `await req.request(url, { method: http.RequestMethod.GET, header: {...}, connectTimeout: ..., readTimeout: ..., expectDataType: http.HttpDataType.STRING })`. Both timeouts default to 60000 ms; set shorter ones for UI-facing calls.
- Check `responseCode` before using `result`. `result` may be a string, object or ArrayBuffer; set `expectDataType` and parse into a declared interface.
- Responses over 5 MB fail before API 23; use `requestInStream` for large bodies.
- Plain `http://` can be restricted by `network_config.json`; default to HTTPS.
- Errors arrive as `BusinessError` with `code` and `message`. Surface a user-readable state; never swallow. Do not log tokens or full bodies.
- Put all requests behind one small client class (base URL, timeouts, error shape) rather than scattering `http.request` across pages. A request router is a plain class with typed methods; build its options objects from declared interfaces (no spread, no untyped literals).

## 8. Permissions and location

Sources: `refs/js-apis-permissionrequestresult`, `guides/request-user-authorization`, `guides/request-user-authorization-second`, `guides/declare-permissions`, `guides/location-permission-guidelines`, `guides/location-guidelines`.

- Every permission is declared in `module.json5`. `user_grant` ones also need `reason` (a `$string:` resource, not a literal) and `usedScene` (`abilities`, `when: "inuse"`).
- Runtime request: `abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [...])`, called when the user triggers the feature, not at launch.
- Result `authResults[i]`: `0` granted, `-1` not granted, `2` invalid request (not declared, bad name, or conditions not met). When `-1`, `dialogShownResults[i] === true` means the user just refused; `false` means the system will not prompt again, so guide the user to Settings or call `requestPermissionOnSetting`. Do not loop prompts.
- Location: request `ohos.permission.APPROXIMATELY_LOCATION` alone for city-level accuracy, or together with `ohos.permission.LOCATION` for precise. Precise cannot be requested by itself. For weather, approximate is enough.
- Before locating: `geoLocationManager.isLocationEnabled()`. One-shot fix: `geoLocationManager.getCurrentLocation(request)` with a `SingleLocationRequest` (priority + timeout). Handle refusal, location switched off and timeout with a manual-city fallback.
- Scan Kit default scanner: `scanBarcode.startScanForResult(context, options)` from `@kit.ScanKit` shows the system scan UI and needs **no** camera permission from the app. Source: `guides/scan-scanbarcode`, `refs/scan-scanbarcode-api`.

## 9. Preferences

Source: `guides/data-persistence-by-preferences`, `refs/js-apis-data-preferences`.

- For small key-value settings only. No encryption: do not store secrets. Keys up to 1024 bytes. The default XML mode is not safe across processes; a widget provider and the main app writing the same file can race, so keep writes short and tolerate missing values.
- `put` changes memory; `flush()` writes to disk. Call `flush` after writes that must survive a kill.
- Always pass a default to `get`, and cast the result to the expected type.

## 10. Common build and lint errors

| Message contains | Usual cause | Fix |
|---|---|---|
| `arkts-no-any-unknown` | `any`/`unknown`, often from `JSON.parse` or `catch` | Declare an interface and cast with `as` |
| `arkts-no-untyped-obj-literals` | Literal without a target type, or literal for a class with methods/constructor | Annotate the type or use `new` |
| `arkts-no-obj-literals-as-types` | Inline `{ a: T }` type | Named interface |
| `arkts-no-props-by-index` | `obj[key]` | Field access, `Map`, or `Record` |
| `arkts-no-spread` | Object spread | Field-by-field copy |
| `arkts-no-destruct-*` | Destructuring | Plain property reads |
| `arkts-no-ctor-prop-decls` | `constructor(private x)` | Field + assignment |
| `arkts-limited-throw` | Throwing a non-Error | Wrap in `Error` |
| Property has no initializer | Class field without default | Default value or constructor assignment |
| Decorator not allowed / state error in `@ComponentV2` | V1 decorator in a V2 struct or the reverse | Use the matching generation |
| Cannot find resource / `$r` error | Name missing from `base/element/*.json` | Add it in `base/` (and `dark/` for colours) |
| Deprecated API warning (`router`, `promptAction`, `getContext`, `animateTo`) | Global UI functions deprecated at API 18 | Go through `this.getUIContext()` |
| Widget shows blank or fails to load | Card page imports an unsupported module, or bound key names differ | Import only widget-capable APIs; match `@LocalStorageProp` keys to the binding data |
| Permission request returns `2` | Not declared in `module.json5`, or precise location requested alone | Declare it; request the pair |
| http fails immediately | Missing `INTERNET`, cleartext blocked, or reused request object | Declare it, use HTTPS, create a new object |

Linter rule sets live in the project's `code-linter.json5`; rule reference: `guides/ide-codelinter-rule`. Report what the compiler or linter actually says; do not describe a check as passed unless it was run.

## 11. Review checklist

1. Types: no `any`/`unknown`, no untyped literals, no dynamic keys, no spread or destructuring of objects.
2. State: one generation per component; every UI-driving field decorated; mutations hit the observed instance.
3. Async: results checked for staleness; errors surfaced; request objects destroyed; listeners and timers released in `aboutToDisappear`.
4. Resources: no literal colours or user-visible strings; names exist in `base/` and colours in `dark/`.
5. Touch targets at least 40 vp, aiming for 48 vp; text scales; contrast holds in both modes.
6. Widgets: card page imports only widget-capable APIs; `formId` stored and removed; refresh settings realistic; sizes all laid out.
7. Permissions: declared with reason; requested in context; `-1` and `2` handled; no prompt loops.
8. API levels: nothing newer than API 20 without a guard; no newly added deprecated calls.
