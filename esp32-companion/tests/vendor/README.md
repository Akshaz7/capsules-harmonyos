`cJSON/` is cJSON 1.7.18 (MIT, see `cJSON/LICENSE`), copied unchanged from ESP-IDF v5.5
(`components/json/cJSON`), so the host tests parse JSON with the same code as the firmware.
It is used by `tests/` only; the firmware build uses ESP-IDF's own copy.
