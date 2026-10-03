#include "http_api.h"

#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_http_server.h"
#include "esp_log.h"

#include "capsule.h"
#include "motion.h"
#include "ui.h"
#include "validate.h"

static const char *TAG = "http";

#define MAX_BODY_BYTES 1024
#define MAX_JSON_DEPTH 8  // cJSON recurses once per level, on this task's stack

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

static const struct {
    const char *name;
    capsule_action_t action;
} ACTIONS[] = {
    { "start", CAPSULE_ACT_START },         { "pause", CAPSULE_ACT_PAUSE },
    { "toggle", CAPSULE_ACT_TOGGLE },       { "reset", CAPSULE_ACT_RESET },
    { "increment", CAPSULE_ACT_INCREMENT }, { "motion_on", CAPSULE_ACT_MOTION_ON },
    { "motion_off", CAPSULE_ACT_MOTION_OFF },
};

// ---- responses ----

static esp_err_t send_json(httpd_req_t *req, const char *status, cJSON *root)
{
    char *text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (!text) {
        return httpd_resp_send_500(req);
    }
    httpd_resp_set_status(req, status);
    httpd_resp_set_type(req, "application/json");
    esp_err_t err = httpd_resp_sendstr(req, text);
    cJSON_free(text);
    return err;
}

static esp_err_t send_error(httpd_req_t *req, const char *status, const char *message)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "error", message);
    return send_json(req, status, root);
}

static esp_err_t send_state(httpd_req_t *req)
{
    capsule_state_t state;
    capsule_get(&state);
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "type", capsule_type_name(state.type));
    cJSON_AddStringToObject(root, "label", state.label);
    cJSON_AddNumberToObject(root, "count", state.count);
    cJSON_AddNumberToObject(root, "seconds", state.seconds);
    cJSON_AddNumberToObject(root, "remaining_seconds", state.remaining_seconds);
    cJSON_AddBoolToObject(root, "running", state.running);
    cJSON_AddBoolToObject(root, "done", state.done);
    cJSON_AddBoolToObject(root, "motion", state.motion);
    return send_json(req, "200 OK", root);
}

// ---- request parsing ----

// Reads the body into *json. When *json comes back NULL the request has been answered with
// an error and the handler returns this function's result: ESP_FAIL where part of the body
// was never read, so that the server closes the socket instead of waiting for the rest.
static esp_err_t read_json_body(httpd_req_t *req, cJSON **json)
{
    *json = NULL;
    if (req->content_len > MAX_BODY_BYTES) {
        send_error(req, "413 Content Too Large", "body too large");
        return ESP_FAIL;
    }
    char body[MAX_BODY_BYTES + 1];
    size_t received = 0;
    while (received < req->content_len) {
        int n = httpd_req_recv(req, body + received, req->content_len - received);
        if (n <= 0) {
            send_error(req, "408 Request Timeout", "body not received");
            return ESP_FAIL;
        }
        received += n;
    }
    body[received] = '\0';
    switch (json_scan(body, received, MAX_JSON_DEPTH)) {
    case JSON_SCAN_TOO_DEEP:
        return send_error(req, "400 Bad Request", ERR_TOO_DEEP);
    case JSON_SCAN_HAS_NUL:
        return send_error(req, "400 Bad Request", ERR_HAS_NUL);
    case JSON_SCAN_OK:
        break;
    }
    // Strict: nothing but whitespace may follow the JSON value.
    cJSON *parsed = cJSON_ParseWithLengthOpts(body, received + 1, NULL, true);
    if (!cJSON_IsObject(parsed)) {
        cJSON_Delete(parsed);
        return send_error(req, "400 Bad Request", ERR_BAD_JSON);
    }
    *json = parsed;
    return ESP_OK;
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

static const char *apply_timer(const cJSON *json, const char *label)
{
    int seconds = 0;  // stays 0 when the field is missing, which is rejected too
    bool running = true;
    if (!read_int(json, "seconds", 1, CAPSULE_MAX_SECONDS, &seconds) || seconds == 0) {
        return ERR_BAD_SECONDS;
    }
    if (!read_bool(json, "running", &running)) {
        return ERR_BAD_RUNNING;
    }
    capsule_set_timer(label, seconds, running);
    return NULL;
}

static const char *apply_counter(const cJSON *json, const char *label)
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
    capsule_set_counter(label, count, motion && motion_available());
    return NULL;
}

// Returns NULL on success or the reason the capsule was rejected.
static const char *apply_capsule(const cJSON *json)
{
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
        return apply_timer(json, text);
    }
    if (strcmp(type->valuestring, "counter") == 0) {
        return apply_counter(json, text);
    }
    return ERR_BAD_TYPE;
}

static bool find_action(const cJSON *json, capsule_action_t *action)
{
    const cJSON *name = cJSON_GetObjectItemCaseSensitive(json, "action");
    for (size_t i = 0; cJSON_IsString(name) && i < sizeof(ACTIONS) / sizeof(ACTIONS[0]); i++) {
        if (strcmp(name->valuestring, ACTIONS[i].name) == 0) {
            *action = ACTIONS[i].action;
            return true;
        }
    }
    return false;
}

// ---- handlers ----

static esp_err_t get_state(httpd_req_t *req)
{
    return send_state(req);
}

static esp_err_t post_capsule(httpd_req_t *req)
{
    cJSON *json;
    esp_err_t err = read_json_body(req, &json);
    if (!json) {
        return err;
    }
    const char *error = apply_capsule(json);
    cJSON_Delete(json);
    if (error) {
        return send_error(req, "400 Bad Request", error);
    }
    ESP_LOGI(TAG, "new capsule");
    return send_state(req);
}

static esp_err_t post_action(httpd_req_t *req)
{
    cJSON *json;
    esp_err_t err = read_json_body(req, &json);
    if (!json) {
        return err;
    }
    capsule_action_t action;
    bool known = find_action(json, &action);
    cJSON_Delete(json);
    if (!known) {
        return send_error(req, "400 Bad Request", ERR_BAD_ACTION);
    }
    if (action == CAPSULE_ACT_MOTION_ON && !motion_available()) {
        // Still 409 where motion_on does not apply at all: the missing sensor is not the reason.
        capsule_state_t state;
        capsule_get(&state);
        if (state.type == CAPSULE_COUNTER) {
            return send_error(req, "503 Service Unavailable", ERR_NO_MOTION);
        }
        return send_error(req, "409 Conflict", ERR_WRONG_CAPSULE);
    }
    if (!capsule_apply(action)) {
        return send_error(req, "409 Conflict", ERR_WRONG_CAPSULE);
    }
    return send_state(req);
}

static void put_le32(uint8_t *dst, uint32_t value)
{
    dst[0] = value;
    dst[1] = value >> 8;
    dst[2] = value >> 16;
    dst[3] = value >> 24;
}

// Debug aid: what LVGL currently draws, as a 24-bit BMP.
static esp_err_t get_screenshot(httpd_req_t *req)
{
    int width, height;
    uint16_t *pixels = ui_snapshot(&width, &height);
    if (!pixels) {
        return send_error(req, "503 Service Unavailable", "display not available");
    }
    const uint32_t row_bytes = width * 3;  // 368 * 3 is already a multiple of 4, so no padding
    uint8_t header[54] = { 'B', 'M', [10] = 54, [14] = 40, [26] = 1, [28] = 24 };
    put_le32(header + 2, sizeof(header) + row_bytes * height);
    put_le32(header + 18, width);
    put_le32(header + 22, height);
    uint8_t *row = malloc(row_bytes);
    if (!row) {  // found out before the header goes out, while an error can still be sent
        free(pixels);
        return send_error(req, "500 Internal Server Error", "out of memory");
    }
    httpd_resp_set_type(req, "image/bmp");
    esp_err_t err = httpd_resp_send_chunk(req, (const char *)header, sizeof(header));
    for (int y = height - 1; err == ESP_OK && y >= 0; y--) {  // BMP rows go bottom-up
        for (int x = 0; x < width; x++) {
            uint16_t pixel = pixels[y * width + x];  // RGB565 -> 8-bit B, G, R
            uint8_t r = pixel >> 11, g = (pixel >> 5) & 0x3F, b = pixel & 0x1F;
            row[x * 3 + 0] = (b << 3) | (b >> 2);
            row[x * 3 + 1] = (g << 2) | (g >> 4);
            row[x * 3 + 2] = (r << 3) | (r >> 2);
        }
        err = httpd_resp_send_chunk(req, (const char *)row, row_bytes);
    }
    free(row);
    free(pixels);
    return err == ESP_OK ? httpd_resp_send_chunk(req, NULL, 0) : err;
}

static esp_err_t on_not_found(httpd_req_t *req, httpd_err_code_t error)
{
    return send_error(req, "404 Not Found", "not found");
}

static esp_err_t on_wrong_method(httpd_req_t *req, httpd_err_code_t error)
{
    return send_error(req, "405 Method Not Allowed", "method not allowed");
}

void http_api_start(void)
{
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = HTTP_API_PORT;
    config.stack_size = 8192;        // the screenshot renders LVGL on this task
    config.lru_purge_enable = true;  // never run out of sockets because of idle keep-alives
    config.recv_wait_timeout = 2;    // seconds; a body that stalls holds up everyone else

    httpd_handle_t server = NULL;
    ESP_ERROR_CHECK(httpd_start(&server, &config));

    static const httpd_uri_t routes[] = {
        { .uri = "/state", .method = HTTP_GET, .handler = get_state },
        { .uri = "/capsule", .method = HTTP_POST, .handler = post_capsule },
        { .uri = "/action", .method = HTTP_POST, .handler = post_action },
        { .uri = "/screenshot", .method = HTTP_GET, .handler = get_screenshot },
    };
    for (size_t i = 0; i < sizeof(routes) / sizeof(routes[0]); i++) {
        ESP_ERROR_CHECK(httpd_register_uri_handler(server, &routes[i]));
    }
    httpd_register_err_handler(server, HTTPD_404_NOT_FOUND, on_not_found);
    httpd_register_err_handler(server, HTTPD_405_METHOD_NOT_ALLOWED, on_wrong_method);
    ESP_LOGI(TAG, "listening on port %d", HTTP_API_PORT);
}
