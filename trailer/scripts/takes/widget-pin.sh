#!/bin/sh
# widget-pin.mp4: add the capsule's widget and land back on the home screen.
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
sleep 3
tap $TAB_CAPSULES_X $TAB_Y 2
card 356 1380                # Pomodoro: widget-sized and not pinned yet
hold 2                       # capsule page
tap 662 2494 2               # Add to home screen (preview sheet opens)
hold 2.5                     # widget preview
tap 662 2500 4               # confirm in the sheet; the system lands on the widget
home
hold 2.5                     # home screen with the new widget
