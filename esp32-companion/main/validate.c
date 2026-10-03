#include "validate.h"

#include <string.h>

json_scan_t json_scan(const char *body, size_t len, int max_depth)
{
    int depth = 0;
    bool in_string = false;
    for (size_t i = 0; i < len; i++) {
        char c = body[i];
        if (c == '\0') {
            return JSON_SCAN_HAS_NUL;
        }
        if (in_string) {
            if (c == '\\') {
                if (len - i > 5 && memcmp(body + i + 1, "u0000", 5) == 0) {
                    return JSON_SCAN_HAS_NUL;
                }
                i++;  // whatever is escaped, it cannot end the string
            } else if (c == '"') {
                in_string = false;
            }
        } else if (c == '"') {
            in_string = true;
        } else if (c == '[' || c == '{') {
            if (++depth > max_depth) {
                return JSON_SCAN_TOO_DEEP;
            }
        } else if ((c == ']' || c == '}') && depth > 0) {
            depth--;
        }
    }
    return JSON_SCAN_OK;
}

bool utf8_valid(const char *text)
{
    const unsigned char *p = (const unsigned char *)text;
    while (*p) {
        unsigned char lead = *p++;
        if (lead < 0x80) {
            continue;
        }
        // The second byte's range is what rules out overlong forms, surrogates and > U+10FFFF.
        unsigned char low = 0x80, high = 0xBF;
        int more;
        if (lead >= 0xC2 && lead <= 0xDF) {
            more = 1;
        } else if (lead >= 0xE0 && lead <= 0xEF) {
            more = 2;
            low = lead == 0xE0 ? 0xA0 : low;
            high = lead == 0xED ? 0x9F : high;
        } else if (lead >= 0xF0 && lead <= 0xF4) {
            more = 3;
            low = lead == 0xF0 ? 0x90 : low;
            high = lead == 0xF4 ? 0x8F : high;
        } else {
            return false;  // a continuation byte on its own, or a byte UTF-8 never uses
        }
        if (*p < low || *p > high) {
            return false;  // also stops at the terminator, so p never runs past it
        }
        p++;
        while (--more > 0) {
            if ((*p & 0xC0) != 0x80) {
                return false;
            }
            p++;
        }
    }
    return true;
}
