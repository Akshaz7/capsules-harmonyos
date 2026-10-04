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

/** The app's widget card: white, tinted icon tile + title + status dot, value and pill actions. */
const Widget: React.FC<{i: number; frame: number; at: number; flood: number}> = ({i, frame, at, flood}) => {
  const w = S5.widgets[i];
  const s = slot(i);
  const fold = spring({frame: frame - at, fps: FPS, config: {damping: 13, mass: 0.7}, durationInFrames: 14});
  if (frame < at) return null;
  const dot = w.kind === 'checklist' ? '#12A150' : '#2F5BFF';
  const row = 'rows' in w && w.rows ? w.rows[0] : '';
  const more = 'more' in w ? w.more : '';
  const label = 'label' in w ? w.label : '';
  const action = 'action' in w ? w.action : '';
  const action2 = 'action2' in w ? w.action2 : '';
  return (
    <div style={{position: 'absolute', left: s.x, top: s.y, width: W, perspective: 700}}>
      <div
        style={{
          height: H,
          borderRadius: 26,
          background: '#FFFFFF',
          boxShadow: '0 10px 26px rgba(27,34,54,0.14), 0 1px 2px rgba(27,34,54,0.06)',
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
        <div style={{display: 'flex', alignItems: 'center', gap: 9}}>
          <div style={{width: 34, height: 34, borderRadius: 12, background: '#EEF3FF', display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
            <WidgetGlyph kind={w.kind} />
          </div>
          <div style={{flex: 1, fontSize: 17, fontWeight: 700, color: COLORS.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}}>{w.title}</div>
          <div style={{width: 9, height: 9, borderRadius: 5, background: dot}} />
        </div>
        {w.kind === 'checklist' ? (
          <>
            <div style={{marginTop: 12, fontSize: 15, fontWeight: 600, color: COLORS.secondary}}>{w.caption}</div>
            <div style={{marginTop: 10, display: 'flex', alignItems: 'center', gap: 9}}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="9" stroke="#B9C0CE" strokeWidth="2" />
              </svg>
              <span style={{fontSize: 15, fontWeight: 600, color: COLORS.text}}>{row}</span>
            </div>
            <div style={{marginTop: 'auto', fontSize: 13, fontWeight: 600, color: COLORS.secondary}}>{more}</div>
          </>
        ) : (
          <>
            <div style={{marginTop: 14, fontSize: 13, fontWeight: 600, color: COLORS.secondary}}>{label}</div>
            <div style={{fontSize: 34, fontWeight: 800, letterSpacing: -0.5, color: COLORS.text}}>{w.caption}</div>
            <div style={{marginTop: 'auto', display: 'flex', gap: 10}}>
              <div style={{flex: 1, height: 44, borderRadius: 22, background: COLORS.blue, color: '#FFFFFF', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 700}}>{action}</div>
              <div style={{flex: 1, height: 44, borderRadius: 22, background: '#DCE5FF', color: '#2A47C7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 700}}>{action2}</div>
            </div>
          </>
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
