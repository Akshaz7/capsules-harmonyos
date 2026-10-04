import React from 'react';
import {FONT, SCREEN_W} from './common';
import {Glyph, ICON_DEFS} from './HomeScreen';
import {COLORS, S1} from '../timeline';

// Home-screen grid geometry inside the 406x906 phone screen.
export const COLS = 4;
export const ROWS = 6;
export const ICON = 74;
export const CELL_W = SCREEN_W / COLS;
export const CELL_H = 122;
export const GRID_TOP = 78;

export const ICONS = ICON_DEFS.slice(0, COLS * ROWS);
export const iconIndex = (name: string) => ICONS.findIndex((d) => d.name === name);

/** Top-left of the icon square for icon i, in screen coordinates. */
export const iconPos = (i: number) => {
  const col = i % COLS;
  const row = Math.floor(i / COLS);
  return {x: col * CELL_W + (CELL_W - ICON) / 2, y: GRID_TOP + row * CELL_H, row, col};
};

/** A flat rounded-square icon with one glyph and a label. */
export const AppIcon: React.FC<{i: number; size?: number; labelSize?: number; style?: React.CSSProperties; tag?: number; labelColor?: string}> = ({
  i,
  size = ICON,
  labelSize = 13,
  style,
  tag = 0,
  labelColor = COLORS.text,
}) => {
  const d = ICONS[i];
  return (
    <div style={{width: size, display: 'flex', flexDirection: 'column', alignItems: 'center', position: 'relative', ...style}}>
      <div
        style={{
          width: size,
          height: size,
          borderRadius: size * 0.28,
          background: d.color,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: '0 2px 6px rgba(27,34,54,0.12)',
        }}
      >
        <div style={{transform: `scale(${size / 60})`, display: 'flex'}}>
          <Glyph type={d.glyph} />
        </div>
      </div>
      <div style={{marginTop: size * 0.1, fontFamily: FONT, fontSize: labelSize, fontWeight: 600, color: labelColor, whiteSpace: 'nowrap'}}>{d.name}</div>
      {tag > 0 && <OpenedOnceTag scale={tag} size={size} />}
    </div>
  );
};

/** Grey "Opened once." tag stamped on an icon. `scale` is the stamp animation (0 = hidden). */
export const OpenedOnceTag: React.FC<{scale: number; size: number}> = ({scale, size}) => (
  <div
    style={{
      position: 'absolute',
      left: '50%',
      top: size * 0.62,
      transform: `translateX(-50%) rotate(-8deg) scale(${scale})`,
      padding: `${size * 0.04}px ${size * 0.09}px`,
      borderRadius: size * 0.1,
      background: '#6B7385',
      color: '#FFFFFF',
      fontFamily: FONT,
      fontSize: size * 0.15,
      fontWeight: 700,
      whiteSpace: 'nowrap',
      boxShadow: '0 2px 6px rgba(0,0,0,0.25)',
      opacity: Math.min(1, scale * 1.5),
    }}
  >
    {S1.tag}
  </div>
);

export type IconState = {hidden?: boolean; dx?: number; dy?: number; rot?: number; opacity?: number; scale?: number; tag?: number};

/** The full grid; per-icon overrides via `state(i)`. */
export const HomeGrid: React.FC<{state?: (i: number) => IconState; drain?: number}> = ({state, drain = 0}) => (
  <div style={{position: 'absolute', inset: 0, filter: drain > 0 ? `grayscale(${drain})` : undefined}}>
    {ICONS.map((_, i) => {
      const s = state?.(i) ?? {};
      if (s.hidden) return null;
      const p = iconPos(i);
      return (
        <AppIcon
          key={i}
          i={i}
          tag={s.tag}
          style={{
            position: 'absolute',
            left: p.x,
            top: p.y,
            opacity: s.opacity ?? 1,
            transform: `translate(${s.dx ?? 0}px, ${s.dy ?? 0}px) rotate(${s.rot ?? 0}deg) scale(${s.scale ?? 1})`,
          }}
        />
      );
    })}
  </div>
);

/** Plain generic wallpaper. */
export const Wallpaper: React.FC<{tint?: number}> = ({tint = 1}) => (
  <div
    style={{
      position: 'absolute',
      inset: 0,
      background: `linear-gradient(160deg, rgba(220,229,255,${tint}) 0%, rgba(242,244,249,1) 45%, rgba(234,238,250,${tint}) 100%)`,
    }}
  />
);
