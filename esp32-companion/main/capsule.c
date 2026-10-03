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

static void timer_start(void)
{
    if (s_state.done) {
        timer_reset();
    }
    if (!s_state.running) {
        s_deadline_ms = now_ms() + s_remaining_ms;
        s_state.running = true;
    }
}

static void timer_pause(void)
{
    if (s_state.running) {
        s_remaining_ms = s_deadline_ms - now_ms();
        if (s_remaining_ms < 1) {
            s_remaining_ms = 1;  // paused on the last tick: not done yet
        }
        s_state.running = false;
    }
}

// Nothing ticks in the background: expiry is noticed whenever the state is read or changed.
static void timer_sync(void)
{
    if (s_state.type == CAPSULE_TIMER && s_state.running && now_ms() >= s_deadline_ms) {
        s_remaining_ms = 0;
        s_state.running = false;
        s_state.done = true;
    }
}

static bool timer_apply(capsule_action_t action)
{
    switch (action) {
    case CAPSULE_ACT_START:
        timer_start();
        return true;
    case CAPSULE_ACT_PAUSE:
        timer_pause();
        return true;
    case CAPSULE_ACT_TOGGLE:
        if (s_state.done) {
            timer_reset();
        } else if (s_state.running) {
            timer_pause();
        } else {
            timer_start();
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
    timer_sync();
    *out = s_state;
    if (s_state.type == CAPSULE_TIMER) {
        int64_t ms = s_state.running ? s_deadline_ms - now_ms() : s_remaining_ms;
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
        timer_start();
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
    timer_sync();
    if (s_state.type == CAPSULE_TIMER) {
        applied = timer_apply(action);
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
