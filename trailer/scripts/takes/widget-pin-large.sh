#!/bin/sh
# widget-pin-large.mp4: pin the large checklist widget.
# Creates a short checklist capsule first (off camera), then films the pin.
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap 400 830 1                                        # focus the prompt field
"$HDC" shell "uitest uiInput inputText 400 830 'checklist: milk, eggs, bread'" >/dev/null 2>&1
back                                                 # dismiss the keyboard
tap 1124 1209 3                                      # Create -> build card
tap 660 2476 4                                       # Run capsule (no permissions)
hold 2                                               # new checklist capsule
tap 660 2275 2                                       # Add to home screen
hold 2.5                                             # widget preview sheet
tap 660 2535 3                                       # confirm
home
swipe 1150 1500 170 1500 900                         # to the widget page
hold 3                                               # large checklist widget
