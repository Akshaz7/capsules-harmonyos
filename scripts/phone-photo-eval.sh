#!/bin/sh
# Photo eval on a phone (or the emulator): the 10 photos in scripts/eval-images/ through the app's own
# generateCapsuleFromImage (system OCR -> local text pipeline; then the cloud if a config is pushed).
# Needs a debuggable build of the app installed (hdc file send -b). The app runs the eval headless on its next
# launch (core/providers/CactusProvider.ets runPhotoEvalIfRequested) and the results are judged with
# scripts/eval-images.mjs --no-cloud.
#
# Usage: scripts/phone-photo-eval.sh <device-id> [--vlm]
#   --vlm also times one LFM2-VL image prompt on a 256x256 photo (15 s limit, ignores ON_DEVICE_VISION).
# Holds /tmp/hy-phone.lock (phones) or /tmp/hy-emu.lock (127.0.0.1:*) with an owner file while it runs.
set -eu
cd "$(dirname "$0")/.."
TARGET="${1:?usage: scripts/phone-photo-eval.sh <device-id> [--vlm]}"
VLM="${2:-}"
BUNDLE="${BUNDLE:-com.hackyeah.capsules}"
HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"
FILES="/data/app/el2/100/base/$BUNDLE/haps/entry/files"
case "$TARGET" in 127.0.0.1:*) LOCK=/tmp/hy-emu.lock ;; *) LOCK=/tmp/hy-phone.lock ;; esac
OWNER="${HY_SESSION:-T5-cactus} phone-photo-eval $$"

until mkdir "$LOCK" 2>/dev/null; do
  echo "$LOCK held by $(cat "$LOCK/owner" 2>/dev/null || echo 'another session'); retrying in 30s" >&2
  sleep 30
done
echo "$OWNER" > "$LOCK/owner"
release() { [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$OWNER" ] && rm -f "$LOCK/owner" && rmdir "$LOCK"; }
trap release EXIT
trap 'exit 130' INT TERM

STAGE="$(mktemp -d)/photo-eval"
mkdir -p "$STAGE"
cp scripts/eval-images/*.jpg "$STAGE/"
: > "$STAGE/run"
if [ "$VLM" = "--vlm" ]; then
  python3 -c "from PIL import Image; im=Image.open('scripts/eval-images/sticky_note.jpg'); im=im.resize((256,256)); im.save('$STAGE/vlm.jpg', quality=90)"
fi

"$HDC" -t "$TARGET" shell "ls -d $FILES" 2>&1 | grep -q "^$FILES\$" || { echo "error: launch the app once first" >&2; exit 1; }
"$HDC" -t "$TARGET" shell "aa force-stop $BUNDLE" >/dev/null
out="$("$HDC" -t "$TARGET" file send -b "$BUNDLE" "$STAGE" data/storage/el2/base/haps/entry/files/ 2>&1)"
echo "$out" | grep -q "FileTransfer finish" || { echo "$out" >&2; exit 1; }
"$HDC" -t "$TARGET" shell "aa start -a EntryAbility -b $BUNDLE" | tail -1
START=$(date +%s)
until "$HDC" -t "$TARGET" shell "ls $FILES/photo-eval/results.jsonl.done" 2>/dev/null | grep -q "done$"; do
  sleep 5
  [ $(( $(date +%s) - START )) -gt 480 ] && { echo "timeout after 480 s" >&2; break; }
done
echo "eval took $(( $(date +%s) - START )) s"
RES="$(dirname "$STAGE")/photo-eval-$TARGET.jsonl"
"$HDC" -t "$TARGET" file recv -b "$BUNDLE" data/storage/el2/base/haps/entry/files/photo-eval/results.jsonl "$RES" | tail -1
echo "raw results: $RES"
"$HDC" -t "$TARGET" shell "aa force-stop $BUNDLE" >/dev/null  # a stuck LFM2-VL call must not keep running
node scripts/eval-images.mjs --ondevice "$RES" --no-cloud
