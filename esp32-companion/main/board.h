// Board bring-up that Waveshare's BSP leaves to the application.
#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    BOARD_REV_UNKNOWN,   // no touch controller answered
    BOARD_REV_ORIGINAL,  // SH8601 display + FT3168 touch
    BOARD_REV_V2,        // CO5300 display + CST816-family touch
} board_rev_t;

// Releases the display/touch resets and reports which hardware revision is fitted.
board_rev_t board_power_up(void);
const char *board_rev_name(board_rev_t rev);

// True if a chip acknowledges this 7-bit address on the board's I2C bus.
bool board_i2c_probe(uint8_t address);
