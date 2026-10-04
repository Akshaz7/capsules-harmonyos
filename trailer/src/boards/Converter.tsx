import React from 'react';
import {BOARD_STRINGS} from '../timeline';
import {countUp} from '../lib/motion';
import {Shell} from './Shell';

export const Converter: React.FC<{f: number; tapAt?: number}> = ({f: fRaw}) => {
  const f = Math.max(0, fRaw);
  const full = '10';
  // one char per 4 frames, starting at f=4
  const n = Math.min(full.length, Math.max(0, Math.floor((f - 4) / 4) + 1));
  const val = full.slice(0, n);
  const doneAt = 4 + 4 * (full.length - 1);
  const result = countUp(f, doneAt, 0, 10 * 0.621371).toFixed(2);
  return (
    <Shell
      icon={
        <>
          <path d="M7 4v16M4 7l3-3 3 3" />
          <path d="M17 20V4M14 17l3 3 3-3" />
        </>
      }
      title={BOARD_STRINGS.converter.title}
      chip="phone"
    >
      <div style={{display: 'flex', flexDirection: 'column', gap: 6, padding: '16px 18px', borderRadius: 22, background: '#F5F7FB'}}>
        <span style={{fontSize: 14, fontWeight: 600, color: '#5B6478'}}>Kilometres</span>
        <span style={{display: 'flex', alignItems: 'baseline', gap: 8}}>
          <span style={{flex: 1, minWidth: 0, height: 60, lineHeight: '60px', fontSize: 48, fontWeight: 800, letterSpacing: -1, color: '#1B2236', fontVariantNumeric: 'tabular-nums'}}>{val}</span>
          <span style={{fontSize: 20, fontWeight: 700, color: '#5B6478'}}>km</span>
        </span>
      </div>

      <div style={{position: 'relative', height: 8, zIndex: 1}}>
        <div style={{position: 'absolute', left: '50%', top: '50%', transform: 'translate(-50%, -50%)', width: 52, height: 52, borderRadius: 26, border: '4px solid #FFFFFF', boxSizing: 'border-box', background: '#2F5BFF', display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
          <svg width={20} height={20} viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
            <path d="M8 4v16M4 8l4-4 4 4" />
            <path d="M16 20V4M12 16l4 4 4-4" />
          </svg>
        </div>
      </div>

      <div style={{display: 'flex', flexDirection: 'column', gap: 6, padding: '16px 18px', borderRadius: 22, background: '#EAF0FF'}}>
        <span style={{fontSize: 14, fontWeight: 600, color: '#2A47C7'}}>Miles</span>
        <div style={{display: 'flex', alignItems: 'baseline', gap: 8}}>
          <span style={{flex: 1, fontSize: 56, fontWeight: 800, lineHeight: '64px', letterSpacing: -1.5, color: '#2F5BFF', fontVariantNumeric: 'tabular-nums'}}>{result}</span>
          <span style={{fontSize: 20, fontWeight: 700, color: '#2A47C7'}}>mi</span>
        </div>
      </div>

      <div style={{display: 'flex', flexDirection: 'column', gap: 10, marginTop: 22}}>
        <span style={{fontSize: 14, fontWeight: 600, color: '#3D4A66'}}>Common distances</span>
        <div style={{display: 'flex', flexWrap: 'wrap', gap: 8}}>
          {['5 km', '10 km', '21.1 km', '42.2 km'].map((l) => (
            <div key={l} style={{height: 44, padding: '0 16px', borderRadius: 22, border: '1px solid #DCE2EE', boxSizing: 'border-box', background: '#FFFFFF', color: '#1B2236', fontSize: 15, fontWeight: 600, display: 'flex', alignItems: 'center'}}>{l}</div>
          ))}
        </div>
      </div>

      <span style={{marginTop: 16, fontSize: 13, fontWeight: 500, color: '#5B6478'}}>1 km is 0.621 mi</span>
    </Shell>
  );
};
