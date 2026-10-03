#include "ui.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bsp/esp-bsp.h"
#include "esp_heap_caps.h"
#include "lvgl.h"

#include "beep.h"
#include "capsule.h"
#include "net.h"

LV_FONT_DECLARE(font_digits_128);  // 0-9 : + -
LV_FONT_DECLARE(font_digits_72);   // same glyphs, for values too long for the big font
LV_FONT_DECLARE(font_text_40);     // Latin incl. accented letters: labels come from the app
LV_FONT_DECLARE(font_small_22);    // ASCII

#define COLOR_BG 0x000000  // black is "off" on an AMOLED
#define COLOR_TEXT 0xFFFFFF
#define COLOR_DIM 0x9AA0A6
#define COLOR_ACCENT 0x00D1B2
#define COLOR_ACCENT_PRESSED 0x00877A
#define COLOR_PAUSED 0xFFB300
#define COLOR_ALERT 0xFF3B30

#define REFRESH_MS 100
#define FLASH_TICKS 60       // timer end: flash for 6 s ...
#define FLASH_HALF_PERIOD 3  // ... switching colour every 0.3 s
#define TEXT_WIDTH 336       // keeps text clear of the rounded display corners
#define BUTTON_MARGIN 10
#define BIG_TIMER_CHARS 5    // "00:00" fits in the big font, "1:40:00" does not
#define BIG_COUNTER_CHARS 4
#define HOUR_FORMAT_FROM 6000  // seconds; from 100 minutes on show h:mm:ss

typedef struct {
    lv_obj_t *root;
    lv_obj_t *label;
    lv_obj_t *value;
    lv_obj_t *hint;  // NULL on the counter view
} view_t;

// Everything that is visible. The screen is only touched when this changes.
typedef struct {
    capsule_type_t view;
    char status[48];  // small line at the top
    char label[CAPSULE_LABEL_MAX_BYTES];
    char value[40];
    const char *hint;
    uint32_t value_color;
    uint32_t bg_color;
} frame_t;

static view_t s_views[3];  // indexed by capsule_type_t
static lv_obj_t *s_status;
static frame_t s_shown;
static bool s_ready;
static bool s_was_done;
static int s_flash_ticks;

// ---- deciding what to show ----

static void format_time(char *out, size_t size, int seconds)
{
    if (seconds >= HOUR_FORMAT_FROM) {
        snprintf(out, size, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60);
    } else {
        snprintf(out, size, "%02d:%02d", seconds / 60, seconds % 60);
    }
}

static void fill_idle(frame_t *frame, const net_status_t *net)
{
    frame->hint = "harmoniser.local";
    frame->value_color = net->state == NET_CONNECTED ? COLOR_TEXT : COLOR_PAUSED;
    switch (net->state) {
    case NET_CONNECTED:
        snprintf(frame->value, sizeof(frame->value), "%s", net->ip);
        snprintf(frame->label, sizeof(frame->label), "%s", net->ssid);
        break;
    case NET_JOINING:
        snprintf(frame->value, sizeof(frame->value), "joining");
        snprintf(frame->label, sizeof(frame->label), "%s", net->ssid);
        break;
    case NET_OFFLINE:
        snprintf(frame->value, sizeof(frame->value), "no Wi-Fi");
        snprintf(frame->label, sizeof(frame->label), "still looking");
        break;
    default:
        snprintf(frame->value, sizeof(frame->value), "no Wi-Fi");
        snprintf(frame->label, sizeof(frame->label), "not set up");
        break;
    }
}

static void fill_timer(frame_t *frame, const capsule_state_t *state)
{
    format_time(frame->value, sizeof(frame->value), state->remaining_seconds);
    if (state->done) {
        bool lit = s_flash_ticks / FLASH_HALF_PERIOD % 2;
        frame->bg_color = lit ? COLOR_ALERT : COLOR_BG;
        frame->value_color = lit ? COLOR_TEXT : COLOR_ALERT;
        frame->hint = "tap to reset";
    } else if (state->running) {
        frame->hint = "tap to pause";
    } else {
        frame->value_color = COLOR_PAUSED;
        frame->hint = "tap to start";
    }
}

static void fill_frame(frame_t *frame, const capsule_state_t *state, const net_status_t *net)
{
    memset(frame, 0, sizeof(*frame));  // also the padding: frames are compared with memcmp
    frame->view = state->type;
    frame->hint = "";
    frame->value_color = COLOR_TEXT;
    frame->bg_color = COLOR_BG;
    memcpy(frame->label, state->label, sizeof(frame->label));
    if (state->type == CAPSULE_IDLE) {
        fill_idle(frame, net);
        return;
    }
    snprintf(frame->status, sizeof(frame->status), "%s%s", net->state == NET_CONNECTED ? net->ip : "no Wi-Fi",
             state->motion ? "   motion on" : "");
    if (state->type == CAPSULE_TIMER) {
        fill_timer(frame, state);
    } else {
        snprintf(frame->value, sizeof(frame->value), "%d", state->count);
        frame->value_color = state->motion ? COLOR_ACCENT : COLOR_TEXT;
    }
}

// ---- drawing ----

static void show_frame(const frame_t *frame)
{
    for (int i = 0; i < 3; i++) {
        lv_obj_set_hidden(s_views[i].root, i != (int)frame->view);
    }
    const view_t *view = &s_views[frame->view];
    lv_label_set_text(view->label, frame->label);
    lv_label_set_text(view->value, frame->value);
    lv_obj_set_style_text_color(view->value, lv_color_hex(frame->value_color), 0);
    if (view->hint) {
        lv_label_set_text(view->hint, frame->hint);
    }
    if (frame->view != CAPSULE_IDLE) {
        size_t big_chars = frame->view == CAPSULE_TIMER ? BIG_TIMER_CHARS : BIG_COUNTER_CHARS;
        const lv_font_t *font = strlen(frame->value) > big_chars ? &font_digits_72 : &font_digits_128;
        lv_obj_set_style_text_font(view->value, font, 0);
    }
    lv_label_set_text(s_status, frame->status);
    lv_obj_set_style_bg_color(lv_screen_active(), lv_color_hex(frame->bg_color), 0);
}

// Runs on the LVGL task every REFRESH_MS, and right after a tap.
static void refresh(lv_timer_t *timer)
{
    capsule_state_t state;
    net_status_t net;
    capsule_get(&state);
    net_get_status(&net);

    bool done = state.type == CAPSULE_TIMER && state.done;
    if (done && !s_was_done) {
        s_flash_ticks = FLASH_TICKS;
        beep_play();
    } else if (!done) {
        s_flash_ticks = 0;
    } else if (timer && s_flash_ticks > 0) {
        s_flash_ticks--;
    }
    s_was_done = done;

    frame_t frame;
    fill_frame(&frame, &state, &net);
    if (memcmp(&frame, &s_shown, sizeof(frame)) != 0) {
        show_frame(&frame);
        s_shown = frame;
    }
}

static void on_timer_tap(lv_event_t *event)
{
    capsule_apply(CAPSULE_ACT_TOGGLE);
    refresh(NULL);
}

static void on_plus(lv_event_t *event)
{
    capsule_apply(CAPSULE_ACT_INCREMENT);
    refresh(NULL);
}

// ---- building the screens ----

static lv_obj_t *make_label(lv_obj_t *parent, const lv_font_t *font, uint32_t color, lv_align_t align, int y)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_text(label, "");
    lv_obj_align(label, align, 0, y);
    return label;
}

// One line of app-supplied text: fixed width, too-long text ends in dots.
static lv_obj_t *make_text_line(lv_obj_t *parent, uint32_t color, lv_align_t align, int y)
{
    lv_obj_t *label = make_label(parent, &font_text_40, color, align, y);
    lv_label_set_long_mode(label, LV_LABEL_LONG_MODE_DOTS);
    lv_obj_set_size(label, TEXT_WIDTH, lv_font_get_line_height(&font_text_40));
    return label;
}

static lv_obj_t *make_root(lv_obj_t *screen)
{
    lv_obj_t *root = lv_obj_create(screen);
    lv_obj_remove_style_all(root);
    lv_obj_set_size(root, LV_PCT(100), LV_PCT(100));
    lv_obj_set_scrollable(root, false);
    lv_obj_set_hidden(root, true);
    return root;
}

static void make_idle_view(view_t *view, lv_obj_t *screen)
{
    view->root = make_root(screen);
    lv_obj_t *title = make_label(view->root, &font_text_40, COLOR_ACCENT, LV_ALIGN_TOP_MID, 70);
    lv_label_set_text(title, "harmoniser");
    view->value = make_text_line(view->root, COLOR_TEXT, LV_ALIGN_CENTER, -6);   // IP address
    view->label = make_text_line(view->root, COLOR_DIM, LV_ALIGN_CENTER, 50);    // network name
    view->hint = make_label(view->root, &font_small_22, COLOR_DIM, LV_ALIGN_BOTTOM_MID, -36);
}

static void make_timer_view(view_t *view, lv_obj_t *screen)
{
    view->root = make_root(screen);
    view->label = make_text_line(view->root, COLOR_TEXT, LV_ALIGN_TOP_MID, 56);
    view->value = make_label(view->root, &font_digits_128, COLOR_TEXT, LV_ALIGN_CENTER, 0);
    view->hint = make_label(view->root, &font_text_40, COLOR_DIM, LV_ALIGN_BOTTOM_MID, -30);
    lv_obj_add_event_cb(view->root, on_timer_tap, LV_EVENT_CLICKED, NULL);  // the whole screen is the button
}

static void make_counter_view(view_t *view, lv_obj_t *screen)
{
    view->root = make_root(screen);
    view->label = make_text_line(view->root, COLOR_TEXT, LV_ALIGN_TOP_MID, 42);
    // Centred in the space between the label and the button.
    view->value = make_label(view->root, &font_digits_128, COLOR_TEXT, LV_ALIGN_CENTER, -64);

    lv_obj_t *button = lv_button_create(view->root);
    lv_obj_set_size(button, BSP_LCD_H_RES - 2 * BUTTON_MARGIN, BSP_LCD_V_RES / 2 - BUTTON_MARGIN);
    lv_obj_align(button, LV_ALIGN_BOTTOM_MID, 0, -BUTTON_MARGIN);
    lv_obj_set_style_radius(button, 40, 0);
    lv_obj_set_style_shadow_width(button, 0, 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(COLOR_ACCENT), 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(COLOR_ACCENT_PRESSED), LV_STATE_PRESSED);
    // Count on touch-down: a tap that slides a little still counts.
    lv_obj_add_event_cb(button, on_plus, LV_EVENT_PRESSED, NULL);
    lv_obj_t *plus = make_label(button, &font_digits_128, COLOR_BG, LV_ALIGN_CENTER, 0);
    lv_label_set_text(plus, "+");
}

void ui_start(void)
{
    bsp_display_lock(0);
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_hex(COLOR_BG), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(screen, false);

    make_idle_view(&s_views[CAPSULE_IDLE], screen);
    make_timer_view(&s_views[CAPSULE_TIMER], screen);
    make_counter_view(&s_views[CAPSULE_COUNTER], screen);
    s_status = make_label(screen, &font_small_22, COLOR_DIM, LV_ALIGN_TOP_MID, 10);

    memset(&s_shown, 0xFF, sizeof(s_shown));  // matches no real frame, so the first refresh draws
    refresh(NULL);
    lv_timer_create(refresh, REFRESH_MS, NULL);
    s_ready = true;
    bsp_display_unlock();
}

uint16_t *ui_snapshot(int *width, int *height)
{
    const uint32_t stride = BSP_LCD_H_RES * sizeof(uint16_t);
    const uint32_t size = stride * BSP_LCD_V_RES;
    uint16_t *pixels = s_ready ? heap_caps_malloc(size, MALLOC_CAP_SPIRAM) : NULL;
    if (!pixels || !bsp_display_lock(2000)) {
        free(pixels);
        return NULL;
    }
    lv_draw_buf_t buffer;
    lv_draw_buf_init(&buffer, BSP_LCD_H_RES, BSP_LCD_V_RES, LV_COLOR_FORMAT_RGB565, stride, pixels, size);
    lv_result_t result = lv_snapshot_take_to_draw_buf(lv_screen_active(), LV_COLOR_FORMAT_RGB565, &buffer);
    bsp_display_unlock();
    if (result != LV_RESULT_OK) {
        free(pixels);
        return NULL;
    }
    *width = BSP_LCD_H_RES;
    *height = BSP_LCD_V_RES;
    return pixels;
}
