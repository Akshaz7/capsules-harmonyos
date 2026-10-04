#!/bin/sh
# demo-core: the unedited core flow for the second ("Demo") video —
# ask -> consent sheet -> run -> use it -> pin the widget -> tap the widget.
# Record it with the window recorder for a continuous shot:
#   scripts/capture-emulator.sh demo-core 75 scripts/takes/demo-core.sh
# or, with the Mac screen unavailable, as stop-motion:
#   scripts/capture-states.sh demo-core scripts/takes/demo-core.sh
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap 330 740 1                # focus the prompt field (IME appears)
# One call, not word-by-word: the device strips trailing spaces, which turned
# "pomodoro 50/10" into "pomodoro50/10" and sent it down the cloud path.
"$HDC" shell "uitest uiInput inputText 330 740 'pomodoro 50/10'" >/dev/null 2>&1
hold 1
tap 1062 1142 3              # Create -> build card, then the consent sheet
hold 3                       # consent sheet: reminders permission
tap 365 2102 1               # Allow
hold 1
tap 662 2496 3               # Run capsule -> the capsule opens
hold 3                       # Pomodoro, Made by rules
tap 662 1108 2               # Start focus
hold 3                       # timer running
tap 662 2494 2               # Add to home screen -> widget preview sheet
hold 2
tap 662 2500 3               # confirm
home
hold 2
swipe 170 1500 1150 1500 900 # page 1 -> the widget page
hold 2
tap 478 502 2                # use the widget (timer widget: start)
hold 2
