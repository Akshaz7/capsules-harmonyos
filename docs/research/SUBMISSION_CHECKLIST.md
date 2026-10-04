# Submission readiness checklist: Harmoniser (Huawei "Imagine What's Next", HackYeah 2026)

> AI-assisted desk research (a Claude Code sub-agent, 2026-10-04, about 01:00–01:30). Read from the rules, this repository at `origin/main` and public sources. Nothing was run on a device or emulator and no code was changed. Line references are to the commit named in the text and will drift as work lands.

> **Status since writing (re-checked on 2026-10-04):** most items in section 3 are now fixed in the docs: the MCP wording, "nothing is simulated", the marketplace configuration note, the README tab-bar, shared-image and widget rows, the byte-scan wording, the On-device only wording, the compliance re-check and the status stamp. Still open: the vibration claim in the app text and cloud prompt (code), the recorded demo, the final release `.hap`, and per-run phone logs in `AI_WORKFLOW.md`.

Written Sunday 4 Oct 2026, about 01:15 CEST. **Deadline: Sunday 4 Oct, 11:00, on HackTribe.** About 9 h 45 min left.

State audited (read-only, nothing changed or pushed):

| Repo | Ref | Head | Visibility | Licence on GitHub |
| --- | --- | --- | --- | --- |
| `Akshaz7/capsules-harmonyos` | `origin/main` | `7292381` (committed 3 Oct 22:36 CEST, pushed 00:56 CEST) | PUBLIC | Apache-2.0 |
| `SimpsonLWH/harmoniser-web` | `origin/main` | `f13b42d` (3 Oct 22:12 CEST) | PUBLIC | **none detected** |

Key: **[R]** = quoted from the rules. **[Me]** = my reading or inference, not a rule.

Sources, with the short names used below:

| Short name | Source |
| --- | --- |
| HR | `tracks/Partner Task [Huawei] - Imagine what_s  next/RULES Imagine What_s Next.pdf` (5 pages, sections 1 to 9) |
| HC | `tracks/Partner Task [Huawei] - Imagine what_s  next/CRITERIA Imagine What_s Next.pdf` (4 pages). Same text as https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/hackathon_challenge.md (repo last pushed 1 Oct, one commit) |
| FAQ | https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/FAQ.md |
| WS | `presentation/Huawei Hackathon Challenge Workshop.pdf` in the challenge repo (21 slides, image-only; I read slides 9 to 21) |
| GR | General HackYeah 2026 Rules, https://hackyeah.pl/rules (updated 7 Jul 2026) |
| Guide | `hackyeah-2026-guide-EN.md` (participant guide, page numbers of the original) |
| T&P | `Tasks & Prizes, HackYeah 2026.pdf` |

---

## 0. The five things that matter most

1. **There is no demo recording.** It is a required deliverable (HC "Required Deliverables" item 4), it is 10% of the score on its own, and judging starts from it. `HACKATHON_BRIEF.md:67` still says "Demo video: TBD". It needs humans, an emulator, a phone and editing, so it is the longest pole.
2. **The only published `.hap` is stale.** Release `test-1` was built from `e493911` (3 Oct 16:09 UTC), a pre-release, many features behind `7292381`. `HACKATHON_BRIEF.md:66` says "final release TBD".
3. **A judge cannot reproduce the demo from a clean clone.** The live marketplace and cloud AI only work with a git-ignored `config.local.json` that has no example file, the README never documents the `marketplace.baseUrl` key, and all commands use macOS paths.
4. **`AI_WORKFLOW.md` stops at about 20:30 on Saturday** and says "No MCP servers were used", which is not true across the entry. HR section 4 makes AI disclosure mandatory and HR section 8 lets Huawei disqualify for "false or misleading information".
5. **The HackTribe final submission itself.** I cannot see HackTribe. Everything above is worth nothing if the form is not saved before 11:00 with the right task selected.

---

## 1. Required deliverables and rules

### 1a. The seven required deliverables (HC "Required Deliverables")

| # | Requirement | Where stated | Status now | Evidence | What closes it | Who | Time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **[R]** "a public source code repository" | HC p.3; FAQ "What do I have to submit?"; WS slide 16 | **Done** | Both repos PUBLIC (`gh repo view`). `origin/main` has 220 commits from 3 Oct 14:59 | Keep it public. Push everything before 11:00. Decide on open PRs #8, #9, #10 (app) and #3 (web) | Ash (app repo owner), Lewis (web repo owner) | 10 min |
| 2 | **[R]** "reproducible setup, build, installation and launch instructions" | HC p.2 and p.3; criteria "Can someone else build and run it from the README and the repository alone?" (HC p.4) | **Partly** | `README.md:137-205` exists and is detailed. Gaps in section 1c below | Fix the gaps in 1c | Anyone (docs), checked by a human with DevEco | 45 min |
| 3 | **[R]** "a working `.hap` package" | HC p.3; WS slide 14 ".hap package as the expected app deliverable" | **Partly** | Only release is `test-1`, pre-release, asset `harmoniser-test-1.hap` (4.87 MB), target `e493911`, unsigned | Build from the frozen submission commit, byte-scan for keys, publish a full (not pre-release) GitHub release with SHA-256, link it from README and brief | A human with DevEco (Ash/T1) | 30 min |
| 4 | **[R]** "a brief recorded demonstration" | HC p.3; FAQ "Who records the demo video? You do." | **Missing** | No video in the repo, releases or docs. `HACKATHON_BRIEF.md:67` "Demo video: TBD". `docs/DEMO_SCRIPT.md` is a 90 s script | Record, edit, upload, link from README, brief and HackTribe | Ash (phone and emulator), anyone can edit | 90 to 120 min |
| 5 | **[R]** "a concise architecture and implementation description" | HC p.3 | **Done** | `README.md:22-83` (Mermaid diagram, stage table), `README.md:85-102` (Cactus port), `SCHEMA.md` | Fix the stale rows listed in section 3 | Anyone | 20 min |
| 6 | **[R]** "an `AI_WORKFLOW.md` file when AI-assisted development tools were used" | HC p.2 to 3; HR s.4; FAQ "Is `AI_WORKFLOW.md` mandatory? Yes, if you used AI at all." | **Partly** | File exists, no template placeholders left. But the work log ends at the template library and several tools are missing. Detail in 1d | Add the missing tools and log rows, fix the MCP sentence, point to the two other AI logs | Each person for their own tools; anyone can write it up | 45 min |
| 7 | **[R]** "additional AI integration documentation when the submission includes AI features" | HC p.3; must cover "the model or service, inference flow, data handling, limitations, validation approach and privacy considerations" (HC p.2) | **Done** | `docs/AI_INTEGRATION.md` (98 lines) covers all six | Re-check the "byte scan of the release HAP found no key" line (`:66`) against the final HAP | Whoever builds the HAP | 5 min |

Notes on what the rules do **not** say **[Me]**: no video length limit, no format, no hosting requirement, and nothing on where the `.hap` must live (release asset, repo or upload). "Brief" is the only word. Whatever HackTribe's form asks for wins; see section 5.

On signing **[R]** FAQ "Do I need a Huawei account to sign my app?": "You only need an account-backed signing configuration once you want a `.hap` you can hand in or share." **[Me]** That reads as an expectation that the handed-in `.hap` is signed. The repo's HAP is unsigned (`build-profile.json5` has `"signingConfigs": []`), which installs on the emulator only. Ask a Huawei mentor (section 5). Safest: attach both an unsigned emulator HAP and a signed one.

### 1b. Technical requirements (HC "Technical Requirements")

| Requirement | Where stated | Status | Evidence | What closes it | Who | Time |
| --- | --- | --- | --- | --- | --- | --- |
| **[R]** "target HarmonyOS, OpenHarmony or Oniro" | HC p.2 | Done | `build-profile.json5`: `"runtimeOS": "HarmonyOS"` | Nothing | | |
| **[R]** "target API 20 or later and, where applicable, declare API 20 as the minimum supported API level" | HC p.2; FAQ "Which API level should I target?" | Done | `compatibleSdkVersion: "6.0.0(20)"`, `targetSdkVersion: "6.1.1(24)"` | Nothing | | |
| **[R]** "run successfully on an OpenHarmony or HarmonyOS emulator or a compatible physical device" | HC p.2; WS slide 16 "the DevEco Studio emulator is the practical default" | **Cannot tell for a Windows emulator** | Verified only on an Apple Silicon host (`README.md:94`). The Cactus HAR is `abiFilters: ["arm64-v8a"]` (`cactus/build-profile.json5`) and `cactus/Index.ets:6` imports `libcactus_napi.so` statically. **[Me]** The Windows DevEco emulator is x86_64 as far as I know; an arm64-only native library may fail to install or load there. I could not test it | Ask a Huawei mentor what the jury runs it on. Either way, state in the README which emulator host it was verified on and that native libs are arm64-v8a only | A human with DevEco on Windows, or a mentor | 15 min to ask and document |
| **[R]** "demonstrate the use or improvement of at least one platform, device or system capability" | HC p.2 | Done | Calendar Kit, Notification Kit, Form Kit, Share Kit, Scan Kit, Core Vision Kit, Node-API (`README.md:253`) | Nothing | | |
| **[R]** "Any team whose submission includes an AI feature, or who used AI tools during development, must publish an AI_WORKFLOW.md file." | HC p.2 | Partly | See 1d | See 1d | | |
| **[R]** "API keys, credentials, personal data and other confidential information must be removed before publication." | HC p.3 | Done | Secrets scan clean, section 2 | Re-scan after the last push | Anyone | 5 min |
| **[R]** "Repositories may undergo an automated technical pre-review; the final assessment is made by the jury." | HC p.4 | n/a | **[Me]** Expect a bot to look for `AI_WORKFLOW.md`, a `.hap`, build files, secrets and README sections | Keep file names exact: root `AI_WORKFLOW.md`, root `README.md` | | |

### 1c. Build and run from a clean clone: gaps found

| Gap | Evidence | Fix | Who | Time |
| --- | --- | --- | --- | --- |
| No example config file. `config.local.json` is git-ignored (`.gitignore`: `*.local.json`) and only shown inline for the AI provider keys | `README.md:165-173`; no `*example*` file in the tree except `esp32-companion/main/secrets.h.example` | Commit `config.example.json` showing all keys with placeholders: provider(s), `marketplace.baseUrl`, `devices.relayBaseUrl`. Name it so `*.local.json` does not ignore it | Anyone | 10 min |
| `marketplace.baseUrl` is not documented in the setup section, yet the live marketplace depends on it | Read by `adapters/MarketplaceClient.ets:304-315`; used at `pages/Index.ets:346-347`. Only mentioned in `README.md:79` and `docs/DEMO_SCRIPT.md:13` | Add an "Optional: live marketplace" subsection with the JSON and the `hdc file send` command. Say that without it the tab shows the 108 shipped examples | Anyone | 10 min |
| macOS-only commands | `README.md:144` (`/Applications/DevEco-Studio.app/...hdc`), `:200-201` (hvigorw). No mention of Windows anywhere in the README. The challenge's default path is Windows (FAQ "Do I have to use Windows? Windows is recommended") | Add the Windows `hdc` and `hvigorw` paths, or say "use `hdc` from your DevEco SDK `toolchains` folder" | A human with DevEco on Windows, or copy the path from `hackathon-resources/devecocli.md` | 10 min |
| `devecocli` version not in the README | `1.3.4` appears only in `AI_WORKFLOW.md:10` and `docs/COMPLIANCE.md:57` | Add "devecocli 1.3.4, Node 18+" to "You need" (`README.md:139`) | Anyone | 2 min |
| Emulator architecture not stated | See 1b | One line under "You need" | Anyone | 2 min |
| Model download step | Fine: `scripts/push-model.sh`, URL, tag `v2.0`, sha256 in `docs/THIRD_PARTY.md:31`. "This works on debug builds only" (`README.md:187`) | **[Me]** Say plainly that the release HAP must be a debug build for the model push to work, and which one the release asset is | Whoever builds the HAP | 5 min |
| Signing instructions | Present (`README.md:159`) | Nothing | | |
| Unit test command | Present, macOS path (`README.md:199-205`). Count verified: 243 `it(` calls in `entry/src/test` at `origin/main` | Nothing beyond the path note | | |
| Status stamp is stale and garbled | `README.md:11` says "commit `37e5c5d`"; main is 4 commits later. Broken sentences: "without reaching any model. the main screen is wired", "and a home-screen widget that stays in sync with the app are included" | Rewrite the status paragraph for the submission commit | Anyone | 10 min |
| `AppScope/app.json5` `"vendor": "example"` | Template default | Cosmetic. Leave unless someone is already rebuilding | | |

### 1d. `AI_WORKFLOW.md` audit

**Placeholders, TODO, TBD, empty rows in the root file:** none. The earlier `[Describe ...]` placeholders that `docs/COMPLIANCE.md:28-29` complains about are gone, so that audit is itself out of date.

**Does the root file point to the other AI logs?** No. `AI_WORKFLOW.md` has no mention of `esp32-companion/AI_WORKFLOW.md` or of `harmoniser-web/AI_WORKFLOW.md`. Only `README.md:135` links the ESP32 one. `esp32-companion/AI_WORKFLOW.md:4` says "merge these rows into that file if a single log is preferred".

**Tools used but not in the root tools table** (`AI_WORKFLOW.md:7-17`):

| Missing tool | Evidence it was used | Where it should go |
| --- | --- | --- |
| OpenAI Codex (GPT-5.x, desktop app) | `harmoniser-web/AI_WORKFLOW.md:10-11`; branches `codex/*`, web PRs #2 to #5 | Root table, as "marketplace backend, see harmoniser-web" |
| Chrome DevTools MCP server | `harmoniser-web/AI_WORKFLOW.md:15`; also 48 calls in Keanu's local session logs since 3 Oct | Root table. It contradicts `AI_WORKFLOW.md:19` "No MCP servers were used to build the product" |
| Parallel web search/fetch MCP | 95 calls in Keanu's local session logs since 3 Oct (research: widget research PR #6, PRs #9 and #10) | Root table, role "web research" |
| Mistral `pixtral-12b-latest` (runtime, photos) | `docs/AI_INTEGRATION.md:17`, `README.md:235` | Root table runtime rows |
| Core Vision Kit OCR and Core Speech Kit recognition (platform AI, runtime) | `docs/AI_INTEGRATION.md:16`, `README.md:242` | Root table runtime rows |
| Claude Sonnet 5.5 through the Anthropic API, for generating the 108 templates | Only in a log row (`AI_WORKFLOW.md:55`), not the tools table | Root table |
| T6 templates session | Table row lists "T1 ... T5" only (`AI_WORKFLOW.md:13`); T6 appears at `:55` | Edit that row |
| Claude Code sub-agents as implementers and as independent reviewers (ESP32) | `esp32-companion/AI_WORKFLOW.md:11-12, 37, 41` | Covered if the root file links the ESP32 log |
| "Instinct brief" as the source spec for the marketplace | `harmoniser-web/AI_WORKFLOW.md:12` | Covered if the root file links the web log |
| Community HarmonyOS skill packs that were vetted | Open app PR #10 "a vetting of community skills" | One line: evaluated, used or not used |
| Google Docs, Google Drive and Discord MCP servers (72, 6 and 1 calls in Keanu's sessions) | Local session logs | **[Me]** Coordination, not code. One honest line is enough |
| Whatever Lewis used for the sharing code (app PR #1, 6 commits by SimpsonLWH) | Not recorded anywhere I can see | Lewis to state |
| Whatever Ash's sessions used beyond the listed skills | I can only see Keanu's machine | Ash to confirm the table is complete |

**Work log gaps.** The last row (`AI_WORKFLOW.md:55`) is the template library. Nothing is logged for work that the README describes as built: marketplace tab and client, device relay adapter and panel, photo path with OCR and Pixtral, `editCapsule` and "Change it", Snap button, voice input core, UI-1 and UI-2 (tab bar), widget redesign and BUG-13, share target, v1.1 triggers, timer pause/stop, sharing (PR #1), and the real-phone test runs. HC p.2 asks for "the workflow from ideation and architecture through implementation, testing and debugging" and "how generated output was reviewed, tested and validated". **[Me]** One row per feature built from the commit messages is enough; they already record what was checked.

**Other inconsistencies:**

| File:line | Issue |
| --- | --- |
| `AI_WORKFLOW.md:13` | "builds the signed HAP from committed `main`" but `README.md:157` says the HAP is unsigned |
| `AI_WORKFLOW.md:19` | "No MCP servers were used to build the product." Not true for the entry as a whole |
| `esp32-companion/AI_WORKFLOW.md:55-56` | "the real backend is not deployed yet". At 01:09 `https://harmoniser-web.vercel.app/pair` and `/device` returned 200 and `/api/devices` returned 401, so the relay routes are deployed. Open app PR #8 "relay is live" fixes this but is unmerged |
| `harmoniser-web/AI_WORKFLOW.md:10-11` | Model given as "GPT-5.x". Give the exact model if known |
| `harmoniser-web/AI_WORKFLOW.md:45-47` | "Not yet verified by a human: ... the live deployment smoke test" sits next to `:39-44`, which describes a live smoke test. Reword |
| `harmoniser-web/AI_WORKFLOW.md:88-89` | Mentions "Atlas password rotation" as Lewis's review item. See section 2 |

### 1e. Rules about originality, licences, language, team, IP, external services

| Rule | Where stated | Status | Evidence | What closes it | Who | Time |
| --- | --- | --- | --- | --- | --- | --- |
| **[R]** "The submitted solution should be created or substantially developed during the Challenge." | HR s.4 | Done | First commit 3 Oct 14:59 from the template. `README.md:7`, `HACKATHON_BRIEF.md:28-39` say what came from the template | Nothing | | |
| **[R]** "Participants shall identify material pre-existing or third-party components, as well as the use of AI tools, in their submission documentation." | HR s.4 | Partly | App: `README.md:247-262`, `docs/THIRD_PARTY.md`. Gaps in the next table | Close the gaps below | Anyone | 20 min |
| **[R]** "provided that their use complies with the applicable licences and third-party rights" | HR s.4, s.7 | Partly | Cactus licence is source-available with funding and revenue limits, disclosed at `README.md:254` and `docs/THIRD_PARTY.md:15-21` | **[Me]** Fine for the team. Note HR s.7: a prize grants Huawei a licence that "does not extend to pre-existing or third-party components", so Cactus stays under its own licence. Keep the disclosure prominent | | |
| **[R]** "All submissions, presentations, demonstrations and project documentation submitted for evaluation must be prepared in English." | HR s.4; T&P "Note: Projects must be submitted in English." | Done in the repo | All docs English. The demo script deliberately types Polish only in the README verify table, not in the demo | Record the voice-over and captions in English. HackTribe text in English | Ash | |
| **[R]** "individually or in teams of up to 6 people" and "Only persons registered as HackYeah 2026 participants may be members of a team." | HR s.3 | Done **[Me]** | 3 people: Ash, Lewis, Keanu (`HACKATHON_BRIEF.md:56-60`) | All three must be on the HackTribe team. First names only in the brief; add full names if the form or jury needs them | Ash (team leader on HackTribe) | 5 min |
| **[R]** "Each monetary prize is awarded jointly to the members of the awarded team, as indicated in the team's submission" | HR s.6 | Cannot tell | HackTribe not visible to me | Check the member list on HackTribe before 11:00. Guide FAQ 2: "make sure the team leader adds you to the final submission" | Ash | 5 min |
| **[R]** "Solutions must be submitted before the official submission deadline through the platform specified by HackYeah." and "Submissions received after the deadline will not be considered." | HR s.4 | Cannot tell | | Save the final submission on HackTribe by 10:30 at the latest | Ash | 20 min |
| **[R]** "Submit only through HackTribe. Before the deadline, check you've picked the right task or category, and save every required field." | Guide p.13 | Cannot tell | | Task must be the Huawei partner task | Ash | |
| **[R]** Checkpoint: "Your project must already exist on HackTribe. After 20:00 no new projects can be created." | Guide p.13 | Cannot tell | Organisers said a draft had to exist by Sat 20:00 | Confirm the draft exists. If not: "contact the organisers immediately" (Guide FAQ 1) | Ash | 2 min |
| **[R]** "Can one project be submitted to more than one category or partner task? Yes, but they recommend focusing on one main challenge" | Guide FAQ 3. Organisers earlier: one solution per category | n/a | | **[Me]** If you also enter an open category (AI), that category wants "maximum 10-slides PDF presentation" (`Rules - ARTIFICIAL INTELLIGENCE.pdf` item 5e) and uses different criteria | Ash decides | |
| **[R]** "AI tools and open-source libraries are allowed, but must be named in the final presentation." | Guide FAQ 5 | Partly | `docs/SLIDES_OUTLINE.md` exists; I did not find a slide deck file | Put one "Built with" slide in the pitch deck | Whoever makes the deck | 10 min |
| **[R]** "Mentors keep your project confidential" | Guide p.12 | n/a | | | | |
| **[R]** IP: "Participants retain ownership"; winners grant Huawei a 3-year non-exclusive demo/promotion licence; every submitter grants Huawei and PROIDEA a 3-year licence to use "the project name, team name, project description, screenshots, presentation materials and recordings of the project demonstration" | HR s.7 | n/a | | **[Me]** The demo video will be reused publicly. Do not show keys, personal data or other people's faces in it | Ash | |
| External services and hardware | **[Me]** No rule restricts them. HC p.2: "AI may run locally, remotely through a service or in a hybrid architecture." HC p.4: "If part of it can't run on the emulator ... explain clearly how it would work." WS slide 19: "Say plainly what is real and what is faked. Simulated sensor data is fine if you declare it." | Done | `README.md:207-245` "What's real and what's simulated" | Keep that section accurate (section 3) | | |
| "Real vs simulated" README section | Not a formal rule. AGENTS.md:17 "Clearly label mocked services and simulated sensor or device data"; WS slide 19 | Done, with errors | `README.md:207-245`, `HACKATHON_BRIEF.md:41-54` | Section 3 | | |
| Known limitations section | Asked for inside `AI_WORKFLOW.md` (HC p.2 "known limitations, unsuccessful approaches and lessons learned") | Done | `AI_WORKFLOW.md:85-121`, `docs/AI_INTEGRATION.md:91-98` | Nothing | | |

**Licence and third-party notice gaps:**

| Item | Repo | Status | Fix | Who | Time |
| --- | --- | --- | --- | --- | --- |
| No `LICENSE` file. `package.json` has `"private": true` and no `license` field; GitHub shows no licence | harmoniser-web | **Missing** | Add a `LICENSE` (Apache-2.0 to match the app, if Lewis agrees). Not a stated rule **[Me]**, but a public repo with no licence is "all rights reserved" and it vendors Apache-2.0 files from the app | Lewis (repo owner) | 5 min |
| EFF Short Wordlist #1, CC BY 3.0 US | harmoniser-web | Done | `NOTICE` attributes it; list at `scripts/devices/eff_short_wordlist_1.txt` and `lib/devices/wordlist.ts` | Nothing | | |
| Geist and Geist Mono fonts through `next/font/google` (`app/layout.tsx:2`) | harmoniser-web | Not listed | One line in `NOTICE` (SIL OFL 1.1) | Lewis | 2 min |
| Vendored app sources under `vendor/upstream/452777e.../` | harmoniser-web | Not attributed in `NOTICE` | One line: "from Akshaz7/capsules-harmonyos, Apache-2.0" | Lewis | 2 min |
| App's `README.md` and `docs/THIRD_PARTY.md` do not list the web backend's services (Vercel, MongoDB Atlas) or Pixtral | app | Partly | Add `pixtral-12b-latest` to `README.md:256`; add a row "Marketplace and relay backend: harmoniser-web on Vercel fra1 + MongoDB Atlas Frankfurt" | Anyone | 5 min |
| ESP32: Roboto bitmaps, cJSON (`tests/vendor/cJSON/LICENSE` present), LVGL, ESP-IDF, Waveshare BSP | app | Done | `README.md:258`, `esp32-companion/README.md:543` "Third-party" | Nothing | | |
| Eval photos in `scripts/eval-images/*.jpg` were rendered with macOS system fonts (`render.py:9-31`: Courier New, Georgia, Chalkduster, Bradley Hand, Arial) | app | Not mentioned | **[Me]** Low risk: they are rendered images, not font files. One line in `docs/THIRD_PARTY.md` saying they are synthetic and how they were made | Anyone | 2 min |
| LFM2-VL-450M weights, Cactus engine | app | Done | `docs/THIRD_PARTY.md`, `cactus/CACTUS_LICENSE` | Nothing | | |
| Open-Meteo | both | Not present | No match for `open-meteo` in either `origin/main`. Open app PR #9 is research on a "task-list-and-weather" failure. If weather lands tonight, add the Open-Meteo attribution (CC BY 4.0) to README and `docs/THIRD_PARTY.md` in the same commit | Whoever adds it | 2 min |
| App fonts, word lists | app | None bundled | No `fontFamily`, `.ttf` or word list in `entry/`. The fake relay's word list is its own (`esp32-companion/mock_relay.py:82-84`) | Nothing | | |

### 1f. HackTribe fields

I cannot see the form. What the sources say it will want:

| Field | Source | Ready? |
| --- | --- | --- |
| Project name and short description (minimum at checkpoint) | Guide p.13 | Text exists in `HACKATHON_BRIEF.md:5-17` |
| Right task or category selected | Guide p.13, p.19 item 1 | Check |
| Team details correct | Guide p.19 item 2 | Check all three members |
| All required fields filled | Guide p.19 item 3 | Check |
| "The jurors can run or view your project." | Guide p.19 item 4 | Needs the final `.hap` release and the video |
| "Links and uploads work." | Guide p.19 item 5 | Open every link in a private browser window |
| "The description matches the final solution." | Guide p.19 item 6 | Use the brief's "Real vs not yet" wording |
| "No drafts or missing information are left." | Guide p.19 item 7 | |
| Possibly: presentation, screenshots, demo, prototype, repository | HR s.4 "They may include a project description, presentation, screenshots, demo, prototype, source-code repository or other materials" | No screenshots in the app repo (`docs/COMPLIANCE.md:50` flags it); no deck file found |
| Possibly a PDF deck of at most 10 slides | Open-category rules item 5e. **[Me]** May be a shared HackTribe field | `docs/SLIDES_OUTLINE.md` is only an outline |

---

## 2. Disqualification risks

| Risk | Rule | Current exposure | Action |
| --- | --- | --- | --- |
| Late submission | **[R]** HR s.8: Huawei may disqualify a team that "submits a solution after the deadline". HR s.4: "Submissions received after the deadline will not be considered." | Open | Submit on HackTribe by 10:30. Do not rely on the "11:00 PM" wording in GR 4.3 ("from 11:00 PM on October 3, 2026, to 11:00 PM on October 4, 2026"); the guide and the agenda say Sunday 11:00 |
| Changes after the deadline | **[R]** GR 5.8: "After the designated submission time has elapsed, no changes or amendments to submitted solutions are permitted. Any changes or amendments made after this time will not be considered by the jury." Open-category rules item 13: "Any alterations or revisions made after the statutory time is expired are illegal." | Open | **[Me]** Tag the submission commit (for example `submission`) in both repos before 11:00 and put the tag and SHA in the README and on HackTribe. Push nothing to either `main` after 11:00 until results are out. Do not edit the release or re-upload the video after 11:00. Redeploying `harmoniser-web` on Vercel after 11:00 also changes what judges see |
| False or misleading information | **[R]** HR s.8: "provides false or misleading information". HC p.3: "Does it actually work as described? Claims should be backed by the code, the demo, logs or test results." | **Real exposure**: section 3, and `AI_WORKFLOW.md:19` | Fix the items in section 3 and 1d |
| Undisclosed AI use | **[R]** HR s.4 "shall identify ... the use of AI tools, in their submission documentation"; HC p.2 "must publish an AI_WORKFLOW.md file" | Partial disclosure (1d) | Close 1d |
| Missing required deliverable (video, final `.hap`) | **[R]** HC "Each team must submit" | Video missing, `.hap` stale | Section 4, items 1 to 4 |
| Private repo | **[R]** HC deliverable 1 | None: both PUBLIC | Do not change visibility. The video and release links must also be public: test logged out |
| Third-party rights | **[R]** HR s.8 "infringes third-party rights" | Low. Cactus is disclosed. Web repo has no licence | Add the web `LICENSE` and NOTICE lines |
| Not English | **[R]** HR s.4 | Low | English voice-over and HackTribe text |
| Team members not registered participants | **[R]** HR s.3 | Cannot tell | Each member confirms their HackYeah registration |
| Score under 50% | **[R]** HR s.5: no prize if a solution "does not achieve at least 50% of the maximum possible final score" | n/a | |
| Secrets in the repo | **[R]** HC p.3 "Basic hygiene matters: no secrets in the repo"; FAQ "Should I commit my keystore and its passwords? You shouldn't." | **Clean**, see below | Re-scan after the last push and byte-scan the final HAP |

### Secrets scan (both `origin/main`, tree and full history)

Patterns: Anthropic and OpenAI style keys, AWS, GitHub, Slack, Google, Hugging Face tokens, JWTs, private key blocks, MongoDB URIs with credentials, long literals assigned to `apiKey` / `secret` / `token` / `password` / `psk` / `authorization`, and sensitive file names (`.env*`, `config.local*`, `secrets.h`, `*.p12`, `*.cer`, `*.p7b`, `*.pem`, `*.key`, keystores, `sdkconfig`, `*.local`).

| Repo | Result | Paths that matched |
| --- | --- | --- |
| `capsules-harmonyos` | **No hits** in the tree or in history. No sensitive file names ever committed. `esp32-companion/main/secrets.h.example` holds placeholders only | none |
| `harmoniser-web` | **Placeholder hits only.** MongoDB URI pattern matched in three files; every match uses user `user`, a dummy password and an `example.mongodb.net` or `localhost` host | `.env.example`, `lib/db.ts`, `tests/env.test.ts` |

Not a repo finding, but related: `harmoniser-web/AI_WORKFLOW.md:88-89` lists "Atlas password rotation" as a review item for Lewis. **[Me]** That suggests the production database password was exposed somewhere outside the repo (a chat, a terminal, an agent session). Lewis should say whether it was rotated.

Personal data: commit author emails are public in both histories (one university address per `docs/COMPLIANCE.md:38`). Not a secret; nothing to do.

Not scanned: the release asset `harmoniser-test-1.hap` (I did not download it; `docs/COMPLIANCE.md:25` records an earlier clean byte scan) and the unmerged PR branches of the app repo beyond file names.

---

## 3. Claims the code or the evidence does not back

Ordered by how badly each could read as "misleading" to a judge.

| # | File:line | Claim | What the repo actually shows | Honest rewording |
| --- | --- | --- | --- | --- |
| 1 | `AI_WORKFLOW.md:19` | "No MCP servers were used to build the product." | Chrome DevTools MCP was used on the backend (`harmoniser-web/AI_WORKFLOW.md:15`); Parallel and others in Keanu's sessions | "No MCP servers were used for the app code in `entry/`. The backend and research used: ..." and list them |
| 2 | `HACKATHON_BRIEF.md:54` | "Nothing is simulated in the app." | A simulated device relay ships in the app: `adapters/DeviceRelay.ets:324-326` (`SimulatedDeviceRelay`), chosen at `pages/Index.ets:344` when no relay URL is set; shown when the dev flag `devices.simulate` is on (`DeviceRelay.ets:416-419`). `README.md:135` admits it | "No sensor or device data is simulated in normal use. A labelled dev-only device simulation exists behind a config flag." |
| 3 | `README.md:219`, `docs/DEMO_SCRIPT.md:3`, `:27` | Marketplace "Browse and install: real, live." | Live only if `config.local.json` sets `marketplace.baseUrl` (`MarketplaceClient.ets:304-315`). A judge who installs the release HAP sees the shipped examples. In-app install of a template listing "hasn't been checked separately" (`README.md:219`); publishing "not tested" | Add "needs `marketplace.baseUrl` in `config.local.json`; without it the tab lists the 108 shipped examples". Caption the demo beat "live API, configured by a local file" |
| 4 | `docs/DEMO_SCRIPT.md:3` | "Every step shows something that is built and has been seen working." | Step 6 (refusal): `README.md:290` says "**not yet verified on the emulator**". Step 7 ("Made on-device" through the main screen on a phone): `README.md:214` and `:283` say "It is not yet demonstrated through the main screen" and "This hasn't been demonstrated through the UI yet", while `docs/COMPLIANCE.md:15` says a phone run is recorded in commit `b1dd029` | Whoever ran it decides which is true, then fix both. If the phone run happened, update `README.md:214`, `:283`. If not, do not script it as certain |
| 5 | `docs/DEMO_SCRIPT.md:30`; `docs/SLIDES_OUTLINE.md:36` | "No network, no account. It works offline." / "Real phone: the on-device LLM, with no network." | `README.md:214`: "offline use was not strictly tested (emulator airplane mode doesn't cut its network)". No recorded airplane-mode run on a phone | Record step 7 with airplane mode visibly on, then the claim is shown. Otherwise say "runs on the device; needs no cloud" |
| 6 | `pages/Index.ets:147-148` (user-facing), `core/CapsuleModel.ets:148`, `:151` (cloud prompt), `pages/ConsentView.ets:41` | "Capsules can only use: ... vibration and the motion sensor"; "steps and reps can use the motion sensor"; "Count reps or steps with the motion sensor" | Neither is built (`README.md:239-241`, `README.md:220` "Known mismatch"). Flagged since Saturday 20:00 in `docs/COMPLIANCE.md:46-47` and still in the code | Code change: remove the two phrases from the string and the prompt. If no code change is allowed now, keep `README.md:220` and make sure the refusal card is not shown in the video with that list readable |
| 7 | `HACKATHON_BRIEF.md:45` | "Real (seen working)": "on-device LLM" | Same conflict as item 4: README says not shown through the main screen | Align with item 4 |
| 8 | `HACKATHON_BRIEF.md:26` | "Validated ... on real phones (on-device model, Share)" | Evidence is commit messages only. `docs/COMPLIANCE.md:15` asked for one `AI_WORKFLOW.md` line for the phone runs (device model, build, what was checked); it was never added | Add that row to `AI_WORKFLOW.md` |
| 9 | `README.md:135` | "The real relay routes are an open pull request on the backend and **not deployed**"; "The team's cut-off: live end to end by 01:00, otherwise ..." | Web PR #1 is merged; `/pair` and `/device` returned 200 and `/api/devices` 401 at 01:09. The 01:00 cut-off has passed. Same stale text at `esp32-companion/README.md:47-50` and `esp32-companion/AI_WORKFLOW.md:55-56` | State the outcome: what is deployed, what has run end to end (board to live relay? app to live relay?), what has not. Merge or close app PR #8 |
| 10 | `HACKATHON_BRIEF.md:52` | "Wrist companion works on its own hardware; not connected to the app" | App has a "Show on another device" panel and relay client (`README.md:135`), hidden without config, checked only against the in-app simulation | "App-side pairing and send exist behind a config flag; checked only against a simulation / the live relay (whichever is true)" |
| 11 | `README.md:67` and `README.md:273` | "an Import icon next to Settings and Log"; "The log (document icon, top right)" | `README.md:68`: tab bar replaced them, "header icons removed"; log is on capsule pages (commit `b84e49c`) | Update both rows to the tab-bar layout. A judge following `:273` will not find the icon |
| 12 | `README.md:76` vs `README.md:234-235` | `:76` "Shared images only show a toast until the vision path lands." | `:234` "Shared images now take the photo path below." | Delete the stale sentence at `:76` |
| 13 | `README.md:232` | Widget row describes BUG-2 "under investigation" and several "no emulator check" notes | `acfbaef` "widget taps work again ... (BUG-13)" landed after; the README does not mention it. The demo's step 3 depends on the widget | Add what `acfbaef` fixed and whether it was re-checked on the emulator or a phone |
| 14 | `README.md:18`, `docs/AI_INTEGRATION.md:66` | "a byte scan of the rebuilt `.hap` found none" / "of the release HAP found no key" | True for an older build | Re-run on the final HAP and keep the sentence |
| 15 | `docs/SLIDES_OUTLINE.md:70` | "The **On-device only** mode guarantees nothing leaves the phone." | **[Me]** The mode governs AI requests. The marketplace tab still calls the backend when configured, and device sends go to the relay | "In On-device only mode no request is ever sent to an AI provider." |
| 16 | `AI_WORKFLOW.md:13` | "builds the signed HAP" | `README.md:157` "the HAP is unsigned" | Say which |
| 17 | `docs/COMPLIANCE.md` (whole file) | Dated 3 Oct 20:00 at `a9d853e`; says `HACKATHON_BRIEF.md` "is still the empty template" (`:49`), placeholders remain (`:28-29`), "5 commits ... not pushed" (`:23`) | All three are no longer true | Re-date it and correct, or add a top line "superseded by the state at <submission SHA>". A judge reading it sees problems that are already fixed |
| 18 | `README.md:11` | Status stamp "commit `37e5c5d`" | Main is at `7292381` | See 1c |

Claims I checked that **do** hold: 243 unit tests (243 `it(` calls); API 20 minimum and API 24 target; permissions limited to INTERNET, VIBRATE, READ_CALENDAR, WRITE_CALENDAR (`entry/src/main/module.json5:15-29`), no MICROPHONE or location; key never in the repo; `esp32-companion` test counts match its own log; marketplace API answers 200 for `/api/capsules` and for `tag=template`.

---

## 4. To-do list for the next ten hours

Times are rough. "DevEco human" means someone at a machine with DevEco Studio, the emulator and a phone.

### Must have before 11:00 (in this order)

| # | Task | Owner | Time | Done when |
| --- | --- | --- | --- | --- |
| 1 | **Record the demo video.** Freeze a commit first (step 2 can run in parallel on another machine). Follow `docs/DEMO_SCRIPT.md`, but drop or reword any beat from section 3 items 4 and 5 that has not been seen working. Phone segment with airplane mode visible. English captions. No key file on screen | Ash + DevEco human; anyone edits | 90 to 120 min | A public (or unlisted) link plays logged out |
| 2 | **Code freeze, then build the final `.hap`** from the frozen commit. Decide now whether section 3 item 6 (remove "vibration and the motion sensor" from `Index.ets:147-148` and `CapsuleModel.ets:148,151`) goes in before the freeze. Byte-scan the HAP for keys | DevEco human (Ash/T1) | 30 min | HAP installs and launches on a clean emulator |
| 3 | **Publish a full GitHub release** (not pre-release) with the HAP, SHA-256, the commit SHA, install steps, and whether it is a debug build. Attach a signed HAP too if one can be made | Ash (repo owner) | 15 min | Release page opens logged out |
| 4 | **Fix the misleading statements**: section 3 items 1, 2, 3, 4, 5, 9 at minimum | Anyone, reviewed by Ash | 30 min | Brief and README agree with each other |
| 5 | **Complete `AI_WORKFLOW.md`**: add the missing tools (1d), add log rows for everything after the template library, add the phone-run row, link `esp32-companion/AI_WORKFLOW.md` and `harmoniser-web/AI_WORKFLOW.md`, correct line 19 | Anyone drafts; Ash, Lewis and Keanu each confirm their own tools | 45 min | No tool used by any member is missing |
| 6 | **Make the build reproducible for a stranger**: `config.example.json`, the marketplace subsection, Windows paths, devecocli version, emulator architecture line, fresh status paragraph (1c) | Anyone; DevEco human checks the Windows path | 30 min | A teammate follows the README from a fresh clone without asking |
| 7 | **Replace the two TBDs** in `HACKATHON_BRIEF.md:66-67` and add the video and release links to the top of `README.md` | Anyone | 5 min | No "TBD" in the repo |
| 8 | **Merge or close open PRs** (#8, #9, #10 app; #3 web), push, **tag the submission commit** in both repos, re-run the secrets scan | Ash, Lewis | 15 min | Tag visible on GitHub; scan clean |
| 9 | **HackTribe final submission**: right task (Huawei), all three members listed, English description, repo link, release link, video link, every required field saved. Open every link logged out | Ash (team leader) | 20 min | Saved by **10:30**. Screenshot the saved form |
| 10 | **Hands off after 11:00**: no pushes to `main`, no release edits, no Vercel redeploys, no video re-uploads | Everyone | | |

Suggested clock **[Me]**: freeze and build by 03:00; video recorded by 05:30 and uploaded by 07:00; docs done by 08:30; tag and push by 09:30; HackTribe saved by 10:30.

### Should have

| Task | Owner | Time |
| --- | --- | --- |
| Ask a Huawei mentor: signed or unsigned `.hap`, where it must live, video length and hosting, which emulator host the jury uses (see section 5) | Anyone at the venue, as early as mentors are around | 10 min |
| Add `LICENSE` to `harmoniser-web` and three `NOTICE` lines (Geist fonts, vendored app sources) | Lewis | 10 min |
| Add 4 to 6 screenshots to the app README (`docs/screenshots/`: consent sheet, widget, tennis capsule, marketplace, dark mode) and to HackTribe | Ash | 20 min |
| Fix the remaining section 3 items (7, 8, 10 to 18) | Anyone | 30 min |
| Add Pixtral and the backend services to the third-party table; note the synthetic eval images | Anyone | 10 min |
| Re-date or correct `docs/COMPLIANCE.md` | Anyone | 10 min |
| A PDF deck of at most 10 slides from `docs/SLIDES_OUTLINE.md`, with a "Built with" slide naming AI tools and open-source libraries (Guide FAQ 5). Needed for the 16:00 pitch if shortlisted, and possibly a HackTribe field | Anyone | 60 min |
| Lewis confirms the Atlas password was rotated | Lewis | 5 min |

### Nice to have

| Task | Owner | Time |
| --- | --- | --- |
| A second HAP built without the Cactus HAR for x86_64 emulators, if a mentor confirms the jury uses Windows | DevEco human | 60 min or more, risky |
| Fold the ESP32 and web AI logs into the root `AI_WORKFLOW.md` as sections instead of links | Anyone | 20 min |
| Change `AppScope/app.json5` `"vendor": "example"` | DevEco human, only if rebuilding anyway | 2 min |
| Exact Codex model name in `harmoniser-web/AI_WORKFLOW.md` | Lewis | 2 min |
| Rehearse the 16:00 pitch and Q&A (finalists announced 15:00, Guide p.14) | All | 30 min |

---

## 5. What I could not determine, and who can answer

| Question | Why it matters | Who can answer |
| --- | --- | --- |
| Does a final-submission draft exist on HackTribe, with which task selected and which members? What fields does the form require (video upload or link, deck, screenshots)? | The submission is void without it | Ash (team leader); HackTribe itself |
| Must the `.hap` be signed, and must it be a release asset, in the repo, or uploaded to HackTribe? | The rules say only "a working `.hap` package". The FAQ hints at signed | Huawei mentors on site; Huawei's Discord channel (WS slide 20) |
| Is there a length limit or required host for the demo recording? | Rules say only "brief" | Huawei mentors; the HackTribe form |
| What does the jury run the app on: Apple Silicon emulator, Windows x86_64 emulator, or phones? Does the arm64-only HAP install on a Windows emulator? | Could make the HAP "not working" for the jury | Huawei mentors; anyone with DevEco on Windows can test in 10 minutes |
| Is the deadline in GR 4.3 ("11:00 PM on October 4") a typo? | I treated 11:00 as the deadline, as the guide, the agenda and the organisers say | Organisers, `#ask-organizers` on Discord |
| Has "Made on-device" been seen through the main screen on a real phone, and offline? | Decides how section 3 items 4, 5, 7 are reworded | Ash (phone testing) |
| Is the wrist companion live end to end through the deployed relay (board to relay, app to relay)? | README, ESP32 README and ESP32 AI log all still say "not deployed" | Keanu (board), Lewis (backend), Ash (app) |
| Which AI tools did Ash's and Lewis's sessions use beyond what is logged (MCP servers, skills, other models)? | Disclosure must be complete. I could only inspect Keanu's local session logs | Ash, Lewis |
| Was the production Atlas password exposed and rotated? | `harmoniser-web/AI_WORKFLOW.md:88-89` lists rotation as open | Lewis |
| Is the release asset `harmoniser-test-1.hap` free of keys? Is the final one? | I did not download or scan binaries | Whoever builds the release |
| Will the "automated technical pre-review" check anything specific? | HC p.4 mentions it without detail | Huawei mentors |
| Does the entry also go into an open category (AI)? | Different criteria and a 10-slide PDF requirement | Ash |
| Is every team member registered as a HackYeah participant? | HR s.3 | Each member |

Things I did not do: build the app, run the tests, install the HAP, watch any video, open HackTribe, or read slides 1 to 8 of the workshop deck (title and background slides by position; the deliverables and judging slides were read).
