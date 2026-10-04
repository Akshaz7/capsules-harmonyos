#!/bin/sh
# Stop-motion capture from the device itself: the take script alternates
# `hold <seconds>` (real frames pulled over hdc) with taps, so input is never
# lost and the Mac screen can stay locked.
#
#   scripts/capture-states.sh <name> scripts/takes/<name>.sh
set -eu

NAME=${1:?usage: capture-states.sh <name> <take-script>}
DRIVE=${2:?usage: capture-states.sh <name> <take-script>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CAPTURE_MODE=states
CAP_DIR=${CAP_DIR:-/tmp/harmoniser-capture/state-$NAME-$(date +%s)}
export CAPTURE_MODE CAP_DIR
mkdir -p "$CAP_DIR" "$ROOT/public/footage"

sh "$DRIVE"

frames=$(wc -l < "$CAP_DIR/times.txt" | tr -d ' ')
echo "captured $frames frames in $CAP_DIR"

python3 - "$CAP_DIR" <<'PY'
import os, sys
d = sys.argv[1]
rows = [l.split() for l in open(os.path.join(d, 'times.txt')) if l.strip()]
times = [(f, int(t)) for f, t in rows]
last = times[-1][1] - times[-2][1] if len(times) > 1 else 150
lines = []
for i, (f, t) in enumerate(times):
    nxt = times[i + 1][1] if i + 1 < len(times) else t + last
    lines.append(f"file '{f}.jpeg'")
    lines.append(f"duration {max(0.02, (nxt - t) / 1000.0):.3f}")
lines.append(f"file '{times[-1][0]}.jpeg'")
open(os.path.join(d, 'list.txt'), 'w').write('\n'.join(lines) + '\n')
PY

ffmpeg -y -loglevel error -f concat -safe 0 -i "$CAP_DIR/list.txt" \
  -vf "fps=30,scale=1320:2856:flags=lanczos" -an -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
  "$ROOT/public/footage/$NAME.mp4"

echo "wrote $ROOT/public/footage/$NAME.mp4"
