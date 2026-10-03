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
| `find_esp32.sh` | Finds the board's IP on the local network (mDNS, then MAC lookup). |
| `main/` | The firmware (ESP-IDF, C). |
| `main/secrets.h.example` | Template for the Wi-Fi credentials (`main/secrets.h` is git-ignored). |
| `tools/gen_fonts.sh` | Regenerates the fonts in `main/fonts/`. Not needed for a normal build. |

## Status

As of 2026-10-03.

| | State |
| --- | --- |
| Mock server | Passes `test_api.sh` (50 checks). |
| Firmware build | Builds without warnings on ESP-IDF v5.5. 1,532,720 bytes, 82% of the app partition free. |
| Boot on hardware | Checked on the serial log of one board (revision V2): boots, display and touch drivers start, accelerometer and audio codec answer, HTTP server starts. |
| Wi-Fi on hardware | Joins the phone hotspot (WPA3) and gets an address. The venue network `HackYeah2026` is 5 GHz only and the board cannot see it. |
| **HTTP API on hardware** | **Not tested.** The laptop was on a different network from the board. Run `./test_api.sh http://<board ip>` from a machine on the same network. |
| **Screen, touch, beep** | **Not looked at by anyone yet.** See [Two-minute check](#two-minute-check-with-the-board-in-your-hand). |
| Rep counting | Experimental and untuned. Off unless asked for. |

Full list in [Tested and not tested](#tested-and-not-tested).

## The API

Base URL: `http://<board ip>` (port 80) or `http://harmoniser.local`. The mock listens on
port 8080. Requests and responses are JSON. No `Content-Type` header is needed.

The board shows one capsule at a time. A new `POST /capsule` replaces the current one.

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
| `label` | both | String. Optional, default empty. Cut to 47 bytes of UTF-8. |
| `seconds` | timer | Required. Number from 1 to 359999. |
| `count` | counter | Number from 0 to 999999. Optional, default 0. |
| `running` | timer | *Extra.* `false` loads the timer paused. Default `true`: **the countdown starts as soon as the capsule arrives.** |
| `motion` | counter | *Extra.* `true` counts reps with the motion sensor. Default `false`. Ignored if the sensor did not start: check `motion` in the response. |

Unknown fields are ignored. The response is the new state, the same object as `GET /state`.

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
| `motion_on`, `motion_off` | 409 | Switch rep counting on or off |

The response is the new state.

### `GET /screenshot` (extra, board only)

Debug aid: what the UI is drawing right now, as a 368x448 BMP. It shows what LVGL renders,
not what the panel displays. `curl -s -o screen.bmp http://<board ip>/screenshot`.
The mock answers 503.

### Errors

Errors are `{"error":"<what was wrong>"}`.

| Status | When |
| --- | --- |
| 400 | Body is not a JSON object, or a field is missing, of the wrong type or out of range |
| 404 | Unknown path |
| 405 | Known path, wrong method |
| 409 | The action does not fit the current capsule (for example `pause` on a counter, or anything while idle) |
| 413 | Body larger than 1024 bytes |
| 503 | `motion_on` on a board whose motion sensor did not start; `/screenshot` without a display |

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

It prints its LAN address at start-up and one line per request. Differences from the board:
port 8080 instead of 80; no screen; `motion_on` always works, and while a counter is in
motion mode it adds one rep every 2 seconds so that polling has something to see
(`--motion-interval 0` turns that off).

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
going): `idf.py reconfigure && ninja -C build -j4`.

### Wi-Fi

`main/secrets.h` lists networks in order of preference:

```c
#define WIFI_NETWORKS \
    { "Venue network", "password" }, \
    { "Phone hotspot", "password" }
```

At boot the board scans, logs every network it can see, and joins the first listed network
that is in range. If that fails for 15 seconds it tries the next, and it keeps cycling until
one works. It reconnects by itself when the network drops. WPA2, WPA3 and mixed networks
work. The radio is **2.4 GHz only**: a 5 GHz-only network never shows up in its scan.

### Flash

```sh
ls /dev/serial/by-id/                      # the board is the "Espressif_USB_JTAG_serial_debug_unit"
idf.py -p /dev/ttyACM0 flash monitor       # Ctrl+] leaves the monitor
```

Check which `ttyACM` number is the board first. On this laptop a phone was also plugged in
as a `ttyACM` device and the numbers swapped after a re-plug; the `/dev/serial/by-id/...`
path does not change. If the port is not writable, add yourself to the `dialout` group
(`sudo usermod -aG dialout $USER`, then log in again). Opening the serial port usually
resets the board.

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

## Two-minute check with the board in your hand

The serial log cannot show what is on the glass. With the board powered and the hotspot on:

1. The screen is lit: "harmoniser" in teal, an IP address in white, the network name below.
   If it is black, look at the serial log for `color failed` or a reboot loop.
2. From a machine on the same network: `./test_api.sh http://<that ip>`. It should end with
   `50 passed, 0 failed`. During the run the screen shows a counter, then a timer.
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

- `mock_esp32.py` against `test_api.sh`: 50 of 50 checks, plus manual checks of UTF-8
  labels, oversized bodies and simulated motion reps.
- Firmware build: no warnings, ESP-IDF v5.5, Waveshare BSP 2.0.3, LVGL 9.6.0.
- On one V2 board, from the serial log only: five complete boot logs with no crash and no
  display transfer errors, both the display and the touch controller initialise,
  accelerometer reads 0.99 g at rest, audio codec initialises, HTTP server starts, Wi-Fi
  scan and join of a WPA3 hotspot, the `HARMONISER_IP=` line every 10 seconds.
- `find_esp32.sh`: the not-found path, and the MAC lookup using another device's MAC.

Not tested:

- The HTTP API on the board. No request has reached it yet.
- Anything visible or audible: that the panel shows the UI, colours, font sizes, text
  position, the flash at timer end, the beep and its volume.
- Touch: taps on the timer and on the + button.
- `GET /screenshot` on the board.
- Rep counting with a moving board. Thresholds are guesses.
- The original hardware revision (SH8601 + FT3168).
- The fallback from one network to the next when the first one is in range but refuses
  the board, and reconnection after a drop. On about half of the boots the first join
  attempt to the hotspot failed (reason 4, then 205) and the retry got through about
  6 seconds later; the other boots joined in 2 seconds.
- `harmoniser.local` from another device, and `find_esp32.sh` finding the real board.
- Long runs, battery operation, and the mock on macOS (it uses nothing platform-specific).

## Third-party

| Component | Licence |
| --- | --- |
| [Waveshare BSP](https://components.espressif.com/components/waveshare/esp32_s3_touch_amoled_1_8) and QMI8658 driver | Apache-2.0 |
| LVGL 9.6, Espressif LVGL port, LCD/touch/codec drivers, mDNS | See each folder in `managed_components/` |
| Roboto (the bitmaps in `main/fonts/`, generated with `lv_font_conv`) | Apache-2.0 |
