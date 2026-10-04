#!/bin/sh
# widget-tap.mp4: tick checklist rows straight on the home-screen widget.
# Start from the home screen page that shows the widget (page 2 on the demo
# device): the take must not swipe or press Home first, or the taps land on the
# wrong page while the recording runs.
set -eu
. "$(dirname "$0")/_hdc.sh"

home
swipe 1150 1500 170 1500 900  # home page 1 -> page 2, where the widget sits
hold 1.5
tap 478 502 2                # first checklist row on the widget
hold 2
tap 478 668 2                # and the next one
hold 2
