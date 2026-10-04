import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {loadFont} from '@remotion/google-fonts/Manrope';
import {COLORS} from '../timeline';
import {tap} from '../lib/motion';

export const {fontFamily: MANROPE} = loadFont('normal', {weights: ['400', '500', '600', '700', '800'], subsets: ['latin', 'latin-ext']});
export const FONT = `${MANROPE}, system-ui, sans-serif`;

/** Light background with one blue glow fading out by a third of the height. */
export const Bg: React.FC<{children?: React.ReactNode; white?: boolean}> = ({children, white}) => (
  <AbsoluteFill style={{background: white ? '#FFFFFF' : COLORS.bg, fontFamily: FONT, color: COLORS.text}}>
    {!white && (
      <AbsoluteFill style={{background: `linear-gradient(180deg, ${COLORS.glow} 0%, rgba(220,229,255,0) 33%)`}} />
    )}
    {children}
  </AbsoluteFill>
);

export const PHONE_W = 430;
export const PHONE_H = 930;
export const SCREEN_INSET = 12;
export const SCREEN_W = PHONE_W - SCREEN_INSET * 2; // 406
export const SCREEN_H = PHONE_H - SCREEN_INSET * 2; // 906

/** Plain rounded phone, soft shadow, no brand marks. Children fill the screen (406x906). */
export const Phone: React.FC<{children?: React.ReactNode; style?: React.CSSProperties; screenBg?: string}> = ({
  children,
  style,
  screenBg = COLORS.bg,
}) => (
  <div
    style={{
      width: PHONE_W,
      height: PHONE_H,
      borderRadius: 64,
      background: '#11141C',
      padding: SCREEN_INSET,
      boxSizing: 'border-box',
      boxShadow: '0 40px 90px rgba(27,34,54,0.22), 0 8px 24px rgba(27,34,54,0.12)',
      position: 'relative',
      ...style,
    }}
  >
    <div
      style={{
        width: SCREEN_W,
        height: SCREEN_H,
        borderRadius: 52,
        overflow: 'hidden',
        position: 'relative',
        background: screenBg,
      }}
    >
      {children}
    </div>
  </div>
);

/** Centres a phone in the frame. */
export const Center: React.FC<{children: React.ReactNode; style?: React.CSSProperties}> = ({children, style}) => (
  <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', ...style}}>{children}</AbsoluteFill>
);

/** Renders a 390x844 board scaled to the phone screen width. */
export const BoardFit: React.FC<{children: React.ReactNode}> = ({children}) => {
  const s = SCREEN_W / 390;
  return (
    <div style={{position: 'absolute', inset: 0, background: 'linear-gradient(180deg, #DCE5FF 0px, #EEF2FB 200px, #F2F4F9 360px)'}}>
      <div style={{position: 'absolute', left: 0, top: 18, width: 390, height: 844, transform: `scale(${s})`, transformOrigin: 'top left'}}>
        {children}
      </div>
    </div>
  );
};

/** 44px white dot with a blue ring at (x, y) — tap feedback. `at` is a frame in the caller's timeline. */
export const TapDot: React.FC<{x: number; y: number; at: number; frame?: number}> = ({x, y, at, frame}) => {
  const f = useCurrentFrame();
  const t = tap(frame ?? f, at);
  if (!t) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: x - 22,
        top: y - 22,
        width: 44,
        height: 44,
        borderRadius: 22,
        background: '#FFFFFF',
        border: `3px solid ${COLORS.blue}`,
        boxSizing: 'border-box',
        boxShadow: '0 4px 14px rgba(47,91,255,0.35)',
        transform: `scale(${t.scale})`,
        opacity: t.opacity,
        pointerEvents: 'none',
        zIndex: 50,
      }}
    />
  );
};

/** Harmoniser speech-bubble logo (from the board header). */
export const Logo: React.FC<{size: number; tilesIn?: [number, number, number]}> = ({size, tilesIn = [1, 1, 1]}) => (
  <svg width={size} height={size} viewBox="0 0 32 32">
    <path d="M8 3h16a6 6 0 0 1 6 6v10a6 6 0 0 1-6 6H13l-6 5v-5.3A6 6 0 0 1 2 19V9a6 6 0 0 1 6-6z" fill={COLORS.blue} />
    <g style={{transformOrigin: '11px 12.5px', transform: `scale(${tilesIn[0]})`}}>
      <rect x="7" y="8.5" width="8" height="8" rx="2.2" fill="#FFFFFF" />
    </g>
    <g style={{transformOrigin: '21.25px 10.1px', transform: `scale(${tilesIn[1]})`}}>
      <rect x="17.5" y="8.5" width="7.5" height="3.2" rx="1.6" fill="#FFFFFF" />
    </g>
    <g style={{transformOrigin: '19.8px 14.9px', transform: `scale(${tilesIn[2]})`}}>
      <rect x="17.5" y="13.3" width="4.6" height="3.2" rx="1.6" fill={COLORS.orange} />
    </g>
  </svg>
);

/** Grey placeholder shown when a required recording is missing. */
export const Placeholder: React.FC<{name: string}> = ({name}) => (
  <AbsoluteFill
    style={{
      background: '#C9CDD6',
      alignItems: 'center',
      justifyContent: 'center',
      flexDirection: 'column',
      gap: 12,
      fontFamily: FONT,
      color: '#3D4454',
      textAlign: 'center',
      padding: 24,
    }}
  >
    <div style={{fontSize: 30, fontWeight: 800}}>Real recording needed</div>
    <div style={{fontSize: 20, fontWeight: 600}}>{name}</div>
  </AbsoluteFill>
);
