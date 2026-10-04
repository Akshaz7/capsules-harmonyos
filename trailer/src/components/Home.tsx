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

/** In-screen status bar (time, signal, battery). Drawn, not a real OS. */
export const StatusBar: React.FC<{time?: string}> = ({time = '9:41'}) => (
  <div
    style={{
      position: 'absolute',
      top: 0,
      left: 0,
      right: 0,
      height: 46,
      padding: '0 28px',
      boxSizing: 'border-box',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      fontFamily: FONT,
      fontSize: 15,
      fontWeight: 700,
      color: '#1B2236',
    }}
  >
    <span>{time}</span>
    <div style={{display: 'flex', alignItems: 'center', gap: 7}}>
      <svg width="17" height="12" viewBox="0 0 17 12" fill="none">
        {[0, 1, 2, 3].map((i) => (
          <rect key={i} x={i * 4.4} y={9 - i * 3} width="3" height={3 + i * 3} rx="1" fill="#1B2236" />
        ))}
      </svg>
      <svg width="26" height="13" viewBox="0 0 26 13" fill="none">
        <rect x="0.5" y="0.5" width="21" height="12" rx="3.5" stroke="#1B2236" strokeOpacity="0.5" />
        <rect x="2.5" y="2.5" width="15" height="8" rx="2" fill="#1B2236" />
        <path d="M23 4.5v4a2 2 0 0 0 0-4z" fill="#1B2236" fillOpacity="0.5" />
      </svg>
    </div>
  </div>
);

const DOCK = [
  {glyph: 'chat', color: '#3B82F6'},
  {glyph: 'map-pin', color: '#10B981'},
  {glyph: 'camera', color: '#EC4899'},
  {glyph: 'music-note', color: '#8B5CF6'},
];

/** Frosted dock with four generic icons, like a real phone home screen. */
export const Dock: React.FC = () => (
  <div
    style={{
      position: 'absolute',
      left: 26,
      right: 26,
      bottom: 28,
      height: 98,
      borderRadius: 34,
      background: 'rgba(255,255,255,0.38)',
      boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.5), 0 10px 26px rgba(27,34,54,0.10)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-around',
      padding: '0 22px',
      boxSizing: 'border-box',
    }}
  >
    {DOCK.map((d) => (
      <div
        key={d.glyph}
        style={{
          width: 56,
          height: 56,
          borderRadius: 17,
          background: d.color,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: '0 4px 10px rgba(27,34,54,0.18)',
        }}
      >
        <div style={{transform: 'scale(0.86)', display: 'flex'}}>
          <Glyph type={d.glyph} />
        </div>
      </div>
    ))}
  </div>
);

/** Page dots above the dock. */
export const PageDots: React.FC<{active?: number; count?: number}> = ({active = 0, count = 3}) => (
  <div style={{position: 'absolute', left: 0, right: 0, bottom: 140, display: 'flex', justifyContent: 'center', gap: 8}}>
    {Array.from({length: count}).map((_, i) => (
      <div key={i} style={{width: 8, height: 8, borderRadius: 4, background: i === active ? '#1B2236' : 'rgba(27,34,54,0.25)'}} />
    ))}
  </div>
);
