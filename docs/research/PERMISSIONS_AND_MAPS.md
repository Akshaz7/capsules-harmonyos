# Permissions and maps: what is real, what to cut, what to say

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04). Written from the code and documents of the repository. Nothing was built or run. Line references are to the commits named in the text and will drift. The "offline Huawei docs mirror" it cites is a local copy of Huawei's developer documentation that is not in this repository.

Written Sunday 4 Oct 2026 for the 11:00 submission. Read-only research: nothing in any repository was changed.

Evidence labels: **[code]** read in the code at `file:line` · **[mirror]** verified in the offline Huawei docs mirror
(path relative to `harmony-skills/liasica__harmonyos-skills/harmonyos/references/`) · **[live]** verified on the live
site (URL) · **[memory]** from memory, not verified. Nothing here was compiled or run on the emulator.

## 0. Read this first: the premise has changed

**PR #12 is no longer unmerged.** `origin/main` is now `547d27b` "Merge pull request #12 from Akshaz7/codex/ark-kits",
committed 2026-10-04 00:45 +0100. `origin/codex/ark-kits` (`52450b0`) has no commits that main lacks.

So the pitch briefing's statement "on main only `reminders` has a working effect" (`PITCH_BRIEF.md:129`, `:598`) is
**out of date**. On today's main, four capsule permissions gate something real. "Main before PR #12" below means
`a58e0f3`; "main now" means `547d27b` and is identical to the PR #12 branch for every fact in this document.

| | main before PR #12 (`a58e0f3`) | main now = PR #12 branch (`547d27b`) |
|---|---|---|
| Capsule permissions in the schema | 6 (`CapsuleTypes.ets:143`) | 8: adds `battery`, `weather` (`CapsuleTypes.ets:4`, `:156`) |
| Working, gated effect | `reminders` only | `reminders`, `motion`, `battery`, `weather` |
| Gates a no-op | `notifications` | `notifications` (unchanged) |
| Wording only | `vibration`, `location`, `widget`; `motion` not built | `vibration`, `location`, `widget` |
| OS permissions in `module.json5` | INTERNET, VIBRATE, READ_CALENDAR, WRITE_CALENDAR | the same plus ACCELEROMETER |

Paths below are under `entry/src/main/ets/` unless they start with another folder, and are from main now.

---

## Question 1. Which capsule permissions are real?

### 1.1 The two layers

- A **capsule permission** is Harmoniser's own consent, per generated mini-app. The capsule's JSON lists the
  permissions it needs; the validator rejects a capsule that uses something it did not list; the consent sheet shows
  one switch per listed permission, all off by default (`pages/ConsentView.ets:80`, `:95`); the gatekeeper allows
  something only if the capsule listed it **and** the user switched it on (`gatekeeper/Gatekeeper.ets:85-87`), and
  writes every allow, deny and block to a log (`Gatekeeper.ets:78-81`, `:99`, `:112`). The operating system knows
  nothing about this layer.
- A **HarmonyOS system permission** belongs to the whole app. It is declared in `module.json5`. `system_grant`
  permissions are given at install with no prompt; `user_grant` permissions also need a run-time prompt through
  `requestPermissionsFromUser()`. Some capabilities need no permission at all, and notifications use their own
  switch (`requestEnableNotification`) rather than a manifest permission.

A capsule permission can therefore be "allowed" while the system permission underneath is refused (calendar is the
only case in this app where that can happen), and several capsule permissions have no system permission under them.

### 1.2 Every capsule permission (main now)

All eight are declared in `core/CapsuleTypes.ets:4` (type) and `:156` (`PERMISSIONS`). The validator accepts any of
them in `"permissions"` (`core/CapsuleValidator.ets:856`) and rejects a capsule whose component, action or trigger
needs one that is not listed (`:909-911`, `:810-812`, `:523-525`).

| Permission | What the validator ties to it | Consent row (`pages/ConsentView.ets`) | Where the gatekeeper is asked at run time | Allowed / denied | OS permission and run-time request | Verdict |
|---|---|---|---|---|---|---|
| `reminders` | `timer` component (`CapsuleValidator.ets:157-158`); timer actions and `startAllTimers` (`:171-172`); `time` triggers (`:523`) | "Save timers to your calendar and alert you when they finish" (`:39`) | `checkComponents` when the capsule is loaded (`pages/Index.ets:1071`); every action (`renderer/CapsuleRuntime.ets:272`, `:337`); triggers (`widget/TriggerGate.ets:18`); widget taps (`widget/WidgetService.ets:307`, `:316`) | Allowed: a calendar event with a reminder (`adapters/TimerAdapter.ets:85-94`) and a notification when the timer ends (`Index.ets:200`, attached only if allowed, `:1073-1075`). Denied: the timer is drawn as "Blocked timer" (`renderer/CapsuleView.ets:462-463`, `:93`), its buttons do nothing, each block is logged (`Gatekeeper.ets:99`, `:112`) | `READ_CALENDAR` + `WRITE_CALENDAR` declared with a reason (`entry/src/main/module.json5`), asked at run time (`TimerAdapter.ets:44`), first when a capsule with `reminders` allowed is accepted (`Index.ets:1326-1327`). Notification switch asked in the same place (`adapters/NotificationAdapter.ets:23`) | **Working** |
| `motion` | `counter` with `source: "motion"` (`:160-161`); `motion` triggers (`:523`) | "React to shaking the phone while the capsule is open. It does not count steps or reps" (`:45`) | Which capsules receive shakes (`Index.ets:825`); again before every single increment and trigger (`Index.ets:855`); `checkComponents` | Allowed: shakes increment the counter and fire motion triggers while the app is in front (`Index.ets:829-863`, `adapters/MotionAdapter.ets:68`). Denied: counter drawn as blocked, no sensor subscription for it. Shakes themselves are not logged; the allow/deny decision is | `ohos.permission.ACCELEROMETER` declared (`module.json5`), `system_grant`, no prompt | **Working** in code (new with PR #12). Real-phone behaviour untested per `PR12_REVIEW.md:190`, `:295`; the two docs disagree on what the emulator shows (`PR12_REVIEW.md:235-236`) |
| `battery` | `device` component with `bind: "battery"` (`:163-164`) | "Read the battery level and charging state while the capsule is open" (`:49`) | `Index.ets:629`; `checkComponents` | Allowed: level and charging state read on open and on return to foreground (`Index.ets:632-645`, `adapters/BatteryAdapter.ets:24-29`). Denied: no read, component blocked | None needed (`capabilities/CapabilityRegistry.ets:68`) | **Working** (new with PR #12) |
| `weather` | `device` with `bind: "weather"`; optional `city` must be a bundled city id (`:332-339`); at most 1 per capsule (`:886`) | "Send the chosen city's coordinates to Open-Meteo (open-meteo.com) to show its weather" (`:51`) | Before the fetch (`Index.ets:675`) and again before the result is shown (`Index.ets:703`); `checkComponents` | Allowed: one HTTPS GET to a host fixed in code with only the city's coordinates (`adapters/WeatherAdapter.ets:16`, `:74-77`), 15-minute cache, attribution on the card (`renderer/CapsuleView.ets:237-242`). Denied: nothing is fetched | `ohos.permission.INTERNET` declared, `system_grant`, no prompt | **Working** in code (new with PR #12). The team is fixing the weather request tonight; this document did not test it |
| `notifications` | `notify:<text>` action (`:174-175`) | "Show notifications from this capsule" (`:41`) | Every action, as above | Allowed: **nothing happens.** `case 'notify': // Delivered by the notification adapter (step 4). break;` (`renderer/CapsuleRuntime.ets:396-398`). The only caller of `NotificationAdapter.publish` is the timer-finished alert (`Index.ets:200`). Denied: the press shows "Blocked: … needs a permission you didn't allow" (`CapsuleRuntime.ets:273`) and is logged | No manifest permission. `requestEnableNotification` is only reached when `reminders` is allowed (`Index.ets:1326-1327`) | **Gates a no-op.** It is not dead text: the habit, vitamin and medication templates add `notify:Time for …` daily triggers and both permissions (`core/templates/TemplateLibrary.ets:193`, `:204`), and the on-device model's reminder shape uses it (`core/providers/CactusProvider.ets:394`). Today the only visible effect of such a trigger is a toast (`Index.ets:579`) |
| `vibration` | Nothing. No component, action or trigger maps to it | "Vibrate the phone for alerts" (`:43`) | Never | No effect either way. (The app's own success tick vibrates ungated, `pages/Motion.ets:28`, `Index.ets:1322`; that is app chrome, not a capsule) | `ohos.permission.VIBRATE` declared, `system_grant` | **Wording only** |
| `location` | Nothing | "Use where you are" (`:47`) | Never | No effect. Marked `implemented: false` in `capabilities/CapabilityRegistry.ets:98-115` | Not declared | **Wording only** |
| `widget` | Nothing | "Show this capsule on your home screen" (`:53`) | Never. "Add to home screen" does not consult it (`widget/AddToHomeButton.ets` has no gate call) | No effect | Form Kit needs none | **Wording only** |

Who can produce the three wording-only names: the rules and the 108 bundled templates never do (template library
permissions are `[]` ×85, `["reminders"]` ×20, `["reminders","notifications"]` ×2, `["motion"]` ×1). But the AI
prompt still advertises them (`core/CapsuleModel.ets:15`, copied from `SCHEMA.md:5`), and a capsule from the
marketplace or a QR code may list them, because the validator only checks that the name is known. Such a capsule
shows a switch that does nothing.

### 1.3 System permissions per capability

| Capability | System permission | Grant type | Evidence | In this app |
|---|---|---|---|---|
| Notifications | None in the manifest. `notificationManager.requestEnableNotification(context)` shows a one-time system dialog; refusal is error 1600004 and the dialog cannot be shown again that way | own switch | [mirror] `harmonyos-guides/notification-enable.md:11`, `:22`, `:40` | Used (`NotificationAdapter.ets:23`) |
| Vibration | `ohos.permission.VIBRATE` | system_grant | [mirror] `harmonyos-guides/permissions-for-all.md:249-257` | Declared; used only for the app's own tick |
| Approximate location | `ohos.permission.APPROXIMATELY_LOCATION` | user_grant | [mirror] `harmonyos-guides/permissions-for-all-user.md:129-137` | Not declared |
| Precise location | `ohos.permission.LOCATION`, only together with APPROXIMATELY_LOCATION | user_grant | [mirror] `permissions-for-all-user.md:117-127` | Not declared |
| Accelerometer | `ohos.permission.ACCELEROMETER` | system_grant | [mirror] `permissions-for-all.md:77-85` | Declared, used |
| Step count (not used) | `ohos.permission.ACTIVITY_MOTION` | user_grant | [mirror] `permissions-for-all-user.md:60-68` | Not declared |
| Calendar | `ohos.permission.READ_CALENDAR`, `WRITE_CALENDAR` | user_grant | [mirror] `permissions-for-all-user.md:149-167` | Declared and requested at run time |
| Camera for QR scan | None for Scan Kit's default scanning screen (camera access is pre-authorised); `ohos.permission.CAMERA` (user_grant) only for a custom scanning screen |, | [mirror] `harmonyos-guides/scan-scanbarcode.md:11`, `scan-customscan.md:90` |, |
| Internet | `ohos.permission.INTERNET` | system_grant | [mirror] `permissions-for-all.md:167-175` | Declared, used |
| Home-screen widgets | None |, | [memory]; the Form Kit pages read do not ask for one | Used |
| Clipboard, reading | Either the system `PasteButton` (no permission) or `ohos.permission.READ_PASTEBOARD`, a restricted user_grant permission | restricted | [mirror] `harmonyos-guides/get-pastedata-permission-guidelines.md:38-43`, `restricted-permissions.md:243` | Not used |
| Clipboard, writing | None |, | [memory] |, |
| Continuous background task | `ohos.permission.KEEP_BACKGROUND_RUNNING` plus `backgroundModes` on the ability | system_grant | [mirror] `permissions-for-all.md:179-185`, `harmonyos-guides/continuous-task.md:124-135` | Not used |
| Agent reminders | `ohos.permission.PUBLISH_AGENT_REMINDER` | system_grant | [mirror] `permissions-for-all.md:225-231` | Not used, see below |

**How calendar events are created today.** Not through a picker. The app declares both calendar permissions with a
reason string and `usedScene` (`module.json5`), calls `requestPermissionsFromUser` (`TimerAdapter.ets:44`), then
uses `calendarManager` directly: its own local calendar account "Harmoniser" (`TimerAdapter.ets:25-29`, `:51-53`)
and `addEvent` with `reminderTime: [0]` (`:85-94`). If the user refuses the system prompt, `prepare()` returns false
and the timer still counts down in the app but no system reminder is set (`:45-48`, `:80-83`).

**Why not agent reminders.** The permission itself is system_grant, but on phones, tablets and PCs the capability
is "controlled": the app must apply for it in AppGallery Connect and wait about 8 working days, or use Calendar Kit
instead, which is what Huawei's own page recommends [mirror] `harmonyos-guides/agent-powered-reminder.md:18-21`,
`:89`. Limits: 30 valid reminders per app up to API 25, 64 from API 26, 12 000 system-wide (`:40-44`). The code
comment says the same from experience: `publishReminder` fails with 1700002 (`TimerAdapter.ets:17-19`).

### 1.4 What to do with each permission that is not real, in order of value per minute

| # | Item | Do | Effort | Emulator | Risk this late |
|---|---|---|---|---|---|
| 1 | `vibration`, `location`, `widget` | **Cut from what the AI and the docs offer.** Remove the three names from the permissions line in `SCHEMA.md:5` and `core/CapsuleModel.ets:15`. Leave the validator accepting them so stored and marketplace capsules do not break | 5 min | n/a | Very low. No test references these names (searched `entry/src/test`, `entry/src/ohosTest`). Residual gap: a marketplace or QR capsule listing them still shows a dead switch |
| 2 | `notifications` | **Build.** Deliver `notify:<text>` through the existing `NotificationAdapter` | 20-30 min with a build and one emulator check | Notification Kit supports the emulator [mirror] `harmonyos-guides/notification-overview.md:79`; the timer-finished alert already uses the same adapter | Low. One optional field and one call; no schema change |
| 3 | `vibration` as a real capsule action | Do not build | 60+ min (new action in types, validator, prompt, tests) | **Vibrator is not supported on the emulator** [mirror] `harmonyos-guides/sensorservice-kit-intro.md:43`, so it cannot be tested or shown | High for no visible gain |
| 4 | `location` | Do not build | 60-90 min: two user_grant permissions with reason strings, `requestPermissionsFromUser`, `geoLocationManager.getCurrentLocation`, a nearest-bundled-city step | Location Kit supports the emulator [mirror] `harmonyos-guides/location-kit-intro.md:64`; what position it returns was not checked | Medium-high; adds a second OS prompt to the demo |
| 5 | `widget` | Do not build |, |, | Gating "Add to home screen" on it would break that button for every existing capsule, since none declares `widget`. Placing a widget is already an explicit act by the user |

**Item 2 in detail (untested sketch).** Deny is already enforced: `press`, `dispatch` and triggers all call
`allowAction` before `run` (`CapsuleRuntime.ets:272`, `:337`; `core/Triggers.ets:151-155`). Only delivery is missing.

- `renderer/CapsuleRuntime.ets`, next to `alert?` at `:144`: add `notifier?: (text: string) => void;` and change
  `:396-398` to `case 'notify': this.notifier?.(arg); break;`.
- `pages/Index.ets`, inside `if (this.gate) {` at `:1070`:

  ```ts
  const gate = this.gate;
  const notes = this.notifications;
  if (notes) {
    rt.notifier = (text: string): void => {
      if (gate.isAllowed(capsule, 'notifications') && !gate.isRemoved(capsule.id)) {
        notes.publish(capsule.name, text);
      }
    };
  }
  ```

- `pages/Index.ets:1326`: also call `this.notifications?.ensureEnabled()` when `notifications` is allowed, so the
  system dialog appears at consent time and not at the first press.
- Consent row: "Show a notification when you press its button, or at its daily time while Harmoniser is open".
  That is the honest scope: daily triggers only fire while the app is open (`Index.ets:556-559`), and a `notify`
  pressed on a home-screen widget does not go through this runtime (`widget/WidgetService.ets:300-320`), so it stays
  silent there.
- What a judge sees: "remind me to take vitamins" → consent with Notifications → press → banner. Deny → "Blocked"
  line and a log entry.

If item 2 is not done, say so (section 1.5) and do not demo a capsule whose only permission is `notifications`.

### 1.5 Two sentences for a judge

If nothing more is built:

> Four are enforced end to end today: reminders, the motion sensor, battery and weather. Deny one and that part of
> the capsule is shown as blocked and the attempt is written to the log; weather is the only one that sends anything
> off the phone, and it sends only a city's coordinates. Notifications is checked but not delivered yet, and the
> other names in the schema are reserved and do nothing.

If item 2 is built, replace the last sentence with: "Notifications makes five; the remaining names in the schema are
reserved and not offered."

---

## Question 2. Maps inside capsules and widgets

### 2.1 Huawei Map Kit

| Point | Finding | Evidence |
|---|---|---|
| Import | `import { MapComponent, mapCommon, map, staticMap, petalMaps } from '@kit.MapKit'` | [mirror] `harmonyos-guides/map-static-diagram.md`, `map-petalmaps.md` |
| Account setup | The Map service must be enabled for the app: in DevEco Studio (Project Structure → Signing Configs → "Enable open capabilities" → Map Kit, DevEco 6.0.0 Beta5 or later, works with automatic signing) or on the AppGallery Connect site (then: debug certificate, registered device, new debug profile, manual signing) | [mirror] `harmonyos-guides/map-config-agc.md`; `harmonyos-faqs/faqs-map-35.md` |
| Client ID / fingerprint | No longer needed from HarmonyOS 5.0.2 (API 14) | [mirror] `map-config-agc.md` (note at the top) |
| Signed build | **Required, on the emulator too.** "Map service needs signing before it can be used" | [mirror] `faqs-map-35.md` step 2 |
| This repo | `build-profile.json5` has `"signingConfigs": []`; bundle name `com.hackyeah.capsules`. Someone would need a Huawei developer account, an app with this bundle name, the Map switch and a signing profile | [code] `build-profile.json5`, `AppScope/app.json5` |
| Outside mainland China | Supported in Poland, Germany, the UK and about 230 other regions, and in mainland China. Mainland uses GCJ02 coordinates, everywhere else WGS84 | [mirror] `harmonyos-guides/map-supported.md:54`, `:177`; `map-introduction.md`. The live English page exists and its list starts the same way (only the first rows were seen) [live] https://developer.huawei.com/consumer/en/doc/harmonyos-guides/map-supported |
| Emulator | Map display works from DevEco Studio 5.1.0. Not supported there: "my location", opening the Petal Maps app, offline maps | [mirror] `map-introduction.md:58-62`, `faqs-map-35.md` |
| API level | Static map `getMapImage(options)` from 4.1.0 (API 11); the overload with a context from 5.0.0 (API 12) | [mirror] `harmonyos-references/map-staticmap.md:33`, `:92` |
| Static map limits | `zoom` 2-17 (integer); `imageWidth`/`imageHeight` up to 1024 px at scale 1, 512 at scale 2; returns `image.PixelMap` | [mirror] `map-staticmap.md:150-156` |
| Quotas | Error codes exist for "call times exceed the quota", "QPS exceeds the quota", "in arrears", "not subscribed to any pay-as-you-go package". The actual HarmonyOS NEXT numbers were not found | [mirror] `map-staticmap.md:54-63`. The HMS Core pricing page lists static map as free for Android [live] https://developer.huawei.com/consumer/pt/doc/HMSCore-Guides/about-charging-0000001051637068, which is a different SDK |
| `MapComponent` in a widget | **No.** A widget may only use interfaces marked "supported in ArkTS widgets"; `MapComponent`'s reference page carries no such mark, and widgets cannot load native libraries | [mirror] `harmonyos-guides/arkts-form-overview.md:84-87`; no widget mark in `harmonyos-references/map-mapcomponent.md` |
| A map picture in a widget | Possible in principle: `Image` is widget-capable; the form ability passes file descriptors in `formImages` and the widget shows `'memory://' + key`. The form ability only lives about 5 seconds, so the picture must already be on disk. Size limits were not found | [mirror] `harmonyos-guides/arkts-ui-widget-image-update.md:51-54`, `:83-84`, `:201-209`; `harmonyos-references/ts-basic-components-image.md:56` |

Conclusion: Map Kit is the right long-term answer and Poland is covered, but tonight it costs an account, an app
registration and a signing change on a project that currently builds unsigned. Do not start it before 11:00.

### 2.2 Alternatives that need no Huawei account

| Option | Feasible | Terms and limits | Evidence |
|---|---|---|---|
| **One OpenStreetMap raster tile** fetched over HTTPS, shown with `Image`, marker drawn on top | Yes. Only needs INTERNET, already declared. A test request for the Kraków tile at zoom 13 with an identifying User-Agent returned 200, `image/png`, 38 kB | Allowed if: the exact URL `https://tile.openstreetmap.org/{z}/{x}/{y}.png`; visible "© OpenStreetMap contributors"; a User-Agent that names the app (library defaults and `com.example.*` ids get blocked); cache per HTTP headers or at least 7 days; no bulk download or prefetch; no `no-cache` headers. No SLA; access can be blocked without notice. A few tiles for a demo, cached, is within the policy; a shipped product should move to a paid or self-hosted tile source | [live] https://operations.osmfoundation.org/policies/tiles ; enforcement notes https://community.openstreetmap.org/t/133421 and /t/141796 |
| Hosted static-map services | Need an API key: Geoapify (free plan 3000 credits a day, "Powered by Geoapify" attribution), MapTiler, Mapbox, Stadia (free tier is for non-commercial or evaluation use; key needed outside localhost) | A key in the app is a secret to manage; none is faster tonight than the single tile | [live] https://www.geoapify.com/static-maps-api/ , https://apidocs.geoapify.com/docs/maps/map-tiles/ , https://stadiamaps.com/terms-of-service/ , https://docs.stadiamaps.com/static-maps ; MapTiler and Mapbox [memory] |
| Open the system map app | `petalMaps.openMapPoiDetail(context, { destinationPosition, destinationName, zoom, coordinateType })` (from 5.0.3, API 15), or `startAbilityByType('navigation', { sceneType: 4, destinationLatitude, destinationLongitude, destinationName })` which shows the system's list of map apps | **Opening the map app is not supported on the emulator**, so it cannot be tested or filmed tonight. `petalMaps` is also part of Map Kit; whether it needs the Map service enabled was not confirmed. The navigation panel's docs say coordinates are GCJ-02 | [mirror] `harmonyos-guides/map-petalmaps.md`, `map-introduction.md:61`, `start-navigation-apps.md`. A `geo:` URI: [memory], not found in the mirror |
| `Web` component with an embedded web map | Works in the app (needs INTERNET) but loads third-party script inside a capsule, which breaks the "JSON only, no code" promise; heavier; not allowed in widgets | Not recommended | [memory] apart from the widget rule above |
| Draw with `Canvas` | A dot on a blank outline with no base map is not a map. Canvas is useful only for the marker on top of a tile |, |, |

### 2.3 The smallest `map` that fits the architecture

Reuse the PR #12 "device reading" pattern exactly; it already solved the hard parts (fixed host, bundled cities,
consent wording, cache, offline state, attribution, widget rule).

- **Schema.** `{ "type": "device", "bind": "map", "city"?: "<bundled city id>", "label"?: string }`, needs
  permission `"map"`. No latitude, longitude, zoom or URL field in the first version: the capsule can only name one
  of the 12 bundled cities (`capabilities/WeatherData.ets:17-30`), or omit it so the user picks one in the app, as
  weather does (`Index.ets:656-662`). Zoom is fixed in code (12 shows a whole city in one tile).
- **Validator.** Add `'map'` to `Permission`/`PERMISSIONS` and to `DeviceBind`/`DEVICE_BINDS`
  (`core/CapsuleTypes.ets:4`, `:112`, `:156`, `:163`); allow `city` for map as for weather
  (`core/CapsuleValidator.ets:280`, `:332`); at most one map per capsule, like `MAX_WEATHER_COMPONENTS` (`:73`,
  `:886`). The permission mapping is automatic (`:163-164` returns the bind). Unknown fields are already rejected.
  If free coordinates are added later: latitude −85 to 85, longitude −180 to 180, zoom 3 to 16, numbers only, and
  still no host or URL from the capsule. Capsules arrive from the marketplace and QR codes, so anything that selects
  a host would let a stranger make the phone call a server of their choice.
- **Consent row.** Title "Map". Text: "Download a map picture of the chosen city from OpenStreetMap
  (tile.openstreetmap.org). The request shows them which area you looked at, and your internet address." Deny
  blocks the download and the component, as weather does (`Index.ets:675`).
- **What leaves the phone.** One HTTPS GET to one host fixed in code, whose path contains only three tile numbers
  for a bundled city, plus the app's User-Agent. No capsule text, state or identifiers.
- **Adapter.** `adapters/MapAdapter.ets`, modelled on `adapters/WeatherAdapter.ets`: host constant, 6-second
  timeout, size cap, one tile per city, memory cache plus a file in the cache directory kept at least 7 days
  (the tile policy requires caching), states ok / stale / offline / error.
- **Screen.** `renderer/CapsuleView.ets` `deviceItem` (`:213-245`): for `bind === 'map'` show the picture, a pin at
  the city's position inside the tile, the label, and "© OpenStreetMap contributors" always visible and tappable
  like the Open-Meteo line (`:237-242`). Offline: a neutral card "Map unavailable offline" with the city name.
- **Registry and prompt.** A `MAP` entry in `capabilities/CapabilityRegistry.ets` with `implemented: true` is what
  makes the generator advertise it (`:156-164`); add the line to `SCHEMA.md` (v1.2 section, `:83-101`).
- **Rules and templates.** In `core/RuleParser.ets`, the same city matching weather uses
  (`cityIdFromText`, `WeatherData.ets:61-65`): "map of Kraków" → one map component with `city: "krakow"`.
  "Where is the venue" has no bundled place, so it must fail honestly ("I can only show maps of these cities")
  unless a `venue` entry is added to the bundled list for the demo.
- **Widgets.** Leave map capsules app-only, the rule `SCHEMA.md:101` already states for every device reading. A
  later version can write the cached tile to a file and pass it through `formImages`.
- **Wrist screen.** The relay sends text and state to the ESP32; send the place name and coordinates as a text
  line, not the picture. (Not checked against the relay code.)

### 2.4 Verdict for tonight

**Do not build it before 11:00 unless the demo is recorded, the weather request is fixed, and two clear hours
remain.** It touches the types, the validator, the consent sheet, the gatekeeper mapping, the renderer, the page,
the generator prompt, the schema docs and the tests: the same surface PR #12 needed, on the morning of submission.

- **Option I would pick if there is time:** the single OpenStreetMap tile as `device`/`map` (section 2.3).
- **Effort:** 90-120 minutes for someone who knows the PR #12 code, including tests and one emulator check.
- **Emulator:** should work; it is the same network path as weather. Not tried.
- **Risks:** the tile server may refuse a default User-Agent (set one; whether `http.request` lets the app override
  `User-Agent` is not confirmed); `tile.openstreetmap.org` has no SLA and venue Wi-Fi may block it; a schema change
  can invalidate the cached requests and the 249 existing tests need to stay green; a marker near a tile edge looks
  off-centre with a single tile.
- **Map Kit** (static map or `MapComponent`): not tonight, because of the account and signing work in 2.1.

APIs: `http.createHttp().request(url, { expectDataType: http.HttpDataType.ARRAY_BUFFER, header })` from
`@kit.NetworkKit`; `image.createImageSource(buffer).createPixelMap()` from `@kit.ImageKit`; `Image(pixelMap)`.

```ts
// adapters/MapAdapter.ets, UNTESTED sketch, strict-mode ArkTS, not compiled.
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { City, cityById } from '../capabilities/WeatherData';

const TILE_HOST: string = 'https://tile.openstreetmap.org'; // fixed in code, never from a capsule
const USER_AGENT: string = 'Harmoniser/1.0 (+https://github.com/Akshaz7/capsules-harmonyos)';
const ZOOM: number = 12;
const MAX_TILE_BYTES: number = 200 * 1024;
export const MAP_SOURCE: string = '© OpenStreetMap contributors';
export const MAP_URL: string = 'https://www.openstreetmap.org/copyright';

export interface MapTile {
  pixels: image.PixelMap;
  /** Where the city sits inside the tile, 0..1 from the left and from the top, for the pin. */
  pinX: number;
  pinY: number;
}

interface TilePoint {
  x: number;
  y: number;
}

function tilePoint(latitude: number, longitude: number, zoom: number): TilePoint {
  const n: number = Math.pow(2, zoom);
  const rad: number = latitude * Math.PI / 180;
  const x: number = (longitude + 180) / 360 * n;
  const y: number = (1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2 * n;
  return { x: x, y: y };
}

export class MapAdapter {
  private cache: Map<string, MapTile> = new Map();

  /** One tile for a bundled city, or null when offline or refused. Call only after the gatekeeper allowed 'map'. */
  async tileFor(cityId: string): Promise<MapTile | null> {
    const hit: MapTile | undefined = this.cache.get(cityId);
    if (hit !== undefined) {
      return hit;
    }
    const city: City | undefined = cityById(cityId);
    if (city === undefined) {
      return null;
    }
    const p: TilePoint = tilePoint(city.latitude, city.longitude, ZOOM);
    const tx: number = Math.floor(p.x);
    const ty: number = Math.floor(p.y);
    const headers: Record<string, string> = { 'User-Agent': USER_AGENT };
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(`${TILE_HOST}/${ZOOM}/${tx}/${ty}.png`, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 6000,
        readTimeout: 6000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (resp.responseCode !== 200 || !(resp.result instanceof ArrayBuffer)) {
        return null;
      }
      const bytes: ArrayBuffer = resp.result as ArrayBuffer;
      if (bytes.byteLength === 0 || bytes.byteLength > MAX_TILE_BYTES) {
        return null;
      }
      const source: image.ImageSource = image.createImageSource(bytes);
      const pixels: image.PixelMap = await source.createPixelMap();
      await source.release();
      const tile: MapTile = { pixels: pixels, pinX: p.x - tx, pinY: p.y - ty };
      this.cache.set(cityId, tile);
      return tile;
    } catch (e) {
      hilog.warn(0x0001, 'MapAdapter', 'tile unreachable: %{public}s', (e as BusinessError).message);
      return null;
    } finally {
      req.destroy();
    }
  }
}
```

The sketch keeps tiles in memory only. Before shipping, write each tile to the cache directory and reuse it for at
least 7 days, which the tile policy requires.

**If it is not built, say this in the pitch:**

> A map is on the roadmap as one more component behind the same consent. Weather already shows the pattern: the
> capsule can only name a city from a list on the phone, the server address is fixed in our code and never comes
> from the capsule, and the consent sheet says exactly what leaves the phone and where it goes. A map is the same
> shape with a picture instead of a number.

Do not say "we support maps", and do not show a mock map.

---

## What I could not confirm

- Nothing was compiled or run. Every "working" verdict is from reading the code on `origin/main` `547d27b`.
- Whether motion counts on the emulator: the repo's own docs disagree (`PR12_REVIEW.md:235-236`).
- Whether the weather request currently works; the team is said to be fixing it and this was not investigated.
- Map Kit quota numbers for HarmonyOS NEXT, and whether an individual (non-enterprise) account gets the Map service
  outside China.
- Whether `petalMaps.openMap…` needs the Map service enabled, and whether a `geo:` URI is handled on HarmonyOS NEXT.
- Size and count limits for `formImages` in a widget.
- Whether `http.request` lets an app replace the default `User-Agent` header, and what the default is. The policy
  blocks library defaults, so this decides whether the tile option works at all; check it first.
- Whether `resp.result instanceof ArrayBuffer` compiles under the project's strict settings.
- What position the emulator reports to Location Kit.
- The wrist-screen suggestion was not checked against `adapters/DeviceRelay.ets`.
- MapTiler and Mapbox key requirements are from memory.
- The local checkout of `capsules-harmonyos` is at `0ffd7c9` on `main`; it was not compared with `origin/main`.

One thing to know: the single test request to `tile.openstreetmap.org` was sent with a User-Agent that contained
the account email address as the contact. It was one request for one tile.
