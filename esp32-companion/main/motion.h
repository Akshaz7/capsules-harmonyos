// EXPERIMENTAL: counts reps (squats, curls, ...) from the QMI8658 accelerometer.
// Only active while the current capsule is a counter with motion switched on.
#pragma once

#include <stdbool.h>

void motion_init(void);
bool motion_available(void);  // false if the sensor did not answer at boot
