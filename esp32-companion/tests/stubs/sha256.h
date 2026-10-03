// Host stand-in for mbedTLS's SHA-256, for the tests of relay_hw_id(). Not used by the firmware.
#pragma once

#include <stddef.h>
#include <stdint.h>

void test_sha256(const uint8_t *data, size_t len, uint8_t digest[32]);
