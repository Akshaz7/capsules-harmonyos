// JSON in and out of the capsule: the rules for a capsule object, an action name and the
// state object. The local HTTP API (http_api.c) and the cloud relay client (relay_sync.c)
// both go through these functions, so a capsule is judged the same way whoever sent it.
#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "cJSON.h"

#include "capsule.h"

#define CAPSULE_JSON_MAX_DEPTH 8  // cJSON recurses once per level, on the caller's stack

#define ERR_BAD_JSON "body must be a JSON object"
#define ERR_BAD_TYPE "type must be \"timer\" or \"counter\""
#define ERR_TOO_DEEP "JSON nested too deeply"
#define ERR_HAS_NUL "body must not contain a NUL character"
#define ERR_BAD_LABEL "label must be a UTF-8 string"
#define ERR_BAD_SECONDS "seconds must be a number from 1 to 359999"
#define ERR_BAD_COUNT "count must be a number from 0 to 999999"
#define ERR_BAD_RUNNING "running must be true or false"
#define ERR_BAD_MOTION "motion must be true or false"
#define ERR_BAD_ACTION "action must be one of start, pause, toggle, reset, increment, motion_on, motion_off"
#define ERR_WRONG_CAPSULE "action does not apply to the current capsule"
#define ERR_NO_MOTION "motion sensor not available"

// Parses untrusted text that must be one JSON object. `text[len]` must be a NUL (the caller
// keeps one spare byte). The nesting is checked before cJSON sees the text. Returns the
// object (free it with cJSON_Delete) or NULL with *error set to one of the ERR_ texts.
cJSON *capsule_json_parse(const char *text, size_t len, const char **error);

// Makes `json` the current capsule. Returns NULL, or the reason it was refused; a refused
// capsule leaves the current one untouched.
const char *capsule_json_apply(const cJSON *json);

// The action a JSON string names. False if `name` is not a string or not an action.
bool capsule_json_action(const cJSON *name, capsule_action_t *action);

typedef enum {
    CAPSULE_RUN_OK,
    CAPSULE_RUN_WRONG_CAPSULE,  // e.g. "pause" on a counter, or anything while idle
    CAPSULE_RUN_NO_SENSOR,      // motion_on for a counter on a board without a working sensor
} capsule_run_t;

capsule_run_t capsule_json_run(capsule_action_t action);

// The object GET /state answers with. NULL if memory ran out.
cJSON *capsule_json_state(const capsule_state_t *state);
