import React from 'react';
import {BOARD_STRINGS} from '../timeline';
import {TapDot} from '../components/common';
import {countUp, pressScale} from '../lib/motion';
import {Shell} from './Shell';

const GOAL = 8;
const R = 100;
const CIRC = 2 * Math.PI * R;
const SEG = CIRC / GOAL - 10; // 68.54

export const Water: React.FC<{f: number; tapAt?: number}> = ({f: fRaw, tapAt = 14}) => {
  const f = Math.max(0, fRaw);
  const c = countUp(f, tapAt + 2, 5, 6);
  const shown = Math.round(c);
  const left = GOAL - shown;
  return (
    <Shell
      icon={<path d="M12 3.5c3.5 4.2 6 7.4 6 10.5a6 6 0 0 1-12 0c0-3.1 2.5-6.3 6-10.5z" />}
      title={BOARD_STRINGS.water.title}
      chip="rules"
      contentStyle={{gap: 16}}
      overlay={<TapDot x={195} y={625} at={tapAt} frame={f} />}
    >
      <div style={{flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16}}>
        <div style={{position: 'relative', width: 240, height: 240}}>
          <svg width={240} height={240} viewBox="0 0 240 240">
            {Array.from({length: GOAL}).map((_, i) => {
              const fill = Math.min(1, Math.max(0, c - i));
              const off = -(5 + i * (SEG + 10));
              return (
                <g key={i}>
                  <circle cx="120" cy="120" r={R} fill="none" stroke="#E4E9F3" strokeWidth={20} strokeDasharray={`${SEG} ${CIRC}`} strokeDashoffset={off} transform="rotate(-90 120 120)" />
                  {fill > 0 && (
                    <circle cx="120" cy="120" r={R} fill="none" stroke="#2F5BFF" strokeWidth={20} strokeDasharray={`${SEG * fill} ${CIRC}`} strokeDashoffset={off} transform="rotate(-90 120 120)" />
                  )}
                </g>
              );
            })}
          </svg>
          <div style={{position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center'}}>
            <span style={{fontSize: 72, fontWeight: 800, lineHeight: '76px', letterSpacing: -2, fontVariantNumeric: 'tabular-nums'}}>{shown}</span>
            <span style={{fontSize: 15, fontWeight: 600, color: '#5B6478'}}>of {GOAL} glasses</span>
          </div>
        </div>
        <span style={{fontSize: 17, fontWeight: 700}}>{left} more to reach today's goal</span>
      </div>
      <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
        <div style={{height: 54, borderRadius: 18, background: '#2F5BFF', color: '#FFFFFF', fontSize: 17, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, transform: `scale(${pressScale(f, tapAt)})`}}>
          <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth={2.4} strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
          Add a glass
        </div>
        <div style={{height: 48, borderRadius: 16, border: '1px solid #DCE2EE', boxSizing: 'border-box', background: '#FFFFFF', color: '#1B2236', fontSize: 15, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>Undo last glass</div>
      </div>
      <span style={{textAlign: 'center', fontSize: 13, fontWeight: 500, color: '#5B6478'}}>Resets at midnight</span>
    </Shell>
  );
};
