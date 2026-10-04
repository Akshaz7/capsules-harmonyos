#!/bin/sh
# calendar.mp4: the timer the capsule started, in the system calendar.
set -eu
. "$(dirname "$0")/_hdc.sh"

"$HDC" shell "aa start -b com.huawei.hmos.calendar -a MainAbility" >/dev/null 2>&1
sleep 4
tap 506 428 2                # Month view (with the Today agenda below)
hold 2.5                     # month view with today's Harmoniser timer
