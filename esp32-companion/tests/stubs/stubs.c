#include "stubs.h"

#include "esp_timer.h"

int stub_lock_depth;
int stub_clock_reads;
static int64_t s_now_us;

void stub_set_ms(int64_t uptime_ms)
{
    s_now_us = uptime_ms * 1000;
}

void stub_advance_ms(int64_t ms)
{
    s_now_us += ms * 1000;
}

int64_t esp_timer_get_time(void)
{
    stub_clock_reads++;
    return s_now_us;
}
