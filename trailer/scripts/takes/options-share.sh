#!/bin/sh
# options-share.mp4: a capsule's share sheet - QR code to import on another phone.
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap $TAB_CAPSULES_X $TAB_Y 2
card 356 683                 # "Chicken and rice" (from the marketplace)
hold 2
tap 662 2142 3               # Show as QR code
hold 2.5
