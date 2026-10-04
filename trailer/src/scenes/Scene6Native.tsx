import React from 'react';
import {AbsoluteFill, Sequence, useCurrentFrame} from 'remotion';
import {FONT, Phone} from '../components/common';
import {FootageVideo} from '../components/Footage';
import excerpt from '../generated/arkts-excerpt.json';
import {COLORS, S6, SCENES} from '../timeline';
import {lerp, popStyle} from '../lib/motion';

const F = (abs: number) => abs - SCENES.native.from;

const KEYWORDS = /\b(let|new|private|struct|this|if|else|return|const|void|string|@Entry|@Component|@LocalStorageProp)\b|(@\w+)/g;

const CodeLine: React.FC<{text: string}> = ({text}) => {
  const parts: React.ReactNode[] = [];
  let last = 0;
  text.replace(KEYWORDS, (m, _a, _b, idx: number) => {
    if (idx > last) parts.push(text.slice(last, idx));
    parts.push(
      <span key={idx} style={{color: '#5B83FF'}}>
        {m}
      </span>,
    );
    last = idx + m.length;
    return m;
  });
  parts.push(text.slice(last));
  return <div style={{whiteSpace: 'pre', height: 44}}>{parts.length ? parts : ' '}</div>;
};

export const Scene6Native: React.FC = () => {
  const frame = useCurrentFrame();
  const scroll = lerp(frame, [0, 180], [120, -560]);
  const largeAt = S6.largeAt;
  const tapAt = S6.tapAt;
  const calAt = S6.calendarAt;
  return (
    <AbsoluteFill style={{background: COLORS.navy, fontFamily: FONT, overflow: 'hidden'}}>
      <AbsoluteFill style={{background: 'radial-gradient(60% 50% at 50% 0%, rgba(47,91,255,0.28), rgba(15,21,40,0) 70%)'}} />
      <AbsoluteFill style={{filter: 'blur(2.5px)', opacity: 0.75, padding: '0 160px', transform: `translateY(${scroll}px)`}}>
        <div style={{fontFamily: 'Menlo, Monaco, monospace', fontSize: 30, color: 'rgba(220,229,255,0.55)', marginTop: 120}}>
          {excerpt.lines.map((l, i) => (
            <CodeLine key={i} text={l} />
          ))}
        </div>
      </AbsoluteFill>
      <div style={{position: 'absolute', left: 120, top: 90, fontSize: 30, fontWeight: 600, color: '#DCE5FF', padding: '10px 22px', borderRadius: 24, background: 'rgba(47,91,255,0.22)', ...popStyle(frame, 4)}}>
        {S6.label}
      </div>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', ...popStyle(frame, 0)}}>
        <Phone screenBg="#202638" style={{boxShadow: '0 40px 120px rgba(47,91,255,0.35)'}}>
          <Sequence durationInFrames={tapAt} layout="none">
            <FootageVideo name="widget-pin" />
          </Sequence>
          <Sequence from={largeAt} durationInFrames={tapAt - largeAt} layout="none">
            <FootageVideo name="widget-pin-large" />
          </Sequence>
          <Sequence from={tapAt} durationInFrames={calAt - tapAt} layout="none">
            <FootageVideo name="widget-tap" />
          </Sequence>
          <Sequence from={calAt} layout="none">
            <FootageVideo name="calendar" />
          </Sequence>
        </Phone>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
