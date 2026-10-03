# AI workflow: ESP32 wrist companion

This folder was built with AI assistance on 2026-10-03, during HackYeah 2026. It follows the
format of the root [`AI_WORKFLOW.md`](../AI_WORKFLOW.md); merge these rows into that file if a
single log is preferred.

## Tools used

| Model, agent, MCP server, or Agent Skill | Version or source | Role |
| --- | --- | --- |
| Claude Code (Claude Opus 5.5), main session | Anthropic | Wrote the task brief, checked the board over serial, ran the API tests against the real board, reviewed the result |
| Claude Code background sub-agent (general-purpose) | Anthropic | Wrote the firmware, the mock server, the test and finder scripts and the README; built and flashed the board |
| ESP-IDF | v5.5 | Build system and SDK |
| Waveshare `esp32_s3_touch_amoled_1_8` BSP | 2.0.3 | Display, touch, IMU and audio drivers |
| LVGL | 9.6.0 | UI toolkit |
| esptool | 5.3.1 | Flashing |

## Important prompts and instructions

- The API contract came from the app owner: Wi-Fi and HTTP (the emulator has no Bluetooth),
  `POST /capsule` with `{"type":"timer","label","seconds"}` or `{"type":"counter","label","count"}`,
  `GET /state` for the current count. Stretch goal; must never block the main app.
- The sub-agent was told to start from Waveshare's BSP rather than write drivers, to keep Wi-Fi
  credentials out of tracked files, to deliver a mock server first so the app could be wired
  without hardware, and to state plainly what was untested.
- After an out-of-memory crash on the build laptop, builds were limited to four parallel jobs.

## AI-assisted work log

| Date | Tool/model | Request or task | Generated or changed | Human review and validation |
| --- | --- | --- | --- | --- |
| 2026-10-03 | Claude Code sub-agent | Mock server and API test script for the companion API | `mock_esp32.py`, `test_api.sh` | `test_api.sh` passes 50/50 against the mock |
| 2026-10-03 | Claude Code sub-agent | Firmware: Wi-Fi, HTTP API, timer and counter screens, timer-end beep, optional motion counting | `main/*.c`, `main/*.h`, `sdkconfig.defaults`, `partitions.csv`, generated fonts in `main/fonts/` | Builds with no warnings; five clean boot logs on the board |
| 2026-10-03 | Claude Code sub-agent | Fix "spi transmit (queue) color failed" on every screen update | LVGL draw buffer reduced to 20 lines (`sdkconfig.defaults`) | Errors gone from later boot logs |
| 2026-10-03 | Claude Code main session | Test on the real board | none | `test_api.sh` passes 50/50 against the board; a screenshot fetched from the board shows the counter screen; the owner read the board's IP off its screen |
| 2026-10-03 | Claude Code main session | Remove device-specific details before publishing | `find_esp32.sh`, `README.md` | Secret scan of files and history: no Wi-Fi passwords |
| 2026-10-03 | Claude Code sub-agent (independent reviewer, read-only) | Review the firmware and mock source for real defects | none; a findings list | One critical finding (deeply nested JSON overflows the HTTP task stack and reboots the board), five medium, several low |
| 2026-10-03 | Claude Code sub-agent | Fix the review findings and add host-side tests | `main/validate.c`, `main/http_api.c`, `main/net.c`, `main/capsule.c`, `mock_esp32.py`, `find_esp32.sh`, `test_api.sh`, `tests/`, `README.md` | Host tests: 1,108 C checks and 19 Python tests pass. `test_api.sh` 72/72 on the mock and on the board. 300-level nested JSON on the board: 400, no reboot. Main session read the diff and re-ran all three suites |
| 2026-10-03 | Owner | Hands-on check of the board | none | Tapped + (count went up) and heard the timer-end beep |
| 2026-10-03 | Claude Code sub-agent | Cloud relay client for the firmware, a fake relay and its test script | `main/relay.c`, `main/relay_sync.c`, `main/capsule_json.c`, `main/ui.c` (QR code and phrase), `mock_relay.py`, `test_relay.sh`, `RELAY.md`, `tests/` | On the real board against the fake: register, pair by phrase, capsule and action from the relay, state back, offline and recovery. QR decoded from a board screenshot. Host tests 1,646 C checks; `test_relay.sh` 106/106 |
| 2026-10-03 | Claude Code sub-agent (independent reviewer, read-only) | Review the relay client | none; a findings list | No memory-safety or secret findings. One high (re-register loop without backoff), three medium, several low; all fixed and re-checked on the board |
| 2026-10-03 | Claude Code sub-agent | Make the board's hardware id unguessable | `main/relay.c`, `main/relay_sync.c`, `RELAY.md` | Prompted by a security review of the server: the id was derived from the Wi-Fi MAC alone. Now mixes in a random secret kept on the board; verified across two reboots |

## Unsuccessful approaches

- First conclusion about the venue Wi-Fi was wrong: early scans did not list it, so it was written
  off as 5 GHz only. It is also on 2.4 GHz; the board joins it, though often only after several
  attempts.
- Closing the socket straight after a 413 (as the reviewer suggested): the connection was reset
  and the client never saw the error body. The firmware now reads and drops up to 8 KiB first.
- The BSP's default 100-line LVGL draw buffer: too large once Wi-Fi is running.

## Known limitations

- The relay client has only talked to a local fake over plain HTTP. HTTPS was checked as a
  handshake, not as sustained polling, and the real backend is not deployed yet.
- No person has scanned the QR code off the board's screen with a phone yet.

- Motion rep counting is untuned; its thresholds are guesses and it is off by default.
- The motion counter has not been checked by a person.
- The mock and the firmware are separate implementations of the same rules. Shared test vectors
  and `test_api.sh` run against both; remaining differences are listed in the README.
- The lost-link recovery and the 408 path are covered by code reading and host tests only.
- Wi-Fi credentials are compiled into the firmware binary, so the binary must not be shared.
