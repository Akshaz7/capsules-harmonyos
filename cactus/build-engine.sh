#!/bin/sh
# Rebuild cactus/libs/arm64-v8a/libcactus_engine.so from source with the OpenHarmony NDK.
# See cactus/BUILD.md. Usage: cactus/build-engine.sh [work-dir]   (default: /tmp/cactus-build)
set -eu

CACTUS_REPO=https://github.com/cactus-compute/cactus.git
CACTUS_COMMIT=2cfcdb8568eb9192323b27fd0012a834517b4419   # v2.2.2
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-/tmp/cactus-build}"
NATIVE="${OHOS_NATIVE:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
CMAKE="$NATIVE/build-tools/cmake/bin/cmake"
NINJA="$NATIVE/build-tools/cmake/bin/ninja"
STRIP="$NATIVE/llvm/bin/llvm-strip"

[ -x "$CMAKE" ] || { echo "error: OpenHarmony NDK not found at $NATIVE (set OHOS_NATIVE)" >&2; exit 1; }

mkdir -p "$WORK"
if [ ! -d "$WORK/cactus/.git" ]; then
  git clone --filter=blob:none --no-checkout "$CACTUS_REPO" "$WORK/cactus"
fi
git -C "$WORK/cactus" fetch --depth 1 origin "$CACTUS_COMMIT"
git -C "$WORK/cactus" checkout --force -q "$CACTUS_COMMIT"
git -C "$WORK/cactus" clean -fdq
git -C "$WORK/cactus" apply "$HERE/cactus-ohos.patch"

"$CMAKE" -S "$WORK/cactus/cactus-engine" -B "$WORK/build-ohos" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_TOOLCHAIN_FILE="$NATIVE/build/cmake/ohos.toolchain.cmake" \
  -DOHOS_ARCH=arm64-v8a -DOHOS_PLATFORM=OHOS -DCMAKE_BUILD_TYPE=Release
"$NINJA" -C "$WORK/build-ohos"

"$STRIP" --strip-unneeded -o "$HERE/libs/arm64-v8a/libcactus_engine.so" "$WORK/build-ohos/libcactus_engine.so"
echo "Built $HERE/libs/arm64-v8a/libcactus_engine.so ($(wc -c < "$HERE/libs/arm64-v8a/libcactus_engine.so") bytes)"
