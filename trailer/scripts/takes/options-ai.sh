#!/bin/sh
# options-ai.mp4: Settings, AI mode (on-device + EU cloud, opt-in).
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap $TAB_SETTINGS_X $TAB_Y 3
hold 4                       # AI mode card and its note (no advanced rows)
