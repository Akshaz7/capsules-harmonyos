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
#include "relay.h"

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
#define STATUS_MAX_CHARS 32    // of the small line at the top: more runs into the rounded corners
#define QR_BOX 300             // white square behind the pairing QR code
#define QR_QUIET_MODULES 4     // white border the QR standard asks for, on every side

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
    char pair[sizeof(((relay_status_t *)0)->code)];  // idle only: pairing phrase, shown instead of value and label
    char pair_url[sizeof(((relay_status_t *)0)->pair_url)];  // and what the QR code above it holds, if anything
    char hint[24];
    uint32_t value_color;
    uint32_t bg_color;
} frame_t;

static view_t s_views[3];  // indexed by capsule_type_t
// On the idle view while the board waits to be paired:
static lv_obj_t *s_idle_title;  // "harmoniser"; makes way for the QR code
static lv_obj_t *s_qr_box;      // white square (a QR code needs a light border) ...
static lv_obj_t *s_qr;          // ... with the code in its middle
static lv_obj_t *s_pair_title;  // "or type:" under the QR code; "pair:" when there is none
static lv_obj_t *s_pair_code;   // the phrase
static lv_obj_t *s_pair_ip;     // the address, below everything else
static int s_qr_size;           // pixels the QR canvas currently has
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

static void set_hint(frame_t *frame, const char *hint)
{
    snprintf(frame->hint, sizeof(frame->hint), "%s", hint);
}

// The cloud relay's part of the small line at the top. Empty when the relay is off, has
// not answered yet, or the pairing phrase is on the screen anyway.
static const char *cloud_marker(const relay_status_t *relay)
{
    switch (relay->state) {
    case RELAY_CLAIMED:
        return "cloud";
    case RELAY_OFFLINE:
        return "cloud offline";
    default:
        return "";
    }
}

static void fill_idle(frame_t *frame, const net_status_t *net, const relay_status_t *relay)
{
    set_hint(frame, "harmoniser.local");
    frame->value_color = net->state == NET_CONNECTED ? COLOR_TEXT : COLOR_PAUSED;
    snprintf(frame->status, sizeof(frame->status), "%s", cloud_marker(relay));
    switch (net->state) {
    case NET_CONNECTED:
        if (relay->state == RELAY_UNCLAIMED) {
            // Waiting to be paired: the phrase takes the middle of the screen, the address moves down.
            snprintf(frame->pair, sizeof(frame->pair), "%s", relay->code);
            snprintf(frame->pair_url, sizeof(frame->pair_url), "%s", relay->pair_url);
            set_hint(frame, net->ip);
            break;
        }
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
        set_hint(frame, "tap to reset");
    } else if (state->running) {
        set_hint(frame, "tap to pause");
    } else {
        frame->value_color = COLOR_PAUSED;
        set_hint(frame, "tap to start");
    }
}

// The small line above a capsule: where the board is, the cloud marker, motion counting.
// While the board waits to be paired the phrase stands in for the address. If it all gets
// too long the address goes: it is also on the idle screen and on the serial port.
static void fill_status(frame_t *frame, const capsule_state_t *state, const net_status_t *net,
                        const relay_status_t *relay)
{
    char place[sizeof(frame->status)];
    if (net->state != NET_CONNECTED) {
        snprintf(place, sizeof(place), "no Wi-Fi");
    } else if (relay->state == RELAY_UNCLAIMED) {
        snprintf(place, sizeof(place), "pair: %s", relay->code);
    } else {
        snprintf(place, sizeof(place), "%s", net->ip);
    }
    const char *cloud = net->state == NET_CONNECTED ? cloud_marker(relay) : "";
    const char *motion = state->motion ? "motion on" : "";
    const char *parts[] = { place, cloud, motion };
    size_t separators = 3 * ((*cloud != '\0') + (*motion != '\0'));
    if (strlen(place) + strlen(cloud) + strlen(motion) + separators > STATUS_MAX_CHARS) {
        parts[0] = "";  // only ever true with a marker to show in its place
    }
    for (size_t i = 0; i < sizeof(parts) / sizeof(parts[0]); i++) {
        if (*parts[i]) {
            strlcat(frame->status, frame->status[0] ? "   " : "", sizeof(frame->status));
            strlcat(frame->status, parts[i], sizeof(frame->status));
        }
    }
}

static void fill_frame(frame_t *frame, const capsule_state_t *state, const net_status_t *net,
                       const relay_status_t *relay)
{
    memset(frame, 0, sizeof(*frame));  // also the padding: frames are compared with memcmp
    frame->view = state->type;
    frame->value_color = COLOR_TEXT;
    frame->bg_color = COLOR_BG;
    memcpy(frame->label, state->label, sizeof(frame->label));
    if (state->type == CAPSULE_IDLE) {
        fill_idle(frame, net, relay);
        return;
    }
    fill_status(frame, state, net, relay);
    if (state->type == CAPSULE_TIMER) {
        fill_timer(frame, state);
    } else {
        snprintf(frame->value, sizeof(frame->value), "%d", state->count);
        frame->value_color = state->motion ? COLOR_ACCENT : COLOR_TEXT;
    }
}

// ---- drawing ----

// Modules along one side of the QR code LVGL makes for `bytes` bytes of text (it uses error
// correction level M and the smallest version that fits). 0: too long for the sizes listed.
static int qr_modules(size_t bytes)
{
    static const uint8_t capacity[] = { 14, 26, 42, 62, 84, 106, 122, 152, 180, 213 };  // versions 1..10, level M
    for (size_t version = 1; version <= sizeof(capacity); version++) {
        if (bytes <= capacity[version - 1]) {
            return 17 + 4 * (int)version;
        }
    }
    return 0;
}

// Draws `url` as dark modules on the white square, as large as whole pixels per module allow
// with the quiet zone kept. False if it cannot be drawn; the phrase is then shown alone.
static bool show_qr(const char *url)
{
    int modules = qr_modules(strlen(url));
    if (modules == 0) {
        return false;
    }
    int size = modules * (QR_BOX / (modules + 2 * QR_QUIET_MODULES));
    if (size != s_qr_size) {
        lv_qrcode_set_size(s_qr, size);
        s_qr_size = size;
    }
    return lv_qrcode_update(s_qr, url, strlen(url)) == LV_RESULT_OK;
}

// One line of the phrase in the label font, or in the small font if that is too wide.
static void fit_phrase_line(const char *phrase)
{
    lv_obj_set_style_text_font(s_pair_code, &font_text_40, 0);
    lv_label_set_text(s_pair_code, phrase);
    lv_obj_update_layout(s_pair_code);
    if (lv_obj_get_width(s_pair_code) > TEXT_WIDTH) {
        lv_obj_set_style_text_font(s_pair_code, &font_small_22, 0);
    }
}

// The phrase as large as the label font goes: on one line if that fits between the rounded
// corners, else one word per line.
static void fit_phrase_lines(const char *phrase)
{
    lv_obj_set_style_text_font(s_pair_code, &font_text_40, 0);
    lv_label_set_text(s_pair_code, phrase);
    lv_obj_update_layout(s_pair_code);
    if (lv_obj_get_width(s_pair_code) > TEXT_WIDTH) {
        char lines[sizeof(((frame_t *)0)->pair)];
        snprintf(lines, sizeof(lines), "%s", phrase);
        for (char *c = lines; *c; c++) {
            if (*c == '-' || *c == ' ') {
                *c = '\n';
            }
        }
        lv_label_set_text(s_pair_code, lines);
    }
}

// The idle view while the board waits to be paired: the QR code with the phrase under it as
// the fallback, or the phrase alone if the relay gave no URL. `phrase` empty: not pairing.
static void show_pair(const view_t *idle, const char *phrase, const char *url, const char *ip)
{
    bool pairing = phrase[0] != '\0';
    bool qr = pairing && url[0] != '\0' && show_qr(url);
    lv_obj_set_hidden(s_idle_title, qr);
    lv_obj_set_hidden(idle->value, pairing);
    lv_obj_set_hidden(idle->label, pairing);
    lv_obj_set_hidden(idle->hint, qr);
    lv_obj_set_hidden(s_qr_box, !qr);
    lv_obj_set_hidden(s_pair_ip, !qr);
    lv_obj_set_hidden(s_pair_title, !pairing);
    lv_obj_set_hidden(s_pair_code, !pairing);
    if (qr) {
        lv_label_set_text(s_pair_title, "or type:");
        lv_obj_align(s_pair_title, LV_ALIGN_TOP_MID, 0, 324);
        fit_phrase_line(phrase);
        lv_obj_align(s_pair_code, LV_ALIGN_TOP_MID, 0, 346);
        lv_label_set_text(s_pair_ip, ip);
    } else if (pairing) {
        lv_label_set_text(s_pair_title, "pair:");
        lv_obj_align(s_pair_title, LV_ALIGN_TOP_MID, 0, 132);
        fit_phrase_lines(phrase);
        lv_obj_align(s_pair_code, LV_ALIGN_CENTER, 0, 22);
    }
}

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
    if (frame->view == CAPSULE_IDLE) {
        show_pair(view, frame->pair, frame->pair_url, frame->hint);
    } else {
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
    relay_status_t relay;
    capsule_get(&state);
    net_get_status(&net);
    relay_get_status(&relay);

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
    fill_frame(&frame, &state, &net, &relay);
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
    s_idle_title = make_label(view->root, &font_text_40, COLOR_ACCENT, LV_ALIGN_TOP_MID, 70);
    lv_label_set_text(s_idle_title, "harmoniser");
    view->value = make_text_line(view->root, COLOR_TEXT, LV_ALIGN_CENTER, -6);   // IP address
    view->label = make_text_line(view->root, COLOR_DIM, LV_ALIGN_CENTER, 50);    // network name
    view->hint = make_label(view->root, &font_small_22, COLOR_DIM, LV_ALIGN_BOTTOM_MID, -36);

    // Shown instead while the board waits to be paired; show_pair() places the two labels.
    s_qr_box = lv_obj_create(view->root);
    lv_obj_remove_style_all(s_qr_box);
    lv_obj_set_size(s_qr_box, QR_BOX, QR_BOX);
    lv_obj_align(s_qr_box, LV_ALIGN_TOP_MID, 0, 18);
    lv_obj_set_style_bg_color(s_qr_box, lv_color_white(), 0);
    lv_obj_set_style_bg_opa(s_qr_box, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(s_qr_box, 12, 0);
    lv_obj_set_scrollable(s_qr_box, false);
    s_qr = lv_qrcode_create(s_qr_box);
    lv_qrcode_set_dark_color(s_qr, lv_color_black());
    lv_qrcode_set_light_color(s_qr, lv_color_white());
    lv_qrcode_set_quiet_zone(s_qr, false);  // the white square is the quiet zone
    lv_obj_center(s_qr);
    s_pair_title = make_label(view->root, &font_small_22, COLOR_DIM, LV_ALIGN_TOP_MID, 132);
    s_pair_code = make_label(view->root, &font_text_40, COLOR_TEXT, LV_ALIGN_CENTER, 22);
    lv_obj_set_style_text_line_space(s_pair_code, 0, 0);
    s_pair_ip = make_label(view->root, &font_small_22, COLOR_DIM, LV_ALIGN_BOTTOM_MID, -12);
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
