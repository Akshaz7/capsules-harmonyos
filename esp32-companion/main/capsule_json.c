#include "capsule_json.h"

#include <string.h>

#include "motion.h"
#include "validate.h"

static const struct {
    const char *name;
    capsule_action_t action;
} ACTIONS[] = {
    { "start", CAPSULE_ACT_START },         { "pause", CAPSULE_ACT_PAUSE },
    { "toggle", CAPSULE_ACT_TOGGLE },       { "reset", CAPSULE_ACT_RESET },
    { "increment", CAPSULE_ACT_INCREMENT }, { "motion_on", CAPSULE_ACT_MOTION_ON },
    { "motion_off", CAPSULE_ACT_MOTION_OFF },
};

cJSON *capsule_json_parse(const char *text, size_t len, const char **error)
{
    switch (json_scan(text, len, CAPSULE_JSON_MAX_DEPTH)) {
    case JSON_SCAN_TOO_DEEP:
        *error = ERR_TOO_DEEP;
        return NULL;
    case JSON_SCAN_HAS_NUL:
        *error = ERR_HAS_NUL;
        return NULL;
    case JSON_SCAN_OK:
        break;
    }
    // Strict: nothing but whitespace may follow the JSON value.
    cJSON *parsed = cJSON_ParseWithLengthOpts(text, len + 1, NULL, true);
    if (!cJSON_IsObject(parsed)) {
        cJSON_Delete(parsed);
        *error = ERR_BAD_JSON;
        return NULL;
    }
    return parsed;
}

// Optional integer field. False if it is present but not a number in [min, max].
static bool read_int(const cJSON *json, const char *key, int min, int max, int *value)
{
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key);
    if (!item) {
        return true;
    }
    if (!cJSON_IsNumber(item) || item->valuedouble < min || item->valuedouble > max) {
        return false;
    }
    *value = (int)item->valuedouble;
    return true;
}

// Optional boolean field. False if it is present but not true/false.
static bool read_bool(const cJSON *json, const char *key, bool *value)
{
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key);
    if (!item) {
        return true;
    }
    if (!cJSON_IsBool(item)) {
        return false;
    }
    *value = cJSON_IsTrue(item);
    return true;
}

static const char *apply_timer(const cJSON *json, const char *label, uint32_t *generation)
{
    int seconds = 0;  // stays 0 when the field is missing, which is rejected too
    bool running = true;
    if (!read_int(json, "seconds", 1, CAPSULE_MAX_SECONDS, &seconds) || seconds == 0) {
        return ERR_BAD_SECONDS;
    }
    if (!read_bool(json, "running", &running)) {
        return ERR_BAD_RUNNING;
    }
    *generation = capsule_set_timer(label, seconds, running);
    return NULL;
}

static const char *apply_counter(const cJSON *json, const char *label, uint32_t *generation)
{
    int count = 0;
    bool motion = false;
    if (!read_int(json, "count", 0, CAPSULE_MAX_COUNT, &count)) {
        return ERR_BAD_COUNT;
    }
    if (!read_bool(json, "motion", &motion)) {
        return ERR_BAD_MOTION;
    }
    // Without a working sensor the counter still works by hand; /state shows motion:false.
    *generation = capsule_set_counter(label, count, motion && motion_available());
    return NULL;
}

const char *capsule_json_apply(const cJSON *json, uint32_t *generation)
{
    uint32_t unused;
    generation = generation ? generation : &unused;
    const cJSON *type = cJSON_GetObjectItemCaseSensitive(json, "type");
    const cJSON *label = cJSON_GetObjectItemCaseSensitive(json, "label");
    if (!cJSON_IsString(type)) {
        return ERR_BAD_TYPE;
    }
    if (label && !cJSON_IsString(label)) {
        return ERR_BAD_LABEL;
    }
    const char *text = label ? label->valuestring : "";
    if (!utf8_valid(text)) {
        return ERR_BAD_LABEL;  // raw bytes in the body that are not UTF-8: the screen cannot show them
    }
    if (strcmp(type->valuestring, "timer") == 0) {
        return apply_timer(json, text, generation);
    }
    if (strcmp(type->valuestring, "counter") == 0) {
        return apply_counter(json, text, generation);
    }
    return ERR_BAD_TYPE;
}

bool capsule_json_action(const cJSON *name, capsule_action_t *action)
{
    for (size_t i = 0; cJSON_IsString(name) && i < sizeof(ACTIONS) / sizeof(ACTIONS[0]); i++) {
        if (strcmp(name->valuestring, ACTIONS[i].name) == 0) {
            *action = ACTIONS[i].action;
            return true;
        }
    }
    return false;
}

capsule_run_t capsule_json_run(capsule_action_t action)
{
    if (action == CAPSULE_ACT_MOTION_ON && !motion_available()) {
        // Still "wrong capsule" where motion_on does not apply at all: the missing sensor is
        // not the reason then.
        capsule_state_t state;
        capsule_get(&state);
        return state.type == CAPSULE_COUNTER ? CAPSULE_RUN_NO_SENSOR : CAPSULE_RUN_WRONG_CAPSULE;
    }
    return capsule_apply(action) ? CAPSULE_RUN_OK : CAPSULE_RUN_WRONG_CAPSULE;
}

cJSON *capsule_json_state(const capsule_state_t *state)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "type", capsule_type_name(state->type));
    cJSON_AddStringToObject(root, "label", state->label);
    cJSON_AddNumberToObject(root, "count", state->count);
    cJSON_AddNumberToObject(root, "seconds", state->seconds);
    cJSON_AddNumberToObject(root, "remaining_seconds", state->remaining_seconds);
    cJSON_AddBoolToObject(root, "running", state->running);
    cJSON_AddBoolToObject(root, "done", state->done);
    cJSON_AddBoolToObject(root, "motion", state->motion);
    return root;
}
