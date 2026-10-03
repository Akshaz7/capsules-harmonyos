#!/bin/sh
# Push the on-device model (Cactus v2 weights folder) into the Capsules app's files dir.
# The model is never packed into the .hap. Works for debug (debuggable) builds only.
#
# Usage: scripts/push-model.sh [model-folder] [device-id]
#   [model-folder]  an unzipped Cactus v2 model folder. If omitted, lfm2-vl-450m-cq4 is downloaded once to
#                   ~/.cache/harmoniser/ from Hugging Face (about 380 MB) and reused on later runs.
#   [device-id]     hdc target; default 127.0.0.1:5555 (emulator). See: hdc list targets
# Install the app first. The script launches it once if needed (the files dir only exists after the
# first launch). Reinstalling with "hdc install -r" keeps the model.
set -eu

BUNDLE="${BUNDLE:-com.hackyeah.capsules}"
MODEL_NAME=lfm2-vl-450m-cq4
MODEL_URL=https://huggingface.co/Cactus-Compute/LFM2-VL-450M/resolve/v2.0/lfm2-vl-450m-cq4.zip
CACHE_DIR="$HOME/.cache/harmoniser"
HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"
FILES_DIR="/data/app/el2/100/base/$BUNDLE/haps/entry/files"

fail() {
  echo "error: $*" >&2
  exit 1
}

# Runs hdc and fails on any "[Fail]" line (hdc itself exits 0 even when a command fails).
hdc_checked() {
  out="$("$HDC" -t "$TARGET" "$@" 2>&1)" || fail "hdc $1 failed: $out"
  printf '%s\n' "$out"
  if printf '%s\n' "$out" | grep -q '\[Fail\]'; then
    fail "hdc $1 reported a failure (see above)"
  fi
}

# Arguments: an existing directory is the model folder; anything else is the device id.
SRC=""
TARGET="127.0.0.1:5555"
for arg in "$@"; do
  if [ -d "$arg" ]; then
    SRC="${arg%/}"
  else
    TARGET="$arg"
  fi
done

if [ -z "$SRC" ]; then
  SRC="$CACHE_DIR/$MODEL_NAME"
  if [ ! -f "$SRC/config.txt" ]; then
    mkdir -p "$CACHE_DIR"
    echo "Downloading $MODEL_NAME (about 380 MB) to $CACHE_DIR ..."
    curl -fL --progress-bar -o "$CACHE_DIR/$MODEL_NAME.zip.part" "$MODEL_URL" || fail "download failed: $MODEL_URL"
    mv "$CACHE_DIR/$MODEL_NAME.zip.part" "$CACHE_DIR/$MODEL_NAME.zip"
    rm -rf "$SRC"
    unzip -q "$CACHE_DIR/$MODEL_NAME.zip" -d "$CACHE_DIR" || fail "could not unzip $CACHE_DIR/$MODEL_NAME.zip"
  else
    echo "Using cached model $SRC"
  fi
fi
NAME="$(basename "$SRC")"

if [ ! -f "$SRC/config.txt" ] || [ ! -f "$SRC/components/manifest.json" ]; then
  fail "$SRC is not a Cactus v2 model folder (needs config.txt and components/manifest.json)"
fi
if [ "$NAME" != "$MODEL_NAME" ]; then
  echo "warning: the app loads files/$MODEL_NAME; this folder is named $NAME" >&2
fi

# The app must be installed, and launched once so that its files dir exists.
"$HDC" -t "$TARGET" shell "bm dump -n $BUNDLE" 2>&1 | grep -q '"bundleName"' ||
  fail "$BUNDLE is not installed on $TARGET (install the .hap first)"
if ! "$HDC" -t "$TARGET" shell "ls -d $FILES_DIR" 2>&1 | grep -q "^$FILES_DIR\$"; then
  echo "The app has not been launched yet; launching it once to create its files dir ..."
  hdc_checked shell "aa start -a EntryAbility -b $BUNDLE" >/dev/null
  sleep 3
  "$HDC" -t "$TARGET" shell "ls -d $FILES_DIR" 2>&1 | grep -q "^$FILES_DIR\$" ||
    fail "the app's files dir still does not exist after launching it"
fi

echo "Pushing $NAME ($(du -sh "$SRC" | cut -f1)) to $BUNDLE on $TARGET ..."
sent="$(hdc_checked file send -b "$BUNDLE" "$SRC" "data/storage/el2/base/haps/entry/files/")"
printf '%s\n' "$sent" | tail -1
printf '%s\n' "$sent" | grep -q "FileTransfer finish" || fail "hdc did not confirm the transfer"
check="$(hdc_checked shell "ls -la $FILES_DIR/$NAME/config.txt")"
printf '%s\n' "$check" | grep -q config.txt || fail "the model is not on the device after the push"
hdc_checked shell "aa force-stop $BUNDLE" >/dev/null
echo "Done. The model loads on the next launch: $HDC -t $TARGET shell \"aa start -a EntryAbility -b $BUNDLE\""
