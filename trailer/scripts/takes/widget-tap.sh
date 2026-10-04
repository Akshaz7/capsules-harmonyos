#!/bin/sh
# widget-tap.mp4: tick checklist rows straight on the home-screen widget.
# Start from the home screen page that shows the widget (page 2 on the demo
# device): the take must not swipe or press Home first, or the taps land on the
# wrong page while the recording runs.
set -eu
. "$(dirname "$0")/_hdc.sh"

# Start from the home screen page that holds the widgets (page 2 on the demo
# device): the take must not swipe or press Home first, so the taps land right.
hold 1.5
tap 893 1087 2               # "Start" on the small timer widget
hold 2                       # the timer counts down
tap 251 862 2                # tick the first row on the wide checklist widget
hold 2
