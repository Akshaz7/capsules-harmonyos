# Harmoniser launch trailer

A 65-second launch trailer built in [Remotion](https://www.remotion.dev/) (React + TypeScript). The output is 1920x1080 at 30 fps, 1950 frames long.

## Quick start

```sh
git checkout trailer
cd trailer
npm install
npm run studio    # live preview and timeline in the browser
npm run render    # final video → out/harmoniser-trailer.mp4 (about 35 s)
npm run preview   # half-scale render → out/preview.mp4 (fast timing check)
```

`out/` and `node_modules/` are gitignored. Don't commit the mp4.

## Where to change things

**Start with `src/timeline.ts`.** Every timing, voice line and on-screen string lives there, so most edits take one line.

| You want to change | Edit |
|---|---|
| A voice line or when it plays | `VO` in `src/timeline.ts`. The `text` field is what's shown on screen. `tts` is the respelled version sent to the voice (for example "Krah-koof" for Kraków). |
| Scene lengths | `SCENES` in `src/timeline.ts` |
| A persona (name, prompt, length, board) | `PERSONAS` in `src/timeline.ts` |
| Strings inside the app screens | `BOARD_STRINGS` in `src/timeline.ts` |
| Colours | `COLORS` in `src/timeline.ts` |
| How a scene looks or moves | `src/scenes/Scene1Problem.tsx` … `Scene7End.tsx` |
| The persona beat (typing bar, flying words, moments) | `src/components/PersonaBeat.tsx` |
| The app screens shown in the phone | `src/boards/*.tsx`. These are ported from the design boards in `boards/*.dc.html`. |
| Logo | `Logo` in `src/components/common.tsx`. It's the official mark; a copy is in `assets/harmoniser-mark.svg`. |
| Phone shape, background, tap dot | `src/components/common.tsx` |
| Home-screen icons (scenes 1, 2, 5) | `src/components/Home.tsx` |
| Motion presets (pop, slide, count-up, typing, tap) | `src/lib/motion.ts` |
| Volumes and ducking | `MUSIC_VOLUME`, `VO_VOLUME`, `SFX_VOLUME` and `DUCK_LEVEL` in `src/timeline.ts`. The mixer is `src/components/AudioMix.tsx`. |

The music is 120 BPM, so one beat is 15 frames. Keep cuts on multiples of 15 where you can.

## Real footage

Put screen recordings in `public/footage/` with these exact names. The next `npm run studio` or `npm run render` picks them up automatically, because both run `scripts/footage-manifest.mjs` first.

| File | Used in | Without it |
|---|---|---|
| `judge.mp4` | Judge beat (Kraków to-do list) | Grey "Real recording needed" card |
| `widget-pin.mp4`, `widget-tap.mp4`, `calendar.mp4` | Scene 6 (native) | Grey "Real recording needed" card |
| `emma.mp4`, `tyler.mp4`, `friends.mp4`, `olivia.mp4`, `rose.mp4`, `mike.mp4` | Persona beats (optional) | The design board for that persona |

Recordings are muted, cropped and scaled to fill the phone screen.

## Audio

- **Voice-over:** ElevenLabs, voice Brian. The clips are committed in `public/audio/vo/`, so you only need a key if you change a line.
- **Sound effects:** ElevenLabs. They're committed in `public/audio/sfx/`.
- **Music:** `public/audio/music.mp3`. It's a stand-in track from `scripts/synth-music.mjs` (`node scripts/synth-music.mjs` rebuilds it), because the ElevenLabs Music API needs a paid plan. To use any other track, drop an mp3 at that path. It should be 65 s long, and the drop should land at 13.0 s.

To regenerate voice after editing a line:

1. Create `trailer/.env` containing `ELEVENLABS_API_KEY=your_key`. You can add `VOICE_ID=...` to use a different voice.
2. Run `npm run audio`. It caches by text and settings, so only changed lines cost API calls. It also writes `src/generated/audio-manifest.json`, which holds clip lengths and word timings that some titles cue from (`src/lib/cues.ts`).
3. Watch the output for `OVERRUN`. An overrun means a line is too long for its slot even at 1.1x speed. Shorten the line or give it a longer slot.

Note: `npm run audio` also tries the ElevenLabs music endpoint. On a paid plan that call succeeds and replaces `music.mp3`.

**Never commit `.env`.** It's gitignored. Keys go only in `.env`, never in code or commit messages.

## Rules the content must follow

- English only. Sentence case. Font is Manrope: titles at weight 800, labels at 600.
- No Huawei logos, no real app icons and no Huawei wallpaper. Icons are generic.
- No claims of "first" or "unique".
- Don't mention foldables, dark mode, ESP32, offline mode or photo reading.
- Bottom right of the end card: "Some screens are design previews." Keep it while any board stands in for a real recording.

## Project layout

```
trailer/
  src/timeline.ts         all timings, lines and strings
  src/Trailer.tsx         stacks the seven scenes and the audio mix
  src/scenes/             one file per scene
  src/components/         phone, persona beat, home screen, footage, audio mix
  src/boards/             app screens (frame-driven, no clicks)
  src/lib/                motion presets, beat timing, word cues
  src/generated/          written by scripts (audio and footage manifests, ArkTS excerpt)
  scripts/                gen-audio, synth-music, footage-manifest
  public/audio/           voice, sound effects, music
  public/footage/         put recordings here
  boards/                 original HTML design boards
```
