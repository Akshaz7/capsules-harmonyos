import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {COLORS} from '../timeline';
import {FONT, SCREEN_W, SCREEN_H} from './common';

// 24 icons in a 4-column grid (6 rows)
const GRID_COLS = 4;
const GRID_ROWS = 6;
const GRID_GAP = 8;
const ICON_SIZE = 80;
const LABEL_HEIGHT = 24;
const ITEM_HEIGHT = ICON_SIZE + LABEL_HEIGHT + 4;

const ICON_DEFS = [
  {name: 'Timer', glyph: 'clock', color: '#FF7A45'},
  {name: 'Timer+', glyph: 'plus', color: '#2F5BFF'},
  {name: 'Focus Timer', glyph: 'clock', color: '#8B5CF6'},
  {name: 'Tip', glyph: 'calculator', color: '#10B981'},
  {name: 'Tip Pro', glyph: 'calculator', color: '#F59E0B'},
  {name: 'Packing', glyph: 'suitcase', color: '#EC4899'},
  {name: 'Notes', glyph: 'note', color: '#F59E0B'},
  {name: 'Music', glyph: 'music-note', color: '#8B5CF6'},
  {name: 'Mail', glyph: 'chat', color: '#3B82F6'},
  {name: 'Maps', glyph: 'map-pin', color: '#EF4444'},
  {name: 'Weather', glyph: 'sun', color: '#FBBF24'},
  {name: 'Store', glyph: 'cart', color: '#6366F1'},
  {name: 'Radio', glyph: 'note', color: '#06B6D4'},
  {name: 'Cards', glyph: 'note', color: '#8B5CF6'},
  {name: 'Steps', glyph: 'plus', color: '#10B981'},
  {name: 'Bills', glyph: 'calculator', color: '#F59E0B'},
  {name: 'Lists', glyph: 'note', color: '#3B82F6'},
  {name: 'Units', glyph: 'calculator', color: '#06B6D4'},
  {name: 'Files', glyph: 'note', color: '#EC4899'},
  {name: 'Clock', glyph: 'clock', color: '#10B981'},
  {name: 'Calc', glyph: 'calculator', color: '#F59E0B'},
  {name: 'Chat', glyph: 'chat', color: '#3B82F6'},
  {name: 'Gallery', glyph: 'camera', color: '#EC4899'},
  {name: 'Extras', glyph: 'plus', color: '#8B5CF6'},
];

const Glyph: React.FC<{type: string}> = ({type}) => {
  const w = 40;
  const h = 40;
  const strokeW = 2;
  switch (type) {
    case 'clock':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <circle cx="20" cy="20" r="14" stroke="white" strokeWidth={strokeW} />
          <line x1="20" y1="8" x2="20" y2="14" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <line x1="20" y1="20" x2="26" y2="20" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
        </svg>
      );
    case 'plus':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <line x1="20" y1="8" x2="20" y2="32" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <line x1="8" y1="20" x2="32" y2="20" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
        </svg>
      );
    case 'calculator':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <rect x="8" y="8" width="24" height="24" rx="2" stroke="white" strokeWidth={strokeW} />
          <line x1="8" y1="16" x2="32" y2="16" stroke="white" strokeWidth={strokeW} />
        </svg>
      );
    case 'suitcase':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <rect x="8" y="12" width="24" height="18" rx="2" stroke="white" strokeWidth={strokeW} />
          <path d="M14 12V9a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v3" stroke="white" strokeWidth={strokeW} />
          <circle cx="20" cy="21" r="2" fill="white" />
        </svg>
      );
    case 'note':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <rect x="8" y="8" width="20" height="24" rx="1" stroke="white" strokeWidth={strokeW} />
          <line x1="12" y1="13" x2="24" y2="13" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <line x1="12" y1="18" x2="24" y2="18" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <line x1="12" y1="23" x2="20" y2="23" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
        </svg>
      );
    case 'music-note':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <path d="M20 6v16a3 3 0 1 1-3-3h3V8" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <circle cx="17" cy="25" r="3" stroke="white" strokeWidth={strokeW} />
        </svg>
      );
    case 'chat':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <path d="M8 10a4 4 0 0 1 4-4h16a4 4 0 0 1 4 4v12a4 4 0 0 1-4 4h-4l-6 4v-4H12a4 4 0 0 1-4-4V10z" stroke="white" strokeWidth={strokeW} />
        </svg>
      );
    case 'map-pin':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <path d="M20 8a5 5 0 0 1 5 5c0 3-5 10-5 10s-5-7-5-10a5 5 0 0 1 5-5z" stroke="white" strokeWidth={strokeW} />
          <circle cx="20" cy="13" r="2" fill="white" />
        </svg>
      );
    case 'sun':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <circle cx="20" cy="20" r="7" stroke="white" strokeWidth={strokeW} />
          <line x1="20" y1="5" x2="20" y2="10" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <line x1="20" y1="30" x2="20" y2="35" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <line x1="5" y1="20" x2="10" y2="20" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <line x1="30" y1="20" x2="35" y2="20" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
        </svg>
      );
    case 'cart':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <path d="M10 16h20l-3 12H13l-3-12z" stroke="white" strokeWidth={strokeW} strokeLinecap="round" strokeLinejoin="round" />
          <line x1="14" y1="12" x2="26" y2="12" stroke="white" strokeWidth={strokeW} strokeLinecap="round" />
          <circle cx="16" cy="30" r="1.5" fill="white" />
          <circle cx="26" cy="30" r="1.5" fill="white" />
        </svg>
      );
    case 'camera':
      return (
        <svg width={w} height={h} viewBox="0 0 40 40" fill="none">
          <rect x="7" y="10" width="26" height="22" rx="2" stroke="white" strokeWidth={strokeW} />
          <circle cx="20" cy="21" r="6" stroke="white" strokeWidth={strokeW} />
          <circle cx="28" cy="14" r="1.5" fill="white" />
        </svg>
      );
    default:
      return null;
  }
};

interface IconGridProps {
  visible?: Set<string>; // which icon names are visible
  lifted?: Set<string>; // which icons have 3D lift
  drained?: number; // 0..1 grayscale
  tagged?: boolean; // show "Opened once." tag
  rowDropOffsets?: number[]; // drop offset per row (in pixels)
}

export const HomeScreen: React.FC<IconGridProps> = ({visible, lifted = new Set(), drained = 0, tagged = false, rowDropOffsets = []}) => {
  const availableWidth = SCREEN_W - 16;
  const availableHeight = SCREEN_H - 20;
  const colWidth = availableWidth / GRID_COLS;

  return (
    <AbsoluteFill style={{position: 'relative', overflow: 'hidden', background: COLORS.bg}}>
      <div style={{position: 'absolute', inset: 8, display: 'flex', flexDirection: 'column', gap: GRID_GAP}}>
        {Array.from({length: GRID_ROWS}).map((_, row) => {
          const dropOffset = rowDropOffsets?.[row] ?? 0;
          return (
            <div key={row} style={{display: 'flex', gap: GRID_GAP, transform: `translateY(${dropOffset}px)`, transition: 'transform 0.3s ease'}}>
              {Array.from({length: GRID_COLS}).map((_, col) => {
                const idx = row * GRID_COLS + col;
                if (idx >= ICON_DEFS.length) return null;
                const icon = ICON_DEFS[idx];
                const isVisible = !visible || visible.has(icon.name);
                const isLifted = lifted.has(icon.name);

                if (!isVisible) return <div key={col} style={{flex: 1}} />;

                return (
                  <div key={col} style={{flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4}}>
                    <div
                      style={{
                        width: ICON_SIZE,
                        height: ICON_SIZE,
                        borderRadius: 20,
                        background: icon.color,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        flexShrink: 0,
                        filter: drained > 0 ? `grayscale(${drained})` : 'none',
                        opacity: isLifted ? 0 : 1,
                        transform: isLifted ? 'scale(0.8)' : 'scale(1)',
                        transition: 'opacity 0.3s ease, transform 0.3s ease',
                      }}
                    >
                      <Glyph type={icon.glyph} />
                    </div>
                    <div
                      style={{
                        fontSize: 10,
                        fontWeight: 600,
                        color: COLORS.text,
                        textAlign: 'center',
                        lineHeight: 1.2,
                        maxWidth: ICON_SIZE + 16,
                        filter: drained > 0 ? `grayscale(${drained})` : 'none',
                      }}
                    >
                      {icon.name}
                    </div>
                    {tagged && (
                      <div
                        style={{
                          fontSize: 7,
                          color: '#9CA3AF',
                          textAlign: 'center',
                          lineHeight: 1,
                          fontWeight: 500,
                        }}
                      >
                        Opened once.
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// Helper to get icon positions for lifting
export const getIconPositions = (): Record<string, {row: number; col: number}> => {
  const positions: Record<string, {row: number; col: number}> = {};
  ICON_DEFS.forEach((icon, idx) => {
    positions[icon.name] = {row: Math.floor(idx / GRID_COLS), col: idx % GRID_COLS};
  });
  return positions;
};

export default HomeScreen;
