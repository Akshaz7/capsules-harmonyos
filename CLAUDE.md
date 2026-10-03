# Compatibility Shim

Project instructions are imported below from the canonical `AGENTS.md`.

@./AGENTS.md

SCHEMA.md is the contract. Never change it without asking me.

## Build and run

Run from the project root (`Capsules/`). Verified 2026-10-03 with devecocli 1.3.4 on the emulator at `127.0.0.1:5555`.

```sh
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc

# Build a debug HAP for the entry module
devecocli build --modules entry
# -> entry/build/default/outputs/default/entry-default-unsigned.hap

# Install on the emulator (-r replaces an existing install)
$HDC -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-unsigned.hap

# Launch the entry ability
$HDC -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.hackyeah.capsules
```

`build-profile.json5` has no `signingConfigs`, so hvigor skips signing and outputs an unsigned HAP. The emulator accepts it. A physical device needs signing (`devecocli auth login` then `devecocli signature generate`). Never commit the generated signing material.
