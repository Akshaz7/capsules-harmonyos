#!/bin/sh
# options-market.mp4: marketplace listing, install, consent sheet, run.
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap $TAB_MARKET_X $TAB_Y 3
hold 2.5                     # live listings
tap 662 1166 2               # Install on the first listing
hold 2.5                     # "From the marketplace" consent sheet
tap 662 2441 4               # Run capsule
hold 2
