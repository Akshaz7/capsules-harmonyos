#!/bin/sh
# Voice eval on a phone (or the emulator): 16 kHz mono PCM recordings of spoken requests through the app's own
# VoiceInput (core/providers/SpeechInput.ets, system speech recognizer, offline), headless on the next launch.
# Needs a debuggable build of the app installed (hdc file send -b); INSTALL_HAP=<hap> installs it first (emulator).
#
# Usage: scripts/phone-speech-eval.sh <device-id> <pcm-dir> [languages]
#   <pcm-dir>    folder of NN.pcm files plus requests.txt (line N = what NN.pcm says), e.g. from
#                scripts/eval-speech/make-audio.sh /tmp/speech
#   [languages]  space-separated engine languages to try, default "zh-CN en-US"
# Holds /tmp/hy-phone.lock (phones) or /tmp/hy-emu.lock (127.0.0.1:*) with an owner file while it runs.
set -eu
cd "$(dirname "$0")/.."
TARGET="${1:?usage: scripts/phone-speech-eval.sh <device-id> <pcm-dir> [languages]}"
SRC="${2:?pcm dir}"
LANGS="${3:-zh-CN en-US}"
BUNDLE="${BUNDLE:-com.hackyeah.capsules}"
HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"
FILES="/data/app/el2/100/base/$BUNDLE/haps/entry/files"
case "$TARGET" in 127.0.0.1:*) LOCK=/tmp/hy-emu.lock ;; *) LOCK=/tmp/hy-phone.lock ;; esac
OWNER="${HY_SESSION:-T5-cactus} phone-speech-eval $$"

until mkdir "$LOCK" 2>/dev/null; do
  echo "$LOCK held by $(cat "$LOCK/owner" 2>/dev/null || echo 'another session'); retrying in 30s" >&2
  sleep 30
done
echo "$OWNER" > "$LOCK/owner"
release() { [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$OWNER" ] && rm -f "$LOCK/owner" && rmdir "$LOCK"; }
trap release EXIT
trap 'exit 130' INT TERM

STAGE="$(mktemp -d)/speech-eval"
mkdir -p "$STAGE"
cp "$SRC"/*.pcm "$STAGE/"
echo "$LANGS" > "$STAGE/languages.txt"
: > "$STAGE/run"

if [ -n "${INSTALL_HAP:-}" ]; then  # same lock hold, so no other session can replace the build in between
  "$HDC" -t "$TARGET" install -r "$INSTALL_HAP" | tail -1
  "$HDC" -t "$TARGET" shell "aa start -a EntryAbility -b $BUNDLE" >/dev/null; sleep 4
fi
"$HDC" -t "$TARGET" shell "ls -d $FILES" 2>&1 | grep -q "^$FILES\$" || { echo "error: launch the app once first" >&2; exit 1; }
"$HDC" -t "$TARGET" shell "aa force-stop $BUNDLE" >/dev/null
out="$("$HDC" -t "$TARGET" file send -b "$BUNDLE" "$STAGE" data/storage/el2/base/haps/entry/files/ 2>&1)"
echo "$out" | grep -q "FileTransfer finish" || { echo "$out" >&2; exit 1; }
"$HDC" -t "$TARGET" shell "aa start -a EntryAbility -b $BUNDLE" | tail -1
START=$(date +%s)
until "$HDC" -t "$TARGET" shell "ls $FILES/speech-eval/results.jsonl.done" 2>/dev/null | grep -q "done$"; do
  sleep 5
  [ $(( $(date +%s) - START )) -gt 420 ] && { echo "timeout after 420 s" >&2; break; }
done
echo "eval took $(( $(date +%s) - START )) s"
RES="$(dirname "$STAGE")/speech-eval-$TARGET.jsonl"
"$HDC" -t "$TARGET" file recv -b "$BUNDLE" data/storage/el2/base/haps/entry/files/speech-eval/results.jsonl "$RES" | tail -1
"$HDC" -t "$TARGET" shell "aa force-stop $BUNDLE" >/dev/null
echo "raw results: $RES"
python3 - "$RES" "$SRC/requests.txt" <<'PY'
import json, re, sys
want = open(sys.argv[2]).read().strip().split('\n')
UNITS = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split()
TENS = dict(zip('twenty thirty forty fifty sixty seventy eighty ninety'.split(), range(20, 100, 10)))
def digits(s):  # number words -> digits, same as cleanTranscript, so "nine" and "9" compare equal
    s = re.sub(r"\b(%s)[ -](%s)\b" % ('|'.join(TENS), '|'.join(UNITS[1:10])), lambda m: str(TENS[m[1]] + UNITS.index(m[2])), s)
    return re.sub(r"\b(%s)\b" % '|'.join(UNITS + list(TENS)), lambda m: str(UNITS.index(m[1]) if m[1] in UNITS else TENS[m[1]]), s)
norm = lambda s: re.findall(r"[a-z0-9]+", digits(s.lower().replace('-', ' ')))
def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / max(len(r), 1)
by = {}
for line in open(sys.argv[1]):
    row = json.loads(line)
    if 'file' not in row:
        print(row); continue
    n = int(row['file'][:2]); ref = want[n - 1]
    w = wer(ref, row['text']) if row['text'] else 1.0
    by.setdefault(row['language'], []).append(w)
    print(f"{row['language']} {row['file']} {row['ms']:>5} ms WER {w:.2f}  {row['text'] or row['error']!r}")
for lang, ws in by.items():
    print(f"== {lang}: exact {sum(w == 0 for w in ws)}/{len(ws)}, WER<=0.2 {sum(w <= 0.2 for w in ws)}/{len(ws)}, mean WER {sum(ws)/len(ws):.2f}")
PY
