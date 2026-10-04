import React from 'react';
import {AbsoluteFill, Sequence, useCurrentFrame} from 'remotion';
import {Bg, FONT, Phone} from '../components/common';
import {FootageVideo} from '../components/Footage';
import {COLORS, OPTIONS, SCENES, type OptionsBeat} from '../timeline';
import {popStyle, slide} from '../lib/motion';

const PHONE_CENTRE_X = 1290;
const PHONE_W = 430;
const PHONE_H = 930;

const Beat: React.FC<{beat: OptionsBeat}> = ({beat}) => {
  const frame = useCurrentFrame();
  const inAt = 0;
  const phone = popStyle(frame, inAt);
  const caption = slide(frame, inAt + 2, 10);
  const sub = slide(frame, inAt + 8, 10);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
        <div style={{position: 'absolute', left: PHONE_CENTRE_X - PHONE_W / 2, top: (1080 - PHONE_H) / 2, ...phone}}>
          <Phone screenBg="#F2F4F9">
            <Sequence layout="none">
              <FootageVideo name={beat.footage} />
            </Sequence>
          </Phone>
        </div>
      </AbsoluteFill>
      <div style={{position: 'absolute', left: 150, top: 420, width: 860}}>
        <div style={{fontFamily: FONT, fontWeight: 800, fontSize: 76, letterSpacing: -2.5, color: COLORS.text, opacity: caption, transform: `translateY(${(1 - caption) * 26}px)`}}>
          {beat.caption}
        </div>
        <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 34, color: COLORS.secondary, marginTop: 16, opacity: sub, transform: `translateY(${(1 - sub) * 18}px)`}}>
          {beat.sub}
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const SceneOptions: React.FC = () => (
  <Bg>
    {OPTIONS.map((beat) => (
      <Sequence key={beat.id} from={beat.from - SCENES.options.from} durationInFrames={beat.durationInFrames} name={`options-${beat.id}`}>
        <Beat beat={beat} />
      </Sequence>
    ))}
  </Bg>
);
