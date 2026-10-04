# Ship runbook: Harmoniser, final hours (HackYeah 2026, Huawei "Imagine What's Next")

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04, about 03:15). Written from the code and documents of both repositories, Huawei's documentation and a few read-only requests to the live relay. Nothing was built, installed or run on a device or emulator; the commands below were not executed. Line references are to the commits named in the text and will drift. Paths such as `research/…` mean this folder; the "offline mirror" of Huawei's docs is not in this repository.
>
> **Update when this file was added to the repository:** item 1 of section 0 and the open question near the end ask whether PR #13 conflicts in `README.md`. `main` at `b54cbfe` has since been merged into PR #13's branch with no conflict, and a test merge into `main` is clean.


Written Sunday 4 Oct 2026, about 03:15 CEST. **Deadline: 11:00 today, on HackTribe.** Mentors loan phones from about 08:05.

How this was produced: AI-assisted desk research (Claude Code). Read-only: nothing was built, installed, changed or pushed. I read `origin/main` of both repos after a fetch at about 03:00, the challenge repo, the participant guide, the Huawei rules PDFs, an offline mirror of Huawei's docs, and made a handful of harmless HTTPS requests to the live relay.

Tags used below: **[DOC]** Huawei docs (file in the offline mirror, `harmony-skills/.../references/`). **[FAQ]** the challenge FAQ or statement (`onirodeveloper/hackyeah2026-challenge`, one commit, 1 Oct). **[CODE]** read in the code at `origin/main`, with file:line. **[LIVE]** seen on the live site at about 03:00. **[J]** my judgement. **[U]** unverified.

Earlier work this builds on, not repeated here: `research/SUBMISSION_CHECKLIST.md` (rules, deliverables, claims to fix) and `research/DEMO_REVIEW.md` (video script, Cut A and Cut B, shot list, captions). Both were written against `7292381`; main has moved (see section 1).

Owners: **App** = the app owner with DevEco Studio on the Mac (Ash). **Web** = the web repo owner (Lewis). **Any** = anyone with a laptop (Keanu included).

---

## 0. The six things to know before starting

1. **The merge plan in the brief is already mostly done.** PRs #14, #15 and #16 are merged; `origin/main` is `b54cbfe` ("Merge PR #16", 03:00 CEST). Only **#13 (docs)** is open, and it is now docs-only against main (12 files). GitHub reports it MERGEABLE/CLEAN, but a local `git merge-tree origin/main origin/docs/fix-contradictions` reports **a conflict in `README.md`**. Expect to resolve it by hand. [LIVE, U which is right]
2. **Which branch ships is not settled in what I can see.** The draft release `test-builds-lewis-1` describes a second build from `redesign/app` at `0fdeaa6` ("the UI redesign plus PRs #14-#16 ... 296/296 tests; the add-to-home fix is in Build 2 only"). That commit is **not on `origin`** (no such branch, object not found after fetch). `origin/main` has 286 `it(` calls. If the redesign is what ships, it must be pushed and merged before the freeze. **App owner decides at 03:30.** [LIVE]
3. **The app has no build-info string.** `versionName` is `1.0.0` and `versionCode` `1000000` (`AppScope/app.json5`), the same as `test-1`. Nothing in `entry/src/main/ets` prints a commit. The only proof of which commit a `.hap` came from is the SHA-256 in the release notes plus the commit recorded at build time (step 5). [CODE]
4. **The app has never been run against the live relay.** Section 4 is the test and the mismatches I found by reading. The two that will show on camera: the timer status line moves in 10-second jumps, and after clearing app data the browser tab stays paired to a token the app no longer has (press **New device** in the tab).
5. **`bm clean -d` wipes more than capsules.** It clears the app's data, so the pushed model (480 MB), `config.local.json`, the install token and the paired-device list go with it. Push the config and model again after every data clean. [J from DOC `bm-tool.md:175-196`, U that the files dir is included; assume it is]
6. **The `.hap` on the GitHub release is for the emulator.** A debug-signed `.hap` installs only on phones whose UDID is in its profile. See section 3.

---

## 1. Timeline, working backwards from 11:00

"Latest start" is the last moment the step can begin and still leave the later steps their time. If a step is not started by then, take its fallback and move on.

| # | Step | Owner | Target start | **Latest start** | Lasts | Fallback if it fails or runs late |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Decide what ships (main vs redesign). Resolve and merge PR #13 | App + Any | 03:20 | 04:30 | 30 min | Ship `origin/main` as it is. Leave #13 for step 11 (docs can merge after the build: they are not in the `.hap`) |
| 2 | Live-relay test on the emulator (section 4) | App, Web on call | 03:40 | 05:00 | 30 min | Drop the second-screen beat from the video; README keeps "not tested against the live relay" |
| 3 | **Code freeze** (no more changes under `entry/`, `cactus/`, `AppScope/`) | App | **04:30** | **06:00** | - | Freeze whatever passes the unit tests at 06:00 |
| 4 | Unit tests, then build the final `.hap` from the frozen commit | App | 04:30 | 06:00 | 20 min | Use the newest build that passed smoke tests; say its commit in the release notes |
| 5 | Record the commit, checksum and key scan | App | 04:50 | 06:20 | 10 min | - |
| 6 | Smoke test, 10 items (section 5) | App | 05:00 | 06:30 | 15 min | Any failing item is cut from the video and listed as a known limitation |
| 7 | **Record the video: safe cut first** (Cut B), then the extras | App | 05:15 | **07:00** | 75 min | Cut B alone is a complete video |
| 8 | Edit, voice-over, captions, export | Any (not the App owner) | 06:30 | 08:15 | 60 min | Captions only, no voice-over |
| 9 | Phone slot: re-sign, install, model, config, phone shots (section 3) | App + mentor | 08:05 | 08:45 | 40 min | No phone footage. The emulator video stands alone ("The emulator is the expected default" [FAQ]) |
| 10 | Upload the video (unlisted) and publish the GitHub release | App (repo owner) or Any with push | 09:00 | **09:45** | 20 min | Attach the MP4 to the release only; skip YouTube |
| 11 | README and brief final pass: links, TBDs, status stamp; merge | Any, App reviews | 09:20 | 10:00 | 20 min | Change only the two TBD lines and the status stamp |
| 12 | Tag both repos at the submitted commits | App, Web | 09:50 | 10:15 | 5 min | Tag the app repo only; put the web SHA in the README |
| 13 | **HackTribe: fill, save, re-open, screenshot** | App (team leader) | **10:00** | **10:30** | 20 min | Save with the repo link alone at 10:30, then add the other links |
| 14 | Hands off | Everyone | **10:45** | - | - | - |

Do steps 8 and 11 on a second laptop while the App owner records and handles the phone. Start filling HackTribe text fields (name, description, team) at any quiet moment from now: only the links need to wait. [J]

---

## 2. Steps 1 to 6: merge, freeze, build, verify

Paths below are the repo's own (macOS, DevEco Studio 6.1.1). Run from the repository root.

```sh
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
EMU=127.0.0.1:5555
B=com.hackyeah.capsules
```

### Step 1. Merge (App + Any)

Agreed order was #14 (merge commit), #16, #15, #13. The first three are in. For #13:

```sh
git fetch origin
git switch -c merge-13 origin/main
git merge --no-ff origin/docs/fix-contradictions     # expect a conflict in README.md
# keep main's newer feature rows; take the PR's corrected wording elsewhere
git diff --name-only origin/main...HEAD | grep -vE '\.md$' && echo "STOP: non-docs change"
git push origin merge-13:main        # or update the PR branch and merge on GitHub
```

Expected: only `.md` files differ from main. Verify: `gh pr view 13 --repo Akshaz7/capsules-harmonyos --json state` says `MERGED`.

### Step 3 and 4. Freeze, test, build (App)

```sh
git fetch origin && git switch main && git pull --ff-only
git status --short            # must be empty, except build-profile.json5 if auto-signing wrote to it (see below)
SHA=$(git rev-parse HEAD); echo "$SHA" > /tmp/harmoniser-submit.sha; git log -1 --format='%h %ci %s'

# unit tests (README "Run the unit tests")
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  --mode module -p module=entry@default -p product=default test --no-daemon
tail -1 entry/.test/default/intermediates/test/coverage_data/test_result.txt
# expect: Failure: 0, Error: 0

# build: the command the repo uses (README "Setup, build, install, launch")
devecocli build --modules entry
```

The same build with hvigor directly, if `devecocli` misbehaves [DOC `harmonyos-guides/ide-command-line-building-app.md:206, 246-248`]:

```sh
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

From DevEco Studio: **Build > Build Hap(s)/APP(s) > Build Hap(s)**, with product `default` and build mode `debug` selected in the toolbar.

What comes out [DOC same file, line 263; CODE README]:

| File | When |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | Always |
| `entry/build/default/outputs/default/entry-default-signed.hap` | Only when `build-profile.json5` has a `signingConfigs` entry and the files it names exist. "The signed package can run directly on a real device." |

- **Build mode: debug, for both files.** `buildMode` defaults to debug for a HAP [DOC line 246]. Keep it: `hdc file send -b` (the model and the config) needs an app "signed with a debug certificate, and already started on the device" [DOC `harmonyos-guides/hdc.md:592, 868`]. The release build mode is configured in `entry/build-profile.json5` but nothing in the repo uses it.
- **Debug mode versus release mode:** debug keeps `debuggable` true and debug information; release sets it false and optimises the bytecode [DOC `ide-hvigor-compilation-options-customizing-guide.md:26-47`]. The documented release command is `hvigorw --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap` (same file, line 39). Do not use it today.
- **How long:** not recorded anywhere in the repo. [U] Allow 5 minutes for an incremental build and 10 for a clean one. `cactus/BUILD.md` gives 45 s for the native engine alone, which is prebuilt and not rebuilt here.
- **Auto-signing writes into `build-profile.json5`.** The mentor's login filled `signingConfigs` on the App owner's laptop, so that file shows as modified. Do not commit it (README, and FAQ "Should I commit my keystore and its passwords? You shouldn't"). It does not change the app's code. For a tree that is clean by construction, build the public `.hap` from a second worktree [J]:

```sh
git worktree add ../capsules-release "$SHA" && cd ../capsules-release
devecocli build --modules entry      # signingConfigs is [] here, so only the unsigned .hap is produced
```

### Step 5. Record what was built (App)

```sh
OUT=entry/build/default/outputs/default
S7=$(cut -c1-7 /tmp/harmoniser-submit.sha)
mkdir -p ~/harmoniser-release
cp $OUT/entry-default-unsigned.hap ~/harmoniser-release/harmoniser-$S7-emulator-unsigned.hap
cd ~/harmoniser-release && shasum -a 256 *.hap > SHA256SUMS.txt && cat SHA256SUMS.txt

# no key inside the package (a .hap is a zip)
rm -rf /tmp/hapscan && unzip -q harmoniser-$S7-emulator-unsigned.hap -d /tmp/hapscan
find /tmp/hapscan -name 'config.local.json'                       # expect: nothing
grep -rIlE 'sk-ant-|"apiKey"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_-]{16,}' /tmp/hapscan   # expect: nothing
ls /tmp/hapscan/libs/                                             # expect: arm64-v8a only
```

If `config.local.json` is found inside: it was left in `entry/src/main/resources/rawfile/`. Delete it there, rebuild, and treat the key as leaked (rotate it). [CODE `core/index.ets:4-7`]

### Install on the emulator

The team's emulator is the DevEco phone emulator, API 24, on Apple Silicon (README; `test-1` notes). The native library is **arm64-v8a only** (`cactus/build-profile.json5` `abiFilters`, `cactus/libs/arm64-v8a/`), so an x86-64 emulator cannot load it; an ABI mismatch at install is error `9568347` [DOC `bm-tool.md:2885`]. Whether the package installs at all on a Windows x86-64 emulator is still untested. [U] The emulator needs no signature "in most cases" [DOC `ide-emulator-specification.md:11`].

```sh
$HDC list targets                                   # expect 127.0.0.1:5555
$HDC -t $EMU install -r ~/harmoniser-release/harmoniser-$S7-emulator-unsigned.hap
$HDC -t $EMU shell aa start -a EntryAbility -b $B
$HDC -t $EMU shell "bm dump -n $B" | grep -E '"versionName"|"versionCode"|"installTime"|"appProvisionType"'
```

`install -r` over an existing install keeps app data and the model (`scripts/push-model.sh` header). If install fails with `9568332 install sign info inconsistent`, the copy on the device was signed differently: `$HDC -t $EMU uninstall $B`, then install again (data is lost) [FAQ "Installing a new build fails because the signing information differs"].

### `config.local.json` (section 4 of the brief)

How the app reads it [CODE]: three readers, each looking in the application files dir and then the module files dir (`core/index.ets:117-128` for the model providers, `adapters/MarketplaceClient.ets:305-320` for `marketplace.baseUrl`, `adapters/DeviceRelay.ets:389-414` for `devices.relayBaseUrl`). The model reader also falls back to `rawfile/config.local.json` inside the `.hap`, which must never ship. It is read at launch, so restart the app after pushing.

Create the file **in an editor**, outside the repository or in its root (it is git-ignored by `*.local.json`):

```json
{
  "default": "mistral",
  "providers": { "mistral": { "apiKey": "<your Mistral key>", "model": "ministral-14b-latest" } },
  "marketplace": { "baseUrl": "https://harmoniser.keanuc.net" },
  "devices": { "relayBaseUrl": "https://harmoniser.keanuc.net" }
}
```

```sh
$HDC -t $EMU file send -b $B config.local.json data/storage/el2/base/files/
$HDC -t $EMU shell "aa force-stop $B; aa start -a EntryAbility -b $B"
```

Verify: the home status line names Mistral ("Mistral (EU) when needed"); the Marketplace tab lists live capsules; a timer or counter capsule page shows **Show on another device** without the orange "Simulated device" line. Both URLs must be `https` (`MarketplaceClient.ets:316`, `DeviceRelay.ets:423-425`). Do **not** set `devices.simulate`.

Keeping the key out of the repo and the recording:
- `git status --short` must never list `config.local.json`; `git check-ignore -v config.local.json` should name the `.gitignore` rule.
- Never `cat` the file or open it in an editor while recording. Record only the emulator window (Cmd+Shift+5, selected portion), not the terminal.
- The app never shows the key; error messages are written not to include it (`ModelProvider.ets:186`).
- The public `.hap` is scanned in step 5. Judges get no key: without one the app still runs on rules, templates and the on-device model.

### The model on the emulator

```sh
scripts/push-model.sh                 # downloads 383 MB once to ~/.cache/harmoniser, pushes about 480 MB
$HDC -t $EMU shell "aa force-stop $B; aa start -a EntryAbility -b $B"
$HDC -t $EMU shell hilog | grep cactus_init      # expect: cactus_init ok in ... ms
```

Without the model the app skips on-device inference, the status reads "On-device model not installed", and rules, templates and the cloud still work (`CactusProvider.ets:38, 608-611`; README).

---

## 3. The phone slot at 08:05 (step 9)

Signing is not a blocker: a Huawei mentor signed in on the App owner's laptop and the app has already run on a real phone. What is left is repeating that for the **final** build on **whichever phone is loaned**.

### The one risk

A debug profile lists device UDIDs. Installing on a phone that is not in it fails with `9568423 ... make sure the UDID of your device is configured in the signing profile` [DOC `bm-tool.md:2641`] or `9568322 signature verification failed due to not trusted app source`; cause three in Huawei's list for the latter is "the signature does not contain this debugging device's UDID", and the fix is "use automatic signing: after connecting the device, sign the app again" [DOC `bm-tool.md:1007-1028`, translated]. Automatic signing writes every connected device into the profile [DOC `ide-signing-auto.md:32, 131`, translated], needs the IDE to be signed in [DOC `ide-signing-auto.md:121`], needs the network, and needs the Mac's clock to be correct [DOC `ide-signing-auto.md:21`; `harmonyos-faqs/faqs-signature-service-22.md`]. An unsigned `.hap` on a phone fails with `9568320 no signature file` [DOC `bm-tool.md:533`].

So:
- **If today's loaned phone is the same unit as before:** rebuild and install; nothing to sign.
- **If it is a different unit:** auto-signing must run again with that phone connected, which needs the Huawei ID session in DevEco to still be valid. **Do not sign out of DevEco or restart the Mac before 08:05.** If the session has expired, ask the mentor to sign in again; that is the only thing to ask them about signing. [J]
- Debug profiles are short-lived: the FAQ says about 14 days were observed. Not a concern today.

What the challenge says about the handed-in `.hap` [FAQ]: the deliverable is "a working `.hap` package"; "The emulator is the expected default"; "Mentors have devices on site if you want to try it on real hardware"; and "You only need an account-backed signing configuration once you want a `.hap` you can hand in or share." Nothing says the jury installs on phones. **My reading [J]:** attach the unsigned emulator `.hap` as the main asset, say plainly in the notes that a phone needs a build signed for that phone (README "Signing for a physical device"), and do not attach the debug-signed `.hap` unless a mentor asks for it: it installs only on the listed devices and would fail on anyone else's phone.

### Steps

Phone [DOC `ide-developer-mode.md:15`, `ide-run-device.md:20-27`]: if Settings > System has no "Developer options", open Settings > (device name), tap "Software version" seven times, confirm, enter the PIN; the phone restarts. Then Settings > System > Developer options > **USB debugging** on, with the cable connected. Tap **Allow** on "Allow USB debugging" and **Always trust** on the trust prompt. A phone that shows as `Unauthorized` in `hdc list targets` has not been trusted yet. A mentor's loan phone probably has all this done already. [J]

```sh
$HDC list targets                         # the phone shows as a serial; call it PHONE
PHONE=<serial>
$HDC -t $PHONE shell bm get --udid        # prints the UDID (DOC bm-tool.md:204-222)
```

In DevEco Studio, with the phone connected and selected: **File > Project Structure > Project > Signing Configs**, tick **Automatically generate signature**, OK [DOC `ide-signing-auto.md:121-124`]. Then build (same command as step 4, on the frozen commit) and:

```sh
$HDC -t $PHONE install -r entry/build/default/outputs/default/entry-default-signed.hap
$HDC -t $PHONE shell aa start -a EntryAbility -b $B        # must be launched once before any "-b" file transfer
$HDC -t $PHONE shell "bm dump -n $B" | grep appProvisionType   # expect "debug" (DOC hdc.md:2299-2310)

$HDC -t $PHONE file send -b $B config.local.json data/storage/el2/base/files/
scripts/push-model.sh $PHONE              # device id is the script's optional argument
$HDC -t $PHONE shell "aa force-stop $B; aa start -a EntryAbility -b $B"
```

Or simply press Run in DevEco with the phone selected, then run the three `file send` lines.

Notes on the model push to a phone:
- `-b` works on a real phone as long as the app is debug-signed and has been started [DOC `hdc.md:592`]. Both hold for an auto-signed debug build.
- `push-model.sh` checks the files dir with `hdc shell ls -d /data/app/el2/100/base/<bundle>/haps/entry/files`. The team's `phone-photo-eval.sh` uses the same check and has run on a real phone (commit `cd886e9`), so it should pass. If it reports "the app's files dir still does not exist", send by hand: `$HDC -t $PHONE file send -b $B ~/.cache/harmoniser/lfm2-vl-450m-cq4 data/storage/el2/base/haps/entry/files/` and expect `FileTransfer finish`. [J]
- Time for 480 MB over USB: not measured. [U] Start it first and do the other set-up while it runs. No size limit is documented for `hdc file send` [DOC `hdc.md:781-811`].
- The engine is compiled for `armv8.2-a+fp16+dotprod+i8mm` (`cactus/BUILD.md` notes). A phone whose CPU lacks these would crash on load; the earlier phone run suggests the Pura 70 is fine. [U for any other model]

Phone footage worth 10 minutes, in this order [J]: (1) On-device only mode, a request that ends "Made on-device"; (2) `count my shakes`, shake; (3) scan the `/device` QR code with **Scan its QR code**. Record with DevEco's Log-tab recorder or the `hdc` recorder commands in section 6, or film the phone with another phone if that is quicker.

---

## 4. App against the live relay (step 2): test, pass criteria, mismatches

### Before you start

- Emulator with the final or near-final build, `config.local.json` pushed with `devices.relayBaseUrl` (section 2), app restarted.
- A desktop browser window at `https://harmoniser.keanuc.net/device`, **kept visible in its own window** next to the emulator. It shows a QR code and three words. [LIVE: `/device`, `/pair` 200; `/api/devices` without a token 401 `{"error":{"code":"unauthorized",...}}`; with a fresh token `{"devices":[]}`; unknown device 404 `not_found`; unknown code 404 `code_not_found`; 0.14 to 0.17 s each]
- A terminal running `$HDC -t $EMU shell hilog | grep -E 'DeviceRelay|device send'` for evidence. It never prints the token (`InstallToken.ets:67`).

### Steps

| # | Do | Pass looks like |
| --- | --- | --- |
| 1 | Create `count my squats`, allow, **Run capsule**, open it, tap + three times | Card "Made by rules"; a **Show on another device** panel with two buttons, and no "Simulated device" line |
| 2 | **Type its 3 words**, type the words from the browser (any case, spaces or hyphens), **Pair** | Toast "Paired with Browser". The browser tab stops showing the code. The panel lists "Browser" |
| 3 | **Show on Browser** | Dialog: `Only this leaves your phone: counter "<label>", the count 3.` |
| 4 | **Send** | Status "Sent. Waiting for the device..." then, within about 4 s, `On Browser: <label> 3`. The browser shows the counter at 3 |
| 5 | Tap **+** in the browser twice | Status becomes `On Browser: <label> 5` within about 4 s. **The phone's own counter stays at 3**: that is how the code is written, not a failure |
| 6 | Open the capsule's log | An entry "sent to Browser: counter ..." |
| 7 | Create `tea 4 min`, run, open, **Show on Browser**, **Send** | Dialog `timer "Tea", 240 seconds`. The browser counts down every second. The app's line reads `On Browser: Tea 4:00` and then **changes about every 10 seconds** (3:50, 3:40) |
| 8 | In the dialog of a third send, tap **Don't send** | Nothing changes in the browser; log entry "refused: show on Browser" |
| 9 | Tap the bin icon next to "Browser" | The device leaves the list. Within a few seconds the browser shows a new code |
| 10 | On a real phone only: **Scan its QR code** at the browser | Same as step 2 |

Evidence to keep: a screen recording of the emulator and browser side by side for steps 2 to 7 (it doubles as beat A8 of the video), the hilog lines `device send -> version N`, and one screenshot of the log entry. Then update the README sentence "It has not been tested against the mock relay or the live relay" with what was actually seen.

### Mismatches between the app's client and the live API

Ordered by how likely each is to bite today. File:line is `origin/main` at `b54cbfe` for the app and `25dac75` for the web repo.

| # | What | App | Live contract | Effect and what to do |
| --- | --- | --- | --- | --- |
| M1 | **Timer line moves in 10 s jumps** | `pages/Index.ets:545` prints `remaining_seconds` exactly as last reported, no local countdown | A running timer's remaining time alone is not a reason to report; the device reports on change and every 10 s (`lib/devices/machine.ts:115-129`, `app/device/VirtualDevice.tsx:30`, `esp32-companion/RELAY.md:150`) | The README's "counting down" was seen only with the simulation, which recomputes on every poll (`DeviceRelay.ets:376-379`). On video, show the browser counting, not the app's line; or use a counter. A code fix (count down locally between reports) is small but is a code change before the freeze |
| M2 | **Clearing app data strands the pairing** | A data clean or uninstall makes a new install token (`adapters/InstallToken.ets:56-66`) and empties the paired list (`adapters/DeviceStore.ets:24-31`) | The relay still has the device paired to the old token; a paired device shows no code (`docs/device-relay.md:140-141`) | The browser tab shows no words to type. Press **New device** in the tab (`device-relay.md:157-162`). Do this after every `bm clean -d` |
| M3 | **Stale device after the browser re-registers** | `send` turns every non-200 into `-1` (`DeviceRelay.ets:293-298`) and the page says "Couldn't reach the device. The capsule still works here." (`Index.ets:514-516`); `state` null says "The device is not answering" (`Index.ets:533-535`) | An unknown, unpaired or foreign device is `404 not_found` on all four user routes (`device-relay.md:115-116`); re-registering the same `hw`, or **New device**, unpairs it (`device-relay.md:55-57`) | The message blames the network when the pairing is gone. Fix by hand: bin icon, then pair again. The app keeps the dead entry until then |
| M4 | **429 text is wrong about the wait** | "Too many tries. Wait a minute and try again." (`DeviceRelay.ets:193-194`) | 10 claims per token per **5 minutes**, right or wrong, each counts (`device-relay.md:168`; the fake relay used one minute, `RELAY.md:184`) | Rehearsing pair and unpair ten times in five minutes locks pairing for up to five minutes. Count your attempts. A data clean gives a new token and a fresh allowance (and M2) |
| M5 | **No actions are ever sent** | `action()` exists (`DeviceRelay.ets:307-311`) but no page calls it: the only relay calls are `claim`, `unpair`, `send`, `state` (`Index.ets:463, 473, 512, 532`) | `POST /{id}/action` accepts start, pause, toggle, reset, increment, motion_on, motion_off (`device-relay.md:111`) | One-way after the send. + on the phone does not reach the device; + on the device changes only the status text (`Index.ets:545-546`). Do not say "stays in sync". Say "shows on a second screen, and reports back" |
| M6 | **State before the first report** | `parseDeviceState` needs a numeric `version` or returns null (`DeviceRelay.ets:142-147`), shown as "The device is not answering" (`Index.ets:533-535`) | Before the first report the answer is `last_seen_ms_ago` alone (`lib/devices/relay.ts:256-259`, `device-relay.md:112`); pairing clears the stored state (`device-relay.md:96-98`) | A brief wrong message instead of "Sent. Waiting for the device...". Unlikely with `/device`, which reports on its first poll after pairing; possible with the board. Cosmetic |
| M7 | **A timer is sent whole, and always starts** | Payload is `seconds = minutes * 60`, no `running` field (`DeviceRelay.ets:116-123`) | "`running`: `false` loads the timer paused; otherwise it starts on arrival" (`device-relay.md:129`) | The device starts from the full duration whether or not the phone's timer is running or part-way. Fine for the demo; do not call it a mirror |
| M8 | **Offline after 15 s without a poll** | `OFFLINE_AFTER_MS = 15000` (`DeviceRelay.ets:22, 170-172`) | The tab polls every 2 s (`machine.ts:232`) | A browser tab in the background is throttled by the browser and can go quiet for longer [J, U]: the app then says "Browser is offline". Keep `/device` in a visible window |
| M9 | **4 s timeout** | `TIMEOUT_MS = 4000` for connect and read (`DeviceRelay.ets:23, 255-256`) | Warm answers took 0.14 to 0.17 s [LIVE]. A cold serverless start plus a database connection can take longer [J, U] | The first claim after a quiet period may say "The relay did not answer". Open `/device` first (its polling keeps things warm) and try once more |
| M10 | **Panel only for v0 timers and counters** | Shown only when `payloadFor` finds a `timer` or `counter` component (`Index.ets:2545`, `DeviceRelay.ets:114-135`) | - | v1 goal capsules such as `water 8 glasses` may have neither, so no panel [U]. Use `count my squats` and `tea 4 min` |
| M11 | Stale-version rule | Ignores `version < lastSent` (`DeviceRelay.ets:166-168`) | "Ignore a state whose `version` is not the one the last `PUT` returned" (`RELAY.md:216`) | Harmless today |

What matches, checked: header `X-Harmoniser-Token` (`InstallToken.ets:22` and `lib/ownership.ts:25-26`; the app's token is 43 base64url characters, the relay takes 32 to 256); error envelope `{"error":{"code","message"}}` (`DeviceRelay.ets:175-186`, and the live 401 and 404 bodies); claim 404 and 429 texts (`DeviceRelay.ets:189-197`); 400 and 409 fall through to the relay's own message; `DELETE` answering 204 (`DeviceRelay.ets:318-321`); label cut to 47 bytes on both sides (`DeviceRelay.ets:18, 92-104`; `device-relay.md:126`); ranges 1 to 359999 s and 0 to 999999; `kind: "web"` shown as "Browser" (`DeviceStore.ets:58-60`); QR text `https://<host>/pair?code=...` (`DeviceRelay.ets:69-85`; `device-relay.md:144, 154`).

Network: the relay URL must be `https` (`DeviceRelay.ets:423-425`), so no cleartext setting is involved; `module.json5` declares `ohos.permission.INTERNET` and nothing about cleartext. The certificate is Let's Encrypt, issued 3 Oct [LIVE]. The DevEco emulator has internet access (`hackathon-resources/emulator-capability-comparison.md`). The emulator has no real camera, so pair by typing the words there; Huawei's toolbar page lists a "virtual camera" panel [DOC `ide-emulator-toolbar.md`], untested here [U].

---

## 5. Smoke test (step 6): ten items, about 30 seconds each

Run on the emulator with the final build, config pushed, model pushed. Write pass or fail next to each; a fail means the beat leaves the video and joins "known limitations".

| # | Type or do | Pass |
| --- | --- | --- |
| 1 | `pasta 9 min, sauce 15 min, bread 6 min`, **Create** | Consent sheet lists Reminders; after **Run capsule** the card says "Made by rules" with three timers |
| 2 | Same request, leave **Reminders off**, **Run capsule**, tap the blocked start, open the log | "Blocked timer ... needs reminders (denied by user)"; the log lists the block |
| 3 | Remove it, create again, **Reminders on**, start | Timers count down |
| 4 | Open the system Calendar app | Today shows "<label> is done" in the "Harmoniser" calendar. Allow the calendar permission on first launch |
| 5 | Home screen: add a Harmoniser widget; pick the pasta capsule; tap start or + on it | The widget shows the capsule and reacts; the app shows the same values |
| 6 | **`a task list and the weather for Kraków`** | One capsule with a task list and a weather reading for Kraków, after consent naming Open-Meteo (`Weather.test.ets:120, 138`). Also try `make a task list and the weather for Kraków` (`:184`) |
| 7 | `tennis scoreboard me vs Sam` | "Built from a template"; points reach 40-40, then "Advantage" |
| 8 | Marketplace tab, search `squat`, **Install** on Squat counter | Consent says "From the marketplace"; **Run** adds it |
| 9 | Settings > AI mode > **On-device only**; then `mood tracker` | Status line ends "On-device only"; the capsule is built from the bundled template. With PR #16 no marketplace search is made in this mode (`core/CapsuleGenerator.ets`, unit-tested). To watch for it: `$HDC -t $EMU shell hilog \| grep -iE 'market'` stays quiet during Create [U: I did not confirm the log tag]. Note: a weather capsule still calls Open-Meteo in this mode; the mode governs AI and the marketplace search, so do not say "no network at all" |
| 10 | Second screen: section 4, steps 2 to 5 | As section 4 |

If the on-device model is in the video, add: Smart mode off, one request from `DEMO_REVIEW.md` section 5.4 that ends "Made on-device".

---

## 6. Record and edit the video (steps 7 and 8)

Script, shot list, prompts to avoid and captions: `research/DEMO_REVIEW.md` sections 4 and 5. **Record Cut B first** (every beat is already verified), save it, then record the extras: the weather beat (A6, now on main), the on-device model (A5), the second screen (A8), the phone.

### What the tools can and cannot do

- **Emulator:** the toolbar has a screenshot button and no screen recorder [DOC `ide-emulator-toolbar.md:24`]. Record the emulator window with macOS: **Cmd+Shift+5 > Record Selected Portion**, Options > Show Mouse Clicks; or QuickTime Player > File > New Screen Recording. Capture at the window's native size.
- **Stills:** `$HDC -t $EMU shell snapshot_display -f /data/local/tmp/0.jpeg` then `$HDC -t $EMU file recv /data/local/tmp/0.jpeg .` [DOC `ide-screenshot.md`]; or `$HDC shell uitest screenCap -p /data/local/tmp/1.png` [DOC `uitest-guidelines.md:604-622`]; or the camera icon on DevEco's Log tab [DOC `ide-screenshot.md`].
- **Emulator, again:** "The emulator does not support screen recording" [DOC `ide-screen-recording.md:16`, translated]. The commands below are for a real phone only.
- **Real phone, from DevEco Studio:** connect the phone, open the **Log** tab at the bottom, click the record button in its left toolbar, choose where to save, **Start Recording**, then **Stop Recording**; the file lands in the chosen folder [DOC `ide-screen-recording.md:18-34`]. If the phone has a lock-screen password, unlock it first and keep it unlocked [DOC `:15`].
- **Real phone, from the command line** [DOC `ide-screen-recording.md:47-87`]:

```sh
$HDC -t $PHONE shell aa start -b com.huawei.hmos.screenrecorder -a com.huawei.hmos.screenrecorder.ServiceExtAbility --ps "CustomizedFileName" "phone.mp4"   # start
$HDC -t $PHONE shell aa start -b com.huawei.hmos.screenrecorder -a com.huawei.hmos.screenrecorder.ServiceExtAbility                                        # stop
$HDC -t $PHONE shell mediatool query phone.mp4 -u          # prints the file's location
# if the answer has a "uri" field, copy it somewhere readable first:
$HDC -t $PHONE shell mediatool recv "<the uri>" /data/local/tmp
$HDC -t $PHONE file recv /data/local/tmp/phone.mp4 .
```

- `uitest uiRecord` records touch operations, not video [DOC `uitest-guidelines.md:606`]. Resolution, frame rate and a length limit for the recorder are not documented. [U]
- **Not available:** QuickTime's "New Movie Recording" with a phone as the source is an iOS feature and does not see a HarmonyOS phone [J]. DevEco's screen mirroring is documented as new in version 26.0.0 [DOC `ide-screen-mirroring.md`], so it is probably not in the team's 6.1.1. [U]

### 60-second pre-flight, before every recording session

```sh
$HDC -t $EMU shell bm clean -n $B -d          # first-run state: no capsules, grants, consents, log   (DOC bm-tool.md:175-196)
$HDC -t $EMU file send -b $B config.local.json data/storage/el2/base/files/     # after a launch; see below
```

1. `bm clean -d`, launch the app once, push `config.local.json`, push the model (`scripts/push-model.sh`), restart the app. The clean removes all of them (section 0, item 5). Shortcut when only the capsules need to go: remove them in the app and skip the clean.
2. In `/device`, press **New device** (mismatch M2).
3. Allow the calendar permission on first launch.
4. macOS: Do Not Disturb on; quit chat apps; hide the Dock.
5. Emulator: English, one theme for the whole video, 100% zoom, default font size, notifications dismissed, only Harmoniser on the filmed home page. Battery level and charging state can be fixed in the emulator's Battery panel [DOC `ide-emulator-toolbar.md`]; I found no command for the clock or Do Not Disturb [U], so record all beats within the same hour or crop the status bar consistently.
6. Terminal with the key file: closed.

### Voice-over, captions, export

- Record the voice-over after the picture is cut: QuickTime > New Audio Recording, one file per beat.
- Fastest editor is whichever the editor already knows: iMovie (titles as captions) or CapCut (auto-captions, then correct them). [J]
- Export **H.264, 1080p, 30 fps, AAC**, under about 150 MB for a three-minute video so it uploads in minutes.

```sh
# cut one take
ffmpeg -ss 00:00:03 -to 00:00:21 -i take.mov -c:v libx264 -crf 18 -an beat2.mp4
# final: portrait capture centred on a 1920x1080 canvas, voice-over added
ffmpeg -i cut.mp4 -i voiceover.m4a -map 0:v -map 1:a \
  -vf "scale=-2:1080,pad=1920:1080:(ow-iw)/2:0:color=0x101418,fps=30" \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 160k \
  -movflags +faststart -shortest harmoniser-demo.mp4
```

Watch the export once with the sound off, and once checking every frame for the key file, a terminal, or anyone's face.

---

## 7. Publish (steps 10 to 12)

### Video

The rules name no host, length or format: "a brief recorded demonstration" [FAQ]. Upload unlisted to YouTube (plays in a browser) **and** attach the MP4 to the release (GitHub's limit is 2 GiB per asset). Open both links in a private window.

### Release (repo owner, or anyone with push: `gh api repos/Akshaz7/capsules-harmonyos --jq .permissions` showed `push: true` for this account)

Tag scheme [J]: **`hackyeah-2026-submission`** in both repositories. One fixed name, easy to cite on HackTribe.

```sh
cd ~/harmoniser-release
SHA=$(cat /tmp/harmoniser-submit.sha); S7=$(echo $SHA | cut -c1-7)
gh release create hackyeah-2026-submission \
  --repo Akshaz7/capsules-harmonyos \
  --target "$SHA" \
  --title "Harmoniser: HackYeah 2026 submission" \
  --notes-file notes.md \
  --latest \
  harmoniser-$S7-emulator-unsigned.hap SHA256SUMS.txt harmoniser-demo.mp4
gh release view hackyeah-2026-submission --repo Akshaz7/capsules-harmonyos --json isDraft,isPrerelease,assets,targetCommitish
# expect: isDraft false, isPrerelease false, three assets, the frozen SHA
```

`gh release create` makes the tag at `--target`. If step 11 adds docs commits after the build, the tag stays on the commit the `.hap` was built from; say so in the README ("`.hap` built from `<sha>`; later commits are documentation only"). Delete or leave the draft `test-builds-lewis-1` as a draft (drafts are not public); `test-1` stays a pre-release.

`notes.md`, to fill in:

```markdown
Harmoniser, as submitted to HackYeah 2026 (Huawei "Imagine What's Next").

- Built from commit `<full sha>` with DevEco Studio 6.1.1 (`devecocli build --modules entry`, debug build mode, product `default`), HarmonyOS SDK API 24, minimum API 20.
- `harmoniser-<sha7>-emulator-unsigned.hap` is **unsigned**. It installs on the DevEco Studio phone emulator (verified on Apple Silicon; the native library is arm64-v8a only). A physical phone needs a build signed for that phone: see README, "Signing for a physical device".
- SHA-256: see `SHA256SUMS.txt`.
- Demo video: `harmoniser-demo.mp4` below, and <unlisted link>. Recorded on the emulator at commit `<sha7>`.

## Install
    hdc install -r harmoniser-<sha7>-emulator-unsigned.hap
    hdc shell aa start -a EntryAbility -b com.hackyeah.capsules

## Optional
- On-device model (about 480 MB, not in the package): launch the app once, then `scripts/push-model.sh` from the repository.
- Live marketplace, second screen and cloud AI need a `config.local.json` pushed to the app: see README. Without it the app runs on its rules, 108 built-in templates and the on-device model. No API key is inside this package.

## Known limitations
<copy the "Partial or not yet" column of HACKATHON_BRIEF.md, plus any smoke-test item that failed>
```

### README and brief final pass (step 11, Any)

- `HACKATHON_BRIEF.md:66-67`: replace both "TBD" with the release URL and the video URL. These are the only two "TBD" lines on main.
- `README.md:11`: the status stamp still says commit `6c7e71f`; set the submitted SHA.
- Top of `README.md`: one line with the release, the video and `https://harmoniser.keanuc.net`.
- The relay sentence in the README ("has not been tested against ... the live relay"): update to what step 2 showed.
- Anything else: `SUBMISSION_CHECKLIST.md` section 3. PR #13 covers much of it.

### Tags (step 12)

The app repo's tag was made by the release. For the web repo (Web):

```sh
git -C harmoniser-web fetch origin
git -C harmoniser-web tag -a hackyeah-2026-submission origin/main -m "HackYeah 2026 submission"
git -C harmoniser-web push origin hackyeah-2026-submission
```

Web `origin/main` is `25dac75` now; it deploys on push, so **no pushes to web `main` after the tag**. Check the live site once after the last deploy: `/device` and `/api/capsules?limit=1` both 200.

---

## 8. HackTribe (step 13)

What the sources say; nobody on this side can see the form.

- "Submit **only through HackTribe**. Before the deadline, check you've picked the right task or category, and save every required field." (guide p.13)
- "The finished project must be submitted for judging. The jury starts reviewing after this deadline." (guide p.13). "Submissions received after the deadline will not be considered." (Huawei rules s.4). "After the designated submission time has elapsed, no changes or amendments ... are permitted" (general rules 5.8, quoted in `SUBMISSION_CHECKLIST.md`).
- "Fill in every HackTribe field and prepare the materials your task requires. Requirements differ between the open categories and partner tasks" (guide p.18). Jurors "only have a few minutes per project" and judge "the HackTribe submissions" in stage 1 (guide p.18, FAQ 6).
- The guide's own pre-submit list (p.19): right task; team details correct; all required fields; "the jurors can run or view your project"; "links and uploads work"; the description matches; no drafts left. The phrase "links and uploads" suggests the form takes both. [J]
- Huawei rules s.4: submissions "may include a project description, presentation, screenshots, demo, prototype, source-code repository or other materials", all in English.
- If the platform fails: "Tell the organisers as soon as possible. Don't wait until the deadline" (guide FAQ 4). Channel `#ask-organizers`, or the Info Point on level 0.

Have these ready to paste: project name; the one-paragraph pitch from `HACKATHON_BRIEF.md`; repo URL; release URL; video URL; `https://harmoniser.keanuc.net`; web repo URL; the tag name and SHA; the three team members. Then: save, reload the page, confirm the task is the Huawei partner task and all three members are listed, open every link in a private window, screenshot the saved form.

---

## 9. If we only have 60 minutes

| Minute | Do | Owner |
| --- | --- | --- |
| 0 to 10 | Freeze `origin/main` as it is. Build (`devecocli build --modules entry`). Checksum and key scan (step 5) | App |
| 10 to 30 | Record Cut B in one sitting, captions only, no voice-over: pasta timers, gatekeeper deny then allow with the log, calendar and widget, tennis, marketplace install, end card. macOS screen recording of the emulator | App |
| 10 to 30 | In parallel: HackTribe text fields, team, task | Any |
| 30 to 40 | Trim in QuickTime (Edit > Trim), export 1080p. No ffmpeg, no editor | App or Any |
| 40 to 50 | `gh release create` with the `.hap`, `SHA256SUMS.txt` and the MP4 attached (section 7). Skip YouTube | App |
| 50 to 55 | Replace the two TBD lines in `HACKATHON_BRIEF.md` with the release URL; push | Any |
| 55 to 60 | HackTribe: paste the repo and release URLs, save, reload, screenshot | App |

Skipped in this version: PR #13, the relay test, the phone, the web tag, the voice-over.

---

## 10. After 11:00

- **Push nothing** to either `main`. No release edits, no asset re-uploads, no video replacement, no Vercel redeploys, no marketplace listing changes. Changes after the deadline "will not be considered" and could read as tampering.
- Keep the emulator build, the config and the phone set-up exactly as recorded: finalists are announced at 15:00 and present at 16:00 (guide p.14), and the demo must match the submission.
- Prepare the live pitch from `research/PITCH_BRIEF.md`: problem, what was built, how it works, what was achieved at HackYeah. Name the AI tools and open-source libraries in it (guide FAQ 5). Rehearse the gatekeeper beat and the second screen live, with the recorded video as the fallback if the venue network drops.
- Sleep in shifts. One person stays reachable on Discord for organiser messages.

---

## 11. What I could not confirm, and who can answer

| Question | Why it matters | Who |
| --- | --- | --- |
| Is the redesign (`0fdeaa6`, `redesign/app`) meant to ship? It is not on `origin` | Decides what is frozen and filmed | App owner |
| Does PR #13 really conflict in `README.md`? GitHub says clean; local `merge-tree` says conflict | 10 minutes either way | Whoever merges it |
| Build duration; push time for the model over USB | Timeline slack | App owner, from the last run |
| Does `bm clean -d` remove the pushed model and config? | Pre-flight time | App owner: one try on the emulator |
| Is the Huawei ID session in DevEco still valid, and is today's loaned phone the same unit as before? | Whether the phone slot needs the mentor again | App owner at 08:05; mentor |
| Do judges install the `.hap` on anything other than an emulator? Do they want a signed one? | What to attach to the release | Huawei mentors, in passing; not a blocker |
| Does the unsigned arm64-only `.hap` install on a Windows x86-64 emulator? | "Working `.hap`" for a Windows jury | A mentor, or anyone with DevEco on Windows |
| HackTribe's actual fields, upload limits, and what happens to an unsaved form at 11:00 | The submission itself | Team leader, by opening the form now |
| Does a backgrounded `/device` tab go "offline" in the app (M8)? Does a cold relay exceed 4 s (M9)? | Relay beat on video | Found in step 2 |
| Which rule-built capsules show the device panel (M10)? | Which capsule to film | Found in step 2 |
| Phone menus for developer mode and the built-in screen recorder on the loaned model | Phone slot | Mentor |

Not found in Huawei's docs, after two searches of the mirror: a way to give someone a `.hap` that installs on an arbitrary phone without their UDID (every sideloadable profile type carries a device list; the alternatives are AppGallery invitation or public testing, which need review); whether a self-signed OpenHarmony-style `.hap` installs on a consumer phone (Huawei only says "OpenHarmony signing may affect app running", `ide-signing-auto.md:130`); any `hdc` control for the status-bar clock or Do Not Disturb; a statement that `hdc install -r` keeps sandbox files (the repo's own script says it keeps the model); and sample `bm dump` output naming `versionName` or `installTime`, so the `grep` in section 2 may need adjusting. The mirror documents a newer toolchain (26.0.0) than the team's 6.1.1, so features it marks as new may be missing.

---

## 12. Decisions I'm not confident about

1. **Freeze at 04:30, hard stop 06:00.** Chosen to protect the video. If the relay test finds a bug worth fixing (M1), the freeze moves and recording time shrinks.
2. **Attach only the unsigned `.hap`.** Based on my reading of the FAQ; a mentor could say otherwise in one sentence.
3. **Tag on the build commit, docs commits after it.** Clean for provenance, but the tag then does not point at the final README. The alternative is tagging the last docs commit and stating the build SHA in the notes.
4. **Building the public `.hap` from a second worktree.** Cleaner, costs a second full build. Skipping it is fine if `git status` shows only `build-profile.json5` modified.
5. **Treating `bm clean -d` as wiping the model and config.** Assumed from what "clear data" means; not tested.
6. **Not recommending the M1 fix.** It is the most visible relay flaw, but it is a code change with hours left. Filming around it is safer.
7. **Timings.** Build, upload and phone-push durations are estimates, not measurements.
8. **Relay probes.** I sent five unauthenticated or throwaway-token requests to production (list, state of a made-up id, one claim with a made-up code). They created nothing, but one counted against a claim rate bucket for an address that is not the venue's.
