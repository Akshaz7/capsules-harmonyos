// What the tests control and observe in the stand-ins for ESP-IDF.
#pragma once

#include <stdint.h>

extern int stub_lock_depth;   // 1 while the capsule lock is held; must be 0 between calls
extern int stub_clock_reads;  // how often the firmware asked for the time

void stub_set_ms(int64_t uptime_ms);
void stub_advance_ms(int64_t ms);
