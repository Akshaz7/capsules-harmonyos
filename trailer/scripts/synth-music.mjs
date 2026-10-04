// Stand-in music: a 65 s, 120 BPM minimal tech keynote bed synthesised from scratch.
// Used because the ElevenLabs Music API needs a paid plan. `npm run audio` replaces it
// with the ElevenLabs track once the plan allows it.
// Output: public/audio/music.mp3 (via Remotion's bundled ffmpeg).
import {writeFileSync, unlinkSync, mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const SR = 44100;
const DUR = 65;
const N = SR * DUR;
const BEAT = 0.5;
const DROP = 13; // main beat lands here (video frame 390)
const OUTRO = 58; // big hit (video frame 1740)

// Seeded noise so the track is reproducible.
let seed = 1234567;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

const L = new Float32Array(N);
const R = new Float32Array(N);
const send = new Float32Array(N); // reverb send (mono)
const dly = new Float32Array(N); // delay send (mono)

const put = (buf, t0, sig, gain = 1) => {
  const s0 = Math.round(t0 * SR);
  for (let i = 0; i < sig.length; i++) {
    const j = s0 + i;
    if (j >= 0 && j < N) buf[j] += sig[i] * gain;
  }
};
const putStereo = (t0, sig, gain, pan = 0, rev = 0, del = 0) => {
  const gl = gain * Math.cos(((pan + 1) * Math.PI) / 4);
  const gr = gain * Math.sin(((pan + 1) * Math.PI) / 4);
  put(L, t0, sig, gl);
  put(R, t0, sig, gr);
  if (rev) put(send, t0, sig, gain * rev);
  if (del) put(dly, t0, sig, gain * del);
};

const len = (s) => Math.round(s * SR);

// ---------- One-shots ----------
const kick = (() => {
  const n = len(0.42);
  const out = new Float32Array(n);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = 44 + 90 * Math.exp(-t * 28);
    ph += (2 * Math.PI * f) / SR;
    const body = Math.sin(ph) * Math.exp(-t * 6.5);
    const click = t < 0.004 ? rnd() * (1 - t / 0.004) * 0.5 : 0;
    out[i] = Math.tanh((body + click) * 1.6);
  }
  return out;
})();

const filteredNoise = (dur, decay, hp, lp) => {
  const n = len(dur);
  const out = new Float32Array(n);
  let lpS = 0;
  let hpPrev = 0;
  let hpS = 0;
  const aL = Math.exp((-2 * Math.PI * lp) / SR);
  const aH = Math.exp((-2 * Math.PI * hp) / SR);
  for (let i = 0; i < n; i++) {
    const x = rnd();
    lpS = (1 - aL) * x + aL * lpS;
    hpS = aH * (hpS + lpS - hpPrev);
    hpPrev = lpS;
    out[i] = hpS * decay(i / SR);
  }
  return out;
};

const clap = (() => {
  const env = (t) => {
    const bursts = [0, 0.011, 0.022].reduce((a, o) => a + (t >= o ? Math.exp(-(t - o) * 260) : 0), 0);
    return bursts * 0.8 + (t > 0.022 ? Math.exp(-(t - 0.022) * 16) * 0.55 : 0);
  };
  const out = filteredNoise(0.3, env, 900, 5200);
  return out.map((v) => v * 2.4);
})();

const hat = filteredNoise(0.06, (t) => Math.exp(-t * 90), 7000, 16000).map((v) => v * 2.2);
const openHat = filteredNoise(0.25, (t) => Math.exp(-t * 14), 6500, 15000).map((v) => v * 1.4);

const crash = filteredNoise(2.6, (t) => Math.exp(-t * 1.6), 3000, 14000).map((v) => v * 1.6);

/** Glassy pluck: bell-ish partials with a fast decay. */
const pluck = (f, dur = 0.6, bright = 1) => {
  const n = len(dur);
  const out = new Float32Array(n);
  const parts = [
    [1, 1, 7],
    [2.0, 0.35 * bright, 11],
    [3.01, 0.18 * bright, 16],
    [4.2, 0.08 * bright, 22],
    [1.003, 0.5, 7.5],
  ];
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const att = Math.min(1, t / 0.003);
    let v = 0;
    for (const [m, a, d] of parts) v += a * Math.sin(2 * Math.PI * f * m * t) * Math.exp(-t * d);
    out[i] = v * att * 0.45;
  }
  return out;
};

/** Soft pad: a few harmonics per detuned voice, slow attack. */
const pad = (freqs, dur, att = 0.6, rel = 1.2) => {
  const n = len(dur + rel);
  const out = new Float32Array(n);
  for (const f of freqs)
    for (const det of [-0.004, 0.004]) {
      const ff = f * (1 + det);
      for (let h = 1; h <= 5; h++) {
        const a = 1 / (h * h * 1.6);
        const w = (2 * Math.PI * ff * h) / SR;
        for (let i = 0; i < n; i++) out[i] += a * Math.sin(w * i);
      }
    }
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const e = Math.min(1, t / att) * (t > dur ? Math.max(0, 1 - (t - dur) / rel) : 1);
    out[i] *= e * (0.12 / freqs.length);
  }
  return out;
};

/** Sub bass note: sine + a touch of 2nd harmonic. */
const sub = (f, dur) => {
  const n = len(dur);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const e = Math.min(1, t / 0.006) * Math.min(1, (dur - t) / 0.03);
    out[i] = (Math.sin(2 * Math.PI * f * t) + 0.18 * Math.sin(4 * Math.PI * f * t)) * e * 0.8;
  }
  return out;
};

/** Rising filtered-noise riser. */
const riser = (dur) => {
  const n = len(dur);
  const out = new Float32Array(n);
  let s = 0;
  for (let i = 0; i < n; i++) {
    const p = i / n;
    const cutoff = 300 + 9000 * p * p;
    const a = Math.exp((-2 * Math.PI * cutoff) / SR);
    s = (1 - a) * rnd() + a * s;
    out[i] = s * p * p * 1.8;
  }
  return out;
};

// ---------- Harmony: F – Dm – Bb – C, one chord per bar, bars aligned to the drop ----------
const CHORDS = [
  {root: 87.31, tones: [349.23, 440.0, 523.25, 698.46]}, // F
  {root: 73.42, tones: [293.66, 349.23, 440.0, 587.33]}, // Dm
  {root: 58.27, tones: [233.08, 293.66, 349.23, 466.16]}, // Bb
  {root: 65.41, tones: [261.63, 329.63, 392.0, 523.25]}, // C
];
const chordAt = (t) => CHORDS[(((Math.floor((t - DROP) / 2) % 4) + 4) % 4)];
const ARP = [0, 2, 1, 3, 2, 1, 3, 2];

const inRange = (t, a, b) => t >= a - 1e-6 && t < b - 1e-6;
const section = (t) =>
  t < 8 ? 'intro' : t < 12.5 ? 'tension' : t < 13 ? 'gap' : t < 47 ? 'groove' : t < 52 ? 'lift' : t < OUTRO ? 'native' : 'outro';

const kickTimes = [];

// ---------- Arrange on an eighth-note grid ----------
for (let step = 0; step < DUR / (BEAT / 2); step++) {
  const t = step * (BEAT / 2);
  const sec = section(t);
  const beatIdx = Math.round(t / BEAT);
  const onBeat = Math.abs(t / BEAT - beatIdx) < 1e-6;
  const ch = chordAt(t);
  const barPos = ((((t - DROP) % 2) + 2) % 2) / BEAT; // 0..4 beats within the bar
  const eighth = Math.round(barPos * 2) % 8;

  // Kick
  if (onBeat) {
    if (sec === 'intro' && t >= 2 && beatIdx % 2 === 0) {
      putStereo(t, kick, 0.45);
      kickTimes.push(t);
    }
    if (sec === 'tension' || sec === 'groove' || sec === 'native') {
      putStereo(t, kick, sec === 'tension' ? 0.7 : 0.95);
      kickTimes.push(t);
    }
  }
  // Clap on 2 and 4
  if (onBeat && (sec === 'groove' || sec === 'native') && (Math.round(barPos) === 1 || Math.round(barPos) === 3))
    putStereo(t, clap, sec === 'native' ? 0.38 : 0.5, 0.05, 0.25);
  // Hats
  if (!onBeat && (sec === 'groove' || sec === 'native')) putStereo(t, hat, 0.22, 0.3);
  if (sec === 'groove' && t >= 29 && !onBeat && eighth % 4 === 3) putStereo(t, openHat, 0.16, 0.3);
  // Sub: eighth-note pulse on the root, sidechained by the kick (applied later)
  if ((sec === 'groove' || sec === 'native') && !onBeat) putStereo(t, sub(ch.root, BEAT / 2 - 0.01), 0.55);
  if ((sec === 'groove' || sec === 'native') && onBeat) putStereo(t, sub(ch.root, BEAT / 2 - 0.01), 0.35);
  // Plucks
  const tone = ch.tones[ARP[eighth]];
  if (sec === 'intro' && onBeat) putStereo(t, pluck(tone, 0.6, 0.4), 0.18 + 0.12 * (t / 8), eighth % 2 ? 0.4 : -0.4, 0.4, 0.35);
  if (sec === 'tension') putStereo(t, pluck(tone, 0.5, 0.7), 0.28, eighth % 2 ? 0.4 : -0.4, 0.35, 0.3);
  if (sec === 'groove' || sec === 'lift' || sec === 'native')
    putStereo(t, pluck(tone * (t >= 31 && t < 47 && eighth % 4 === 2 ? 2 : 1), 0.55, 1), sec === 'native' ? 0.3 : 0.34, eighth % 2 ? 0.45 : -0.45, 0.3, 0.3);
}

// 16th hats in the tension build
for (let t = 8; t < 12.5; t += BEAT / 4) putStereo(t, hat, 0.1 + 0.12 * ((t - 8) / 4.5), -0.25);
// Snare (clap) roll accelerating into the gap, and into the end of the lift
const roll = (a, b, gain) => {
  let t = a;
  let step = BEAT;
  while (t < b - 0.01) {
    putStereo(t, clap, gain * (0.4 + 0.6 * ((t - a) / (b - a))), 0, 0.2);
    t += step;
    if (t > a + (b - a) * 0.4) step = BEAT / 2;
    if (t > a + (b - a) * 0.7) step = BEAT / 4;
  }
};
roll(10, 12.5, 0.45);
roll(50, 52, 0.4);
// Fills every 8 bars in the groove
for (let bar = 21; bar < 47; bar += 16) roll(bar - 0.5, bar, 0.35);

// Risers
putStereo(4.5, riser(8), 0.35, 0, 0.3); // ends at 12.5, cut hard
putStereo(47, riser(5), 0.4, 0, 0.3);

// Pads: quiet through intro/groove, cleaner later
for (let b = DROP - 14; b < OUTRO; b += 2) {
  if (b + 2 <= 0) continue;
  const sec = section(Math.max(0, b));
  if (sec === 'gap') continue;
  const ch = chordAt(b + 0.01);
  const g = sec === 'intro' ? 0.6 : sec === 'tension' ? 0.8 : sec === 'native' ? 0.55 : 1;
  putStereo(Math.max(0, b), pad(ch.tones.slice(0, 3).map((f) => f / 2), 2, 0.4, 0.5), g, 0, 0.5);
}

// Impacts: the drop and the outro hit
const impact = (t, g) => {
  putStereo(t, kick, 1.1 * g);
  putStereo(t, crash, 0.5 * g, 0, 0.6);
  putStereo(t, sub(87.31, 1.6).map((v, i) => v * Math.exp(-(i / SR) * 1.8)), 0.8 * g);
  kickTimes.push(t);
};
impact(DROP, 1);
impact(OUTRO, 1.15);
// Outro: full F chord rings out
putStereo(OUTRO, pad([174.61, 220, 261.63, 349.23], 2.5, 0.02, 4), 1.6, 0, 0.8);
for (const [i, f] of [349.23, 440, 523.25, 698.46].entries()) putStereo(OUTRO + i * 0.02, pluck(f, 2.5, 1), 0.35, i % 2 ? 0.4 : -0.4, 0.8, 0.4);

// Silence the gap (12.5–13.0) completely before effects so the drop hits from nothing.
const gapA = Math.round(12.5 * SR);
const gapB = Math.round(13 * SR);
for (let i = gapA; i < gapB; i++) {
  L[i] = R[i] = send[i] = dly[i] = 0;
}

// ---------- Sidechain: duck everything but kick a little after each kick ----------
kickTimes.sort((a, b) => a - b);
let k = 0;
for (let i = 0; i < N; i++) {
  const t = i / SR;
  while (k + 1 < kickTimes.length && kickTimes[k + 1] <= t) k++;
  const since = kickTimes[k] !== undefined && kickTimes[k] <= t ? t - kickTimes[k] : 10;
  const duck = 1 - 0.35 * Math.exp(-since * 14) * (since > 0.012 ? 1 : 0);
  L[i] *= duck;
  R[i] *= duck;
}

// ---------- Effects: ping-pong delay (3/16) and a small Schroeder reverb ----------
const dT = len(0.375);
const dl = new Float32Array(N);
const dr = new Float32Array(N);
for (let i = 0; i < N; i++) {
  const inL = dly[i];
  dl[i] = inL + (i >= dT ? dr[i - dT] * 0.42 : 0);
  dr[i] = i >= dT ? dl[i - dT] * 0.42 : 0;
}
for (let i = 0; i < N; i++) {
  L[i] += (i >= dT ? dl[i - dT] : 0) * 0.35;
  R[i] += dr[i] * 0.35;
  send[i] += (dl[i] + dr[i]) * 0.1;
}

const comb = (input, d, fb, damp) => {
  const out = new Float32Array(N);
  let lp = 0;
  for (let i = 0; i < N; i++) {
    const y = i >= d ? out[i - d] : 0;
    lp = y * (1 - damp) + lp * damp;
    out[i] = input[i] + lp * fb;
  }
  return out;
};
const allpass = (input, d, g) => {
  const out = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const xd = i >= d ? input[i - d] : 0;
    const yd = i >= d ? out[i - d] : 0;
    out[i] = -g * input[i] + xd + g * yd;
  }
  return out;
};
const revOut = (offs) => {
  const combs = [1116, 1188, 1277, 1356].map((d) => comb(send, d + offs, 0.84, 0.3));
  const sum = new Float32Array(N);
  for (const c of combs) for (let i = 0; i < N; i++) sum[i] += c[i] * 0.25;
  return allpass(allpass(sum, 556 + offs, 0.5), 441 + offs, 0.5);
};
const rvL = revOut(0);
const rvR = revOut(23);
for (let i = 0; i < N; i++) {
  L[i] += rvL[i] * 0.22;
  R[i] += rvR[i] * 0.22;
}

// ---------- Master: high-pass DC, fade the end, normalise, soft limit ----------
const fadeA = Math.round(62 * SR);
let peak = 0;
for (const ch of [L, R]) {
  let prevX = 0;
  let prevY = 0;
  for (let i = 0; i < N; i++) {
    const y = 0.9995 * (prevY + ch[i] - prevX);
    prevX = ch[i];
    prevY = y;
    ch[i] = y * (i > fadeA ? Math.max(0, 1 - (i - fadeA) / (N - fadeA)) : 1);
    peak = Math.max(peak, Math.abs(ch[i]));
  }
}
const norm = 1.15 / peak;
const pcm = Buffer.alloc(N * 4);
for (let i = 0; i < N; i++) {
  for (const [c, ch] of [L, R].entries()) {
    const v = Math.tanh(ch[i] * norm) * 0.89;
    pcm.writeInt16LE(Math.round(v * 32767), i * 4 + c * 2);
  }
}

const header = Buffer.alloc(44);
header.write('RIFF', 0);
header.writeUInt32LE(36 + pcm.length, 4);
header.write('WAVE', 8);
header.write('fmt ', 12);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(SR, 24);
header.writeUInt32LE(SR * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.writeUInt32LE(pcm.length, 40);
header.write('data', 36);

mkdirSync(join(root, 'out'), {recursive: true});
const wav = join(root, 'out', 'music.wav');
writeFileSync(wav, Buffer.concat([header, pcm]));
execFileSync('npx', ['remotion', 'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', wav, '-codec:a', 'libmp3lame', '-b:a', '192k', join(root, 'public', 'audio', 'music.mp3')], {cwd: root, stdio: 'inherit'});
unlinkSync(wav);
console.log('wrote public/audio/music.mp3');
