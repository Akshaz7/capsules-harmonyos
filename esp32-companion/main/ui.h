// The screen: idle (name, IP, network), timer (label + countdown, tap to start/pause)
// and counter (label + number + big "+" button). It redraws itself from capsule_get().
#pragma once

#include <stdint.h>

// Builds the screens. Call once, after bsp_display_start() succeeded.
void ui_start(void);

// What LVGL currently draws, as RGB565 pixels (row by row). Free with free().
// NULL if there is no display. Debug aid for GET /screenshot.
uint16_t *ui_snapshot(int *width, int *height);
