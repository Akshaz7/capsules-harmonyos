# Rebuilding libcactus_engine.so

`cactus/libs/arm64-v8a/libcactus_engine.so` is a prebuilt Cactus v2.2.2 engine. It is cross-compiled for HarmonyOS arm64-v8a with the OpenHarmony NDK that ships with DevEco Studio. hvigor only builds the small Node-API wrapper in `src/main/cpp/` and links it against this library.

## One command

```sh
cactus/build-engine.sh            # work dir defaults to /tmp/cactus-build
```

The script:

1. clones https://github.com/cactus-compute/cactus at commit `2cfcdb8568eb9192323b27fd0012a834517b4419` (v2.2.2);
2. applies `cactus/cactus-ohos.patch`;
3. configures with the OHOS toolchain file and builds with the NDK's own cmake and ninja;
4. strips the result into `cactus/libs/arm64-v8a/libcactus_engine.so`.

It takes about 45 s on an M4 Pro. Set `OHOS_NATIVE` if the NDK is not at the default DevEco Studio path.

Verified on 2026-10-03: a clean rebuild is byte-identical to the committed library apart from the GNU build-ID note.

## Requirements

- DevEco Studio 6.1.1 (HarmonyOS SDK 6.1.1.125, API 24) with its native SDK at `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native`. That provides OHOS clang 15.0.4, cmake 3.28.2 and ninja.
- git and network access to GitHub.

## The commands, step by step

```sh
N=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
git clone https://github.com/cactus-compute/cactus.git && cd cactus
git checkout 2cfcdb8568eb9192323b27fd0012a834517b4419
git apply ../Capsules/cactus/cactus-ohos.patch
$N/build-tools/cmake/bin/cmake -S cactus-engine -B build-ohos -G Ninja \
  -DCMAKE_MAKE_PROGRAM=$N/build-tools/cmake/bin/ninja \
  -DCMAKE_TOOLCHAIN_FILE=$N/build/cmake/ohos.toolchain.cmake \
  -DOHOS_ARCH=arm64-v8a -DOHOS_PLATFORM=OHOS -DCMAKE_BUILD_TYPE=Release
$N/build-tools/cmake/bin/ninja -C build-ohos
$N/llvm/bin/llvm-strip --strip-unneeded -o ../Capsules/cactus/libs/arm64-v8a/libcactus_engine.so build-ohos/libcactus_engine.so
```

## What the patch changes (`cactus-ohos.patch`)

- `cactus-engine/CMakeLists.txt`: when `OHOS` is set (the toolchain file sets it), `src/telemetry_impl.cpp` is swapped for a new `src/telemetry_stub.cpp`. The original needs libcurl, which the OpenHarmony NDK does not have.
- `cactus-engine/src/telemetry_stub.cpp` (new): a no-op implementation of `telemetry.h`. The engine sends no telemetry and makes no network calls.
- `cactus-engine/src/index.cpp`, `index_ffi.cpp`: `emplace_back(a, b, c, d)` on the aggregate `Document` becomes `push_back(Document{a, b, c, d})`. The NDK's Clang 15 lacks C++20 parenthesised aggregate initialisation.

## Notes

- The engine is compiled with `-march=armv8.2-a+fp16+simd+dotprod+i8mm` (set by Cactus), so the CPU must support those extensions. Verified on the HarmonyOS emulator on Apple Silicon; not yet verified on a physical phone.
- Cactus only supports arm64-v8a, so `build-profile.json5` filters the HAR to that ABI.
- Licence: `cactus/CACTUS_LICENSE`; summary in `docs/THIRD_PARTY.md`.
