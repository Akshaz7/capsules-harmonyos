#!/bin/sh
# Push the on-device model (Cactus v2 weights folder) into the Capsules app's files dir.
# The model is never packed into the .hap. Works for debug (debuggable) builds only.
#
# Usage: scripts/push-model.sh <path-to-model-folder> [device-id]
#   <path-to-model-folder>  e.g. ~/models/lfm2-vl-450m-cq4 (unzipped lfm2-vl-450m-cq4.zip from
#                           https://huggingface.co/Cactus-Compute/LFM2-VL-450M/resolve/v2.0/lfm2-vl-450m-cq4.zip)
#   [device-id]             hdc target; default 127.0.0.1:5555 (emulator). See: hdc list targets
# Install the app first; reinstalling with "hdc install -r" keeps the model.
set -eu

BUNDLE=com.hackyeah.capsules
HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"

if [ $# -lt 1 ]; then
  sed -n '2,10p' "$0"
  exit 2
fi
SRC="${1%/}"
TARGET="${2:-127.0.0.1:5555}"
NAME="$(basename "$SRC")"

if [ ! -f "$SRC/config.txt" ] || [ ! -f "$SRC/components/manifest.json" ]; then
  echo "error: $SRC is not a Cactus v2 model folder (needs config.txt and components/manifest.json)" >&2
  exit 1
fi
if [ "$NAME" != "lfm2-vl-450m-cq4" ]; then
  echo "warning: the app loads files/lfm2-vl-450m-cq4; this folder is named $NAME" >&2
fi

echo "Pushing $NAME ($(du -sh "$SRC" | cut -f1)) to $BUNDLE on $TARGET ..."
"$HDC" -t "$TARGET" file send -b "$BUNDLE" "$SRC" "data/storage/el2/base/haps/entry/files/"
"$HDC" -t "$TARGET" shell "ls -la /data/app/el2/100/base/$BUNDLE/haps/entry/files/$NAME/config.txt"
echo "Done. Restart the app: $HDC -t $TARGET shell \"aa force-stop $BUNDLE; aa start -a EntryAbility -b $BUNDLE\""
