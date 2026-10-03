#include "http_api.h"

#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_http_server.h"
#include "esp_log.h"

#include "capsule.h"
#include "capsule_json.h"
#include "ui.h"

static const char *TAG = "http";

#define MAX_BODY_BYTES 1024
#define MAX_DISCARD_BYTES 8192  // of a body that is too large, before giving up on the connection

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
    return send_json(req, "200 OK", capsule_json_state(&state));
}

// ---- request parsing ----

// Throws away the body of a request that has already been answered. ESP_OK if all of it was
// read. ESP_FAIL makes the server close the socket: the body is far too long, or it stopped
// coming. A little is read rather than none because closing a socket with unread data
// resets the connection, and the client then never sees the answer it was just sent.
static esp_err_t discard_body(httpd_req_t *req, char *scratch, size_t scratch_size)
{
    size_t left = req->content_len;
    size_t budget = MAX_DISCARD_BYTES;
    while (left > 0 && budget > 0) {
        size_t want = left < scratch_size ? left : scratch_size;
        int n = httpd_req_recv(req, scratch, want < budget ? want : budget);
        if (n <= 0) {
            return ESP_FAIL;
        }
        left -= n;
        budget -= n;
    }
    return left == 0 ? ESP_OK : ESP_FAIL;
}

// Reads the body into *json. When *json comes back NULL the request has been answered with
// an error and the handler returns this function's result: ESP_FAIL where part of the body
// was never read, so that the server closes the socket instead of waiting for the rest.
static esp_err_t read_json_body(httpd_req_t *req, cJSON **json)
{
    *json = NULL;
    char body[MAX_BODY_BYTES + 1];
    if (req->content_len > MAX_BODY_BYTES) {
        send_error(req, "413 Content Too Large", "body too large");
        return discard_body(req, body, sizeof(body));
    }
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
    const char *error = NULL;
    *json = capsule_json_parse(body, received, &error);
    if (!*json) {
        return send_error(req, "400 Bad Request", error);
    }
    return ESP_OK;
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
    const char *error = capsule_json_apply(json);
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
    bool known = capsule_json_action(cJSON_GetObjectItemCaseSensitive(json, "action"), &action);
    cJSON_Delete(json);
    if (!known) {
        return send_error(req, "400 Bad Request", ERR_BAD_ACTION);
    }
    switch (capsule_json_run(action)) {
    case CAPSULE_RUN_NO_SENSOR:
        return send_error(req, "503 Service Unavailable", ERR_NO_MOTION);
    case CAPSULE_RUN_WRONG_CAPSULE:
        return send_error(req, "409 Conflict", ERR_WRONG_CAPSULE);
    case CAPSULE_RUN_OK:
        break;
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
