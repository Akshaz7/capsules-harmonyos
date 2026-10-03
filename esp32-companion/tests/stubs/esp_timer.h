// Host stand-in: the clock is whatever the test set with stub_set_ms() (see stubs.h).
#pragma once

#include <stdint.h>

int64_t esp_timer_get_time(void);  // microseconds since boot
