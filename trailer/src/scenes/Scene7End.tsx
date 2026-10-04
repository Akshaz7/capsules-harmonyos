import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Bg, FONT, Logo} from '../components/common';
import {COLORS, S7, SCENES} from '../timeline';
import {caretOn, lerp, pop, popStyle, slide, typed} from '../lib/motion';

const F = (abs: number) => abs - SCENES.end.from;

/** Each "Try:" line types out, holds, then clears for the next. */
const TryBar: React.FC<{frame: number}> = ({frame}) => {
  const start = F(S7.tryStart);
  const slot = S7.trySlot;
  const i = Math.min(S7.tries.length - 1, Math.max(0, Math.floor((frame - start) / slot)));
  const line = S7.tries[i];
  const text = typed(line, frame, start + i * slot);
  return (
    <div
      style={{
        width: 760,
        height: 80,
        borderRadius: 40,
        background: '#FFFFFF',
        boxShadow: '0 18px 44px rgba(27,34,54,0.12)',
        display: 'flex',
        alignItems: 'center',
        padding: '0 32px',
        boxSizing: 'border-box',
        fontSize: 30,
        fontWeight: 600,
        color: COLORS.text,
        ...popStyle(frame, start - 4),
      }}
    >
      {text}
      <span style={{display: 'inline-block', width: 3, height: 34, marginLeft: 3, background: COLORS.blue, opacity: caretOn(frame) ? 1 : 0}} />
    </div>
  );
};

export const Scene7End: React.FC = () => {
  const frame = useCurrentFrame();
  const logoAt = F(S7.logoAt);
  const tiles = [0, 3, 6].map((d) => pop(frame, logoAt + 4 + d).p) as [number, number, number];
  const tagWords = [
    ...S7.taglineDark.split(' ').map((w) => ({w, c: COLORS.text})),
    ...S7.taglineBlue.split(' ').map((w) => ({w, c: COLORS.blue})),
  ];
  const tagAt = F(S7.taglineAt);
  const built = slide(frame, F(S7.builtAt), 12);
  const lift = slide(frame, F(S7.tryStart) - 10, 14);
  // The home screen shrinks into the glow.
  const shrink = lerp(frame, [0, 12], [1, 0]);
  return (
    <Bg>
      {shrink > 0 && (
        <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
          <div style={{width: 430, height: 930, borderRadius: 64, background: '#11141C', transform: `translateY(${-400 * (1 - shrink)}px) scale(${shrink})`, opacity: shrink}} />
        </AbsoluteFill>
      )}
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', flexDirection: 'column', transform: `translateY(${-110 * lift}px)`}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 34, ...popStyle(frame, logoAt)}}>
          <Logo size={140} tilesIn={tiles} />
          <div style={{fontFamily: FONT, fontSize: 110, fontWeight: 800, letterSpacing: -2.5, color: COLORS.text}}>Harmoniser</div>
        </div>
        <div style={{display: 'flex', gap: 16, marginTop: 40, fontSize: 56, fontWeight: 800, letterSpacing: -0.8}}>
          {tagWords.map(({w, c}, i) => (
            <span key={i} style={{color: c, ...popStyle(frame, tagAt + i * 5)}}>
              {w}
            </span>
          ))}
        </div>
        <div style={{marginTop: 26, fontSize: 56, fontWeight: 800, color: COLORS.secondary, opacity: built, transform: `translateY(${40 * (1 - built)}px)`, display: 'flex', alignItems: 'center', gap: 18}}>
          <span>{S7.built}</span>
        </div>
        <div style={{marginTop: 50, height: 80}}>{frame >= F(S7.tryStart) - 4 && <TryBar frame={frame} />}</div>
      </AbsoluteFill>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 60, display: 'flex', justifyContent: 'center', gap: 60, fontSize: 24, fontWeight: 600, color: COLORS.text, ...popStyle(frame, F(S7.urlsAt))}}>
        {S7.urls.map((u) => (
          <span key={u}>{u}</span>
        ))}
      </div>
      <div style={{position: 'absolute', right: 40, bottom: 24, fontSize: 18, fontWeight: 600, color: COLORS.secondary, opacity: lerp(frame, [F(S7.urlsAt), F(S7.urlsAt) + 10], [0, 1])}}>
        {S7.disclaimer}
      </div>
    </Bg>
  );
};
