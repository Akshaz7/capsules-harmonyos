#!/bin/sh
# Record the DevEco emulator's phone screen straight into public/footage/<name>.mp4.
#
#   scripts/capture-emulator.sh <name> <seconds> [drive-script.sh]
#
# The optional drive script runs in the background while recording; put the
# hdc/uitest sequence for the shot there. It must not need new terminal input,
# because the capture window has to stay free of focus changes.
# Frames come from the macOS screen recording of the emulator window, cropped to
# the phone display (no bezel, no toolbar), conformed to 30 fps, muted.
# Requires: macOS Screen Recording permission for the calling app, ffmpeg, hdc.
set -eu

NAME=${1:?usage: capture-emulator.sh <name> <seconds>}
SECS=${2:?usage: capture-emulator.sh <name> <seconds>}
DRIVE=${3:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RAW_DIR=${RAW_DIR:-/tmp/harmoniser-capture}
HELPER=${HELPER:-$RAW_DIR/emulator-window}

# Crop of the phone display inside the 902x1418 window capture.
CROP_W=${CROP_W:-587}
CROP_H=${CROP_H:-1274}
CROP_X=${CROP_X:-60}
CROP_Y=${CROP_Y:-64}

mkdir -p "$RAW_DIR" "$ROOT/public/footage"

if [ ! -x "$HELPER" ]; then
  swiftc -O -o "$HELPER" "$ROOT/scripts/emulator-window.swift"
fi

INFO=$("$HELPER" 2>/tmp/harmoniser-capture/front.log)
WIN_ID=$(echo "$INFO" | awk '{print $1}')
cat /tmp/harmoniser-capture/front.log >&2 || true
if ! grep -q "frontmost: Emulator" /tmp/harmoniser-capture/front.log; then
  echo "emulator is not frontmost; refusing to record a black window" >&2
  exit 3
fi
echo "recording window $WIN_ID for ${SECS}s -> public/footage/$NAME.mp4"

RAW="$RAW_DIR/$NAME.mov"
screencapture -v -l"$WIN_ID" -V"$SECS" -x "$RAW" &
REC=$!

if [ -n "$DRIVE" ]; then
  sh "$DRIVE"
fi

wait "$REC"

ffmpeg -y -loglevel error -i "$RAW" \
  -vf "crop=${CROP_W}:${CROP_H}:${CROP_X}:${CROP_Y},scale=1320:2856,fps=30" \
  -an -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
  "$ROOT/public/footage/$NAME.mp4"

echo "wrote $ROOT/public/footage/$NAME.mp4"
