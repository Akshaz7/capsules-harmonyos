import React from 'react';
import {BOARD_STRINGS} from '../timeline';
import {lerp, Easing} from '../lib/motion';
import {Shell} from './Shell';

/** Ring centre and radius within the 390x844 board. */
export const POMODORO_RING = {x: 195, y: 406, r: 110};

const CIRC = 2 * Math.PI * 110;

const fmt = (secs: number) => `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;

export const Pomodoro: React.FC<{f: number; tapAt?: number}> = ({f: fRaw}) => {
  const f = Math.max(0, fRaw);
  const {focus, rest} = BOARD_STRINGS.pomodoro;
  const sweep = lerp(f, [0, 45], [0, 1], Easing.inOut(Easing.cubic));
  // clock holds at full time, then ticks down one second per 30 frames
  const elapsed = f < 60 ? 0 : Math.floor((f - 60) / 30) + 1;
  const time = fmt(focus * 60 - elapsed);
  const angle = sweep * 360;
  return (
    <Shell
      icon={
        <>
          <circle cx="12" cy="13" r="7.5" />
          <path d="M12 9.5V13l2.5 2M10 3h4" />
        </>
      }
      title={BOARD_STRINGS.pomodoro.title}
      chip="rules"
      contentStyle={{gap: 16}}
    >
      <div style={{display: 'flex', padding: 3, borderRadius: 14, background: '#F1F3F8'}}>
        <div style={{flex: 1, height: 44, borderRadius: 11, background: '#FFFFFF', boxShadow: '0 1px 3px rgba(27,34,54,0.12)', color: '#1B2236', fontSize: 15, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>Focus {focus} min</div>
        <div style={{flex: 1, height: 44, borderRadius: 11, color: '#5B6478', fontSize: 15, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>Break {rest} min</div>
      </div>

      <div style={{flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
        <div style={{position: 'relative', width: 252, height: 252}}>
          <svg width={252} height={252} viewBox="0 0 252 252">
            <circle cx="126" cy="126" r="110" fill="none" stroke="#E4E9F3" strokeWidth={14} />
            <circle cx="126" cy="126" r="110" fill="none" stroke="#2F5BFF" strokeWidth={14} strokeLinecap="round" strokeDasharray={`${CIRC * sweep} ${CIRC * 2}`} transform="rotate(-90 126 126)" />
            <circle cx="126" cy="16" r="4" fill="#FFFFFF" transform={`rotate(${angle} 126 126)`} opacity={sweep > 0.01 ? 1 : 0} />
          </svg>
          <div style={{position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2}}>
            <span style={{fontSize: 58, fontWeight: 800, lineHeight: '64px', letterSpacing: -1.5, fontVariantNumeric: 'tabular-nums'}}>{time}</span>
            <span style={{fontSize: 15, fontWeight: 600, color: '#5B6478'}}>Focusing</span>
          </div>
        </div>
      </div>

      <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
        <div style={{height: 54, borderRadius: 18, background: '#2F5BFF', color: '#FFFFFF', fontSize: 17, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8}}>
          <svg width={18} height={18} viewBox="0 0 24 24"><path d="M8 5.5v13l10.5-6.5z" fill="#FFFFFF" /></svg>
          Start focus
        </div>
        <div style={{height: 54, borderRadius: 18, background: '#FFEDE4', color: '#A8411A', fontSize: 17, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8}}>
          <svg width={20} height={20} viewBox="0 0 24 24" fill="none" stroke="#A8411A" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
            <path d="M5 9h11v5a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5z" />
            <path d="M16 10.5h1.5a2.5 2.5 0 0 1 0 5H16" />
            <path d="M9 3.5v2.5M12.5 3.5v2.5" />
          </svg>
          Start break
        </div>
      </div>
      <span style={{textAlign: 'center', fontSize: 13, fontWeight: 500, color: '#5B6478'}}>2 focus sessions done today</span>
    </Shell>
  );
};
