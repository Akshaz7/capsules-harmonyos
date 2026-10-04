import audio from '../generated/audio-manifest.json';
import {vo} from '../timeline';

type Clip = {playbackRate: number; words: {word: string; frame: number}[]};
const CLIPS = (audio as unknown as {vo: Record<string, Clip>}).vo;

/** Absolute frame where the n-th word of a voice line is spoken (falls back to the line start). */
export const wordAt = (id: string, n: number): number => {
  const line = vo(id);
  const c = CLIPS[id];
  const w = c?.words?.[n];
  if (!w) return line.at;
  return line.at + Math.round(w.frame / (c.playbackRate || 1));
};
