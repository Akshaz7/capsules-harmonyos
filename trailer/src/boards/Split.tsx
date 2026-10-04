import React from 'react';
import {BOARD_STRINGS} from '../timeline';
import {countUp} from '../lib/motion';
import {Shell} from './Shell';

const circle: React.CSSProperties = {width: 44, height: 44, borderRadius: 22, border: '1px solid #DCE2EE', boxSizing: 'border-box', background: '#FFFFFF', display: 'flex', alignItems: 'center', justifyContent: 'center'};

export const Split: React.FC<{f: number; tapAt?: number}> = ({f: fRaw}) => {
  const f = Math.max(0, fRaw);
  const each = countUp(f, 4, 0, parseFloat(BOARD_STRINGS.split.each)).toFixed(2);
  return (
    <Shell
      icon={
        <>
          <path d="M6 3.5h12v17l-2-1.3-2 1.3-2-1.3-2 1.3-2-1.3-2 1.3z" />
          <path d="M9 8.5h6M9 12h6M9 15.5h3.5" />
        </>
      }
      title={BOARD_STRINGS.split.title}
      chip="rules"
      contentStyle={{gap: 14}}
    >
      <div style={{borderRadius: 22, background: '#2F5BFF', color: '#FFFFFF', padding: '18px 20px 16px', display: 'flex', flexDirection: 'column', gap: 2}}>
        <span style={{fontSize: 14, fontWeight: 600}}>Each person pays</span>
        <span style={{fontSize: 56, fontWeight: 800, lineHeight: '64px', letterSpacing: -1.5, fontVariantNumeric: 'tabular-nums'}}>{each}</span>
        <div style={{display: 'flex', gap: 18, marginTop: 6, fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums'}}>
          <span>Total 120.00</span>
          <span>Tip 0.00</span>
        </div>
      </div>

      <div style={{borderRadius: 20, background: '#F5F7FB', display: 'flex', flexDirection: 'column'}}>
        <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '10px 12px 10px 16px', borderBottom: '1px solid #E3E7F0'}}>
          <span style={{fontSize: 16, fontWeight: 600}}>Bill</span>
          <div style={{width: 132, height: 44, boxSizing: 'border-box', borderRadius: 12, border: '1px solid #DCE2EE', background: '#FFFFFF', padding: '0 14px', display: 'flex', alignItems: 'center', justifyContent: 'flex-end', fontSize: 18, fontWeight: 700, fontVariantNumeric: 'tabular-nums'}}>120.00</div>
        </div>
        <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '10px 12px 10px 16px', borderBottom: '1px solid #E3E7F0'}}>
          <span style={{fontSize: 16, fontWeight: 600}}>People</span>
          <div style={{display: 'flex', alignItems: 'center', gap: 6}}>
            <div style={circle}>
              <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="#1B2236" strokeWidth={2.2} strokeLinecap="round"><path d="M5 12h14" /></svg>
            </div>
            <span style={{minWidth: 36, textAlign: 'center', fontSize: 20, fontWeight: 800, fontVariantNumeric: 'tabular-nums'}}>4</span>
            <div style={circle}>
              <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="#1B2236" strokeWidth={2.2} strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
            </div>
          </div>
        </div>
        <div style={{display: 'flex', flexDirection: 'column', gap: 10, padding: '14px 12px 14px 16px'}}>
          <span style={{fontSize: 16, fontWeight: 600}}>Tip</span>
          <div style={{display: 'flex', gap: 8}}>
            {[0, 10, 15, 20].map((t) => {
              const on = t === 0;
              return (
                <div key={t} style={{flex: 1, height: 44, borderRadius: 12, border: `1px solid ${on ? '#2F5BFF' : '#DCE2EE'}`, boxSizing: 'border-box', background: on ? '#2F5BFF' : '#FFFFFF', color: on ? '#FFFFFF' : '#1B2236', fontSize: 15, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>{t}%</div>
              );
            })}
          </div>
        </div>
      </div>

      <span style={{fontSize: 13, fontWeight: 500, color: '#5B6478'}}>Updates as you type. Each share is rounded to the cent.</span>
    </Shell>
  );
};
