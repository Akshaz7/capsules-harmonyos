import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {Bg, FONT, Logo} from '../components/common';
import {COLORS, S3, SCENES} from '../timeline';
import {Easing, lerp, pop, popStyle, slide} from '../lib/motion';

const F = (abs: number) => abs - SCENES.turn.from;

export const Scene3Turn: React.FC = () => {
  const frame = useCurrentFrame();

  // Everything collapses into a blinking cursor, which stretches into the logo.
  const logoAt = F(S3.logoAt);
  const stretch = lerp(frame, [logoAt - 6, logoAt + 4], [0, 1], Easing.out(Easing.cubic));
  const cursorOn = frame < logoAt - 6 ? Math.floor(frame / 4) % 2 === 0 : true;
  const tiles = [0, 3, 6].map((d) => pop(frame, logoAt + 4 + d).p) as [number, number, number];

  const logoSize = 180;
  // Wordmark slides out from behind the logo.
  const wm = slide(frame, F(S3.wordmarkAt), 12);
  const groupShift = lerp(frame, [F(S3.wordmarkAt), F(S3.wordmarkAt) + 12], [0, -1], Easing.out(Easing.cubic));
  // Lift the lockup when the lines arrive.
  const lift = slide(frame, F(S3.line1At) - 4, 12);

  return (
    <Bg>
      {/* Shockwave as everything is sucked in */}
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
        <div
          style={{
            width: 1200,
            height: 1200,
            borderRadius: 600,
            border: `2px solid ${COLORS.blue}`,
            opacity: lerp(frame, [0, 8], [0.25, 0]),
            transform: `scale(${lerp(frame, [0, 8], [1.6, 0.05])})`,
          }}
        />
      </AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', transform: `translateY(${-130 * lift}px)`}}>
        <div style={{display: 'flex', alignItems: 'center', transform: `translateX(${groupShift * 0}px)`}}>
          <div style={{position: 'relative', width: logoSize, height: logoSize, flexShrink: 0}}>
            {stretch <= 0 ? (
              <div
                style={{
                  position: 'absolute',
                  left: logoSize / 2 - 5,
                  top: logoSize / 2 - 50,
                  width: 10,
                  height: 100,
                  borderRadius: 5,
                  background: COLORS.blue,
                  opacity: cursorOn ? 1 : 0,
                }}
              />
            ) : (
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  transform: `scale(${0.06 + 0.94 * stretch}, ${0.55 + 0.45 * stretch})`,
                }}
              >
                <Logo size={logoSize} tilesIn={tiles} />
              </div>
            )}
          </div>
          <div
            style={{
              overflow: 'hidden',
              maxWidth: 720 * wm,
              marginLeft: 36 * wm,
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'center',
            }}
          >
            <div
              style={{
                fontFamily: FONT,
                fontSize: 96,
                fontWeight: 800,
                letterSpacing: -2,
                color: COLORS.text,
                lineHeight: 1.05,
                whiteSpace: 'nowrap',
                transform: `translateX(${-60 * (1 - wm)}px)`,
              }}
            >
              {S3.wordmark}
            </div>
            <div
              style={{
                fontFamily: FONT,
                fontSize: 40,
                fontWeight: 600,
                color: COLORS.secondary,
                whiteSpace: 'nowrap',
                ...popStyle(frame, F(S3.subAt)),
              }}
            >
              {S3.sub}
            </div>
          </div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', paddingTop: 300, gap: 18, flexDirection: 'column'}}>
        <div style={{fontFamily: FONT, fontSize: 40, fontWeight: 600, color: COLORS.secondary, ...popStyle(frame, F(S3.line1At))}}>{S3.line1}</div>
        <div style={{fontFamily: FONT, fontSize: 48, fontWeight: 800, color: COLORS.blue, ...popStyle(frame, F(S3.line2At))}}>{S3.line2}</div>
      </AbsoluteFill>
    </Bg>
  );
};
