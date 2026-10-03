/**
 * Pure shake detection for the accelerometer stream. No platform APIs, so it is unit-tested directly.
 *
 * One "shake event" is a debounced threshold crossing: motion counters move once per event.
 * A "burst" is a run of motion; its first event also reports "burstStart", which is what motion triggers
 * fire on (the schema says a motion trigger runs when the user starts moving). A burst ends after
 * BURST_END_MS without a high sample, so continuous shaking never refires the trigger.
 * Samples are never stored: only a bounded window of recent high-sample times is kept.
 */

export type MotionEventKind = 'shake' | 'burstStart';

export interface MotionEvent {
  kind: MotionEventKind;
  atMs: number;
}

/** Resting acceleration in m/s^2; a sample counts as motion when it deviates by at least SHAKE_DELTA. */
export const RESTING_MPS2: number = 9.81;
export const SHAKE_DELTA_MPS2: number = 6;
/** This many high samples within SHAKE_WINDOW_MS start a burst and count as one shake. */
export const SHAKE_SAMPLES: number = 3;
export const SHAKE_WINDOW_MS: number = 300;
/** Two counted shakes are at least this far apart. */
export const SHAKE_DEBOUNCE_MS: number = 150;
/** A burst ends after this long without a high sample. */
export const BURST_END_MS: number = 800;
/** Hard cap on remembered high-sample times, so work per sample stays bounded. */
const MAX_HIGH_SAMPLES: number = 32;

export function accelerationMagnitude(x: number, y: number, z: number): number {
  return Math.sqrt(x * x + y * y + z * z);
}

export class ShakeDetector {
  private high: number[] = [];
  private burst: boolean = false;
  private lastShake: number = -Infinity;
  private lastHigh: number = -Infinity;

  /** Feeds one sample; returns the events it produced, burstStart before that burst's first shake. */
  sample(x: number, y: number, z: number, atMs: number): MotionEvent[] {
    const out: MotionEvent[] = [];
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z) || !Number.isFinite(atMs)) {
      return out;
    }
    const high: boolean = Math.abs(accelerationMagnitude(x, y, z) - RESTING_MPS2) >= SHAKE_DELTA_MPS2;
    if (!high) {
      if (this.burst && atMs - this.lastHigh > BURST_END_MS) {
        this.endBurst();
      }
      return out;
    }
    this.lastHigh = atMs;
    this.high.push(atMs);
    while (this.high.length > 0 && atMs - this.high[0] > SHAKE_WINDOW_MS) {
      this.high.shift();
    }
    if (this.high.length > MAX_HIGH_SAMPLES) {
      this.high = this.high.slice(this.high.length - MAX_HIGH_SAMPLES);
    }
    if (this.high.length < SHAKE_SAMPLES) {
      return out;
    }
    if (!this.burst) {
      this.burst = true;
      out.push({ kind: 'burstStart', atMs: atMs });
    }
    if (atMs - this.lastShake >= SHAKE_DEBOUNCE_MS) {
      this.lastShake = atMs;
      out.push({ kind: 'shake', atMs: atMs });
    }
    return out;
  }

  /** Forgets the current burst, e.g. when the sensor subscription stops. */
  reset(): void {
    this.endBurst();
    this.lastShake = -Infinity;
  }

  private endBurst(): void {
    this.burst = false;
    this.high = [];
    this.lastHigh = -Infinity;
  }
}
