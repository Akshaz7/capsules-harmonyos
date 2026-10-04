# Harmoniser wrist companion

Firmware for a Waveshare ESP32-S3-Touch-AMOLED-1.8 that shows one Harmoniser capsule on
the wrist: a timer countdown, or a counter with a big + button. The phone app talks to it
over Wi-Fi with plain HTTP and JSON. A mock server with the same API lets the app be
wired without the hardware.

It is a stretch goal. Nothing in the app should depend on it being there.

| File | What it is |
| --- | --- |
| `mock_esp32.py` | Stand-in for the board. Python 3.8+, standard library only. |
| `test_api.sh` | curl script that checks the API. Same script for the mock and the board. |
| `RELAY.md` | Contract between the board, the cloud relay and the app (`/api/devices/**`). |
| `mock_relay.py` | Stand-in for the cloud relay, in memory. Python 3.8+, standard library only. |
| `test_relay.sh` | curl script that checks a relay against `RELAY.md`. Same script for the fake and the real backend. |
| `find_esp32.sh` | Finds the board's IP on the local network (mDNS, then MAC lookup). |
| `main/` | The firmware (ESP-IDF, C). |
| `main/secrets.h.example` | Template for the Wi-Fi credentials (`main/secrets.h` is git-ignored). |
| `tests/` | Unit tests that run on the laptop, without ESP-IDF: `make -C tests test`. |
| `tools/gen_fonts.sh` | Regenerates the fonts in `main/fonts/`. Not needed for a normal build. |

## Status

As of 2026-10-03.

| | State |
| --- | --- |
| Mock server | Passes `test_api.sh` (72 checks) and its unit tests. |
| Host unit tests | `make -C tests test`: 1,646 checks in C on the firmware's own source files, 19 Python tests on the mock and 37 on the fake relay. All pass. |
| Firmware build | Builds without compiler warnings on ESP-IDF v5.5. 1,717,936 bytes, 80% of the app partition free. |
| Boot on hardware | One board (revision V2): boots, display and touch drivers start, accelerometer and audio codec answer, HTTP server starts. |
| Wi-Fi on hardware | Joins the phone hotspot (WPA3) and the venue network `HackYeah2026`, which it sees on 2.4 GHz channel 1. Joining the venue network often takes several attempts. |
| HTTP API on hardware | **Confirmed**: `./test_api.sh http://<board ip>` passes 72 of 72 against the board over the venue Wi-Fi. JSON nested 300 and 1024 levels deep gets a 400 and the board keeps running (it used to reboot). |
| Screen, touch, beep | **Confirmed on hardware** by the owner: the screen shows the UI, a tap on + raises the count, the speaker beeps when a timer ends. `/screenshot` works on the board. |
| Cloud relay client | **Confirmed on hardware against the fake and against the live relay.** Against `mock_relay.py` (plain HTTP): registration, pairing QR code and phrase, capsules and actions from the relay, state reports, "cloud offline" and recovery. Against production (`https://harmoniser.keanuc.net`): `test_relay.sh` 106 of 106, and 30 minutes of HTTPS polling with no gap, reboot or failed request (see the status note below). See [Cloud relay](#cloud-relay). |
| Rep counting | Experimental and **still untuned**. Off unless asked for. |

Full list in [Tested and not tested](#tested-and-not-tested).

## For the app: sending a capsule to another device

The app does **not** talk to the board directly. It talks to a small cloud relay; devices (this
board, or a browser tab open at `/device`) fetch their capsule from the relay and report back.
That way the phone and the device need no shared Wi-Fi and no IP address.

> **Status, 2026-10-03 22:15:** the relay is **live** at `https://harmoniser.keanuc.net` (also
> `https://harmoniser-web.vercel.app`). `test_relay.sh` passes 106 of 106 against production, and
> the board has polled it over HTTPS for 30 minutes with no gap, reboot or failed request. The real
> app has not yet been run against it.

**Base URL:** `https://harmoniser.keanuc.net`. Keep it in one constant. To work offline, run the fake
and point the app at it:

```sh
python3 esp32-companion/mock_relay.py --port 8090 --host 0.0.0.0
```

The full contract, including the device side and the known gaps, is in [`RELAY.md`](RELAY.md).

**Who you are:** every request from the app carries `X-Harmoniser-Token: <install token>`, the same
header and the same token as the marketplace API. There are no accounts and nothing to register:
the app makes the token itself on first launch (at least 32 random bytes, base64url, so 43 or more
characters of `A-Z a-z 0-9 - _`), keeps it in Preferences and reuses it. The relay accepts any
well-formed token and stores only a keyed hash of it.

The token is a secret, not just a label: whoever holds it can control the devices paired with it.
Generate it with a cryptographic random source, send it only over HTTPS, never log it and never put
it in a shared capsule. Pairing ties a device to the token that claimed it, and only that token can
send to it; the gatekeeper's consent still decides whether the app sends anything at all.

### Pairing

A device that is not paired shows a QR code and, under it, a three-word phrase:

- QR text: `https://<host>/pair?code=brave-otter-lamp`
- Phrase (backup, typed by hand): `brave-otter-lamp`

In the app's QR scanner: if the scanned text is a URL whose path is `/pair` and which has a `code`
parameter, take the `code` and claim the device; anything else is a capsule import as before. The
code is three lower-case words; any case, and hyphens or spaces between words, are accepted. It can
be used once and expires 10 minutes after it was shown, when the device shows a new one.

```sh
curl -X POST https://harmoniser-web.vercel.app/api/devices/claim \
  -H "X-Harmoniser-Token: $INSTALL_TOKEN" \
  -d '{"code":"brave-otter-lamp"}'
# 200 {"id":"dev_8f3a…","kind":"wrist"}      kind is "wrist" (the board) or "web" (a browser tab)
# 404 unknown, used or expired code        429 too many attempts
# errors look like {"error":{"code":"…","message":"…"}}, as in the marketplace API
```

Keep the returned `id`. `GET /api/devices` lists the devices this install has paired.

### Send a capsule

Only timers and counters can be sent, with the same limits as the board's own API below: `label` at
most 47 bytes of UTF-8, `seconds` 1 to 359999, `count` 0 to 999999. A longer label is cut to 47 bytes, not
refused.

```sh
curl -X PUT https://harmoniser-web.vercel.app/api/devices/$ID/capsule \
  -H "X-Harmoniser-Token: $INSTALL_TOKEN" \
  -d '{"type":"counter","label":"Pull-ups","count":0}'

curl -X PUT https://harmoniser-web.vercel.app/api/devices/$ID/capsule \
  -H "X-Harmoniser-Token: $INSTALL_TOKEN" \
  -d '{"type":"timer","label":"Pasta","seconds":540}'
# 200 {"version":7}      400 if the capsule is not valid
```

A timer starts as soon as the device receives it. The device picks a new capsule up within about
two seconds.

Buttons in the app map to actions:

```sh
curl -X POST https://harmoniser-web.vercel.app/api/devices/$ID/action \
  -H "X-Harmoniser-Token: $INSTALL_TOKEN" \
  -d '{"action":"increment"}'       # start | pause | toggle | reset | increment
```

### Read the state back

```sh
curl https://harmoniser-web.vercel.app/api/devices/$ID/state \
  -H "X-Harmoniser-Token: $INSTALL_TOKEN"
# 200 {"type":"counter","label":"Pull-ups","count":7,"seconds":0,"remaining_seconds":0,
#      "running":false,"done":false,"motion":false,"version":7,"last_seen_ms_ago":1200}
```

Poll about every two seconds while the capsule is on screen. A tap on **+** on the device shows up
as a higher `count`; apply the difference to the app's counter. `version` tells you which capsule
the device is showing: ignore a state whose `version` is older than the one your last send
returned. `last_seen_ms_ago` above about 15000 means the device is offline.

`DELETE /api/devices/$ID` unpairs. One install can pair at most 20 devices (`409 too_many_devices`).

A device that is unknown, unpaired or paired to another install answers `404` on every route, so
the app cannot tell those cases apart. Before the device's first report, `state` holds only
`last_seen_ms_ago`. A running timer's `remaining_seconds` can be up to ten seconds old: count down
locally from the value you sent and use the device's state for `running`, `done` and `count`.

### Rules for the app side

- Send only after the user has allowed it in the gatekeeper ("Show on another device"), and log
  both a send and a refusal.
- Never wait on the relay: short timeout, every failure ignored, the capsule keeps working on the
  phone.
- What leaves the phone is the capsule type, its label and one number. Nothing else.

## The API

Base URL: `http://<board ip>` (port 80) or `http://harmoniser.local`. The mock listens on
port 8080. Requests and responses are JSON. No `Content-Type` header is needed.

The board shows one capsule at a time. A new `POST /capsule` replaces the current one.

> **No authentication.** This local API accepts requests from anyone on the same network: any
> device on that Wi-Fi can replace the capsule, change the count or fetch `/screenshot`. That is
> acceptable on a phone hotspot for a demo and not on a shared network. It exists for
> development, for the tests and as an offline fallback; the app should go through the relay
> above, where every request is tied to a paired install.

### `POST /capsule`

```sh
curl -s -X POST http://localhost:8080/capsule -d '{"type":"timer","label":"Pasta","seconds":540}'
```
```json
{"type":"timer","label":"Pasta","count":0,"seconds":540,"remaining_seconds":540,"running":true,"done":false,"motion":false}
```

```sh
curl -s -X POST http://localhost:8080/capsule -d '{"type":"counter","label":"Squats","count":0}'
```
```json
{"type":"counter","label":"Squats","count":0,"seconds":0,"remaining_seconds":0,"running":false,"done":false,"motion":false}
```

| Field | Applies to | Rules |
| --- | --- | --- |
| `type` | both | Required. `"timer"` or `"counter"`. |
| `label` | both | String. Optional, default empty. Must be valid UTF-8. Cut to 47 bytes, never inside a character. |
| `seconds` | timer | Required. Number from 1 to 359999. |
| `count` | counter | Number from 0 to 999999. Optional, default 0. |
| `running` | timer | *Extra.* `false` loads the timer paused. Default `true`: **the countdown starts as soon as the capsule arrives.** |
| `motion` | counter | *Extra.* `true` counts reps with the motion sensor. Default `false`. Ignored if the sensor did not start: check `motion` in the response. |

Unknown fields are ignored. The response is the new state, the same object as `GET /state`.

Limits on any request body: 1024 bytes; arrays and objects nested at most 8 deep (the
board's JSON parser recurses and its stack is small); no NUL character, neither as a raw
byte nor as the escape `\u0000`.

### `GET /state`

```sh
curl -s http://localhost:8080/state
```
```json
{"type":"counter","label":"Squats","count":2,"seconds":0,"remaining_seconds":0,"running":false,"done":false,"motion":false}
```

All eight fields are always present.

| Field | Meaning |
| --- | --- |
| `type` | `"idle"` (nothing sent yet), `"timer"` or `"counter"` |
| `label` | The label as shown on the screen |
| `count` | Counter value. This is how a count made on the wrist gets back to the app: poll `/state`. |
| `seconds` | Timer length |
| `remaining_seconds` | Timer time left, rounded up |
| `running` | Timer is counting down |
| `done` | Timer reached zero |
| `motion` | Counter is being fed by the motion sensor |

### `POST /action` (extra)

Not needed for the basic flow. It does from the app what a finger does on the screen.

```sh
curl -s -X POST http://localhost:8080/action -d '{"action":"pause"}'
```

| `action` | Timer | Counter |
| --- | --- | --- |
| `start` | Run (from the top if it had finished) | 409 |
| `pause` | Stop the countdown | 409 |
| `toggle` | Pause/run; after the end, reset. Same as a tap on the screen. | 409 |
| `reset` | Back to the full time, paused | Count to 0 |
| `increment` | 409 | Count + 1. Same as the + button. |
| `motion_on`, `motion_off` | 409 | Switch rep counting on or off (`motion_on`: 503 without a working sensor) |

The response is the new state.

### `GET /screenshot` (extra, board only)

Debug aid: what the UI is drawing right now, as a 368x448 BMP. It shows what LVGL renders,
not what the panel displays. `curl -s -o screen.bmp http://<board ip>/screenshot`.
The mock answers 503.

### Errors

Errors are `{"error":"<what was wrong>"}`.

| Status | When |
| --- | --- |
| 400 | Body is not a JSON object, is nested deeper than 8 levels or contains a NUL; a field is missing, of the wrong type or out of range; the label is not valid UTF-8; the `Content-Length` is not a number from 0 up |
| 404 | Unknown path, whatever the method |
| 405 | Known path, wrong method (`HEAD` and `OPTIONS` included) |
| 408 | The body did not arrive within 2 seconds (board only) |
| 409 | The action does not fit the current capsule (for example `pause` on a counter, `motion_on` on a timer, or anything while idle) |
| 413 | Body larger than 1024 bytes |
| 500 | Out of memory on the board; a bug in the mock |
| 503 | `motion_on` for a counter on a board whose motion sensor did not start; `/screenshot` without a display |

After a 408 the connection is closed. A body that is too large is read and thrown away up
to 8192 bytes beyond the limit, so that the 413 reaches the client; past that the connection
is closed, and the client may see a reset instead of the answer. Half a surrogate pair (`"\ud83d"`) is not a
character: such a body is not JSON and gets the first 400.

A rejected request leaves the current capsule untouched.

### From a Harmoniser capsule to a wrist capsule

| Capsule component (`SCHEMA.md`) | Send |
| --- | --- |
| `timer { label, minutes }` | `{"type":"timer","label":label,"seconds":minutes*60}` |
| `counter { label, source:"manual" }` | `{"type":"counter","label":label,"count":<current value>}` |
| `counter { label, source:"motion" }` | the same plus `"motion":true` |

The HarmonyOS emulator probably cannot resolve `harmoniser.local`; use the IP address.

## Mock server

```sh
python3 mock_esp32.py                # 0.0.0.0:8080
python3 mock_esp32.py --port 9000
./test_api.sh                        # checks http://localhost:8080
./test_api.sh http://localhost:9000
```

It prints its LAN address at start-up and one line per request.

The mock answers every request in `test_api.sh` and in `tests/` with the status code the
firmware gives, and it cuts and refuses labels by the same rules (`tests/vectors/` is run
against both). It is not the same in every corner. Known differences:

- Port 8080 instead of 80; no screen, so `/screenshot` is always 503.
- `motion_on` always works (never 503), and while a counter is in motion mode it adds one
  rep every 2 seconds so that polling has something to see (`--motion-interval 0` turns
  that off).
- **Duplicate keys**: for `{"count":1,"count":2}` the board uses the first value and the
  mock the last. Left as it is; do not send duplicate keys.
- A negative or non-numeric `Content-Length` is a 400 on both, but the board's HTTP server
  answers it itself, in plain text instead of JSON.
- The mock never answers 408: a body that does not arrive blocks that one connection.
- JSON is parsed by Python on one side and cJSON on the other. They agree on everything
  the tests send; they may not agree on text that is not quite JSON (odd number formats,
  for instance), and the wording of an error can differ where a body is wrong in two ways.

## Firmware

### Build

ESP-IDF v5.5 (Waveshare supports v5.5.x and v6.0.x). On this laptop pyenv's Python hides the
one ESP-IDF was installed with, hence `PYENV_VERSION`:

```sh
export PYENV_VERSION=system
source ~/esp/esp-idf/export.sh
cd esp32-companion
cp main/secrets.h.example main/secrets.h   # then edit, see below
idf.py set-target esp32s3                  # first time only
idf.py build
```

The first build downloads Waveshare's board support package, LVGL and a few drivers
(about 200 MB) into `managed_components/`. `dependencies.lock` pins the versions that were
tested; keep it. `sdkconfig` is generated from `sdkconfig.defaults`; after editing the
defaults, delete `sdkconfig` and build again.

To build with fewer parallel jobs (the laptop ran out of memory once with several builds
going): `idf.py reconfigure && ninja -C build -j2`. When CMake re-runs it prints two
warnings of its own ("Missing kconfig option. Re-run the build process"); they come from
the component manager's second pass, not from the code.

### Unit tests on the laptop

```sh
make -C tests test      # needs a C compiler and Python 3, not ESP-IDF
```

`tests/` compiles `main/capsule.c`, `main/http_api.c` and `main/validate.c` unchanged,
against small stand-ins for ESP-IDF in `tests/stubs/` (a clock the test sets, a lock that
checks it is taken and given in pairs, an HTTP server without sockets) and a copy of the
cJSON version the firmware uses (`tests/vendor/`). They cover the timer state machine, label
cutting, the nesting check and request validation. `tests/test_mock.py` runs the mock
against the same vectors. What they cannot show is anything about stack use, Wi-Fi, the
display or the real HTTP server; that is what `test_api.sh` against the board is for.

### Wi-Fi

`main/secrets.h` lists networks in order of preference:

```c
#define WIFI_NETWORKS \
    { "Venue network", "password" }, \
    { "Phone hotspot", "password" }
```

At boot the board scans, logs every network it can see, and joins the first listed network
that is in range. If that fails for 15 seconds it tries the next, and it keeps cycling until
one works. It reconnects by itself when the network drops, and every 10 seconds it checks
that the link is really still there. WPA2, WPA3 and mixed networks
work. The radio is **2.4 GHz only**: a network that is only on 5 or 6 GHz never shows up in
its scan. A phone hotspot set to 6 GHz is such a network. The app's machine and the board
must be on the same network; a board that prefers the venue network is out of reach of a
laptop on the hotspot.

### Flash

```sh
ls /dev/serial/by-id/                      # the board is the "Espressif_USB_JTAG_serial_debug_unit"
idf.py -p /dev/ttyACM0 flash monitor       # Ctrl+] leaves the monitor
```

Check which `ttyACM` number is the board first. On this laptop a phone was also plugged in
as a `ttyACM` device and the numbers swapped after a re-plug; the `/dev/serial/by-id/...`
path does not change. If the port is not writable, add yourself to the `dialout` group
(`sudo usermod -aG dialout $USER`, then log in again). Opening the serial port resets the
board, and after a reset it may come back on another of its networks with another address.

### Hardware revisions

There are two: the original (SH8601 display, FT3168 touch) and V2 (CO5300 display,
CST816-family touch). **One binary runs on both; there is nothing to select.** Waveshare's
BSP drives both panels with the CO5300 driver and tells them apart by which touch controller
answers on I2C. The firmware logs what it found:

```
I (986) harmoniser: hardware revision: V2 (CO5300 display, CST816 touch at 0x15)
```

Only the V2 path has run on real hardware. Waveshare's `00_board_check` example does not
report the revision (it prints chip, flash and PSRAM details); their `92_qmi8658_imu` and
`13_display_colorbar` examples do.

### Finding the board

1. **Screen**: the idle screen shows the IP address and the network name. Timer and counter
   screens show the IP in small type at the top.
2. **Serial**: one line on connect and every 10 seconds:
   `HARMONISER_IP=192.168.43.57 SSID=<network name> RSSI=-35`
3. **Network**: `./find_esp32.sh` tries `harmoniser.local`, then looks for the board's MAC
   (printed at boot) in the neighbour table after pinging this machine's /24. It prints the IP
   and writes it to `esp32_ip.txt`. Give it the MAC once: `ESP32_MAC=aa:bb:cc:dd:ee:ff ./find_esp32.sh`,
   or put the MAC on one line in `esp32_mac.local` (git-ignored).

### What the screen shows

- **Idle**: "harmoniser", the IP address, the network name. Without Wi-Fi: "no Wi-Fi" in
  amber with "still looking", or "joining" with the network name.
- **Timer**: label, large `mm:ss` (from 100 minutes on, `h:mm:ss` in a smaller font). Tap
  anywhere to pause or start. White while running, amber while paused. At zero the screen
  flashes red for 6 seconds and the speaker beeps three times; a tap then resets the timer.
- **Counter**: label, large number, and a + button over the lower half. The number turns
  teal while motion counting is on.

Labels can use accented Latin letters (the font covers Latin-1 and Latin Extended-A).
Anything else, such as emoji, shows as a placeholder box.

### Rep counting (experimental)

Off by default. Switch it on with `"motion":true` in `POST /capsule` or with
`{"action":"motion_on"}`. The QMI8658 accelerometer is read at 50 Hz; a rep is counted when
the magnitude rises above `REP_HIGH_G` and then falls below `REP_LOW_G`, at most once every
`REP_REFRACTORY_MS` (0.8 s). The constants are at the top of `main/motion.c` and are first
guesses: **nobody has done a squat with it yet.** Each counted rep is logged on serial with
the acceleration, which is what to watch while tuning.

## Cloud relay

Optional. With `RELAY_URL` set in `main/secrets.h` the board also registers itself with a
cloud relay, shows a QR code and a three-word phrase to pair it with the app, and then
fetches capsules from the relay and reports its state to it, with outbound requests only.
The phone and the board then need no shared network. The local API above keeps working;
whichever side sent a capsule last is the one on the screen. Without `RELAY_URL` nothing
of this is started.

The contract, for the backend and the app, is in [`RELAY.md`](RELAY.md).

```sh
python3 mock_relay.py --port 8090 --host 0.0.0.0   # the fake; it prints nothing secret
./test_relay.sh http://localhost:8090              # 106 checks, with a simulated board
```

Put `#define RELAY_URL "http://<laptop ip>:8090"` into `main/secrets.h`, build and flash.
The idle screen then shows the QR code, "or type:" with the phrase, and the IP address.
Scan it with a phone on the same network, or:

```sh
T='X-Harmoniser-Token: any-32-or-more-characters-you-like'   # the app's own anonymous token
curl -X POST http://localhost:8090/api/devices/claim -H "$T" -d '{"code":"brave otter lamp"}'
curl -X PUT http://localhost:8090/api/devices/<id>/capsule -H "$T" -d '{"type":"counter","label":"Squats","count":0}'
curl http://localhost:8090/api/devices/<id>/state -H "$T"
```

On the screen: "cloud" in the small line at the top once the board is paired, "cloud
offline" when the relay has not answered twice in a row, "pair: …" above a capsule while
the board is not paired. The fake forgets everything when it stops; the board notices (401)
and registers again, with a new QR code.

Measured on the board (internal RAM; the largest free block stayed 31,744 bytes throughout):
about 83 KB free with the relay client polling over plain HTTP, about 50 KB free while one
HTTPS connection is open (handshakes with `vercel.com`, `harmoniser-web.vercel.app` and
`example.com` succeeded against the certificate bundle; a self-signed certificate was
refused), lowest ever 39 KB. The relay task used about 4 KB of its 10 KB stack.

## Two-minute check with the board in your hand

The serial log cannot show what is on the glass. With the board powered and the hotspot on:

1. The screen is lit: "harmoniser" in teal, an IP address in white, the network name below.
   If it is black, look at the serial log for `color failed` or a reboot loop.
2. From a machine on the same network: `./test_api.sh http://<that ip>`. It should end with
   `72 passed, 0 failed`. During the run the screen shows a counter, then a timer.
3. The run ends with a 2 second timer. The screen should flash red and the speaker should
   beep three times. Tap the screen: the flashing stops and the timer shows `00:02` in amber.
4. `curl -X POST http://<ip>/capsule -d '{"type":"timer","label":"Pasta","seconds":540}'`
   It counts down in white. Tap: it pauses and turns amber. Tap again: it runs.
5. `curl -X POST http://<ip>/capsule -d '{"type":"counter","label":"Squats","count":0}'`
   Tap the + button a few times. The number goes up; `curl http://<ip>/state` agrees.
6. Is the text the right way up, centred, and not cut off at the rounded corners?
   `curl -o screen.bmp http://<ip>/screenshot` saves what the firmware thinks it is drawing.

If the firmware does not boot at all, flash Waveshare's `00_board_check`
(https://github.com/waveshareteam/ESP32-S3-Touch-AMOLED-1.8, `examples/esp-idf/`) to confirm
the toolchain, flash and PSRAM settings, then their `00_bsp_quickstart` for display and touch.

## Tested and not tested

Tested:

- Host unit tests (`make -C tests test`): timer rounding and expiry, pause at the deadline,
  actions after the end, the longest timer, label cutting for 1- to 4-byte characters at
  the 47-byte limit, invalid UTF-8, the nesting and NUL scan, every validation error of
  `/capsule` and `/action`, 408/413 closing the socket, the `/screenshot` BMP layout.
- `mock_esp32.py` against `test_api.sh`: 72 of 72 checks, and `tests/test_mock.py`.
- Firmware build: no compiler warnings, ESP-IDF v5.5, Waveshare BSP 2.0.3, LVGL 9.6.0.
- On one V2 board, over the venue Wi-Fi, with the serial log captured throughout:
  `test_api.sh` 72 of 72; bodies of 300 and 1024 `[` and of 200 nested objects to `/capsule`
  and `/action` each get `400 JSON nested too deeply`, with no panic and no second boot
  banner, and `/state` answers afterwards; bodies of 1025 to 8000 bytes get the 413 with
  its JSON text; `GET /screenshot` returns a 238,432-byte BMP.
- On the same board, seen by the owner with an earlier build: the screen shows the UI, a
  tap on + raises the count, the speaker beeps at the end of a timer.
- From the serial log: boots without a crash, display, touch, accelerometer and codec
  initialise, joins the hotspot and the venue network, prints the `HARMONISER_IP=` line
  every 10 seconds.
- `find_esp32.sh`: the not-found path, and the MAC lookup using another device's MAC
  (before the change that makes it check the API; not re-run since).

- Cloud relay client, on the same board against `mock_relay.py` on a laptop: registers,
  keeps its registration over a reboot, shows the QR code (decoded from `/screenshot` with
  OpenCV: exactly the `pair_url`, version 4, 7 pixels per module, quiet zone 5 modules) and
  the phrase; after a claim a counter and a timer sent to the relay appear, `increment` and
  `pause` sent to the relay are applied once, a count changed on the board reaches the
  relay within three seconds, a running timer is reported every 10 seconds; a capsule set
  over the local API is reported with `version` 0; with the fake stopped the screen says
  "cloud offline", the retries back off to 30 seconds and `test_api.sh` still passes 72 of
  72; with the fake started again the board gets a 401, waits for its backoff, registers
  again once and carries on; against a fake that registers the board but answers 401 to
  every poll (`mock_relay.py --always-401`) it registered once in 75 seconds, not in a loop;
  unpairing gives the board a new phrase.

Not tested:

- The cloud relay client against a real backend, and any request beyond the TLS handshake
  over HTTPS (polling over a kept-alive TLS connection, for hours). A relay that accepts
  the connection and then says nothing (the 10 second timeout): the fake was either up or
  refusing connections. A pairing code expiring on the board after 10 minutes (host tests
  only). Scanning the QR code off the glass with a phone: it was decoded from the
  screenshot, which shows what LVGL draws, not what the panel displays.

- The 408 path on the board (a body that stops arriving), and a body more than 8192 bytes
  over the limit. Both are covered by the host tests only.
- The 503 for `motion_on` (this board's sensor works), also host tests only.
- The link check that rejoins after a lost disconnect event: it needs a network that
  drops the board without telling it.
- Rep counting with a moving board. Thresholds are guesses.
- The original hardware revision (SH8601 + FT3168).
- Reconnection after a drop. The fallback from one network to the next has been seen on
  the serial log: the venue network refused the board (reason 201, 2 or 205) for 15
  seconds and the board went on to the hotspot. On about half of the boots the first join
  attempt to the hotspot failed (reason 4, then 205) and the retry got through.
- `harmoniser.local` from another device, and `find_esp32.sh` finding the real board.
- Networks with a 32-character name or a 64-character key.
- Long runs, battery operation, and the mock on macOS (it uses nothing platform-specific).

## Third-party

| Component | Licence |
| --- | --- |
| [Waveshare BSP](https://components.espressif.com/components/waveshare/esp32_s3_touch_amoled_1_8) and QMI8658 driver | Apache-2.0 |
| LVGL 9.6, Espressif LVGL port, LCD/touch/codec drivers, mDNS | See each folder in `managed_components/` |
| cJSON 1.7.18 (`tests/vendor/cJSON`, for the host tests; the firmware uses ESP-IDF's copy) | MIT |
| Roboto (the bitmaps in `main/fonts/`, generated with `lv_font_conv`) | Apache-2.0 |
