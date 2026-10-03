// The one capsule the wrist shows. Thread-safe: HTTP handlers, the LVGL task and the
// motion task all go through these functions.
#pragma once

#include <stdbool.h>

#define CAPSULE_LABEL_MAX_BYTES 48   // including the terminator; longer labels are cut
#define CAPSULE_MAX_SECONDS 359999   // 99:59:59
#define CAPSULE_MAX_COUNT 999999

typedef enum {
    CAPSULE_IDLE,
    CAPSULE_TIMER,
    CAPSULE_COUNTER,
} capsule_type_t;

typedef enum {
    CAPSULE_ACT_START,
    CAPSULE_ACT_PAUSE,
    CAPSULE_ACT_TOGGLE,
    CAPSULE_ACT_RESET,
    CAPSULE_ACT_INCREMENT,
    CAPSULE_ACT_MOTION_ON,
    CAPSULE_ACT_MOTION_OFF,
} capsule_action_t;

typedef struct {
    capsule_type_t type;
    char label[CAPSULE_LABEL_MAX_BYTES];
    int count;              // counter value
    int seconds;            // timer length
    int remaining_seconds;  // timer, rounded up
    bool running;           // timer is counting down
    bool done;              // timer reached zero
    bool motion;            // counter is fed by the motion sensor
} capsule_state_t;

void capsule_init(void);
void capsule_get(capsule_state_t *out);
const char *capsule_type_name(capsule_type_t type);

void capsule_set_timer(const char *label, int seconds, bool running);
void capsule_set_counter(const char *label, int count, bool motion);

// Returns false when the action does not fit the current capsule (e.g. "pause" on a counter).
bool capsule_apply(capsule_action_t action);

// Called by the motion task for every detected rep; ignored unless motion counting is on.
void capsule_count_rep(void);
