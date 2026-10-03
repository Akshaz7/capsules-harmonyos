// Checks on untrusted request bytes, done before anything is parsed or stored.
// Pure C with no ESP-IDF dependencies: tests/ builds this file on the host.
#pragma once

#include <stdbool.h>
#include <stddef.h>

typedef enum {
    JSON_SCAN_OK,
    JSON_SCAN_TOO_DEEP,  // more than max_depth arrays/objects open at once
    JSON_SCAN_HAS_NUL,   // a NUL byte, or the escape \u0000 inside a string
} json_scan_t;

// Looks at a JSON text without parsing it. cJSON parses recursively, so the nesting has to
// be bounded first, and a C string cannot hold a NUL. Brackets inside strings do not count.
// mock_esp32.py has the same function; tests/vectors/json_scan.txt holds both to it.
json_scan_t json_scan(const char *body, size_t len, int max_depth);

// True if the NUL-terminated text is well-formed UTF-8 (no overlong forms, no surrogates,
// nothing above U+10FFFF).
bool utf8_valid(const char *text);
