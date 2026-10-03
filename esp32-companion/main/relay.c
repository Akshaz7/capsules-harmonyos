#include "relay.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"
#include "nvs.h"

#include "capsule.h"
#include "net.h"
#include "relay_sync.h"

#if __has_include("secrets.h")
#include "secrets.h"
#endif
#ifndef RELAY_URL
#define RELAY_URL ""
#endif

static const char *TAG = "relay";

#define TASK_STACK_BYTES 10240  // a TLS handshake with certificate checks runs on this stack
#define TASK_PRIORITY 3         // below the UI, the local HTTP server and Wi-Fi handling
#define TICK_MS 250
#define REQUEST_TIMEOUT_MS 4000
#define BASE_URL_MAX 160
#define NVS_NAMESPACE "relay"
#define HW_SALT "harmoniser-wrist:"
#define HW_ID_BYTES 8

typedef enum {
    REQUEST_OK,
    REQUEST_FAILED,        // no answer, an answer that makes no sense, or a server error
    REQUEST_UNAUTHORIZED,  // the relay does not know this device or token (any more)
} outcome_t;

static portMUX_TYPE s_status_lock = portMUX_INITIALIZER_UNLOCKED;
static relay_status_t s_status;

// Everything below is only touched by the relay task.
static char s_base[BASE_URL_MAX + 1];  // RELAY_URL without a trailing slash
static esp_http_client_handle_t s_client;
static bool s_connection_used;  // a request went through on the current connection
static char s_response[RELAY_MAX_RESPONSE + 1];
static size_t s_response_len;
static bool s_response_overflow;
static relay_credentials_t s_credentials;  // id[0] == '\0': not registered
static relay_sync_t s_sync;

// ---- status for the screen ----

static void set_status(relay_state_t state)
{
    relay_status_t next = { .state = state };
    if (state == RELAY_UNCLAIMED) {
        strlcpy(next.code, s_credentials.code, sizeof(next.code));
        strlcpy(next.pair_url, s_credentials.pair_url, sizeof(next.pair_url));
    }
    taskENTER_CRITICAL(&s_status_lock);
    s_status = next;
    taskEXIT_CRITICAL(&s_status_lock);
}

void relay_get_status(relay_status_t *out)
{
    taskENTER_CRITICAL(&s_status_lock);
    *out = s_status;
    taskEXIT_CRITICAL(&s_status_lock);
}

static void set_online(bool claimed)
{
    set_status(claimed ? RELAY_CLAIMED : RELAY_UNCLAIMED);
}

// ---- stored credentials ----

static bool load_string(nvs_handle_t nvs, const char *key, char *out, size_t size)
{
    size_t len = size;
    return nvs_get_str(nvs, key, out, &len) == ESP_OK;
}

static void load_credentials(void)
{
    relay_credentials_t stored = { 0 };
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) != ESP_OK) {
        return;  // never registered
    }
    bool ok = load_string(nvs, "id", stored.id, sizeof(stored.id)) &&
              load_string(nvs, "token", stored.token, sizeof(stored.token)) &&
              load_string(nvs, "code", stored.code, sizeof(stored.code));
    if (ok && !load_string(nvs, "url", stored.pair_url, sizeof(stored.pair_url))) {
        stored.pair_url[0] = '\0';  // optional
    }
    nvs_close(nvs);
    if (ok) {
        s_credentials = stored;
        ESP_LOGI(TAG, "registered as device %s", s_credentials.id);
    }
}

static void save_credentials(void)
{
    nvs_handle_t nvs;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs);
    if (err == ESP_OK) {
        err = nvs_set_str(nvs, "id", s_credentials.id);
        err = err == ESP_OK ? nvs_set_str(nvs, "token", s_credentials.token) : err;
        err = err == ESP_OK ? nvs_set_str(nvs, "code", s_credentials.code) : err;
        err = err == ESP_OK ? nvs_set_str(nvs, "url", s_credentials.pair_url) : err;
        err = err == ESP_OK ? nvs_commit(nvs) : err;
        nvs_close(nvs);
    }
    if (err != ESP_OK) {  // still usable until the next boot, which then registers again
        ESP_LOGW(TAG, "could not store the registration: %s", esp_err_to_name(err));
    }
}

static void forget_credentials(void)
{
    memset(&s_credentials, 0, sizeof(s_credentials));
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) == ESP_OK) {
        nvs_erase_all(nvs);
        nvs_commit(nvs);
        nvs_close(nvs);
    }
}

// ---- HTTP ----

static void log_heap(const char *when)
{
    ESP_LOGI(TAG, "%s: free heap %u bytes internal (largest block %u, lowest ever %u), %u bytes PSRAM", when,
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
}

static esp_err_t on_http_event(esp_http_client_event_t *event)
{
    if (event->event_id == HTTP_EVENT_ON_CONNECTED) {
        log_heap(strncmp(s_base, "https://", 8) == 0 ? "connected (TLS handshake done)" : "connected (plain HTTP)");
    } else if (event->event_id == HTTP_EVENT_ON_DATA) {
        size_t len = (size_t)event->data_len;
        if (len > RELAY_MAX_RESPONSE - s_response_len) {
            s_response_overflow = true;  // the rest is read and dropped
        } else {
            memcpy(s_response + s_response_len, event->data, len);
            s_response_len += len;
        }
    }
    return ESP_OK;
}

static bool open_client(void)
{
    if (s_client) {
        return true;
    }
    bool tls = strncmp(s_base, "https://", 8) == 0;
    esp_http_client_config_t config = {
        .url = s_base,
        .timeout_ms = REQUEST_TIMEOUT_MS,
        .event_handler = on_http_event,
        .crt_bundle_attach = tls ? esp_crt_bundle_attach : NULL,
        .keep_alive_enable = true,
        .disable_auto_redirect = true,  // the token goes to the configured host and nowhere else
        .buffer_size_tx = 1024,         // room for the Authorization header
    };
    s_client = esp_http_client_init(&config);
    s_connection_used = false;
    if (!s_client) {
        ESP_LOGE(TAG, "could not create the HTTP client");
    }
    return s_client != NULL;
}

static void drop_connection(void)
{
    if (s_client) {
        esp_http_client_close(s_client);
    }
    s_connection_used = false;
}

// One request. `body` NULL: no body. Returns the HTTP status with the response body in
// s_response (NUL-terminated), or -1 if there was no usable answer.
static int request(esp_http_client_method_t method, const char *path, bool with_token, const char *body)
{
    static char url[BASE_URL_MAX + RELAY_ID_MAX + 48];
    static char authorization[RELAY_TOKEN_MAX + 8];
    if (!open_client()) {
        return -1;
    }
    snprintf(url, sizeof(url), "%s%s", s_base, path);
    esp_http_client_set_url(s_client, url);
    esp_http_client_set_method(s_client, method);
    if (with_token) {
        snprintf(authorization, sizeof(authorization), "Bearer %s", s_credentials.token);
        esp_http_client_set_header(s_client, "Authorization", authorization);
    } else {
        esp_http_client_delete_header(s_client, "Authorization");
    }
    if (body) {
        esp_http_client_set_header(s_client, "Content-Type", "application/json");
        esp_http_client_set_post_field(s_client, body, (int)strlen(body));
    } else {
        esp_http_client_delete_header(s_client, "Content-Type");
        esp_http_client_set_post_field(s_client, NULL, 0);
    }
    // A kept-alive connection may have been closed by the other side since the last request.
    // That only shows when it is used, so such a failure gets one more go on a new connection.
    for (int attempt = 0; attempt < 2; attempt++) {
        bool reused = s_connection_used;
        s_response_len = 0;
        s_response_overflow = false;
        esp_err_t err = esp_http_client_perform(s_client);
        if (err == ESP_OK) {
            s_connection_used = true;
            s_response[s_response_len] = '\0';
            if (s_response_overflow) {
                ESP_LOGW(TAG, "%s: answer longer than %d bytes", path, RELAY_MAX_RESPONSE);
                return -1;
            }
            return esp_http_client_get_status_code(s_client);
        }
        drop_connection();
        // esp_http_client reports a 401 as an error of its own: it looks for a Basic or
        // Digest challenge to answer and gives up with this code when there is none. For
        // this client a 401 is an answer like any other (the relay forgot the device).
        if (err == ESP_ERR_NOT_SUPPORTED && esp_http_client_get_status_code(s_client) == 401) {
            s_response[0] = '\0';
            return 401;
        }
        if (!reused) {
            ESP_LOGW(TAG, "%s: %s", path, esp_err_to_name(err));
            break;
        }
    }
    return -1;
}

static outcome_t outcome_of(int status, int wanted, const char *what)
{
    if (status == wanted) {
        return REQUEST_OK;
    }
    if (status == 401 || status == 404) {  // 404: a relay that forgot the device and says so that way
        ESP_LOGW(TAG, "%s: HTTP %d, the relay does not know this device or token", what, status);
        return REQUEST_UNAUTHORIZED;
    }
    if (status >= 0) {
        ESP_LOGW(TAG, "%s: HTTP %d", what, status);
    }
    return REQUEST_FAILED;
}

// ---- the three exchanges ----

// A stable id for this board that does not give away its MAC address.
static void hardware_id(char out[HW_ID_BYTES * 2 + 1])
{
    uint8_t input[sizeof(HW_SALT) - 1 + 6];
    uint8_t digest[32];
    memcpy(input, HW_SALT, sizeof(HW_SALT) - 1);
    esp_read_mac(input + sizeof(HW_SALT) - 1, ESP_MAC_WIFI_STA);
    mbedtls_sha256(input, sizeof(input), digest, 0);
    for (int i = 0; i < HW_ID_BYTES; i++) {
        sprintf(out + i * 2, "%02x", digest[i]);
    }
}

static outcome_t do_register(void)
{
    char hw[HW_ID_BYTES * 2 + 1];
    hardware_id(hw);
    char *body = relay_register_body(hw, esp_app_get_description()->version);
    if (!body) {
        return REQUEST_FAILED;
    }
    int status = request(HTTP_METHOD_POST, "/api/devices/register", false, body);
    cJSON_free(body);
    if (status != 201) {
        if (status >= 0) {
            ESP_LOGW(TAG, "register: HTTP %d", status);
        }
        return REQUEST_FAILED;
    }
    if (!relay_parse_register(s_response, s_response_len, &s_credentials)) {
        ESP_LOGW(TAG, "register: the answer is not {id, token, code[, pair_url]}");
        return REQUEST_FAILED;
    }
    save_credentials();
    relay_sync_reset(&s_sync);
    ESP_LOGI(TAG, "registered as device %s, pairing code %s, %s", s_credentials.id, s_credentials.code,
             s_credentials.pair_url[0] ? s_credentials.pair_url : "no pair_url");
    set_online(false);
    return REQUEST_OK;
}

static outcome_t do_poll(void)
{
    char path[RELAY_ID_MAX + 32];
    snprintf(path, sizeof(path), "/api/devices/%s/capsule", s_credentials.id);
    outcome_t outcome = outcome_of(request(HTTP_METHOD_GET, path, true, NULL), 200, "poll");
    if (outcome != REQUEST_OK) {
        return outcome;
    }
    relay_poll_t result = relay_handle_poll(&s_sync, s_response, s_response_len);
    if (!result.ok) {
        ESP_LOGW(TAG, "poll: the answer is not usable");
        return REQUEST_FAILED;
    }
    if (result.capsule_applied) {
        ESP_LOGI(TAG, "capsule version %" PRId64 " applied", s_sync.version);
    } else if (result.capsule_error) {
        ESP_LOGW(TAG, "capsule version %" PRId64 " refused: %s", s_sync.version, result.capsule_error);
    }
    if (result.action_applied || result.action_skipped) {
        ESP_LOGI(TAG, "action %" PRId64 " %s", s_sync.action_seq,
                 result.action_applied ? "applied" : "skipped: unknown, or it does not fit the capsule");
    }
    if (relay_take_pairing(&s_credentials, &result)) {
        save_credentials();
        ESP_LOGI(TAG, "new pairing code %s", s_credentials.code);
    }
    set_online(result.claimed);
    return REQUEST_OK;
}

static outcome_t do_report(const relay_report_t *report)
{
    char path[RELAY_ID_MAX + 32];
    snprintf(path, sizeof(path), "/api/devices/%s/state", s_credentials.id);
    char *body = relay_report_body(report);
    if (!body) {
        return REQUEST_FAILED;
    }
    int status = request(HTTP_METHOD_POST, path, true, body);
    cJSON_free(body);
    return outcome_of(status, 204, "state");
}

// ---- the task ----

static int64_t now_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static void relay_task(void *arg)
{
    unsigned failures = 0;
    int64_t wait_until = 0;      // backoff: nothing is sent before this
    int64_t next_poll = 0;
    int64_t last_report_at = 0;
    relay_report_t last_report;
    bool have_last_report = false;
    bool stack_logged = false;

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(TICK_MS));
        net_status_t net;
        net_get_status(&net);
        if (net.state != NET_CONNECTED) {
            drop_connection();
            relay_status_t status;
            relay_get_status(&status);
            if (status.state != RELAY_STARTING) {
                set_status(RELAY_OFFLINE);
            }
            continue;
        }
        int64_t now = now_ms();
        if (now < wait_until) {
            continue;
        }

        outcome_t outcome = REQUEST_OK;
        if (s_credentials.id[0] == '\0') {
            outcome = do_register();
            have_last_report = false;
            next_poll = 0;
        } else {
            if (now >= next_poll) {
                outcome = do_poll();
                next_poll = now + RELAY_POLL_MS;
            }
            relay_report_t report = { .version = relay_shown_version(&s_sync) };
            capsule_get(&report.state);
            if (outcome == REQUEST_OK &&
                relay_report_due(have_last_report ? &last_report : NULL, &report, now - last_report_at)) {
                outcome = do_report(&report);
                if (outcome == REQUEST_OK) {
                    last_report = report;
                    last_report_at = now;
                    have_last_report = true;
                }
            }
        }

        if (outcome == REQUEST_OK) {
            if (failures >= RELAY_OFFLINE_AFTER) {
                ESP_LOGI(TAG, "the relay answers again");
            }
            failures = 0;
            if (!stack_logged && have_last_report) {
                stack_logged = true;
                ESP_LOGI(TAG, "task stack: %u of %d bytes never used", (unsigned)uxTaskGetStackHighWaterMark(NULL),
                         TASK_STACK_BYTES);
                log_heap("after the first full exchange");
            }
        } else if (outcome == REQUEST_UNAUTHORIZED) {
            // The relay is there, it just lost us: register again on the next tick.
            forget_credentials();
            relay_sync_reset(&s_sync);
            failures = 0;
        } else {
            failures++;
            uint32_t wait = relay_backoff_ms(failures);
            wait_until = now_ms() + wait;
            ESP_LOGW(TAG, "request failed (%u in a row), next try in %u s", failures, (unsigned)(wait / 1000));
            if (failures >= RELAY_OFFLINE_AFTER) {
                set_status(RELAY_OFFLINE);
            }
        }
    }
}

void relay_start(void)
{
    size_t len = strlen(RELAY_URL);
    while (len > 0 && RELAY_URL[len - 1] == '/') {
        len--;
    }
    if (len == 0) {
        ESP_LOGI(TAG, "no RELAY_URL in secrets.h: cloud relay off");
        return;  // s_status stays RELAY_DISABLED
    }
    bool known_scheme = strncmp(RELAY_URL, "http://", 7) == 0 || strncmp(RELAY_URL, "https://", 8) == 0;
    if (len > BASE_URL_MAX || !known_scheme) {
        ESP_LOGE(TAG, "RELAY_URL must start with http:// or https:// and be at most %d characters: cloud relay off",
                 BASE_URL_MAX);
        return;
    }
    memcpy(s_base, RELAY_URL, len);
    s_base[len] = '\0';
    relay_sync_reset(&s_sync);
    load_credentials();
    set_status(RELAY_STARTING);
    ESP_LOGI(TAG, "cloud relay at %s", s_base);
    if (xTaskCreate(relay_task, "relay", TASK_STACK_BYTES, NULL, TASK_PRIORITY, NULL) != pdPASS) {
        ESP_LOGE(TAG, "could not start the relay task: cloud relay off");
        set_status(RELAY_DISABLED);
    }
}
