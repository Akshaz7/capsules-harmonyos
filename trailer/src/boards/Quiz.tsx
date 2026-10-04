import React from 'react';
import {BOARD_STRINGS} from '../timeline';
import {TapDot} from '../components/common';
import {countUp, pressScale} from '../lib/motion';
import {Shell} from './Shell';

export const Quiz: React.FC<{f: number; tapAt?: number}> = ({f: fRaw, tapAt = 14}) => {
  const f = Math.max(0, fRaw);
  const correct = f >= tapAt;
  const score = Math.round(countUp(f, tapAt, 1, 2));
  const row: React.CSSProperties = {
    height: 56,
    borderRadius: 16,
    padding: '0 16px',
    display: 'flex',
    alignItems: 'center',
    fontSize: 17,
    boxSizing: 'border-box',
  };
  const neutral: React.CSSProperties = {...row, border: '1px solid #E3E7F0', background: '#FFFFFF', color: '#5B6478', fontWeight: 600};
  return (
    <Shell
      icon={
        <>
          <circle cx="12" cy="12" r="9" />
          <path d="M9.6 9.3a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.2-2.4 3.6M12 17h.01" />
        </>
      }
      title={BOARD_STRINGS.quiz.title}
      chip="phone"
      contentStyle={{gap: 14}}
      overlay={<TapDot x={195} y={366} at={tapAt} frame={f} />}
    >
      <div style={{display: 'flex', flexDirection: 'column', gap: 8}}>
        <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
          <span style={{fontSize: 14, fontWeight: 600, color: '#5B6478'}}>Question 2 of 3</span>
          <span style={{display: 'inline-flex', alignItems: 'center', height: 28, padding: '0 12px', borderRadius: 14, background: '#EAF0FF', color: '#2A47C7', fontSize: 13, fontWeight: 700}}>Score {score}</span>
        </div>
        <div style={{display: 'flex', gap: 6}}>
          <span style={{flex: 1, height: 6, borderRadius: 3, background: '#2F5BFF'}} />
          <span style={{flex: 1, height: 6, borderRadius: 3, background: '#2F5BFF'}} />
          <span style={{flex: 1, height: 6, borderRadius: 3, background: '#E4E9F3'}} />
        </div>
      </div>

      <div style={{borderRadius: 22, background: '#F5F7FB', padding: '22px 20px'}}>
        <h2 style={{margin: 0, fontSize: 24, fontWeight: 800, lineHeight: '30px', letterSpacing: -0.3}}>What is the capital of Australia?</h2>
      </div>

      <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
        {correct ? (
          <div style={{...row, border: '1.5px solid #2F5BFF', background: '#EAF0FF', justifyContent: 'space-between', padding: '0 14px 0 16px', color: '#1B2236', fontWeight: 700, transform: `scale(${pressScale(f, tapAt)})`}}>
            <span>Canberra</span>
            <span style={{display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 700, color: '#2A47C7'}}>
              {BOARD_STRINGS.quiz.correct}
              <svg width={22} height={22} viewBox="0 0 24 24">
                <circle cx="12" cy="12" r="10" fill="#2F5BFF" />
                <path d="M7.5 12.3l3 3L16.5 9" fill="none" stroke="#FFFFFF" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </div>
        ) : (
          <div style={{...neutral, transform: `scale(${pressScale(f, tapAt)})`}}>Canberra</div>
        )}
        <div style={neutral}>Melbourne</div>
        <div style={neutral}>Perth</div>
      </div>

      <div style={{marginTop: 'auto', height: 54, borderRadius: 18, background: '#2F5BFF', color: '#FFFFFF', fontSize: 17, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>Next question</div>
    </Shell>
  );
};
