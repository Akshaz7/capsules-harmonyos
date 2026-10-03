// Harmoniser wrist companion for the Waveshare ESP32-S3-Touch-AMOLED-1.8.
// Shows one capsule (a timer or a counter) sent over HTTP by the phone app.
#include "bsp/esp-bsp.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "beep.h"
#include "board.h"
#include "capsule.h"
#include "http_api.h"
#include "motion.h"
#include "net.h"
#include "ui.h"

static const char *TAG = "harmoniser";

static void init_nvs(void)  // the Wi-Fi driver keeps its radio calibration there
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);
}

void app_main(void)
{
    init_nvs();
    capsule_init();

    ESP_ERROR_CHECK(bsp_i2c_init());
    board_rev_t revision = board_power_up();
    ESP_LOGI(TAG, "hardware revision: %s", board_rev_name(revision));

    // The BSP aborts when it finds no touch controller, so only start the display if one
    // answered. Without a display the HTTP API still works.
    if (revision != BOARD_REV_UNKNOWN && bsp_display_start() != NULL) {
        ui_start();
        ESP_LOGI(TAG, "display and touch started");
    } else {
        ESP_LOGE(TAG, "display not started: running without a screen");
    }

    motion_init();
    beep_init();
    net_start();
    http_api_start();
    ESP_LOGI(TAG, "ready. free heap: %u bytes internal (largest block %u), %u bytes PSRAM",
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
}
