#!/bin/sh
# Renders requests.txt as synthetic speech (macOS `say`, voice Samantha) to 16 kHz mono 16-bit PCM files
# NN.pcm in <out-dir>, the format scripts/phone-speech-eval.sh and the speech recognizer take.
# Usage: scripts/eval-speech/make-audio.sh <out-dir>
set -eu
OUT="${1:?usage: make-audio.sh <out-dir>}"
mkdir -p "$OUT"
cp "$(dirname "$0")/requests.txt" "$OUT/"
python3 - "$(dirname "$0")/requests.txt" "$OUT" <<'PY'
import subprocess, sys, wave, os
out = sys.argv[2]
for i, line in enumerate(open(sys.argv[1]).read().strip().split('\n'), 1):
    base = os.path.join(out, f'{i:02d}')
    subprocess.run(['say', '-v', 'Samantha', '-r', '170', '-o', base + '.aiff', line], check=True)
    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', base + '.aiff', base + '.wav'], check=True)
    w = wave.open(base + '.wav')
    open(base + '.pcm', 'wb').write(w.readframes(w.getnframes()))
    os.remove(base + '.aiff'); os.remove(base + '.wav')
PY
ls "$OUT"/*.pcm | wc -l
