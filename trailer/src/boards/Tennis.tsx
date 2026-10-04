import React from 'react';
import {BOARD_STRINGS} from '../timeline';
import {TapDot} from '../components/common';
import {pressScale} from '../lib/motion';
import {Shell} from './Shell';

const colStyle: React.CSSProperties = {display: 'inline-block', width: 56, textAlign: 'center'};

export const Tennis: React.FC<{f: number; tapAt?: number}> = ({f: fRaw, tapAt = 14}) => {
  const f = Math.max(0, fRaw);
  const adv = f >= tapAt + 2;
  const status = adv ? BOARD_STRINGS.tennis.advantage : 'Deuce';
  const pts = adv ? ['AD', '40'] : ['40', '40'];
  const cols = [
    {label: 'Set 1', a: '6', b: '4', ink: '#1B2236'},
    {label: 'Set 2', a: '3', b: '2', ink: '#2F5BFF'},
    {label: 'Set 3', a: '', b: '', ink: '#9AA4BA'},
  ];
  const players = [
    {name: 'Me', serving: false, games: 3},
    {name: 'Sam', serving: true, games: 2},
  ];
  return (
    <Shell
      icon={
        <>
          <circle cx="12" cy="12" r="8.5" />
          <path d="M5.2 6.8c3.2 2.6 3.2 7.8 0 10.4M18.8 6.8c-3.2 2.6-3.2 7.8 0 10.4" />
        </>
      }
      title={BOARD_STRINGS.tennis.title}
      chip="phone"
      contentStyle={{gap: 14}}
      overlay={<TapDot x={110} y={518} at={tapAt} frame={f} />}
    >
      <div style={{background: '#F5F7FB', borderRadius: 18, padding: '10px 14px', display: 'flex', flexDirection: 'column', gap: 4}}>
        <div style={{display: 'flex', alignItems: 'center', height: 18}}>
          <span style={{flex: 1, fontSize: 12, fontWeight: 600, color: '#5B6478'}}>Sets</span>
          {cols.map((c) => (
            <span key={c.label} style={{...colStyle, fontSize: 12, fontWeight: 600, color: '#5B6478'}}>{c.label}</span>
          ))}
        </div>
        {(['a', 'b'] as const).map((k, i) => (
          <div key={k} style={{display: 'flex', alignItems: 'center', height: 26}}>
            <span style={{flex: 1, fontSize: 15, fontWeight: 700}}>{i === 0 ? 'Me' : 'Sam'}</span>
            {cols.map((c) => (
              <span key={c.label} style={{...colStyle, fontSize: 18, fontWeight: 800, fontVariantNumeric: 'tabular-nums', color: c.ink}}>{c[k]}</span>
            ))}
          </div>
        ))}
      </div>

      <div style={{display: 'flex', justifyContent: 'center'}}>
        <span style={{display: 'inline-flex', alignItems: 'center', height: 32, padding: '0 14px', borderRadius: 16, fontSize: 14, fontWeight: 700, background: '#FFEFE6', color: '#A8411A'}}>{status}</span>
      </div>

      <div style={{display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: 10}}>
        {players.map((pl, i) => {
          const leading = adv && i === 0;
          return (
            <div key={pl.name} style={{display: 'flex', flexDirection: 'column', gap: 10, padding: 14, borderRadius: 22, background: leading ? '#EAF0FF' : '#F5F7FB', border: `1.5px solid ${leading ? '#2F5BFF' : '#F5F7FB'}`}}>
              <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', height: 22}}>
                <span style={{fontSize: 16, fontWeight: 700}}>{pl.name}</span>
                {pl.serving && (
                  <span style={{display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12, fontWeight: 700, color: '#A8411A'}}>
                    <svg width={14} height={14} viewBox="0 0 24 24">
                      <circle cx="12" cy="12" r="9" fill="#FF7A45" />
                      <path d="M5.5 6.5c3 2.5 3 8.5 0 11M18.5 6.5c-3 2.5-3 8.5 0 11" fill="none" stroke="#FFFFFF" strokeWidth={1.6} />
                    </svg>
                    Serve
                  </span>
                )}
              </div>
              <div style={{fontSize: 76, fontWeight: 800, lineHeight: '84px', letterSpacing: -2, fontVariantNumeric: 'tabular-nums', color: pts[i] === 'AD' ? '#2F5BFF' : '#1B2236'}}>{pts[i]}</div>
              <div style={{fontSize: 14, fontWeight: 600, color: '#5B6478'}}>Games {pl.games}</div>
              <div style={{height: 52, borderRadius: 16, background: '#2F5BFF', color: '#FFFFFF', fontSize: 17, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, transform: i === 0 ? `scale(${pressScale(f, tapAt)})` : undefined}}>
                <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth={2.4} strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
                Point
              </div>
            </div>
          );
        })}
      </div>

      <div style={{display: 'flex', gap: 10, marginTop: 'auto'}}>
        <div style={{flex: 1, height: 46, borderRadius: 15, border: '1px solid #DCE2EE', boxSizing: 'border-box', background: '#FFFFFF', color: '#1B2236', fontSize: 15, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6}}>
          <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="#1B2236" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
            <path d="M9 6L4 11l5 5" />
            <path d="M4 11h10a5 5 0 0 1 0 10h-3" />
          </svg>
          Undo
        </div>
        <div style={{flex: 1, height: 46, borderRadius: 15, border: '1px solid #DCE2EE', boxSizing: 'border-box', background: '#FFFFFF', color: '#1B2236', fontSize: 15, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>New match</div>
      </div>
    </Shell>
  );
};
