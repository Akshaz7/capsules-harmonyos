import React from 'react';
import {BOARD_STRINGS} from '../timeline';
import {FONT, Logo} from '../components/common';

const svgBase = {
  viewBox: '0 0 24 24',
  fill: 'none',
  strokeLinecap: 'round',
  strokeLinejoin: 'round',
} as const;

export const ChipIcon: React.FC<{kind: 'phone' | 'rules'}> = ({kind}) => (
  <svg width={13} height={13} {...svgBase} stroke="#2A47C7" strokeWidth={2.2}>
    {kind === 'phone' ? (
      <>
        <rect x="7" y="3" width="10" height="18" rx="2.5" />
        <path d="M11 17.5h2" />
      </>
    ) : (
      <path d="M5 7h14M5 12h14M5 17h9" />
    )}
  </svg>
);

const circleBtn: React.CSSProperties = {
  width: 44,
  height: 44,
  borderRadius: 22,
  border: 0,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  padding: 0,
  flexShrink: 0,
};

/** Shared Harmoniser frame: header, capsule card header, bottom bar. Root is 390x844, position:relative. */
export const Shell: React.FC<{
  icon: React.ReactNode;
  title: string;
  chip: 'phone' | 'rules';
  children: React.ReactNode;
  overlay?: React.ReactNode;
  contentStyle?: React.CSSProperties;
}> = ({icon, title, chip, children, overlay, contentStyle}) => (
  <div
    style={{
      position: 'relative',
      width: 390,
      height: 844,
      boxSizing: 'border-box',
      display: 'flex',
      flexDirection: 'column',
      overflow: 'hidden',
      background: 'linear-gradient(180deg, #DCE5FF 0px, #EEF2FB 200px, #F2F4F9 360px)',
      color: '#1B2236',
      fontFamily: FONT,
    }}
  >
    <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '18px 16px 10px 20px', flexShrink: 0}}>
      <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
        <Logo size={30} />
        <span style={{fontSize: 19, fontWeight: 700, letterSpacing: -0.2}}>Harmoniser</span>
      </div>
      <div style={{...circleBtn, background: 'rgba(255,255,255,0.72)'}}>
        <svg width={22} height={22} {...svgBase} stroke="#1B2236" strokeWidth={1.8}>
          <path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8" />
          <path d="M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8" />
          <path d="M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16" />
          <path d="M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" />
          <path d="M7.5 12h9" />
        </svg>
      </div>
    </div>

    <div
      style={{
        flex: 1,
        minHeight: 0,
        margin: '4px 12px 16px',
        borderRadius: 28,
        background: 'rgba(255,255,255,0.94)',
        border: '1px solid rgba(47,91,255,0.12)',
        boxShadow: '0 18px 40px rgba(27,34,54,0.10), 0 1px 2px rgba(27,34,54,0.05)',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      <div style={{display: 'flex', alignItems: 'center', gap: 12, padding: '12px 10px 12px 14px', borderBottom: '1px solid #E8ECF4', flexShrink: 0}}>
        <div style={{width: 42, height: 42, borderRadius: 13, background: '#EAF0FF', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0}}>
          <svg width={22} height={22} {...svgBase} stroke="#2F5BFF" strokeWidth={2}>
            {icon}
          </svg>
        </div>
        <div style={{flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 4}}>
          <div style={{maxWidth: '100%', fontSize: 17, fontWeight: 700, lineHeight: '22px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}}>{title}</div>
          <div style={{display: 'inline-flex', alignItems: 'center', gap: 5, padding: '2px 8px 2px 6px', borderRadius: 10, background: '#EEF2FF', color: '#2A47C7', fontSize: 12, fontWeight: 600, lineHeight: '16px'}}>
            <ChipIcon kind={chip} />
            <span>{chip === 'phone' ? BOARD_STRINGS.madeOnPhone : BOARD_STRINGS.madeByRules}</span>
          </div>
        </div>
        <div style={{...circleBtn, background: '#F1F3F8'}}>
          <svg width={18} height={18} {...svgBase} stroke="#1B2236" strokeWidth={2}>
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        </div>
      </div>

      <div style={{flex: 1, minHeight: 0, overflow: 'hidden', padding: 16, display: 'flex', flexDirection: 'column', ...contentStyle}}>{children}</div>

      <div style={{display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px 12px', borderTop: '1px solid #E8ECF4', flexShrink: 0}}>
        <div style={{flex: 1, minWidth: 0, height: 44, borderRadius: 22, border: '1px solid #DCE2EE', background: '#F5F7FB', display: 'flex', alignItems: 'center', gap: 8, padding: '0 16px', color: '#5B6478', fontSize: 15, fontWeight: 500}}>
          <svg width={18} height={18} {...svgBase} stroke="#2F5BFF" strokeWidth={2}>
            <path d="M4 20l1-4L15.5 5.5a2.1 2.1 0 0 1 3 3L8 19z" />
            <path d="M13.5 7.5l3 3" />
          </svg>
          <span>Change it…</span>
        </div>
        <div style={{...circleBtn, border: '1px solid #DCE2EE', background: '#FFFFFF'}}>
          <svg width={20} height={20} {...svgBase} stroke="#1B2236" strokeWidth={1.9}>
            <path d="M12 4v11" />
            <path d="M8 8l4-4 4 4" />
            <path d="M6 12v6.5A1.5 1.5 0 0 0 7.5 20h9a1.5 1.5 0 0 0 1.5-1.5V12" />
          </svg>
        </div>
        <div style={{...circleBtn, border: '1px solid #DCE2EE', background: '#FFFFFF'}}>
          <svg width={20} height={20} {...svgBase} stroke="#1B2236" strokeWidth={1.9}>
            <rect x="4" y="4" width="7" height="7" rx="2" />
            <rect x="13" y="4" width="7" height="7" rx="2" />
            <rect x="4" y="13" width="7" height="7" rx="2" />
            <path d="M16.5 13.5v6M13.5 16.5h6" />
          </svg>
        </div>
      </div>
    </div>
    {overlay}
  </div>
);
