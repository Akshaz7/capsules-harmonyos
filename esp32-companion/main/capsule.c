#include "capsule.h"

#include <stdint.h>
#include <string.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static SemaphoreHandle_t s_lock;
static StaticSemaphore_t s_lock_storage;
static capsule_state_t s_state;   // remaining_seconds is filled in by capsule_get()
static int64_t s_remaining_ms;    // timer: time left while paused
static int64_t s_deadline_ms;     // timer: uptime at which it ends while running

static int64_t now_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static void lock(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
}

static void unlock(void)
{
    xSemaphoreGive(s_lock);
}

static void copy_label(char *dst, const char *src)
{
    size_t len = strlen(src);
    if (len > CAPSULE_LABEL_MAX_BYTES - 1) {
        len = CAPSULE_LABEL_MAX_BYTES - 1;
        // Do not cut a UTF-8 sequence in half.
        while (len > 0 && ((unsigned char)src[len] & 0xC0) == 0x80) {
            len--;
        }
    }
    memcpy(dst, src, len);
    dst[len] = '\0';
}

static void timer_reset(void)
{
    s_remaining_ms = (int64_t)s_state.seconds * 1000;
    s_state.running = false;
    s_state.done = false;
}

// The timer functions take the time from their caller, which reads the clock once per
// operation: expiry and the time left are then worked out from the same instant.
static void timer_start(int64_t now)
{
    if (s_state.done) {
        timer_reset();
    }
    if (!s_state.running) {
        s_deadline_ms = now + s_remaining_ms;
        s_state.running = true;
    }
}

static void timer_pause(int64_t now)
{
    if (s_state.running) {
        s_remaining_ms = s_deadline_ms - now;  // at least 1: timer_sync() saw it still running
        s_state.running = false;
    }
}

// Nothing ticks in the background: expiry is noticed whenever the state is read or changed.
static void timer_sync(int64_t now)
{
    if (s_state.type == CAPSULE_TIMER && s_state.running && now >= s_deadline_ms) {
        s_remaining_ms = 0;
        s_state.running = false;
        s_state.done = true;
    }
}

static bool timer_apply(capsule_action_t action, int64_t now)
{
    switch (action) {
    case CAPSULE_ACT_START:
        timer_start(now);
        return true;
    case CAPSULE_ACT_PAUSE:
        timer_pause(now);
        return true;
    case CAPSULE_ACT_TOGGLE:
        if (s_state.done) {
            timer_reset();
        } else if (s_state.running) {
            timer_pause(now);
        } else {
            timer_start(now);
        }
        return true;
    case CAPSULE_ACT_RESET:
        timer_reset();
        return true;
    default:
        return false;
    }
}

static bool counter_apply(capsule_action_t action)
{
    switch (action) {
    case CAPSULE_ACT_INCREMENT:
        if (s_state.count < CAPSULE_MAX_COUNT) {
            s_state.count++;
        }
        return true;
    case CAPSULE_ACT_RESET:
        s_state.count = 0;
        return true;
    case CAPSULE_ACT_MOTION_ON:
        s_state.motion = true;
        return true;
    case CAPSULE_ACT_MOTION_OFF:
        s_state.motion = false;
        return true;
    default:
        return false;
    }
}

void capsule_init(void)
{
    s_lock = xSemaphoreCreateMutexStatic(&s_lock_storage);
}

const char *capsule_type_name(capsule_type_t type)
{
    switch (type) {
    case CAPSULE_TIMER:
        return "timer";
    case CAPSULE_COUNTER:
        return "counter";
    default:
        return "idle";
    }
}

void capsule_get(capsule_state_t *out)
{
    lock();
    int64_t now = now_ms();
    timer_sync(now);
    *out = s_state;
    if (s_state.type == CAPSULE_TIMER) {
        int64_t ms = s_state.running ? s_deadline_ms - now : s_remaining_ms;
        out->remaining_seconds = (int)((ms + 999) / 1000);
    }
    unlock();
}

void capsule_set_timer(const char *label, int seconds, bool running)
{
    lock();
    memset(&s_state, 0, sizeof(s_state));
    s_state.type = CAPSULE_TIMER;
    copy_label(s_state.label, label);
    s_state.seconds = seconds;
    timer_reset();
    if (running) {
        timer_start(now_ms());
    }
    unlock();
}

void capsule_set_counter(const char *label, int count, bool motion)
{
    lock();
    memset(&s_state, 0, sizeof(s_state));
    s_state.type = CAPSULE_COUNTER;
    copy_label(s_state.label, label);
    s_state.count = count;
    s_state.motion = motion;
    unlock();
}

bool capsule_apply(capsule_action_t action)
{
    bool applied = false;
    lock();
    int64_t now = now_ms();
    timer_sync(now);
    if (s_state.type == CAPSULE_TIMER) {
        applied = timer_apply(action, now);
    } else if (s_state.type == CAPSULE_COUNTER) {
        applied = counter_apply(action);
    }
    unlock();
    return applied;
}

void capsule_count_rep(void)
{
    lock();
    if (s_state.type == CAPSULE_COUNTER && s_state.motion) {
        counter_apply(CAPSULE_ACT_INCREMENT);
    }
    unlock();
}
