#include "motion.h"

#include <math.h>
#include <stdint.h>

#include "bsp/esp-bsp.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#undef M_PI  // qmi8658.h defines its own
#include "qmi8658.h"

#include "board.h"
#include "capsule.h"

static const char *TAG = "motion";

// Rep detection. One rep = the acceleration magnitude rises above REP_HIGH_G (the push)
// and then drops below REP_LOW_G (the fall). 1.0 g is standing still.
// UNTUNED: these numbers are first guesses and need a session with the board on a wrist.
#define REP_HIGH_G 1.20f
#define REP_LOW_G 0.85f
#define REP_REFRACTORY_MS 800  // ignore a second rep sooner than this
#define SMOOTHING 0.2f         // low-pass factor per sample (0..1, lower = smoother)
#define SAMPLE_PERIOD_MS 20    // 50 Hz
#define IDLE_POLL_MS 250       // how often to check whether motion counting was switched on
#define SENSOR_SETTLE_MS 500   // after configuration, before the first sample is valid

// Sensor setup, as in Waveshare's 92_qmi8658_imu example.
#define QMI8658_RESET_REGISTER 0x60
#define QMI8658_RESET_COMMAND 0xB0
#define QMI8658_CTRL1_VALUE 0x60
#define QMI8658_RESET_DELAY_MS 20

typedef struct {
    float smoothed_g;
    bool pushed;  // went above REP_HIGH_G, waiting for the fall
    int64_t last_rep_ms;
} rep_detector_t;

static qmi8658_dev_t s_imu;
static bool s_available;

static bool rep_detected(rep_detector_t *detector, float magnitude_g, int64_t now_ms)
{
    detector->smoothed_g += SMOOTHING * (magnitude_g - detector->smoothed_g);
    if (!detector->pushed) {
        detector->pushed = detector->smoothed_g > REP_HIGH_G;
        return false;
    }
    if (detector->smoothed_g >= REP_LOW_G) {
        return false;
    }
    detector->pushed = false;
    if (now_ms - detector->last_rep_ms < REP_REFRACTORY_MS) {
        return false;
    }
    detector->last_rep_ms = now_ms;
    return true;
}

static bool read_magnitude_g(float *magnitude_g)
{
    float x, y, z;  // milli-g
    if (qmi8658_read_accel(&s_imu, &x, &y, &z) != ESP_OK) {
        return false;
    }
    *magnitude_g = sqrtf(x * x + y * y + z * z) / 1000.0f;
    return true;
}

static bool motion_wanted(void)
{
    capsule_state_t state;
    capsule_get(&state);
    return state.type == CAPSULE_COUNTER && state.motion;
}

// Sanity check for the serial log: a board lying still should read about 1 g.
static void log_rest_reading(void)
{
    float magnitude_g = 0;
    vTaskDelay(pdMS_TO_TICKS(SENSOR_SETTLE_MS));
    if (read_magnitude_g(&magnitude_g)) {
        ESP_LOGI(TAG, "accelerometer reads |a| = %.2f g (about 1.00 when lying still)", magnitude_g);
    } else {
        ESP_LOGW(TAG, "accelerometer read failed");
    }
}

static void motion_task(void *arg)
{
    rep_detector_t detector = { .smoothed_g = 1.0f };
    log_rest_reading();
    for (;;) {
        if (!motion_wanted()) {
            detector = (rep_detector_t){ .smoothed_g = 1.0f };
            vTaskDelay(pdMS_TO_TICKS(IDLE_POLL_MS));
            continue;
        }
        float magnitude_g;
        if (read_magnitude_g(&magnitude_g) && rep_detected(&detector, magnitude_g, esp_timer_get_time() / 1000)) {
            capsule_count_rep();
            ESP_LOGI(TAG, "rep (|a| = %.2f g)", magnitude_g);
        }
        vTaskDelay(pdMS_TO_TICKS(SAMPLE_PERIOD_MS));
    }
}

static esp_err_t configure_sensor(uint8_t address)
{
    esp_err_t err = qmi8658_init(&s_imu, bsp_i2c_get_handle(), address);
    if (err == ESP_OK) {
        err = qmi8658_write_register(&s_imu, QMI8658_RESET_REGISTER, QMI8658_RESET_COMMAND);
    }
    vTaskDelay(pdMS_TO_TICKS(QMI8658_RESET_DELAY_MS));
    if (err == ESP_OK) {
        err = qmi8658_write_register(&s_imu, QMI8658_CTRL1, QMI8658_CTRL1_VALUE);
    }
    if (err == ESP_OK) {
        err = qmi8658_set_accel_range(&s_imu, QMI8658_ACCEL_RANGE_4G);
    }
    if (err == ESP_OK) {
        err = qmi8658_set_accel_odr(&s_imu, QMI8658_ACCEL_ODR_250HZ);
    }
    if (err == ESP_OK) {
        err = qmi8658_enable_sensors(&s_imu, QMI8658_ENABLE_ACCEL | QMI8658_ENABLE_GYRO);
    }
    return err;
}

bool motion_available(void)
{
    return s_available;
}

void motion_init(void)
{
    uint8_t address = board_i2c_probe(QMI8658_ADDRESS_HIGH) ? QMI8658_ADDRESS_HIGH : QMI8658_ADDRESS_LOW;
    esp_err_t err = configure_sensor(address);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "QMI8658 not usable (%s): motion counting disabled", esp_err_to_name(err));
        return;
    }
    ESP_LOGI(TAG, "QMI8658 found at 0x%02x", address);
    s_available = true;
    xTaskCreate(motion_task, "motion", 4096, NULL, 4, NULL);
}
