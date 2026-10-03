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

Before building the submission .hap, delete entry/src/main/resources/rawfile/config.local.json and rebuild. Never ship a .hap with the key.

To use the AI fallback without the key inside the .hap, keep it in `config.local.json` at the project root (git-ignored, not packed) and push it to the app's files dir after installing. This works on debug builds only, and the core reads this location before `rawfile/`:

```sh
$HDC -t 127.0.0.1:5555 file send -b com.hackyeah.capsules config.local.json data/storage/el2/base/files/
```

With no config file anywhere, the app runs rules-only and reports "AI fallback not configured."

`config.local.json` holds one provider (`{"provider":"mistral","apiKey":"...","model":"..."}`) or several, with the one the app uses named in `default`:
`{"default":"mistral","providers":{"mistral":{"apiKey":"...","model":"ministral-14b-latest"},"anthropic":{"apiKey":"..."}}}`. Providers: `anthropic`, `openai` (any OpenAI-compatible endpoint), `mistral` (JSON output mode). Which Mistral models a key may call depends on its tier.

To compare providers, `node scripts/eval-providers.mjs` runs the same 15 requests through every provider in the root `config.local.json` (with the app's own prompt and validator) and prints valid/correct counts.

`build-profile.json5` has no `signingConfigs`, so hvigor skips signing and outputs an unsigned HAP. The emulator accepts it. A physical device needs signing (`devecocli auth login` then `devecocli signature generate`). Never commit the generated signing material.
