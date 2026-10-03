#include "net.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "mdns.h"

#if __has_include("secrets.h")
#include "secrets.h"
#else
#warning "main/secrets.h is missing: building without Wi-Fi (copy main/secrets.h.example)"
#define WIFI_NETWORKS { "", "" }
#endif

static const char *TAG = "net";

#define MDNS_HOSTNAME "harmoniser"
#define HTTP_PORT 80
#define JOIN_TIMEOUT_MS 15000     // per network, then the next one gets its turn
#define JOIN_RETRY_PAUSE_MS 1000  // between attempts inside that window
#define RESCAN_PAUSE_MS 5000      // when no configured network is in range
#define ANNOUNCE_PERIOD_MS 10000  // HARMONISER_IP=... line on the serial port
#define MAX_SCAN_RECORDS 128

#define GOT_IP_BIT BIT0
#define DISCONNECTED_BIT BIT1

typedef struct {
    const char *ssid;
    const char *password;
} network_t;

static const network_t NETWORKS[] = { WIFI_NETWORKS };
#define NETWORK_COUNT (sizeof(NETWORKS) / sizeof(NETWORKS[0]))

static EventGroupHandle_t s_events;
static portMUX_TYPE s_status_lock = portMUX_INITIALIZER_UNLOCKED;
static net_status_t s_status;

static void set_status(net_state_t state, const char *ssid, const char *ip)
{
    net_status_t next = { .state = state };
    strlcpy(next.ssid, ssid, sizeof(next.ssid));
    strlcpy(next.ip, ip, sizeof(next.ip));
    taskENTER_CRITICAL(&s_status_lock);
    s_status = next;
    taskEXIT_CRITICAL(&s_status_lock);
}

void net_get_status(net_status_t *out)
{
    taskENTER_CRITICAL(&s_status_lock);
    *out = s_status;
    taskEXIT_CRITICAL(&s_status_lock);
}

static const char *reason_hint(int reason)
{
    switch (reason) {
    case WIFI_REASON_NO_AP_FOUND:
        return " (network not found)";
    case WIFI_REASON_AUTH_FAIL:
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_HANDSHAKE_TIMEOUT:
        return " (authentication failed: wrong password?)";
    case WIFI_REASON_ASSOC_LEAVE:
        return " (we left)";
    default:
        return "";
    }
}

static void on_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        const wifi_event_sta_disconnected_t *event = data;
        ESP_LOGW(TAG, "disconnected from \"%.*s\": reason %d%s", event->ssid_len, (const char *)event->ssid,
                 event->reason, reason_hint(event->reason));
        xEventGroupSetBits(s_events, DISCONNECTED_BIT);
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        xEventGroupSetBits(s_events, GOT_IP_BIT);
    }
}

static const char *auth_name(wifi_auth_mode_t mode)
{
    switch (mode) {
    case WIFI_AUTH_OPEN:
        return "open";
    case WIFI_AUTH_WPA_PSK:
    case WIFI_AUTH_WPA_WPA2_PSK:
    case WIFI_AUTH_WPA2_PSK:
        return "WPA2";
    case WIFI_AUTH_WPA2_WPA3_PSK:
        return "WPA2/WPA3";
    case WIFI_AUTH_WPA3_PSK:
        return "WPA3";
    case WIFI_AUTH_WPA2_ENTERPRISE:
        return "enterprise";
    default:
        return "other";
    }
}

// Scans all 2.4 GHz channels and marks which configured networks are in range.
// The first scan after boot lists every network it saw, strongest first.
static void scan(bool visible[NETWORK_COUNT], bool list_all)
{
    memset(visible, 0, NETWORK_COUNT * sizeof(visible[0]));
    esp_err_t err = esp_wifi_scan_start(NULL, true);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "scan failed: %s", esp_err_to_name(err));
        return;
    }
    uint16_t total = 0;
    esp_wifi_scan_get_ap_num(&total);
    uint16_t count = total < MAX_SCAN_RECORDS ? total : MAX_SCAN_RECORDS;
    wifi_ap_record_t *records = calloc(count ? count : 1, sizeof(*records));
    if (!records || esp_wifi_scan_get_ap_records(&count, records) != ESP_OK) {
        count = 0;
        esp_wifi_clear_ap_list();
    }
    ESP_LOGI(TAG, "scan: %u networks on 2.4 GHz%s", total, total > count ? " (list truncated)" : "");
    for (int i = 0; i < count; i++) {
        const wifi_ap_record_t *ap = &records[i];
        if (list_all) {
            ESP_LOGI(TAG, "scan: ch %2d  rssi %4d  %-10s \"%s\"", ap->primary, ap->rssi, auth_name(ap->authmode),
                     (const char *)ap->ssid);
        }
        for (size_t n = 0; n < NETWORK_COUNT; n++) {
            if (!visible[n] && strcmp((const char *)ap->ssid, NETWORKS[n].ssid) == 0) {
                visible[n] = true;
                ESP_LOGI(TAG, "scan: configured network \"%s\" seen on channel %d, rssi %d", NETWORKS[n].ssid,
                         ap->primary, ap->rssi);
            }
        }
    }
    for (size_t n = 0; n < NETWORK_COUNT; n++) {
        if (!visible[n]) {
            ESP_LOGW(TAG, "scan: configured network \"%s\" NOT seen", NETWORKS[n].ssid);
        }
    }
    free(records);
}

static bool configure(const network_t *network)
{
    wifi_config_t config = { 0 };
    // Not strlcpy: a 32-character SSID or a 64-character key fills its field with no terminator.
    memcpy(config.sta.ssid, network->ssid, strnlen(network->ssid, sizeof(config.sta.ssid)));
    memcpy(config.sta.password, network->password, strnlen(network->password, sizeof(config.sta.password)));
    // Accept WPA2 and anything stronger (WPA3 or WPA2/WPA3 transition); PMF if the AP offers it.
    config.sta.threshold.authmode = network->password[0] ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    config.sta.sae_pwe_h2e = WPA3_SAE_PWE_BOTH;
    config.sta.pmf_cfg.capable = true;
    config.sta.pmf_cfg.required = false;
    esp_err_t err = esp_wifi_set_config(WIFI_IF_STA, &config);
    if (err != ESP_OK) {  // e.g. a password shorter than 8 characters: skip this network, do not reboot
        ESP_LOGE(TAG, "cannot use the settings for \"%s\": %s", network->ssid, esp_err_to_name(err));
    }
    return err == ESP_OK;
}

// Tries one network for at most JOIN_TIMEOUT_MS. True once it has an IP address.
static bool join(const network_t *network)
{
    ESP_LOGI(TAG, "joining \"%s\"", network->ssid);
    set_status(NET_JOINING, network->ssid, "");
    if (!configure(network)) {
        return false;
    }
    xEventGroupClearBits(s_events, GOT_IP_BIT | DISCONNECTED_BIT);
    esp_wifi_connect();

    int64_t deadline_us = esp_timer_get_time() + JOIN_TIMEOUT_MS * 1000LL;
    for (;;) {
        int64_t left_ms = (deadline_us - esp_timer_get_time()) / 1000;
        if (left_ms <= 0) {
            break;
        }
        EventBits_t bits = xEventGroupWaitBits(s_events, GOT_IP_BIT | DISCONNECTED_BIT, pdTRUE, pdFALSE,
                                               pdMS_TO_TICKS(left_ms));
        if (bits & GOT_IP_BIT) {
            return true;
        }
        if (bits & DISCONNECTED_BIT) {
            vTaskDelay(pdMS_TO_TICKS(JOIN_RETRY_PAUSE_MS));
            esp_wifi_connect();
        }
    }
    ESP_LOGW(TAG, "gave up on \"%s\" after %d s", network->ssid, JOIN_TIMEOUT_MS / 1000);
    esp_wifi_disconnect();
    return false;
}

// One machine-readable line so a script (or a person) can pick the address off the serial port.
// False if the driver has no access point any more: a disconnect event can get lost (join()
// clears it when it arrives together with the address), and nothing else would notice.
static bool announce(esp_netif_t *netif, const network_t *network)
{
    esp_netif_ip_info_t info = { 0 };
    wifi_ap_record_t ap = { 0 };
    if (esp_wifi_sta_get_ap_info(&ap) != ESP_OK) {
        return false;
    }
    esp_netif_get_ip_info(netif, &info);
    char ip[16];
    esp_ip4addr_ntoa(&info.ip, ip, sizeof(ip));
    set_status(NET_CONNECTED, network->ssid, ip);
    printf("HARMONISER_IP=%s SSID=%s RSSI=%d\n", ip, network->ssid, ap.rssi);
    return true;
}

static void stay_connected(esp_netif_t *netif, const network_t *network)
{
    for (;;) {
        if (!announce(netif, network)) {
            ESP_LOGW(TAG, "no link to \"%s\" and no disconnect event was seen", network->ssid);
            esp_wifi_disconnect();  // whatever the driver is in the middle of, start from scratch
            break;
        }
        if (xEventGroupWaitBits(s_events, DISCONNECTED_BIT, pdTRUE, pdFALSE, pdMS_TO_TICKS(ANNOUNCE_PERIOD_MS)) &
            DISCONNECTED_BIT) {
            break;
        }
    }
    ESP_LOGW(TAG, "lost \"%s\", looking for a network again", network->ssid);
    set_status(NET_OFFLINE, "", "");
}

static void net_task(void *arg)
{
    esp_netif_t *netif = arg;
    bool visible[NETWORK_COUNT];
    bool first_scan = true;
    for (;;) {
        scan(visible, first_scan);
        first_scan = false;
        bool connected = false;
        for (size_t n = 0; n < NETWORK_COUNT && !connected; n++) {
            connected = visible[n] && join(&NETWORKS[n]);
            if (connected) {
                stay_connected(netif, &NETWORKS[n]);
            }
        }
        if (!connected) {
            set_status(NET_OFFLINE, "", "");
            vTaskDelay(pdMS_TO_TICKS(RESCAN_PAUSE_MS));
        }
    }
}

static void start_mdns(void)
{
    ESP_ERROR_CHECK(mdns_init());
    ESP_ERROR_CHECK(mdns_hostname_set(MDNS_HOSTNAME));
    mdns_instance_name_set("Harmoniser wrist companion");
    mdns_service_add(NULL, "_http", "_tcp", HTTP_PORT, NULL, 0);
}

void net_start(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_t *netif = esp_netif_create_default_wifi_sta();
    esp_netif_set_hostname(netif, MDNS_HOSTNAME);

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));  // credentials stay out of NVS
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));

    uint8_t mac[6];
    esp_wifi_get_mac(WIFI_IF_STA, mac);
    ESP_LOGI(TAG, "station MAC " MACSTR, MAC2STR(mac));

    if (NETWORKS[0].ssid[0] == '\0') {
        ESP_LOGW(TAG, "no Wi-Fi networks configured: copy main/secrets.h.example to main/secrets.h");
        set_status(NET_UNCONFIGURED, "", "");
        return;
    }

    s_events = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, WIFI_EVENT_STA_DISCONNECTED, on_event, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_event, NULL));
    ESP_ERROR_CHECK(esp_wifi_start());
    esp_wifi_set_ps(WIFI_PS_NONE);  // keep HTTP latency low; this is a demo, not a battery test
    start_mdns();
    set_status(NET_OFFLINE, "", "");
    xTaskCreate(net_task, "net", 4096, netif, 5, NULL);
}
