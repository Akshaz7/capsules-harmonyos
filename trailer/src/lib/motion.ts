import {Easing, interpolate, spring} from 'remotion';
import {FPS} from '../timeline';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** Pop: spring damping 14, mass 0.8, ~12 frames. Returns {scale, opacity, y, p}. */
export const pop = (frame: number, at: number) => {
  const p = spring({frame: frame - at, fps: FPS, config: {damping: 14, mass: 0.8}, durationInFrames: 12});
  const o = interpolate(frame - at, [0, 6], [0, 1], clamp);
  return {p, scale: 0.92 + 0.08 * p, opacity: o, y: 24 * (1 - p)};
};

export const popStyle = (frame: number, at: number): React.CSSProperties => {
  const {scale, opacity, y} = pop(frame, at);
  return {opacity, transform: `translateY(${y}px) scale(${scale})`};
};

/** Slide: spring damping 200, ~10 frames. Returns 0..1. */
export const slide = (frame: number, at: number, dur = 10) =>
  spring({frame: frame - at, fps: FPS, config: {damping: 200}, durationInFrames: dur});

/** Count-up: 18 frames, ease-out. */
export const countUp = (frame: number, at: number, from: number, to: number, dur = 18) =>
  interpolate(frame - at, [0, dur], [from, to], {...clamp, easing: Easing.out(Easing.cubic)});

/** Typing: chars visible. 24 frames for short prompts, 36 for long. */
export const typed = (text: string, frame: number, at: number, dur?: number) => {
  const d = dur ?? (text.length <= 24 ? 24 : 36);
  const n = Math.floor(interpolate(frame - at, [0, d], [0, text.length], clamp));
  return text.slice(0, n);
};
export const typingDuration = (text: string) => (text.length <= 24 ? 24 : 36);

/** Caret blinks every 15 frames. */
export const caretOn = (frame: number) => Math.floor(frame / 15) % 2 === 0;

/** Tap: dot scale 0.6 -> 1 and fade over 10 frames. */
export const tap = (frame: number, at: number) => {
  const t = frame - at;
  if (t < 0 || t > 10) return null;
  return {scale: interpolate(t, [0, 10], [0.6, 1]), opacity: interpolate(t, [0, 3, 10], [0, 1, 0])};
};

/** Pressed button dips to 0.96 and back around the tap. */
export const pressScale = (frame: number, at: number) =>
  interpolate(frame - at, [-1, 2, 6], [1, 0.96, 1], clamp);

export const lerp = (frame: number, input: number[], output: number[], easing?: (t: number) => number) =>
  interpolate(frame, input, output, {...clamp, easing});

export {Easing};
