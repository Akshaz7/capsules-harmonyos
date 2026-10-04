#!/bin/sh
# judge.mp4: the Kraków to-do list + weather capsule, ticking a task off.
set -eu
. "$(dirname "$0")/_hdc.sh"

resetApp
tap $TAB_CAPSULES_X $TAB_Y 2
card 969 683                 # "Tasks and weather · Kraków"
hold 2.5                     # weather card + task list
tap 195 1336 2               # tick the "Pack an umbrella" circle
hold 2
