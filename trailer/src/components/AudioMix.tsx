import React from 'react';
import {Sequence, interpolate, staticFile} from 'remotion';
import {Audio} from '@remotion/media';
import audio from '../generated/audio-manifest.json';
import music from '../generated/music.json';
import {DUCK_FADE, DUCK_LEVEL, MUSIC_VOLUME, S5, S7, SCENES, SFX_VOLUME, SILENT_BEAT, VO, VO_VOLUME} from '../timeline';
import {personaCues} from '../lib/beat';

type VoEntry = {file: string; trimStartFrames: number; durationFrames: number; playbackRate: number};
const VO_CLIPS = (audio as {vo: Record<string, VoEntry | {error: string}>}).vo;
const SFX_FILES = (audio as {sfx: Record<string, {ok: boolean; file?: string; durationFrames?: number}>}).sfx;

const voIntervals = VO.flatMap((l) => {
  const c = VO_CLIPS[l.id];
  return c && 'file' in c ? [[l.at, l.at + c.durationFrames] as const] : [];
});

/** Music level at an absolute frame: muted on the silent beat, ducked under voice. */
export const musicVolume = (f: number) => {
  if (f >= SILENT_BEAT.from && f < SILENT_BEAT.to) return 0;
  let duck = 1;
  for (const [a, b] of voIntervals) {
    const d = interpolate(f, [a - DUCK_FADE, a, b, b + DUCK_FADE], [1, DUCK_LEVEL, DUCK_LEVEL, 1], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
    });
    duck = Math.min(duck, d);
  }
  return MUSIC_VOLUME * duck;
};

type Cue = {key: string; at: number; dur?: number; vol?: number};

const sfxCues = (): Cue[] => {
  const cues: Cue[] = [];
  // Whoosh on scene changes and whip pans.
  for (const s of [SCENES.pain, SCENES.turn, SCENES.people, SCENES.home, SCENES.native, SCENES.end]) cues.push({key: 'whoosh', at: s.from - 6});
  for (const c of personaCues()) if (c.whip) cues.push({key: 'whoosh', at: c.from - 6});
  // Pop on each capsule appearing; ticks under typing.
  for (const c of personaCues()) {
    cues.push({key: 'pop', at: c.boardAt});
    cues.push({key: 'ticks', at: c.typeAt, dur: c.typeDur, vol: 0.6});
  }
  // Thunk as each widget lands.
  S5.widgetLand.forEach((at) => cues.push({key: 'thunk', at}));
  // End card: pop on the logo, ticks under each "Try:" line.
  cues.push({key: 'pop', at: S7.logoAt});
  S7.tries.forEach((_, i) => cues.push({key: 'ticks', at: S7.tryStart + i * S7.trySlot, dur: 34, vol: 0.5}));
  return cues.filter((c) => c.at >= 0 && !(c.at >= SILENT_BEAT.from && c.at < SILENT_BEAT.to));
};

export const AudioMix: React.FC = () => (
  <>
    {music.exists && <Audio src={staticFile('audio/music.mp3')} volume={(f) => musicVolume(f)} />}
    {VO.map((l) => {
      const c = VO_CLIPS[l.id];
      if (!c || !('file' in c)) return null;
      return (
        <Sequence key={l.id} from={l.at} durationInFrames={c.durationFrames + 2} name={`vo:${l.id}`} layout="none">
          <Audio src={staticFile(c.file)} trimBefore={c.trimStartFrames} playbackRate={c.playbackRate} volume={VO_VOLUME} />
        </Sequence>
      );
    })}
    {sfxCues().map((c, i) => {
      const s = SFX_FILES[c.key];
      if (!s?.ok || !s.file) return null;
      return (
        <Sequence key={`${c.key}-${i}`} from={c.at} durationInFrames={c.dur ?? s.durationFrames ?? 30} name={`sfx:${c.key}`} layout="none">
          <Audio src={staticFile(s.file)} volume={SFX_VOLUME * (c.vol ?? 1)} />
        </Sequence>
      );
    })}
  </>
);

