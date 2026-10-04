#!/bin/sh
# options-ai.mp4: Settings, AI mode (on-device + EU cloud, opt-in).
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap $TAB_SETTINGS_X $TAB_Y 3
hold 3                       # AI mode card
swipe 660 2100 660 1800 500  # reveal the note under AI mode
hold 2
