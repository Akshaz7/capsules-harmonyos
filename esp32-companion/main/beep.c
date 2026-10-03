#include "beep.h"

#include <math.h>
#include <stdint.h>

#include "bsp/esp-bsp.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "board.h"

static const char *TAG = "beep";

#define ES8311_I2C_ADDRESS 0x18  // 7-bit form of the codec component's ES8311_CODEC_DEFAULT_ADDR
#define SAMPLE_RATE 22050        // the BSP's default I2S setup: mono, 16 bit
#define TONE_HZ 2000
#define TONE_AMPLITUDE 16000     // of 32767
#define BEEP_MS 150
#define GAP_MS 120
#define BEEP_COUNT 3
#define VOLUME 85                // 0..100
#define RAMP_SAMPLES 64          // fade in/out so the beep does not click
#define TONE_SAMPLES (SAMPLE_RATE * BEEP_MS / 1000)

static esp_codec_dev_handle_t s_speaker;
static TaskHandle_t s_task;
static int16_t s_tone[TONE_SAMPLES];

static void fill_tone(void)
{
    for (int i = 0; i < TONE_SAMPLES; i++) {
        int from_edge = i < TONE_SAMPLES - i ? i : TONE_SAMPLES - 1 - i;
        float ramp = from_edge < RAMP_SAMPLES ? (float)from_edge / RAMP_SAMPLES : 1.0f;
        s_tone[i] = (int16_t)(TONE_AMPLITUDE * ramp * sinf(2.0f * (float)M_PI * TONE_HZ * i / SAMPLE_RATE));
    }
}

static void play_beeps(void)
{
    esp_codec_dev_sample_info_t format = {
        .sample_rate = SAMPLE_RATE,
        .channel = 1,
        .bits_per_sample = 16,
    };
    if (esp_codec_dev_open(s_speaker, &format) != ESP_CODEC_DEV_OK) {
        ESP_LOGW(TAG, "could not open the speaker");
        return;
    }
    esp_codec_dev_set_out_vol(s_speaker, VOLUME);
    for (int i = 0; i < BEEP_COUNT; i++) {
        esp_codec_dev_write(s_speaker, s_tone, sizeof(s_tone));
        vTaskDelay(pdMS_TO_TICKS(GAP_MS));
    }
    esp_codec_dev_close(s_speaker);  // also switches the amplifier off
}

static void beep_task(void *arg)
{
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        play_beeps();
    }
}

void beep_play(void)
{
    if (s_task) {
        xTaskNotifyGive(s_task);
    }
}

void beep_init(void)
{
    // The BSP asserts if the codec does not answer, so check that it is there first.
    if (!board_i2c_probe(ES8311_I2C_ADDRESS)) {
        ESP_LOGW(TAG, "ES8311 codec not found: no beep");
        return;
    }
    s_speaker = bsp_audio_codec_speaker_init();
    if (!s_speaker) {
        ESP_LOGW(TAG, "speaker init failed: no beep");
        return;
    }
    fill_tone();
    xTaskCreate(beep_task, "beep", 6144, NULL, 3, &s_task);
    ESP_LOGI(TAG, "speaker ready");
}
