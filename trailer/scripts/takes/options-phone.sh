#!/bin/sh
# options-phone.mp4: a rule-built capsule on the phone, timer started.
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap $TAB_CAPSULES_X $TAB_Y 2
card 356 1380                # Pomodoro
hold 2.5                     # "Made by rules" capsule
tap 662 1108 3               # Start focus
hold 2.5                     # timer running
