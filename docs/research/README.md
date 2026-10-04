# Research pack

AI-assisted desk research written during HackYeah 2026 (3–4 October). None of it was run on a
device or emulator. Each file says what it read and what it could not verify. Line references
are to the commit named in the file.

| File | What it answers |
| --- | --- |
| [`SUBMISSION_CHECKLIST.md`](SUBMISSION_CHECKLIST.md) | Every deliverable and rule for the Huawei track, its status in the repositories, statements the code does not back, and the order of work before the deadline. **Read this first.** |
| [`PITCH_BRIEF.md`](PITCH_BRIEF.md) | What was built, in full technical detail: architecture stage by stage, schema, gatekeeper, AI pipeline, platform kits, numbers to know, 74 likely questions with spoken answers and "do not say" notes, a crib sheet per person, and 20 places where documents contradict the code. **Read before pitching.** |
| [`PERMISSIONS_AND_MAPS.md`](PERMISSIONS_AND_MAPS.md) | Which capsule permissions gate something real on main after PR #12 (four do, one gates a no-op, three are wording only), the system permissions underneath, and whether a map could be added. Newer than the pitch brief on permissions. |
| [`PR12_REVIEW.md`](PR12_REVIEW.md) | Read-only review of PR #12 (weather, accelerometer, battery) against the judges' request. It found that the request still failed on main; PR #14, now merged, is the follow-up. |
| [`PR14_REVIEW.md`](PR14_REVIEW.md) | Read-only review of PR #14 (the rule that builds a task list with the weather): which phrasings build the capsule, which miss, what the capsule can and cannot do, and the merge order with the documentation pull request. Written before PR #14 was merged; its update note says what changed since (a leading make/create/build is now accepted). |
| [`JURY_AND_DECK.md`](JURY_AND_DECK.md) | Jury research from public sources, the 15 likeliest questions, a 5-minute pitch plan, an 8-slide outline with spoken lines, four Mermaid diagrams and a cue card. |
| [`SHIP_RUNBOOK.md`](SHIP_RUNBOOK.md) | A timed checklist from about 03:15 to the 11:00 submission, a 10-item smoke test, the release command and a notes template, and the app's relay client checked against the live API, with 11 findings by file and line. |
| [`DEMO_REVIEW.md`](DEMO_REVIEW.md) | The demo script scored against the judging criteria, risky beats, and two rewritten cuts shot by shot: "everything landed" and "safe". |
| [`API_LOOKUPS.md`](API_LOOKUPS.md) | Exact HarmonyOS APIs, imports and snippets for the planned UI work: bottom prompt bar, chips, progress screen, QR scan and deep links, add to home screen, icon, polish, weather, accelerometer. Snippets were not compiled. |
| [`DESIGN_PRINCIPLES.md`](DESIGN_PRINCIPLES.md) | Sourced UI/UX principles turned into rules for capsules, cards, widgets and the wrist screen; layout templates; tokens; an audit of the current cards with changes by file and line. |
| [`../JUDGES_FEEDBACK_RESEARCH.md`](../JUDGES_FEEDBACK_RESEARCH.md) | Why "task list + weather" failed, the fix order, a router design, on-device models, widget sizing. |
| [`../WIDGET_RESEARCH.md`](../WIDGET_RESEARCH.md) | Adding a widget per capsule, widget reliability, card design rules. |
| [`../HARMONYOS_DIGEST.md`](../HARMONYOS_DIGEST.md) | ArkTS / ArkUI cheat sheet for assistants. |
| [`../SKILLS_VETTING.md`](../SKILLS_VETTING.md) | Safety and accuracy review of community skill documents. |
| [`../../esp32-companion/RELAY.md`](../../esp32-companion/RELAY.md) | The device relay contract. |

All of the linked files are on `main` since PRs #6 to #12 were merged (2026-10-04, about 01:45). Several were written before those merges and still describe the pull requests as open; the pitch brief has an update box at its top. `PR14_REVIEW.md`, `JURY_AND_DECK.md` and `SHIP_RUNBOOK.md` were added later, with PR #13. The review describes PR #14 as open; PRs #14, #15 and #16 were merged at about 03:00 on 4 Oct.
