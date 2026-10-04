import React from 'react';
import {AbsoluteFill, spring, useCurrentFrame} from 'remotion';
import {Bg, Center, FONT, Phone, SCREEN_W} from '../components/common';
import {HomeGrid, Wallpaper, iconPos} from '../components/Home';
import {BEAT, COLORS, FPS, S5, SCENES} from '../timeline';
import {Easing, lerp} from '../lib/motion';

const F = (abs: number) => abs - SCENES.home.from;

// 2x2-cell widgets laid out in two rows, centred on the screen.
const GAP = 14;
const W = (SCREEN_W - GAP * 3) / 2;
const H = 196;
const LABEL_H = 26;
const TOP = 170;
const slot = (i: number) => ({x: GAP + (i % 2) * (W + GAP), y: TOP + Math.floor(i / 2) * (H + LABEL_H + GAP)});

const WidgetGlyph: React.FC<{kind: string}> = ({kind}) => {
  const p = {fill: 'none', stroke: COLORS.blue, strokeWidth: 2.2, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const};
  return (
    <svg width={22} height={22} viewBox="0 0 24 24">
      {kind === 'checklist' && <path {...p} d="M5 12l4 4 10-10" />}
      {kind === 'timer' && (
        <>
          <circle {...p} cx="12" cy="13" r="8" />
          <path {...p} d="M12 13V9M9 2h6" />
        </>
      )}
      {kind === 'goal' && <path {...p} d="M12 3c3 4 6 7.5 6 11a6 6 0 0 1-12 0c0-3.5 3-7 6-11z" />}
      {kind === 'score' && (
        <>
          <circle {...p} cx="12" cy="12" r="9" />
          <path {...p} d="M5 6c3 3 3 9 0 12M19 6c-3 3-3 9 0 12" />
        </>
      )}
    </svg>
  );
};

/** HarmonyOS-style widget: light grey rounded card, icon circle, title and caption; "Harmoniser" label below. */
const Widget: React.FC<{i: number; frame: number; at: number; flood: number}> = ({i, frame, at, flood}) => {
  const w = S5.widgets[i];
  const s = slot(i);
  const fold = spring({frame: frame - at, fps: FPS, config: {damping: 13, mass: 0.7}, durationInFrames: 14});
  if (frame < at) return null;
  const big = w.kind === 'timer' || w.kind === 'goal';
  return (
    <div style={{position: 'absolute', left: s.x, top: s.y, width: W, perspective: 700}}>
      <div
        style={{
          height: H,
          borderRadius: 26,
          background: '#F3F4F7',
          boxShadow: '0 10px 24px rgba(27,34,54,0.12), 0 1px 2px rgba(27,34,54,0.06)',
          padding: 16,
          boxSizing: 'border-box',
          display: 'flex',
          flexDirection: 'column',
          transformOrigin: '50% 0%',
          transform: `rotateX(${-90 * (1 - fold)}deg)`,
          opacity: Math.min(1, fold * 3),
          filter: `grayscale(${1 - flood})`,
          fontFamily: FONT,
          position: 'relative',
        }}
      >
        <div style={{width: 42, height: 42, borderRadius: 21, background: COLORS.chipBg, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
          <WidgetGlyph kind={w.kind} />
        </div>
        <div style={{marginTop: 'auto', fontSize: 17, fontWeight: 700, color: COLORS.text}}>{w.title}</div>
        <div style={{marginTop: 2, fontSize: big ? 32 : 18, fontWeight: big ? 800 : 600, color: big ? COLORS.text : COLORS.secondary, letterSpacing: big ? -0.5 : 0}}>{w.caption}</div>
        {w.kind === 'goal' && (
          <div style={{position: 'absolute', right: 14, bottom: 16, width: 40, height: 40, borderRadius: 20, background: COLORS.blue, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
            <svg width={18} height={18} viewBox="0 0 24 24">
              <path d="M12 5v14M5 12h14" stroke="#fff" strokeWidth={2.6} strokeLinecap="round" />
            </svg>
          </div>
        )}
      </div>
      <div style={{height: LABEL_H, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', fontFamily: FONT, fontSize: 13, fontWeight: 600, color: COLORS.text, opacity: fold}}>
        {S5.widgetLabel}
      </div>
    </div>
  );
};

export const Scene5Home: React.FC = () => {
  const frame = useCurrentFrame();
  const pull = lerp(frame, [0, 16], [1.35, 1], Easing.out(Easing.cubic));
  const flood = lerp(frame, [F(S5.floodAt), F(S5.floodAt) + 12], [0, 1], Easing.out(Easing.quad));

  // Old icons drop off one row per beat.
  const gridState = (i: number) => {
    const {row, col} = iconPos(i);
    const at = F(S5.dropStart) + row * BEAT;
    const t = frame - at - col;
    if (t < 0) return {tag: 1};
    if (t > 22) return {hidden: true};
    const fall = Easing.in(Easing.quad)(Math.min(1, t / 20));
    return {dy: fall * 900, rot: (col - 1.5) * 14 * fall, opacity: 1 - fall * 0.6, tag: 1};
  };

  return (
    <Bg>
      {/* Colour floods back: a blue glow swells behind the phone */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(40% 55% at 50% 50%, rgba(47,91,255,${0.22 * flood}), rgba(47,91,255,0) 70%)`,
          transform: `scale(${0.8 + 0.4 * flood})`,
        }}
      />
      <Center style={{transform: `scale(${pull})`}}>
        <Phone>
          <div style={{position: 'absolute', inset: 0, filter: `grayscale(${0.75 * (1 - flood)})`}}>
            <Wallpaper />
          </div>
          <HomeGrid state={gridState} drain={0.7} />
          {S5.widgetLand.map((at, i) => (
            <Widget key={i} i={i} frame={frame} at={F(at) - 10} flood={flood} />
          ))}
        </Phone>
      </Center>
    </Bg>
  );
};
