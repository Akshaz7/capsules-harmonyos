# Third-party components

This is a summary for reviewers. It is not legal advice; the licence texts linked below are authoritative.

## Cactus inference engine (bundled in the .hap)

| | |
| --- | --- |
| What | On-device LLM inference engine, C++ with a C FFI |
| Source | https://github.com/cactus-compute/cactus, v2.2.2, commit `2cfcdb8568eb9192323b27fd0012a834517b4419` |
| Where in this repo | `cactus/libs/arm64-v8a/libcactus_engine.so` (prebuilt by us), full licence in `cactus/CACTUS_LICENSE` |
| Licence | Cactus Compute licence (source-available, not OSI open source) |
| Our changes | `cactus/cactus-ohos.patch`. The patch adds a no-op telemetry stub instead of the libcurl-based telemetry (so the engine makes no network calls) and swaps two `emplace_back` calls for `push_back(Document{...})` for the SDK's Clang 15 |

The Cactus licence lets you use, copy, modify, publish and distribute the software if you keep the copyright and permission notice. That grant only covers:
- individuals using it for personal, educational, research or non-commercial purposes;
- organisations with under $2M in total funding and under $2M in annual revenue;
- educational institutions and students;
- registered non-profits.

Anyone else needs a commercial licence from Cactus Compute. A public hackathon repository built by individuals or students is covered. A sponsor or company above those limits that reuses this code is not.

We wrote the Node-API wrapper in `cactus/src/main/cpp/` (`napi_init.cpp`, `cactus_ffi.h`) for this project. `cactus_ffi.h` copies a few function declarations from Cactus's `cactus_engine.h`.

## LFM2-VL-450M model weights (NOT bundled; pushed to the device separately)

| | |
| --- | --- |
| What | 450M-parameter language model in Cactus v2 format, 4-bit (`cq4`), about 480 MB on device |
| Source | `Cactus-Compute/LFM2-VL-450M`, file `lfm2-vl-450m-cq4.zip`, tag `v2.0` (https://huggingface.co/Cactus-Compute/LFM2-VL-450M). Base model: https://huggingface.co/LiquidAI/LFM2-VL-450M |
| sha256 of the zip | `b3adcf299df8b0eac1a2224e8c90f910a1a88a719fb6f5211b14c7dc5e892e19` |
| Where | Not in the repository or the .hap. `scripts/push-model.sh` copies it to the app's files dir (`haps/entry/files/lfm2-vl-450m-cq4`) |
| Licence | LFM Open License v1.0 (Liquid AI), https://huggingface.co/LiquidAI/LFM2-VL-450M/blob/main/LICENSE |

LFM Open License v1.0 is Apache-2.0-style: perpetual, royalty-free copyright and patent grants, with notice and attribution requirements when you redistribute. It adds a commercial-use limit. Commercial use is licensed only if the user's legal entity has under $10M in annual revenue; qualifying non-profits doing non-commercial or research work are exempt. Use in a hackathon demo is within these terms. Because we don't redistribute the weights, anyone installing the model downloads it from Hugging Face under that licence.
