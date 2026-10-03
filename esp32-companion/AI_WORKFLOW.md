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

## Unsuccessful approaches

- Joining the venue Wi-Fi: its access points are 5 GHz only and the ESP32-S3 radio is 2.4 GHz
  only. The board's own scan never lists it, so it runs on a phone hotspot.
- The BSP's default 100-line LVGL draw buffer: too large once Wi-Fi is running.

## Known limitations

- Motion rep counting is untuned; its thresholds are guesses and it is off by default.
- Timer-end flash and beep, touch input and the motion counter have not been checked by a person.
- No unit tests for the C code. The mock and the firmware are separate implementations of the
  same rules; only the HTTP behaviour is tested, on both.
- Wi-Fi credentials are compiled into the firmware binary, so the binary must not be shared.
