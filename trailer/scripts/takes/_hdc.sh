#!/bin/sh
# Shared hdc helpers for the take scripts. Override HDC if hdc is not on PATH.
HDC=${HDC:-$(command -v hdc 2>/dev/null || echo /Users/lewissimpson/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc)}

tap() { "$HDC" shell "uitest uiInput click $1 $2" >/dev/null 2>&1; sleep "${3:-1}"; }
back() { "$HDC" shell "uitest uiInput keyEvent Back" >/dev/null 2>&1; sleep 1; }
home() { "$HDC" shell "uitest uiInput keyEvent Home" >/dev/null 2>&1; sleep 1; }
swipe() { "$HDC" shell "uitest uiInput swipe $1 $2 $3 $4 ${5:-600}" >/dev/null 2>&1; sleep 1; }

_ms() { perl -MTime::HiRes=time -e 'print int(time()*1000)' 2>/dev/null || python3 -c 'import time;print(int(time.time()*1000))'; }

# Hold a state on screen. With the window recorder this is just a pause; with
# capture-states.sh it pulls device frames for that many seconds. Frames and
# taps never overlap, so the taps are never swallowed by the capture stream.
_cap_index=${_cap_index:-0}
_capture_frames() {
  _secs=$1
  _secs_ms=$(python3 -c "print(int(float('$_secs') * 1000))")
  _end=$(( $(_ms) + _secs_ms ))
  mkdir -p "$CAP_DIR"
  while [ "$(_ms)" -lt "$_end" ]; do
    _f=$(printf '%04d' "$_cap_index")
    _t=$(_ms)
    "$HDC" shell "snapshot_display -f /data/local/tmp/hcap.jpeg" >/dev/null 2>&1 || true
    "$HDC" file recv /data/local/tmp/hcap.jpeg "$CAP_DIR/$_f.jpeg" >/dev/null 2>&1 || true
    [ -s "$CAP_DIR/$_f.jpeg" ] && echo "$_f $_t" >> "$CAP_DIR/times.txt"
    _cap_index=$((_cap_index + 1))
  done
}
hold() {
  if [ "${CAPTURE_MODE:-}" = "states" ]; then _capture_frames "$1"; else sleep "$1"; fi
}

# Navigation shortcuts (device 1320x2856).
TAB_CREATE_X=213; TAB_CAPSULES_X=519; TAB_MARKET_X=813; TAB_SETTINGS_X=1115; TAB_Y=2593
CLOSE_CAPSULE_X=1196; CLOSE_CAPSULE_Y=293
CLOSE_SHEET_X=1196; CLOSE_SHEET_Y=838

openApp() { "$HDC" shell "aa start -b com.hackyeah.capsules -a EntryAbility" >/dev/null 2>&1; sleep 3; }
closeCapsule() { tap $CLOSE_CAPSULE_X $CLOSE_CAPSULE_Y 2; }
closeSheet() { tap $CLOSE_SHEET_X $CLOSE_SHEET_Y 2; }
card() { tap "$1" "$2" 1; } # a capsule card in the Capsules grid

# Deterministic start: leave the app, kill it, relaunch on the Create tab.
resetApp() {
  home
  "$HDC" shell "aa force-stop com.hackyeah.capsules" >/dev/null 2>&1
  sleep 1
  openApp
}
