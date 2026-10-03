# Device relay contract

How the wrist companion talks to the cloud backend, and what the backend has to offer under
`/api/devices/**` for that to work. The board only makes outbound requests: it registers
itself, shows a QR code and a pairing phrase, and then polls for capsules and reports its
state. Its local HTTP API (`README.md`) keeps working next to this.

This is a proposal written from the firmware side. `mock_relay.py` implements all of it in
memory; `test_relay.sh <base url>` checks any implementation from outside, the fake today
and the real routes later.

- Everything is JSON, UTF-8. Errors are `{"error":{"code":"…","message":"…"}}`, the
  envelope of the rest of the backend, on every route. The app can switch on `code`; the
  board only looks at the status and never reads an error body.
- The base URL is build-time configuration on the board (`RELAY_URL` in `main/secrets.h`).
  The planned one is `https://harmoniser-web.vercel.app` (not deployed when this was written).
  `https://` is verified against ESP-IDF's certificate bundle; `http://` is for the fake.
- The board does not follow redirects, so its token never goes to another host.

## The flow

```
board                           relay                              user (app or browser)
  | POST /register {hw,kind,fw}   |                                   |
  |------------------------------>|                                   |
  |<-- 201 {id,token,code,pair_url}                                   |
  | shows pair_url as a QR code, and the code under it                |
  | GET /{id}/capsule  (every 2 s)|                                   |
  |------------------------------>|   scans the QR code -> GET pair_url, presses the button
  |<-- 200 {claimed:false,...}    |   or types the phrase: POST /claim {code}
  |                               |<----------------------------------|
  |                               |--- 200 {id,kind} ---------------->|
  |<-- 200 {claimed:true,...}     |   PUT /{id}/capsule {...}         |
  | QR code goes, "cloud" marker  |<----------------------------------|
  |<-- 200 {version:1,capsule:{}} |                                   |
  | shows the capsule             |                                   |
  | POST /{id}/state {...}        |   GET /{id}/state                 |
  |------------------------------>|<----------------------------------|
```

## Device side

### `POST /api/devices/register`

Called when the board has no stored token (first boot, or after a 401).

```json
{"hw":"3f9c2a7be01d4c55","kind":"wrist","fw":"8a14f2c"}
```

| Field | Meaning |
| --- | --- |
| `hw` | Stable id of the board: 16 hex digits, the first 8 bytes of SHA-256 over `"harmoniser-wrist:"` followed by the 6 bytes of the Wi-Fi MAC. Not the MAC, and the MAC cannot be read back from it. 1 to 64 characters of `A-Z a-z 0-9 _ -`. |
| `kind` | `"wrist"`. Room for other devices later. |
| `fw` | Firmware version, free text up to 64 characters. |

Answer: `201`

```json
{"id":"dev_4b1f","token":"<secret>","code":"brave-otter-lamp","pair_url":"https://harmoniser-web.vercel.app/pair?code=brave-otter-lamp"}
```

| Field | Limits the board enforces | Meaning |
| --- | --- | --- |
| `id` | 1 to 64 characters of `A-Z a-z 0-9 _ -` (it goes into the URL path) | Device id. |
| `token` | 1 to 128 characters of `A-Z a-z 0-9 . _ ~ + / = -` | Device token, sent as `Authorization: Bearer <token>`. |
| `code` | 1 to 32 bytes of printable ASCII | Pairing code, see below. The board does not interpret it, it displays it. |
| `pair_url` | optional; 1 to 200 bytes of printable ASCII | The page that pairs the device. **The server builds it**; the board draws it as a QR code and never builds a URL itself. Without it the board shows the phrase alone. Keep it short: see [QR code](#qr-code). |

An answer that breaks one of the limits on `id`, `token` or `code` is treated as a failed
request. A `pair_url` that breaks its limits is ignored.

Registering the same `hw` again gives the same `id` with a new `token`, `code` and
`pair_url`. The old token and code stop working, the device is unclaimed again, and its
capsule and pending action are dropped. (A board that lost its token may have changed hands.)

The board keeps `id`, `token`, `code` and `pair_url` in flash (NVS).

### `GET /api/devices/{id}/capsule`

With `Authorization: Bearer <token>`. The board polls this every 2 seconds, on one kept-alive
connection.

```json
{"claimed":true,"version":3,"capsule":{"type":"counter","label":"Squats","count":0},
 "action_seq":7,"action":"increment","code":null,"pair_url":null}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `claimed` | yes | Whether a user has claimed the device. |
| `version` | yes | Whole number, 0 to 2^53. Changes whenever the capsule changes. The board compares for equality only, so a counter and a timestamp both work. |
| `capsule` | no | `null`, or a capsule object exactly like the body of the local `POST /capsule`: `{"type":"timer","label":"…","seconds":N}` or `{"type":"counter","label":"…","count":N}`, with the optional `running` and `motion`. |
| `action_seq` | yes | Whole number, 0 to 2^53. Changes with every new action. |
| `action` | no | `null`, or one of `start`, `pause`, `toggle`, `reset`, `increment`, `motion_on`, `motion_off`. |
| `code`, `pair_url` | no | While unclaimed: the current pairing code and its URL. This is how a renewed code reaches the board. `null` or absent otherwise. A `pair_url` without a `code` is ignored. |

What the board does with it:

- **Capsule.** If `version` differs from the version it last took, it applies `capsule` under
  the rules of the local `POST /capsule` (same validation, same code). A capsule it refuses
  is logged and not tried again until `version` changes. `capsule: null` with a new version
  leaves the screen as it is. Applying a capsule restarts it: a timer runs from the top.
- **Action.** If `action_seq` differs from the one it last took, it runs `action` once. An
  action that does not fit the capsule (`pause` on a counter) is skipped, not retried.
  When both are new in one answer, the capsule comes first.
- **After a restart or a registration** the first answer's capsule is applied (the board
  gets its capsule back), but its `action_seq` is only noted: an action from before the
  restart is not run a second time.
- **Pairing.** A `code` different from the one it holds replaces it on the screen and in flash.

Limits on the answer: 2048 bytes, nested at most 8 deep. Anything else counts as a failed request.

`401` when the id or the token is unknown. The board then forgets its registration and
registers again. An unknown device id must be a 401 too; the board treats a 404 on this
route the same way, in case the backend prefers that.

### `POST /api/devices/{id}/state`

With the bearer token. Body: the object of the local `GET /state`, plus `version`.

```json
{"type":"counter","label":"Squats","count":4,"seconds":0,"remaining_seconds":0,
 "running":false,"done":false,"motion":false,"version":3}
```

`version` is the relay version of the capsule on the screen. It is `0` when the screen
shows nothing from the relay: the board is idle, or somebody set a capsule over the local
API since. (So capsule versions should start at 1.)

Answer: `204`, no body. `401` as above.

When it is sent: after any change of `type`, `label`, `count`, `seconds`, `running`, `done`,
`motion` or `version` (a tap on + is a change of `count`), at most once a second; and every
10 seconds as a heartbeat. A running timer's `remaining_seconds` alone is not a change, so
a countdown does not cause a request per second; for a stopped timer it is (a reset).

### When the relay does not answer

Requests time out after 4 seconds. After a failure the board waits 2, 4, 8, 16, then 30
seconds between attempts. After two failures in a row the screen says "cloud offline". The
screen, the touch buttons, the timer and the local API carry on as before. The first
request that succeeds ends the backoff. Anything other than the expected status (200, 201,
204) or a 401 counts as a failure, 5xx included.

## User side

What the app calls. The app-facing summary of this section is "For the app: sending a
capsule to another device" in the team repo's `esp32-companion/README.md`; the two are
meant to say the same thing, and [the differences](#where-the-fake-goes-beyond-the-app-section)
are listed below.

Every request carries `X-Harmoniser-Token: <token>`, the same anonymous token the app
already uses for the marketplace routes: 32 to 256 characters of `A-Z a-z 0-9 _ -`, made up
by the app itself on first run (a browser makes its own). Nothing issues it and there are
no accounts. A device belongs to the token that claimed it. `Authorization: Bearer` is the
board's header, with the device token from the registration; it does nothing on these routes.

| Route | Body | Answer |
| --- | --- | --- |
| `POST /api/devices/claim` | `{"code":"brave-otter-lamp"}` | `200 {"id":"…","kind":"wrist"}`. `404` for an unknown, used or expired code. `429` after too many wrong codes (fake: 10 within a minute per token; then even the right code is refused until the minute is over). `400` if `code` is not three words. |
| `GET /api/devices` | | `200 {"devices":[{"id":"…","kind":"wrist","last_seen_ms_ago":N}]}`: the devices this token has claimed. |
| `PUT /api/devices/{id}/capsule` | like the local `POST /capsule` | `200 {"version":N}`. The version goes up and a pending action is dropped. `400` under the board's rules (`README.md`), and then nothing changes. |
| `POST /api/devices/{id}/action` | `{"action":"start"}`, or `pause`, `toggle`, `reset`, `increment` | `200 {"action_seq":N}`. `400` for anything that is not an action. |
| `GET /api/devices/{id}/state` | | `200`: the state the board last reported, with its `version`, plus `last_seen_ms_ago`, the time since the board's last request (poll or report). |
| `DELETE /api/devices/{id}` | | `204`. Unpairs: the device keeps its id and token, loses its owner, its capsule and its pending action, and gets a new code, which the board shows after its next poll. |
| `GET /pair?code=…` | | The web page behind the QR code, see below. No token needed to open it. |

`401` when `X-Harmoniser-Token` is missing or not of that shape. `404` for a device that
does not exist, is not claimed, or was claimed by another token: the three look the same
on purpose.

Error codes, taken from the backend's `lib/devices/errors.ts`:

| Status | `code` | When |
| --- | --- | --- |
| 400 | `invalid_json` | The body is not a JSON object, is nested deeper than 8, or holds a NUL. |
| 400 | `invalid_capsule` | `PUT …/capsule` with a capsule the board would refuse. |
| 400 | `invalid_action` | `POST …/action` with something that is not an action. |
| 400 | `invalid_code` | `claim` with a `code` that is not three words. |
| 401 | `unauthorized` | No usable `X-Harmoniser-Token`; on the device side, an unknown id or device token. |
| 404 | `code_not_found` | `claim` with an unknown, used or expired code. |
| 404 | `not_found` | No such device for this token; unknown path. |
| 413 | `payload_too_large` | Body over 1024 bytes. |
| 429 | `rate_limited` | Too many wrong codes. |

Device-side only: `invalid_registration` and `invalid_state` (400). The fake also answers
`405 method_not_allowed`. It never answers 409, 415 or 503, and sends no `Retry-After`
with a 429; the real backend may.

Reading `GET …/state`: `version` says which capsule the board is showing. It is the version
a `PUT` returned, or `0` when the board shows something that did not come from the relay.
Ignore a state whose `version` is not the one the last `PUT` returned. `last_seen_ms_ago`
above about 15000 means the board is offline (it polls every 2 seconds, and backs off to at
most 30 seconds when the relay does not answer).

### Where the fake goes beyond the app section

The app section leaves these open; this is what the fake does, for the backend to copy or change:

- **The token header.** The app section says `Authorization: Bearer <install token>`. The
  backend's convention, and the fake's since this was written, is `X-Harmoniser-Token`
  (above). The app section needs that one line changed.
- **The error body.** The app section shows `{"error":"…"}`; it is `{"error":{"code","message"}}`.
- `claim` answers `400` to a `code` that is not three words. An app that only handles 404 and
  429 should treat any other 4xx as "not paired".
- The shape of `GET /api/devices` (above) and the `204` of `DELETE` are choices made here.
- `action` also takes `motion_on` and `motion_off`, as the board's local API does.
- `GET …/state` before the board's first report has only `last_seen_ms_ago`. The board
  reports within a second of registering, so the app is unlikely to see that.
- `kind` is whatever the device registered with; the fake does not restrict it to `wrist` and `web`.

## Pairing

### The code

`code` is three lower-case ASCII words of 3 to 5 letters joined by hyphens:
`brave-otter-lamp`. The server makes it; the board has no word list.

- `claim` takes it the way a person types it: any case, hyphens or spaces between the
  words (`Brave Otter Lamp`). The server normalises.
- A code works once, and for 10 minutes. In the fake, the device's next poll after the 10
  minutes returns a new `code` and `pair_url`, which the board then shows; the old code
  gets a 404 from that moment (from the 10 minutes on, not from the poll on). Registering
  again also makes a new one. A claimed device has no code.
- `claim` is limited: see the 429 above.
- The fake picks from 332 words embedded in `mock_relay.py`, about 25 bits for three words.
  **The real backend should use the EFF short word list** (1,296 words; CC BY 3.0, so it
  needs an attribution line somewhere in the product): about 31 bits for three words,
  against about 20 bits for six digits. The board copes with any `code` up to 32 bytes; on
  the QR screen a phrase too wide for the large font is shown in the small one.

### QR code

The board draws `pair_url` as a QR code, with the phrase under it as the fallback
("or type:"), and the board's IP address below. Once the device is claimed both go away.

- The fake's URL is `http://<host>:<port>/pair?code=<code>`, with the host and port from
  the `Host` header of the board's request (so the address the board reached the fake on),
  or from `--public-url`. `GET /pair?code=…` answers with a small page with a
  "Pair this device" button, which posts the code to `/api/devices/claim`. Opening the page
  pairs nothing; the button does. Any phone camera can scan the code and get there. The
  page sends the browser's token in `X-Harmoniser-Token`, kept in `localStorage` under
  `harmoniser.deviceToken`, the key the real site uses (it makes one up if there is none):
  a device paired that way belongs to that browser, not to the app.
- The real backend puts its own page at `pair_url`. The app's Scan Kit scanner reads the
  same QR code: if the scanned text is a URL whose path is `/pair` and which has a `code`
  parameter, take the `code` and call `claim` with it and the app's token.
- Size. The code is drawn at error correction level M on a 300 px white square, with whole
  pixels per module and a quiet zone of at least 4 modules:

  | `pair_url` length | QR version | Pixels per module |
  | --- | --- | --- |
  | up to 62 bytes | 4 or lower | 7 or more |
  | up to 84 bytes | 5 | 6 |
  | up to 106 bytes | 6 | 6 |
  | up to 152 bytes | 7, 8 | 5 |
  | up to 200 bytes | 9, 10 | 4 |

  `https://harmoniser-web.vercel.app/pair?code=brave-otter-lamp` is 60 bytes, 61 with
  three words of 5 letters: version 4, 7 pixels per module, a code 231 pixels wide. That
  leaves one byte before the next version: a longer host or path costs a pixel per module.
  Stay under 85 in any case. Measured on the board with the fake's 54-byte URL, which is
  version 4 as well.

## Known gaps

- **Only the latest action is held.** The relay holds only the latest action. Two actions between two
  polls (2 seconds apart) reach the board as one. For "+1" from the phone that loses taps;
  if that matters, send a new capsule with the count instead, or make `action` a queue.
- **No acknowledgement.** The board does not say which `action_seq` it ran. The state it
  reports afterwards is the only sign.
- **Last write wins.** A capsule set over the local API replaces the relay's on the screen
  (the board then reports `version: 0`) until the relay's version changes again.
- **A restart replays the capsule.** A board that reboots applies the relay's current
  capsule from the start: a timer that was half done, or done, runs again in full.
- **Unpairing leaves the capsule.** After `DELETE` the board gets a new code, but a capsule
  that is on its screen stays there (with "pair: …" in the small line at the top) until
  somebody sends another; the QR code is on the idle screen only. The board has no "clear".
- **Registering again unclaims.** A board that registers its `hw` again is unpaired from
  its owner. `hw` is derived from the MAC and is not a secret, so anyone who knows it can
  knock a device off its owner (they cannot read what was sent to it, and get no access to
  the owner's token). The backend may want to keep the claim, or ask for the old token.
- **HTTPS is not soak-tested.** On the board, TLS was checked as a handshake against the
  certificate bundle (`vercel.com`, `harmoniser-web.vercel.app`, `example.com`; a
  self-signed certificate was refused), with about 50 KB of internal RAM free while the
  connection was open. All polling so far was over plain HTTP to the fake. Polling over a
  kept-alive TLS connection for hours has not been run.
- **Polling.** One request every 2 seconds per board, for as long as it is on.
