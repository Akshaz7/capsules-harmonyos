# HarmonyOS / ArkTS skill documents: download and vetting index

> AI-assisted vetting (a Claude Code sub-agent, 2026-10-04) of public community "skill" documents for HarmonyOS/ArkTS that were suggested to the team. Folder names refer to local clones made for the review; the repositories are not vendored here. Read this before loading any of them into an assistant.

Vetted 2026-10-04. Everything here is **community guidance, not Huawei-certified**. It was read as untrusted text; nothing in these folders was executed or installed. Total on disk: about 332 MB.

Target app for the accuracy checks: native HarmonyOS NEXT, ArkTS/ArkUI, Stage model, API 20 minimum, API 24 emulator, `@kit.*` imports, some `@ComponentV2`/`@Local`/`@Trace`, Form Kit widgets, Scan Kit, Network Kit http, Preferences.

## 1. What was downloaded

| Path | What it is | Verdict | Why |
|---|---|---|---|
| `douya-labs__harmony-app-dev/` | `SKILL.md` (139 lines) + 40 reference files (~11,400 lines), EN/ZH mixed. MIT, 2 stars, last commit 2026-05-13, 740 KB | **Load with edits** (pick single reference files) | Good capability map, UI token, resource, widget and permission notes. But: code samples break ArkTS strict mode, imports are old `@ohos.*` style, state management is V1 only, doc links are the `-V5` (API 12) set, one permission claim is wrong. Skip `references/development-workflow.md` (tells the assistant to commit and push). |
| `fadinglight9291117__arkts_skills/arkts-development/` | `SKILL.md` (297 lines) + 10 references + 3 `.ets` templates, EN. **No licence**, 7 stars, 2026-06-25 | **Load with edits** | Closest match to the app: `@kit.*` imports, V1 and V2 state tables, ArkTS restrictions. Edit out the CLI sections (hvigorw test, `codelinter --fix`, hstack) and note that `router.*`, `promptAction.showToast`, `getContext` are deprecated since API 18. |
| `fadinglight9291117__arkts_skills/harmonyos-build-deploy/` | Build and device-install skill (312 lines + 2 references) | **Reference only** | It is a list of shell commands (build, install, wipe app data, `rm -rf` on device). It does say "confirm with the user first", but should not be auto-loaded. |
| `MaxHan7__frontend-ui-standards-skill/frontend-ui-standards/` | One `SKILL.md` (193 lines), EN. MIT, 105 stars, 2026-06-27 | **Safe to load as-is** | Pure process guidance (tokens, component reuse, review checklist). Framework-agnostic; examples are SwiftUI/React/Flutter, so translate: tokens become `resources/base/element/*.json` + `$r()`. |
| `anthropics__skills/skills/frontend-design/` | One `SKILL.md` (72 lines), EN. Apache-2.0, 179.5k stars (whole repo), 2026-09-28. Sparse checkout, only this folder | **Load with edits** | Safe, no commands. Written for web pages (hero, CSS, custom typefaces). Its push for unusual typefaces and palettes works against HarmonyOS system-font and system-colour conventions; use only the restraint, copywriting and "avoid templated look" parts. |
| `CoreyLyn__harmonyos-skills/skills/harmonyos-review/` | `SKILL.md` (113 lines, EN) + checklist, doc routing, report template (ZH). MIT, 32 stars, 2026-07-23 | **Safe to load as-is** | Read-only review method: evidence bar, severity, "do not modify code". Makes almost no hard API claims. Many of its doc links are dead (see section 3). |
| `CoreyLyn__harmonyos-skills/skills/harmonyos-dev/` | The other skill in that repo: `SKILL.md` (93 lines) + 6 short ZH references (state, UI, persistence, network, permissions, performance) | **Safe to load as-is** | Same style: derive SDK from repo config, verify against official docs, never report an unrun check as passed. Checklists, not API recipes. |
| `linhay__harmony-next.skills/harmony-next/SKILL.md` | 247-line skill, EN/ZH, mostly DevEco/emulator automation. No LICENSE file (`package.json` says MIT), 358 stars, 2026-09-20 | **Do not use** | Drives 11 bundled Python scripts, states the user "has full execution permission by default" and that the skill does not ask for confirmation, can edit `~/.zshrc`, download archives, file GitHub issues. See section 4. |
| `linhay__harmony-next.skills/harmony-next/references/` | 72 MB offline snapshot of Huawei docs (API 12 to 23 guides, API 26 `.d.ts` declarations), ~4,280 `.md` | **Reference only** | Useful to grep. Content is Huawei's, not the repo author's. Guides stop at API 23; the team's emulator is API 24. Largely duplicated by the liasica mirror. |
| `liasica__harmonyos-skills/harmonyos/references/` | Mirror of 16,823 official doc pages (guides, API references, releases incl. 6.1.1(24) and 26.0.0, best practices, FAQs), ZH. MIT, 25 stars, last commit 2026-10-03. 225 MB (185 MB docs + 40 MB `.git`) | **Reference only** (grep, then read one page) | Each page keeps its official `url` and `doc_updated_at`. Pages spot-checked against the live site matched. This is the best offline source here. |
| `liasica__harmonyos-skills/harmonyos/rules/arkts-coding-rules.md` | 93-line list of ArkTS compile rules + API usage rules, ZH | **Safe to load as-is** | Matches the official migration guide rule by rule. Best single file for ArkTS correctness. |
| `liasica__harmonyos-skills/harmonyos/SKILL.md`, `install.sh`, `mcp/`, `.claude-plugin/` | Skill wrapper, installer, MCP server | **Do not use** (the wrapper and installer) | `install.sh` symlinks into `~/.claude/skills`, `~/.codex`, `~/.cursor` etc. and `rm -rf`s what is there; the plugin manifest starts an MCP server via `uv run`; `rules/online-fallback.md` has the assistant `curl` a Huawei endpoint. Not needed to read the docs. |

Other skills in `CoreyLyn/harmonyos-skills`: only two exist, `harmonyos-dev` and `harmonyos-review`.

### Not downloaded

| Item | Why | What to use instead |
|---|---|---|
| `openharmony/docs` (4.18 GB, CC-BY-4.0, last push 2026-08-22) | Far over the size limit | Paths below, confirmed to exist via the GitHub API |
| `linhay__harmony-next.skills/harmony-next.skill.zip` (11.7 MB) | Came with the clone; not extracted. It is a packaged copy of the same folder (64 MB unpacked) | Nothing; ignore it |

Useful `openharmony/docs` paths (prefix `https://github.com/openharmony/docs/blob/master/`):

- ArkTS rules: `en/application-dev/quick-start/typescript-to-arkts-migration-guide.md`
- State V2: `en/application-dev/ui/state-management/arkts-new-componentV2.md` (same folder: `arkts-new-local.md`, `arkts-new-observedV2-and-trace.md`)
- Layout: `en/application-dev/ui/arkts-layout-development-overview.md`
- Resources: `en/application-dev/quick-start/resource-categories-and-access.md`
- Form Kit: `en/application-dev/form/arkts-ui-widget-configuration.md`, API `en/application-dev/reference/apis-form-kit/js-apis-app-form-formProvider.md`
- Network Kit: `en/application-dev/network/http-request.md`, API `en/application-dev/reference/apis-network-kit/js-apis-http.md`
- Location Kit: `en/application-dev/device/location/location-guidelines.md`
- Permissions: `en/application-dev/security/AccessToken/request-user-authorization.md`
- Preferences: `en/application-dev/database/data-persistence-by-preferences.md`
- Scan Kit is a Huawei (HMS) kit and is **not** in `openharmony/docs`. Use the mirror: `liasica__harmonyos-skills/harmonyos/references/harmonyos-guides/scan-scanbarcode.md` and `harmonyos-references/scan-scanbarcode-api.md`.

## 2. Commands each skill would have an assistant run

None of these were run during vetting.

| Skill | Commands or actions it asks for |
|---|---|
| douya `harmony-app-dev` | No shell commands. `references/development-workflow.md` tells the agent to "commit + push" each stage and name the reference files in commit messages. `scripts/sync-references.mjs` (Node, writes files under `web/`) is the author's site generator; the skill never calls it. Points readers to `ohosdev.com`. |
| fadinglight `arkts-development` | `hvigorw onDeviceTest ...`, `hvigorw test ...`, `codelinter`, `codelinter --fix` (rewrites source files), `codelinter -i`, `hstack -i ... -o ...`. |
| fadinglight `harmonyos-build-deploy` | `hvigorw clean`, `hvigorw assembleApp/assembleHap/assembleHsp/assembleHar`, `hvigorw --sync`, `ohpm install --all`, `ohpm clean && ohpm cache clean`, `ohpm install --registry https://repo.harmonyos.com/ohpm/`, `hdc list targets`, `hdc shell mkdir/rm -rf` (on device), `hdc file send`, `bm install -r`, `bm uninstall`, `bm clean -c` / `-d` (wipes app cache/data), `aa start`, `aa force-stop`, `hdc kill && hdc start`, `rm outputs/*.hsp`, `find`. Also says to always delegate these to a subagent. |
| MaxHan7 `frontend-ui-standards` | "Run the relevant build/typecheck", "install or run in simulator/device", "capture a screenshot when feasible". No concrete command lines. `agents/openai.yaml` sets `allow_implicit_invocation: true`. |
| anthropics `frontend-design` | None. Suggests taking screenshots if the environment supports it. |
| CoreyLyn `harmonyos-review` | Five example `rg -n ...` searches (read-only), "inspect working-tree state", "run the narrowest relevant build/test commands when authorized". Explicitly: do not modify code or write reports unless asked. README (not the skill) shows `npx skills add coreylyn/harmonyos-skills`. |
| CoreyLyn `harmonyos-dev` | "Compile or build the affected module", "run related tests". No concrete command lines. |
| linhay `harmony-next` | `rg` lookups; `python3 scripts/commandline_tools_manager.py doctor/download/install/bootstrap/configure`; `hvd_manager.py doctor/list/launch/launch-preflight` (starts the emulator, `--accept-license`); `device_evidence_bundle.py capture/webview-devtools` (screenshots, layout dumps, logs, port forward); `device_ui_action.py tap`; `ux_audit_pipeline.py capture-audit`; `profiler_trace_audit.py audit`; `sync_api26_snapshot.py`; `hdc list targets`, `hdc shell uitest dumpLayout/screenCap/uiInput`, `hdc file recv`, `bm dump`, `aa dump`, `hilog`; `ohpm install`; `hvigorw ... assembleHap`; `npx skills add ...`, `gemini skills install ...`; `gh issue create --repo linhay/harmony-next.skills`. |
| liasica `harmonyos` | `rg -n "<keyword>" references/INDEX.md`; online fallback: `curl -X POST https://developer.huawei.com/consumer/cn/documentPortal/getDocumentById ... | jq | pandoc`. `install.sh` (not referenced by the skill): `git clone/pull`, `ln -s`, `rm -rf` on existing skill dirs. |

## 3. API spot-checks

Sources: live `developer.huawei.com` pages fetched with the Parallel web tools, plus the liasica mirror (each mirror page records its official URL). "Mirror" below means checked in the mirror only.

### douya `harmony-app-dev`

| Claim | Result | Source |
|---|---|---|
| `updateDuration` is in units of 30 minutes | Right | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-configuration |
| `authResults` value `-1` means "never ask again" (banned) | **Wrong.** `-1` is "not granted"; `2` is "invalid request"; use `dialogShownResults` to tell refused-now from no-longer-prompting | https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-permissionrequestresult |
| Function-parameter destructuring is not allowed | Right (`arkts-no-destruct-params`) | https://developer.huawei.com/consumer/en/doc/harmonyos-guides/typescript-to-arkts-migration-guide |
| Its own sample code (`constructor(private opts)`, object spread `...headers`, `unknown`, `throw lastErr`, `type R = { success: true; ... } | {...}`) | **Would not compile**: `arkts-no-ctor-prop-decls`, `arkts-no-spread`, `arkts-no-any-unknown`, `arkts-limited-throw`, `arkts-no-obj-literals-as-types` | same migration guide |
| `@Persistent('settings')` decorator (shown commented out) | **No such decorator** in the mirror; persistence is `PersistentStorage` (V1) or `PersistenceV2` | mirror search |
| `postCardAction` actions are `router`, `call`, `message` | Right | https://developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-form-overview |
| Use `colorMode: "auto"` for widget dark mode | **Outdated.** Deprecated from API 20, only ever applied to JS cards; cards follow the system mode | widget configuration page above |
| `connectTimeout`/`readTimeout` in ms, call `destroy()` | Right (both default 60000) | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-http (mirror) |
| Type scale 11/12/14/16/18/20/24/28 fp, radii 4/8/12/16/24, 48 vp buttons | **Not verified.** I found no official page with these exact scales; treat as the author's convention | n/a |

### fadinglight `arkts-development`

| Claim | Result | Source |
|---|---|---|
| State management V2 from API 12 | Right | https://developer.huawei.com/consumer/en/doc/harmonyos-references/ts-custom-component-decorator-componentv2 |
| `@Local` cannot be initialised from outside; `@Param` is read-only in the child and needs a local default or `@Require` | Right | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-new-local , .../arkts-new-param (mirror) |
| `any`, `unknown`, `var`, `for..in`, `obj['key']`, `#private`, structural typing, `in` are prohibited | Right | migration guide |
| `router.pushUrl` / `router.getParams` from `@kit.ArkUI` | Works, but **deprecated since API 18**; use `this.getUIContext().getRouter()`, and Navigation is the recommended approach | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-router (mirror) |
| `promptAction.showToast(...)` | **Deprecated**; use `getUIContext().getPromptAction()` | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-promptaction (mirror) |
| http example (`@kit.NetworkKit`, 60000 ms defaults, `destroy()`) | Right | js-apis-http (mirror) |
| `hvigorw assembleHap -p module=entry@default --mode module`, `--no-daemon` recommended on the command line | Right | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-commandline (mirror) |
| codelinter flags `-c`, `--fix`, `-f`, `-o`, `-i`, `-p`, `-e` | Right | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-codelinter (mirror) |
| `UIUtils.getTarget()` fixes `JSON.stringify` of an `@ObservedV2` object | **Not supported by the docs.** The official page only shows the output gaining `__ob_` key prefixes; no `getTarget` fix is given | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-new-observedv2-and-trace (mirror) |
| "Cannot mix V1 and V2" | Oversimplified. Mixing rules were relaxed from API 19; V1 decorators still cannot be combined with `@ObservedV2` classes | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-v1-v2-mixusage (mirror) |

### CoreyLyn `harmonyos-review` / `harmonyos-dev`

These make few concrete API claims on purpose.

| Claim | Result | Source |
|---|---|---|
| V1/V2 mixing validity depends on exact decorators and SDK | Right | arkts-v1-v2-mixusage (mirror) |
| Preferences: writing and persisting are different moments | Right (`flush` persists) | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-preferences (mirror) |
| Each http request object has one owner and must be released | Right ("one HttpRequest per request, not reusable") | https://developer.huawei.com/consumer/en/doc/harmonyos-guides/http-request |
| Not every declared permission can be requested at runtime | Right (system_grant vs user_grant; `authResults` 2 for invalid) | permissionrequestresult page |
| Doc link `harmonyos-guides/arkts-http-request` | **Dead: returns 404.** The real slug is `http-request` | fetched live |
| Other doc links | 9 of 17 slugs checked (`arkts-websocket`, `arkts-socket`, `arkts-preferences`, `arkts-relational-store`, `arkts-acquire-permissions`, `permissions`, `arkts-file-management`, `data-management`, `network-management`, `harmonyos-references/arkui-overview`) are absent from the 16,823-page mirror, so probably dead too | mirror index |

### linhay `harmony-next` (references snapshot)

| Claim | Result | Source |
|---|---|---|
| `hvigorw --mode module -p module=entry@default assembleHap` | Right | ide-hvigor-commandline (mirror) |
| API 26 `formInfo` declaration has `updateDuration: number` | Consistent with the widget configuration page | live page above |
| Snapshot covers API 12 to 23 guides | Means **API 24 (6.1.1) guide changes are missing**; the liasica mirror has the 6.1.1(24) release notes | mirror index |
| "SDK 26.0.0 released 2026-08-29" | Release exists in the mirror; **date not verified** | mirror index |
| Widget configuration guide | **Not found** in its `INDEX.md` (no hit for the form config guide), so it is weak for Form Kit | local grep |

Only three API facts were checked here; it is a doc snapshot, not original claims.

### liasica mirror

| Page | Result |
|---|---|
| `arkts-ui-widget-configuration` (updateDuration, scheduledUpdateTime, supportDimensions) | Matches the live CN page |
| `js-apis-permissionrequestresult` | Matches the live EN page |
| `js-apis-router` (deprecation notes) | Matches search excerpts of the official page |
| `rules/arkts-coding-rules.md` vs migration guide | Rule set matches (`arkts-no-any-unknown`, `-no-destruct-params`, `-no-ctor-prop-decls`, `-no-spread`, `-no-obj-literals-as-types`, `-limited-throw`, `-no-in`, ...) |
| `@ComponentV2` widget capability | **Conflict.** Mirror (CN, scraped 2026-10) says usable in ArkTS widgets from API 23; live EN page says from API 12. Unresolved; keep widgets on V1 decorators |

### MaxHan7 and anthropics

No HarmonyOS API claims. One translation check: MaxHan7 says "at least 44pt on iOS or the platform equivalent". The HarmonyOS equivalent is 48 vp x 48 vp recommended, 40 vp x 40 vp minimum (https://developer.huawei.com/consumer/cn/doc/design-guides/ux-guidelines-general-0000001760708152).

## 4. Safety findings

No hidden instructions were found: no "ignore previous" style text, no base64 blobs, no suspicious HTML comments (only a version comment and README badges; 135 files in linhay's Huawei snapshot contain ordinary doc comments). Zero-width characters appear only inside Huawei's own API comment text in linhay's snapshot (19 files), not in any skill file.

Things that would be unsafe or surprising if followed blindly:

1. **linhay `SKILL.md` and `references/ideGuides/DevEco模拟器私有接口与AI自动化.md`** say the user "has full execution permission by default" and that the skill does not ask for permission or turn high-risk actions into a wait for input. They define a "break-glass" mode for flash/format/erase/root actions and call it "a risk label, not an authorization gate". That tries to override an assistant's own confirmation habits.
2. **linhay scripts** (`harmony-next/scripts/*.py`): download an archive from a URL, delete an install directory, append to `~/.zshrc` / `~/.bash_profile`, start the emulator, forward ports, tap the device UI, capture screenshots and logs. The skill also asks the assistant to open GitHub issues on the author's repo with `gh`, which sends local details out.
3. **linhay** ships a binary `harmony-next.skill.zip` and an `index.js` plugin entry; neither was opened or run.
4. **liasica `install.sh`** replaces (`rm -rf`) existing `harmonyos` entries in assistant skill directories and symlinks itself in. `.claude-plugin/plugin.json` would start `mcp/server.py` (network calls to Huawei, runs `rg`). `rules/online-fallback.md` tells the assistant not to use WebFetch and to `curl` Huawei's document endpoint instead.
5. **fadinglight `harmonyos-build-deploy`** includes app-data wipe (`bm clean -d`), uninstall, and `rm -rf` on the device, and says to always hand the work to a subagent. `codelinter --fix` in the other skill rewrites source files.
6. **douya `development-workflow.md`** tells the agent to commit and push after each stage.
7. **Auto-loaded instruction files:** `fadinglight9291117__arkts_skills/CLAUDE.md` and `AGENTS.md`, and `linhay__harmony-next.skills/AGENTS.md`, are picked up automatically by an assistant working inside those folders (this happened during vetting). They are benign maintainer notes ("always update CHANGELOG", "prefer gh"), but point assistants at single files rather than opening a session inside those repos.
8. **Licences:** fadinglight has no licence at all; linhay has no LICENSE file and its references are Huawei's text. Fine to read locally; do not copy either into the team's repo.

## 5. Usefulness tonight

(a) UI and widget polish, (b) weather component + request router, (c) ArkTS review.

| Skill | (a) | (b) | (c) |
|---|---|---|---|
| douya `harmony-app-dev` | **High**: `ui-design.md`, `resource-management.md`, `widget-cookbook.md` give token, dark-mode and card structure | Medium: right concepts for http, permissions, location, but samples need rewriting to compile | Low: its own samples break the rules |
| fadinglight `arkts-development` | Low: layout basics only, no design conventions | **High**: `@kit.*` http, Preferences, V2 state patterns close to the app | Medium: restriction table and migration guide are right but short |
| MaxHan7 `frontend-ui-standards` | Medium: good token/reuse discipline, not HarmonyOS-specific | Low: not about data or state | Low: UI consistency only |
| anthropics `frontend-design` | Medium for in-app screens, **Low for widget cards** (cards must follow system conventions) | Low | Low |
| CoreyLyn `harmonyos-review` | Low | Low | **High** for method (evidence, lifecycle, async races); it has no compiler-rule list |
| CoreyLyn `harmonyos-dev` | Medium: UI checklist (states, dark mode, font scaling) | Medium: network and permission checklists | Medium |
| linhay references | Low | Medium: API declarations to grep | Low |
| liasica mirror + `arkts-coding-rules.md` | Medium: official widget, dark-mode, resource pages | **High**: exact http, location, permission, Scan Kit pages | **High**: the compile-rule list |

## 6. How to use these

- **UI polish:** hand the assistant `DIGEST.md` plus `douya-labs__harmony-app-dev/references/ui-design.md` (treat its numbers as a convention, not a Huawei spec) and, for discipline, `MaxHan7__frontend-ui-standards-skill/frontend-ui-standards/SKILL.md`.
- **ArkTS correctness:** hand it `liasica__harmonyos-skills/harmonyos/rules/arkts-coding-rules.md` plus `CoreyLyn__harmonyos-skills/skills/harmonyos-review/SKILL.md` and its `references/checklist.md`.
- **API questions:** search `liasica__harmonyos-skills/harmonyos/references/INDEX.md` for the keyword, then read that one page and cite its `url`.
- Give assistants individual files, not whole repos, and do not install any of these as skills or plugins.
- All of this is community material. Where it disagrees with developer.huawei.com or with what DevEco Studio's compiler says for the project's SDK, the official source wins.
