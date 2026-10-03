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
#include "esp_random.h"
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
#define REQUEST_TIMEOUT_MS 10000  // also covers the whole TCP and TLS connect: a cold start, a busy network
#define BASE_URL_MAX 160
#define HEALTH_LOG_MS (5 * 60 * 1000)  // heap, stack and request counts on the serial port this often
#define NVS_NAMESPACE "relay"

static portMUX_TYPE s_status_lock = portMUX_INITIALIZER_UNLOCKED;
static relay_status_t s_status;

// Everything below is only touched by the relay task.
static char s_base[BASE_URL_MAX + 1];  // RELAY_URL without a trailing slash
static esp_http_client_handle_t s_client;
static bool s_connection_used;  // a request went through on the current connection
static char s_response[RELAY_MAX_RESPONSE + 1];
static size_t s_response_len;
static bool s_response_overflow;
static relay_credentials_t s_credentials;  // id[0] == '\0': not registered. Only id and token are in flash.
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

// Only the id and the token are kept in flash, and they are written once per registration.
// The pairing code and its URL come with every poll answer while the board is unclaimed, so
// a relay that changes the code often does not wear the flash.
static void load_credentials(void)
{
    relay_credentials_t stored = { 0 };
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) != ESP_OK) {
        return;  // never registered
    }
    bool ok = load_string(nvs, "id", stored.id, sizeof(stored.id)) &&
              load_string(nvs, "token", stored.token, sizeof(stored.token));
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
        nvs_erase_key(nvs, "code");  // left by firmware that stored them; not there otherwise
        nvs_erase_key(nvs, "url");
        err = nvs_set_str(nvs, "id", s_credentials.id);
        err = err == ESP_OK ? nvs_set_str(nvs, "token", s_credentials.token) : err;
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
        nvs_erase_key(nvs, "id");  // not the whole namespace: the hardware secret stays
        nvs_erase_key(nvs, "token");
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

// `ok_from`..`ok_to`: the statuses that count as success.
static relay_outcome_t outcome_of(int status, int ok_from, int ok_to, const char *what)
{
    if (status >= ok_from && status <= ok_to) {
        return RELAY_OUTCOME_OK;
    }
    if (status == 401) {
        ESP_LOGW(TAG, "%s: HTTP 401, the relay does not know this device or token", what);
        return RELAY_OUTCOME_UNAUTHORIZED;
    }
    if (status >= 0) {
        ESP_LOGW(TAG, "%s: HTTP %d", what, status);
    }
    return RELAY_OUTCOME_FAILED;
}

// ---- the three exchanges ----

static void sha256(const uint8_t *data, size_t len, uint8_t digest[32])
{
    mbedtls_sha256(data, len, digest, 0);
}

// The id this board registers under. The MAC can be read off the air, and registering a
// known id again takes the device from its owner, so the id also depends on 16 random
// bytes that are made here once, kept in NVS and never sent or logged. Erasing NVS makes
// the board a new device to the relay. False if the secret cannot be kept: registering
// under an id that changes with every boot would only litter the relay with devices.
// Only called with Wi-Fi up, which is what makes esp_fill_random() truly random.
static bool hardware_id(char out[RELAY_HW_ID_CHARS + 1])
{
    uint8_t secret[RELAY_HW_SECRET_BYTES];
    uint8_t mac[6];
    nvs_handle_t nvs;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs);
    if (err == ESP_OK) {
        size_t len = sizeof(secret);
        if (nvs_get_blob(nvs, "secret", secret, &len) != ESP_OK || len != sizeof(secret)) {
            esp_fill_random(secret, sizeof(secret));
            err = nvs_set_blob(nvs, "secret", secret, sizeof(secret));
            err = err == ESP_OK ? nvs_commit(nvs) : err;
            if (err == ESP_OK) {
                ESP_LOGI(TAG, "made this board's hardware secret");
            }
        }
        nvs_close(nvs);
    }
    if (err == ESP_OK) {
        err = esp_read_mac(mac, ESP_MAC_WIFI_STA);
    }
    if (err == ESP_OK) {
        relay_hw_id(secret, mac, sha256, out);
    } else {
        ESP_LOGE(TAG, "no hardware id: %s", esp_err_to_name(err));
    }
    memset(secret, 0, sizeof(secret));
    return err == ESP_OK;
}

static relay_outcome_t do_register(void)
{
    char hw[RELAY_HW_ID_CHARS + 1];
    if (!hardware_id(hw)) {
        return RELAY_OUTCOME_FAILED;
    }
    char *body = relay_register_body(hw, esp_app_get_description()->version);
    if (!body) {
        return RELAY_OUTCOME_FAILED;
    }
    int status = request(HTTP_METHOD_POST, "/api/devices/register", false, body);
    cJSON_free(body);
    if (status != 201) {
        if (status >= 0) {
            ESP_LOGW(TAG, "register: HTTP %d", status);
        }
        return RELAY_OUTCOME_FAILED;
    }
    if (!relay_parse_register(s_response, s_response_len, &s_credentials)) {
        ESP_LOGW(TAG, "register: the answer is not {id, token, code[, pair_url]}");
        return RELAY_OUTCOME_FAILED;
    }
    save_credentials();
    relay_sync_reset(&s_sync);
    ESP_LOGI(TAG, "registered as device %s, pairing code %s, %s", s_credentials.id, s_credentials.code,
             s_credentials.pair_url[0] ? s_credentials.pair_url : "no pair_url");
    set_online(false);
    return RELAY_OUTCOME_OK;
}

static relay_outcome_t do_poll(void)
{
    char path[RELAY_ID_MAX + 32];
    snprintf(path, sizeof(path), "/api/devices/%s/capsule", s_credentials.id);
    relay_outcome_t outcome = outcome_of(request(HTTP_METHOD_GET, path, true, NULL), 200, 200, "poll");
    if (outcome != RELAY_OUTCOME_OK) {
        return outcome;
    }
    relay_poll_t result = relay_handle_poll(&s_sync, s_response, s_response_len);
    if (!result.ok) {
        ESP_LOGW(TAG, "poll: the answer is not usable");
        return RELAY_OUTCOME_FAILED;
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
    if (relay_take_pairing(&s_credentials, &result)) {  // in RAM only, see load_credentials()
        ESP_LOGI(TAG, "pairing code %s", s_credentials.code);
    }
    set_online(result.claimed);
    return RELAY_OUTCOME_OK;
}

static relay_outcome_t do_report(const relay_report_t *report)
{
    char path[RELAY_ID_MAX + 32];
    snprintf(path, sizeof(path), "/api/devices/%s/state", s_credentials.id);
    char *body = relay_report_body(report);
    if (!body) {
        return RELAY_OUTCOME_FAILED;
    }
    int status = request(HTTP_METHOD_POST, path, true, body);
    cJSON_free(body);
    return outcome_of(status, 200, 299, "state");  // 204 by the contract; any 2xx will do
}

// ---- the task ----

static int64_t now_ms(void)
{
    return esp_timer_get_time() / 1000;
}

// Carries out what relay_after_request() decided for a registration or a poll.
static void act_on(const relay_verdict_t *verdict, unsigned failures)
{
    if (verdict->forget) {
        // The relay is there, it just does not know us. The registration that follows waits
        // for the backoff like any other request.
        forget_credentials();
        relay_sync_reset(&s_sync);
    }
    if (verdict->wait_ms > 0) {
        ESP_LOGW(TAG, "request failed (%u in a row), next try in %u s", failures, (unsigned)(verdict->wait_ms / 1000));
    }
    if (verdict->offline) {
        set_status(RELAY_OFFLINE);
    } else if (verdict->forget) {
        set_status(RELAY_STARTING);  // the pairing code on the screen died with the registration
    }
    if (verdict->recovered) {
        ESP_LOGI(TAG, "the relay answers again");
    }
}

static void relay_task(void *arg)
{
    relay_schedule_t schedule = { 0 };
    int64_t next_poll = 0;
    int64_t last_report_at = 0;
    relay_report_t last_report;
    bool have_last_report = false;
    bool stack_logged = false;
    unsigned polls_ok = 0, polls_failed = 0, reports_ok = 0, reports_failed = 0;
    int64_t next_health_log = HEALTH_LOG_MS;

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(TICK_MS));
        if (now_ms() >= next_health_log) {
            next_health_log += HEALTH_LOG_MS;
            ESP_LOGI(TAG, "up %u min: polls %u ok %u failed, reports %u ok %u failed, task stack %u bytes never used",
                     (unsigned)(now_ms() / 60000), polls_ok, polls_failed, reports_ok, reports_failed,
                     (unsigned)uxTaskGetStackHighWaterMark(NULL));
            log_heap("now");
        }
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
        if (now < schedule.wait_until) {
            continue;
        }

        if (s_credentials.id[0] == '\0') {
            relay_outcome_t outcome = do_register();
            relay_verdict_t verdict = relay_after_request(&schedule, RELAY_STEP_REGISTER, outcome, now_ms());
            act_on(&verdict, schedule.failures);
            have_last_report = false;
            next_poll = 0;
            continue;
        }
        if (now >= next_poll) {
            relay_outcome_t outcome = do_poll();
            next_poll = now + RELAY_POLL_MS;
            relay_verdict_t verdict = relay_after_request(&schedule, RELAY_STEP_POLL, outcome, now_ms());
            act_on(&verdict, schedule.failures);
            if (outcome != RELAY_OUTCOME_OK) {
                polls_failed++;
                continue;
            }
            polls_ok++;
        }

        // The state report has a schedule of its own: when it fails it is tried again later,
        // and polling (and with it the marker on the screen) carries on regardless.
        relay_report_t report = { .version = relay_shown_version(&s_sync) };
        capsule_get(&report.state);
        if (now >= schedule.report_wait_until &&
            relay_report_due(have_last_report ? &last_report : NULL, &report, now - last_report_at)) {
            relay_outcome_t outcome = do_report(&report);
            relay_after_request(&schedule, RELAY_STEP_REPORT, outcome, now_ms());
            if (outcome == RELAY_OUTCOME_OK) {
                reports_ok++;
                last_report = report;
                last_report_at = now;
                have_last_report = true;
            } else {
                reports_failed++;
                ESP_LOGW(TAG, "state report failed (%u in a row), polling carries on", schedule.report_failures);
            }
        }
        if (!stack_logged && have_last_report) {
            stack_logged = true;
            ESP_LOGI(TAG, "task stack: %u of %d bytes never used", (unsigned)uxTaskGetStackHighWaterMark(NULL),
                     TASK_STACK_BYTES);
            log_heap("after the first full exchange");
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
