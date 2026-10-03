# Pitch deck outline (6 slides)

Every number here comes from the README, `docs/COMPLIANCE.md` or `AI_WORKFLOW.md`. Don't add claims the code doesn't back. In particular, don't claim vibration, motion counting or alerts firing with the app closed.

## 1. Problem

**Title:** Small needs, big apps

- People want tiny, single-purpose tools: a pasta timer, a squat counter, a bill split, a tennis score. Today they install a whole app (ads, accounts, permissions) or do without.
- AI app builders generate *code*, which is unsafe to run on a phone and opaque about what it touches.
- Most AI features send everything to a US cloud by default.

*Visual:* a phone home screen crowded with single-use apps, next to one Harmoniser card.

## 2. Solution

**Title:** Harmoniser: tiny apps, made by asking

- Describe it in one sentence, and get a working native mini-app (a *capsule*) in seconds.
- A capsule is JSON, not code. A strict schema plus our own expression interpreter means nothing from a model ever executes.
- You decide what each capsule may use, on a consent sheet. Denied actions are blocked and logged.
- Simple capsules live on the home screen as widgets. Any capsule can be shared as a file or QR code.

*Visual:* request, then consent sheet, then running capsule, then widget (four screenshots).

## 3. Demo flow

**Title:** What you'll see (or: live demo)

1. `pasta 9 min, sauce 15 min, bread 6 min`: made by rules, instantly and offline, with calendar events and a widget.
2. `km to miles converter`: logic, so it goes to an EU cloud model after a one-time consent. It comes back as a live v1 capsule.
3. `demo tennis`: a full scoreboard (deuce, advantage) run by the safe interpreter.
4. `read my contacts and text them…`: refused by design.
5. Real phone: the on-device LLM, with no network.

*Visual:* the step list beside a QR code to the recorded demo.

## 4. Architecture

**Title:** Rules, then on-device, then EU cloud, then validator, then gatekeeper

- Paste the README's Mermaid diagram (rendered).
- **Every source is re-validated:** the validator type-checks every expression, rejects unknown fields, actions and permissions, and enforces limits.
- **Smart routing:** a rule match returns at once; simple requests go on-device; logic requests go to the cloud; requests for capabilities capsules don't have are refused.
- **Two-step cloud generation:** plan, then capsule, then validate, then self-check. A revision is kept only if it is still valid.
- **164 unit tests**, plus a provider eval with held-out and refusal sets.

## 5. Platform capabilities used

**Title:** Built on HarmonyOS, not just running on it

| Capability | Used for |
| --- | --- |
| **Cactus ported to HarmonyOS** (Node-API, arm64-v8a) | On-device LLM (LFM2-VL-450M): 92–114 tok/s decode, about 0.3 s to first token, about 380 MB (emulator figures) |
| **Form Kit** | Home-screen widgets (2x2 and 2x4), synced both ways with the app |
| **Calendar Kit** | Capsule timers become system calendar events |
| **Notification Kit** | Timer-finished notifications |
| **Share Kit / Scan Kit / Document picker** | Share capsules as files or QR codes |
| **ArkUI + ArkData Preferences** | Native rendering, dark mode, saved capsules, grants and the block log |

*Note for the speaker:* the Cactus port is original work: 3 patches, telemetry stubbed out, our own Node-API wrapper.

## 6. AI and privacy

**Title:** Intelligent, and on your side

- **Local first:** rules and the on-device model need no network. The **On-device only** mode guarantees nothing leaves the phone.
- **EU-first cloud:** used automatically only with Mistral (EU). Claude or OpenAI only if you enable non-EU providers. Each provider gets its own consent. Only the request text is sent.
- **Honest trade-off:** Mistral 14/15 tuning and 4/5 held-out; Claude 14/15 and 5/5. On hard logic requests Claude led 4/4 to 2/4. We default to EU anyway, and the validator catches the failures.
- **Transparency:** every capsule shows how it was made: rules, on-device, Mistral (EU), Claude, or from someone else.
- **Built openly with AI:** coding agents throughout, with the full log in `AI_WORKFLOW.md`.

*Closing line:* "Rules, on-device AI, an EU-first cloud, and a gatekeeper you control."
