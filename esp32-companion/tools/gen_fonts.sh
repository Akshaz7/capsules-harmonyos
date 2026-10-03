#!/usr/bin/env bash
# Regenerates main/fonts/*.c from Roboto (Apache-2.0) with lv_font_conv.
# Only needed if you want different sizes or glyphs; the generated files are checked in.
# Needs Node.js (npx) and the Roboto TTFs (Fedora: google-roboto-fonts).
set -euo pipefail
cd "$(dirname "$0")/.."

ROBOTO_DIR="${ROBOTO_DIR:-/usr/share/fonts/google-roboto}"
OUT=main/fonts
DIGITS='0123456789:+-'
# ASCII, Latin-1, Latin Extended-A, plus the punctuation an LLM likes to emit.
TEXT_RANGES='0x20-0x7E,0xA0-0x17F,0x2013,0x2014,0x2018,0x2019,0x201C,0x201D,0x2022,0x2026'

gen() { # gen <weight> <size> <name> <glyph args...>
    local weight=$1 size=$2 name=$3
    shift 3
    npx --yes lv_font_conv@1.5.3 --font "$ROBOTO_DIR/Roboto-$weight.ttf" --size "$size" \
        --bpp 4 --format lvgl --no-compress --no-kerning --lv-include lvgl.h \
        "$@" -o "$OUT/$name.c"
}

gen Bold   128 font_digits_128 --symbols "$DIGITS"
gen Bold    72 font_digits_72  --symbols "$DIGITS"
gen Medium  40 font_text_40    --range "$TEXT_RANGES"
gen Medium  22 font_small_22   --range 0x20-0x7E
