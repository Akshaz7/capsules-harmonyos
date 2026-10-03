#include "board.h"

#include "bsp/esp-bsp.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "board";

// TCA9554 expander outputs (same wiring on both revisions).
#define EXPANDER_RESET_PINS (IO_EXPANDER_PIN_NUM_0 | IO_EXPANDER_PIN_NUM_1 | IO_EXPANDER_PIN_NUM_2)
#define RESET_PULSE_MS 20
#define RESET_SETTLE_MS 150

// The touch controller is the only chip that differs visibly on the I2C bus.
#define TOUCH_ADDR_V2 0x15        // CST816 family
#define TOUCH_ADDR_ORIGINAL 0x38  // FT3168

bool board_i2c_probe(uint8_t address)
{
    // A NACK is the normal answer from an absent chip, so keep the driver quiet about it.
    esp_log_level_t saved = esp_log_level_get("i2c.master");
    esp_log_level_set("i2c.master", ESP_LOG_NONE);
    bool found = i2c_master_probe(bsp_i2c_get_handle(), address, 100) == ESP_OK;
    esp_log_level_set("i2c.master", saved);
    return found;
}

// LCD reset, panel power and touch reset hang off the IO expander and the BSP never drives
// it. This is the sequence from Waveshare's own board_variant.c and Arduino examples.
static void release_resets(void)
{
    esp_io_expander_handle_t expander = NULL;
    esp_err_t err = esp_io_expander_new_i2c_tca9554(bsp_i2c_get_handle(), BSP_IO_EXPANDER_I2C_ADDRESS, &expander);
    if (err == ESP_OK) {
        err = esp_io_expander_set_dir(expander, EXPANDER_RESET_PINS, IO_EXPANDER_OUTPUT);
    }
    if (err == ESP_OK) {
        err = esp_io_expander_set_level(expander, EXPANDER_RESET_PINS, 0);
    }
    vTaskDelay(pdMS_TO_TICKS(RESET_PULSE_MS));
    if (err == ESP_OK) {
        err = esp_io_expander_set_level(expander, EXPANDER_RESET_PINS, 1);
    }
    vTaskDelay(pdMS_TO_TICKS(RESET_SETTLE_MS));
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "IO expander not driven (%s); display may stay in reset", esp_err_to_name(err));
    }
}

board_rev_t board_power_up(void)
{
    release_resets();
    if (board_i2c_probe(TOUCH_ADDR_V2)) {
        return BOARD_REV_V2;
    }
    if (board_i2c_probe(TOUCH_ADDR_ORIGINAL)) {
        return BOARD_REV_ORIGINAL;
    }
    return BOARD_REV_UNKNOWN;
}

const char *board_rev_name(board_rev_t rev)
{
    switch (rev) {
    case BOARD_REV_V2:
        return "V2 (CO5300 display, CST816 touch at 0x15)";
    case BOARD_REV_ORIGINAL:
        return "original (SH8601 display, FT3168 touch at 0x38)";
    default:
        return "unknown (no touch controller at 0x15 or 0x38)";
    }
}
