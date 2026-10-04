#!/bin/sh
# widget-pin.mp4: pin the small (2x2) timer widget - Pomodoro.
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap 590 2640 1               # Capsules tab
hold 1.5                     # grid
tap 950 700 2                # Pomodoro card
hold 2                       # capsule page
tap 660 2275 2               # Add to home screen -> widget preview sheet
hold 2.5                     # small preview, page dots
tap 660 2535 4               # confirm; the widget lands on the home screen
hold 2.5
