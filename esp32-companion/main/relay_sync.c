#include "relay_sync.h"

#include <string.h>

#include "capsule_json.h"

#define MAX_SAFE_INTEGER 9007199254740992.0  // 2^53: every whole number up to here is exact in a double

#define ID_EXTRA "_-"
#define TOKEN_EXTRA "._~+/=-"

bool relay_text_ok(const char *text, size_t max, const char *extra)
{
    size_t len = strlen(text);
    if (len == 0 || len > max) {
        return false;
    }
    for (size_t i = 0; i < len; i++) {
        char c = text[i];
        bool alnum = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
        if (!alnum && !strchr(extra, c)) {  // c is never NUL here, which strchr would "find"
            return false;
        }
    }
    return true;
}

bool relay_code_ok(const char *text)
{
    size_t len = strlen(text);
    if (len == 0 || len > RELAY_CODE_MAX) {
        return false;
    }
    for (size_t i = 0; i < len; i++) {
        if (text[i] < 0x20 || text[i] > 0x7E) {
            return false;
        }
    }
    return true;
}

static const char *string_field(const cJSON *json, const char *key)
{
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key);
    return cJSON_IsString(item) ? item->valuestring : NULL;
}

// A whole number from 0 to 2^53. Versions are only compared for equality, so a relay may
// count from 1 or use a timestamp.
static bool read_counter(const cJSON *json, const char *key, int64_t *value)
{
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(json, key);
    if (!cJSON_IsNumber(item) || !(item->valuedouble >= 0 && item->valuedouble <= MAX_SAFE_INTEGER)) {
        return false;
    }
    int64_t whole = (int64_t)item->valuedouble;
    if ((double)whole != item->valuedouble) {
        return false;
    }
    *value = whole;
    return true;
}

static bool absent_or_null(const cJSON *item)
{
    return !item || cJSON_IsNull(item);
}

char *relay_register_body(const char *hw, const char *fw)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "hw", hw);
    cJSON_AddStringToObject(root, "kind", "wrist");
    cJSON_AddStringToObject(root, "fw", fw);
    char *text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return text;
}

bool relay_parse_register(const char *body, size_t len, relay_credentials_t *out)
{
    const char *error = NULL;
    cJSON *json = capsule_json_parse(body, len, &error);
    if (!json) {
        return false;
    }
    const char *id = string_field(json, "id");
    const char *token = string_field(json, "token");
    const char *code = string_field(json, "code");
    bool ok = id && token && code && relay_text_ok(id, RELAY_ID_MAX, ID_EXTRA) &&
              relay_text_ok(token, RELAY_TOKEN_MAX, TOKEN_EXTRA) && relay_code_ok(code);
    if (ok) {
        memset(out, 0, sizeof(*out));
        strcpy(out->id, id);  // the lengths were checked just above
        strcpy(out->token, token);
        strcpy(out->code, code);
    }
    cJSON_Delete(json);
    return ok;
}

void relay_sync_reset(relay_sync_t *sync)
{
    memset(sync, 0, sizeof(*sync));
    sync->version = -1;
}

static void take_capsule(relay_sync_t *sync, const cJSON *capsule, int64_t version, relay_poll_t *result)
{
    sync->version = version;
    if (absent_or_null(capsule)) {
        return;  // the relay has nothing to show; what is on screen stays
    }
    result->capsule_error = capsule_json_apply(capsule);
    if (!result->capsule_error) {
        result->capsule_applied = true;
        sync->shown = version;
        sync->generation = capsule_generation();
    }
}

static void take_action(relay_sync_t *sync, const cJSON *name, int64_t action_seq, relay_poll_t *result)
{
    bool first_poll = !sync->synced;
    sync->action_seq = action_seq;
    if (first_poll || absent_or_null(name)) {
        return;
    }
    capsule_action_t action;
    if (capsule_json_action(name, &action) && capsule_json_run(action) == CAPSULE_RUN_OK) {
        result->action_applied = true;
    } else {
        result->action_skipped = true;
    }
}

relay_poll_t relay_handle_poll(relay_sync_t *sync, const char *body, size_t len)
{
    relay_poll_t result = { 0 };
    const char *error = NULL;
    cJSON *json = capsule_json_parse(body, len, &error);
    if (!json) {
        return result;
    }
    const cJSON *claimed = cJSON_GetObjectItemCaseSensitive(json, "claimed");
    const cJSON *capsule = cJSON_GetObjectItemCaseSensitive(json, "capsule");
    const cJSON *action = cJSON_GetObjectItemCaseSensitive(json, "action");
    const cJSON *code = cJSON_GetObjectItemCaseSensitive(json, "code");
    int64_t version = 0;
    int64_t action_seq = 0;
    bool usable = cJSON_IsBool(claimed) && read_counter(json, "version", &version) &&
                  read_counter(json, "action_seq", &action_seq) &&
                  (absent_or_null(capsule) || cJSON_IsObject(capsule)) &&
                  (absent_or_null(action) || cJSON_IsString(action));
    if (usable) {
        result.ok = true;
        result.claimed = cJSON_IsTrue(claimed);
        // Optional: a relay that renews an expired pairing code hands out the new one here.
        // One that cannot be shown is ignored; the code from the registration stays.
        if (cJSON_IsString(code) && relay_code_ok(code->valuestring)) {
            strcpy(result.code, code->valuestring);
        }
        if (version != sync->version) {
            take_capsule(sync, capsule, version, &result);
        }
        if (!sync->synced || action_seq != sync->action_seq) {
            take_action(sync, action, action_seq, &result);
        }
        sync->synced = true;
    }
    cJSON_Delete(json);
    return result;
}

int64_t relay_shown_version(const relay_sync_t *sync)
{
    return sync->generation == capsule_generation() ? sync->shown : 0;
}

char *relay_report_body(const relay_report_t *report)
{
    cJSON *root = capsule_json_state(&report->state);
    cJSON_AddNumberToObject(root, "version", (double)report->version);
    char *text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return text;
}

static bool report_differs(const relay_report_t *a, const relay_report_t *b)
{
    const capsule_state_t *x = &a->state, *y = &b->state;
    if (a->version != b->version || x->type != y->type || strcmp(x->label, y->label) != 0 ||
        x->count != y->count || x->seconds != y->seconds || x->running != y->running || x->done != y->done ||
        x->motion != y->motion) {
        return true;
    }
    // A running timer's time left changes every second: that is what the heartbeat is for.
    // On a stopped timer it only changes when something happened (a reset, say).
    return !x->running && x->remaining_seconds != y->remaining_seconds;
}

bool relay_report_due(const relay_report_t *last, const relay_report_t *now, int64_t since_last_ms)
{
    if (!last || since_last_ms >= RELAY_HEARTBEAT_MS) {
        return true;
    }
    return since_last_ms >= RELAY_MIN_POST_GAP_MS && report_differs(last, now);
}

uint32_t relay_backoff_ms(unsigned failures)
{
    if (failures == 0) {
        return 0;
    }
    uint32_t wait = RELAY_BACKOFF_FIRST_MS;
    for (unsigned i = 1; i < failures && wait < RELAY_BACKOFF_MAX_MS; i++) {
        wait *= 2;
    }
    return wait < RELAY_BACKOFF_MAX_MS ? wait : RELAY_BACKOFF_MAX_MS;
}
