import React from 'react';
import {AbsoluteFill, spring, useCurrentFrame} from 'remotion';
import {Bg, FONT, PHONE_H, PHONE_W, Phone, SCREEN_INSET} from '../components/common';
import {AppIcon, HomeGrid, ICON, ICONS, Wallpaper, iconIndex, iconPos} from '../components/Home';
import {BEAT, FPS, S1, SCENES} from '../timeline';
import {Easing, lerp, slide} from '../lib/motion';

const F = (abs: number) => abs - SCENES.problem.from;

// Stage geometry: phone centred in the 1920x1080 frame.
const PHONE_X = (1920 - PHONE_W) / 2;
const PHONE_Y = (1080 - PHONE_H) / 2;
const SCREEN_X = PHONE_X + SCREEN_INSET;
const SCREEN_Y = PHONE_Y + SCREEN_INSET;

// Lifted icon groups: where each icon floats beside the phone (stage centre coords).
const LIFT_SIZE = 150;
const GROUPS = [
  {at: S1.timersAt, until: S1.tipsAt, names: S1.timerIcons, spots: [[470, 250], [360, 520], [490, 790]], side: 1},
  {at: S1.tipsAt, until: S1.packingAt, names: S1.tipIcons, spots: [[1440, 340], [1540, 690]], side: -1},
  {at: S1.packingAt, until: S1.onceAt, names: [S1.packingIcon], spots: [[460, 520]], side: 1},
];

// Big type strings, each flipping in at its cue.
const TYPE = [
  {at: S1.timersAt, text: S1.bigType.timers},
  {at: S1.tipsAt, text: S1.bigType.tips},
  {at: S1.packingAt, text: S1.bigType.packing},
  {at: S1.onceAt, text: S1.bigType.once},
];
const CELLS = Math.max(...TYPE.map((t) => t.text.length));
const pad = (s: string) => {
  const left = Math.floor((CELLS - s.length) / 2);
  return ' '.repeat(left) + s + ' '.repeat(CELLS - s.length - left);
};

/** Split-flap board behind the phone: each cell flips from the previous string to the next. */
const SplitFlap: React.FC<{frame: number}> = ({frame}) => {
  const size = 160;
  const idx = TYPE.reduce((a, t, i) => (frame >= F(t.at) ? i : a), -1);
  if (idx < 0) return null;
  const cur = pad(TYPE[idx].text);
  const prev = idx > 0 ? pad(TYPE[idx - 1].text) : ' '.repeat(CELLS);
  const at = F(TYPE[idx].at);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', perspective: 1200}}>
      <div style={{display: 'flex', gap: 6}}>
        {cur.split('').map((ch, i) => {
          const start = at + i * 0.8;
          const p = lerp(frame, [start, start + 6], [0, 1], Easing.inOut(Easing.quad));
          // First half: old character folds away (0 → 90°). Second half: new one folds in (−90° → 0).
          const angle = p < 0.5 ? p * 180 : -90 + (p - 0.5) * 180;
          const c = p < 0.5 ? prev[i] : ch;
          return (
            <div
              key={i}
              style={{
                width: size * 0.62,
                height: size * 1.2,
                borderRadius: 14,
                background: c === ' ' ? 'rgba(234,238,248,0.5)' : '#EEF2FB',
                boxShadow: 'inset 0 -2px 0 rgba(27,34,54,0.04)',
                backgroundImage: 'linear-gradient(180deg, transparent 49.5%, rgba(255,255,255,0.9) 49.5%, rgba(255,255,255,0.9) 50.5%, transparent 50.5%)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontFamily: FONT,
                fontWeight: 800,
                fontSize: size,
                color: '#B4C2EA',
                transform: `rotateX(${angle}deg)`,
              }}
            >
              {c === ' ' ? ' ' : c}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

export const Scene1Problem: React.FC = () => {
  const frame = useCurrentFrame();

  // Camera starts tight on the screen and pulls back to reveal the phone.
  const cam = lerp(frame, [F(S1.pullBackAt), F(S1.pullBackAt) + 30], [1.6, 1], Easing.inOut(Easing.cubic));

  // Opened once: tags stamp on every icon at the same moment; colour drains to ~70%.
  const onceAt = F(S1.onceAt);
  const stamp = spring({frame: frame - onceAt, fps: FPS, config: {damping: 9, mass: 0.6}, durationInFrames: 14});
  const tag = frame >= onceAt ? 1.8 - 0.8 * stamp : 0;
  const drain = lerp(frame, [onceAt, onceAt + 8], [0, 0.7]);
  const thump = frame >= onceAt ? 1 + 0.02 * Math.sin(lerp(frame, [onceAt, onceAt + 8], [0, Math.PI])) : 1;

  /** How far icon i is lifted out (0..1), and its group/slot. */
  const lift = (i: number) => {
    for (const g of GROUPS) {
      const k = g.names.indexOf(ICONS[i].name);
      if (k >= 0) return {t: Math.max(0, slide(frame, F(g.at), 14) - slide(frame, F(g.until), 12)), g, k};
    }
    return null;
  };

  const gridState = (i: number) => {
    const p = iconPos(i);
    // Two rows land per beat.
    const land = Math.floor(p.row / 2) * BEAT + p.col * 1.5 + (p.row % 2) * 4;
    if (frame < land) return {hidden: true};
    const s = spring({frame: frame - land, fps: FPS, config: {damping: 12, mass: 0.7}, durationInFrames: 14});
    const l = lift(i);
    return {dy: -180 * (1 - s), opacity: Math.min(1, (frame - land) / 3) * (l && l.t > 0.02 ? 0 : 1), tag};
  };

  return (
    <Bg white>
      <SplitFlap frame={frame} />
      <AbsoluteFill style={{transform: `scale(${cam * thump})`, transformOrigin: '960px 531px'}}>
        <div style={{position: 'absolute', left: PHONE_X, top: PHONE_Y}}>
          <Phone>
            <Wallpaper />
            <HomeGrid state={gridState} drain={drain} />
          </Phone>
        </div>
        {/* Lifted icons float out of the phone in 3D */}
        {GROUPS.flatMap((g) =>
          g.names.map((name, k) => {
            const i = iconIndex(name);
            const l = lift(i);
            if (!l || l.t <= 0.02) return null;
            const p = iconPos(i);
            const sx = SCREEN_X + p.x + ICON / 2;
            const sy = SCREEN_Y + p.y + ICON / 2;
            const [tx, ty] = g.spots[k];
            const t = l.t;
            const size = ICON + (LIFT_SIZE - ICON) * t;
            const bob = Math.sin((frame + k * 9) / 9) * 6 * t;
            return (
              <div
                key={name}
                style={{
                  position: 'absolute',
                  left: sx + (tx - sx) * t - size / 2,
                  top: sy + (ty - sy) * t - size / 2 + bob,
                  transform: `perspective(900px) rotateY(${g.side * 22 * t}deg) rotateX(${8 * t}deg) translateZ(${60 * t}px)`,
                  filter: `drop-shadow(0 ${30 * t}px ${40 * t}px rgba(27,34,54,${0.28 * t}))`,
                }}
              >
                <AppIcon i={i} size={size} labelSize={13 + 13 * t} />
              </div>
            );
          }),
        )}
      </AbsoluteFill>
    </Bg>
  );
};
