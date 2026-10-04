#!/bin/sh
# Fallback capture: pull device frames over hdc and rebuild a video from them.
# Use when the Mac screen is locked or covered, so window capture would be black.
#
#   scripts/capture-device.sh <name> <seconds> [drive-script.sh]
#
# Frames land in /tmp/harmoniser-capture/device-<name>/ with a timestamp list,
# and the video is assembled at the real frame times (about 7 fps).
set -eu

NAME=${1:?usage: capture-device.sh <name> <seconds> [drive-script.sh]}
SECS=${2:?usage: capture-device.sh <name> <seconds> [drive-script.sh]}
DRIVE=${3:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HDC=${HDC:-$(command -v hdc 2>/dev/null || echo /Users/lewissimpson/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc)}
DIR=${DIR:-/tmp/harmoniser-capture/device-$NAME-$(date +%s)}

mkdir -p "$DIR" "$ROOT/public/footage"

now_ms() { python3 -c 'import time;print(int(time.time()*1000))'; }

echo "capturing device frames for ${SECS}s -> $DIR"
END=$(( $(now_ms) + SECS * 1000 ))
i=0
while [ "$(now_ms)" -lt "$END" ]; do
  t=$(now_ms)
  f=$(printf '%04d' "$i")
  "$HDC" shell "snapshot_display -f /data/local/tmp/hcap.jpeg" >/dev/null 2>&1 || true
  "$HDC" file recv /data/local/tmp/hcap.jpeg "$DIR/$f.jpeg" >/dev/null 2>&1 || true
  [ -s "$DIR/$f.jpeg" ] && echo "$f $t" >> "$DIR/times.txt"
  i=$((i + 1))
done

fps=$(wc -l < "$DIR/times.txt" | tr -d ' ')
echo "captured $fps frames"

python3 - "$DIR" <<'PY'
import os, sys
d = sys.argv[1]
rows = [l.split() for l in open(os.path.join(d, 'times.txt')) if l.strip()]
times = [(f, int(t)) for f, t in rows]
last = times[-1][1] - times[-2][1] if len(times) > 1 else 150
lines = []
for i, (f, t) in enumerate(times):
    nxt = times[i + 1][1] if i + 1 < len(times) else t + last
    dur = max(0.02, (nxt - t) / 1000.0)
    lines.append(f"file '{f}.jpeg'")
    lines.append(f"duration {dur:.3f}")
lines.append(f"file '{times[-1][0]}.jpeg'")
open(os.path.join(d, 'list.txt'), 'w').write('\n'.join(lines) + '\n')
print('wrote list.txt for', len(times), 'frames')
PY

ffmpeg -y -loglevel error -f concat -safe 0 -i "$DIR/list.txt" \
  -vf "fps=30,scale=1320:2856:flags=lanczos" -an -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
  "$ROOT/public/footage/$NAME.mp4"

echo "wrote $ROOT/public/footage/$NAME.mp4"
