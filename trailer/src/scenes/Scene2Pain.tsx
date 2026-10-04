import React from 'react';
import {useCurrentFrame, interpolate, Easing} from 'remotion';
import {SCENES, S2, COLORS, SILENT_BEAT, BEAT} from '../timeline';
import {Bg, Phone, Center, TapDot, FONT, SCREEN_W, SCREEN_H} from '../components/common';
import {HomeScreen} from '../components/HomeScreen';

export const Scene2Pain: React.FC = () => {
  const frame = useCurrentFrame();
  const F = (abs: number) => abs - SCENES.pain.from;
  const localFrame = frame; // Sequence-local already

  // Check if we're in silent beat (freeze)
  const isSilent = frame + SCENES.pain.from >= SILENT_BEAT.from && frame + SCENES.pain.from < SILENT_BEAT.to;

  // Store tap at S2.storeTapAt
  const storeIconPos = {x: SCREEN_W / 4 + SCREEN_W / 2, y: SCREEN_H * 0.65}; // Approx "Store" position
  const tapStart = S2.storeTapAt - SCENES.pain.from;

  // Store sheet slides up from bottom (damping 200, ~10 frames)
  const sheetSlideT = isSilent ? 1 : Math.min(1, Math.max(0, (localFrame - (tapStart + 5)) / 10));
  const sheetY = (1 - sheetSlideT) * SCREEN_H;

  // Progress ring fill (starts ~20 frames after sheet appears, fills over ~40 frames)
  const progressStart = tapStart + 30;
  const progressT = isSilent ? 1 : Math.min(1, Math.max(0, (localFrame - progressStart) / 40));

  // Account card slams on at S2.accountAt
  const accountStart = S2.accountAt - SCENES.pain.from;
  const accountT = isSilent ? 1 : Math.min(1, Math.max(0, (localFrame - accountStart) / 8));
  const accountScale = accountT > 0 ? 1.3 - 0.3 * Math.min(1, accountT * 1.5) : 0;
  const accountOpacity = accountT > 0 ? Math.min(1, accountT * 2) : 0;

  // Ad card slams on at S2.adAt with rotation
  const adStart = S2.adAt - SCENES.pain.from;
  const adT = isSilent ? 1 : Math.min(1, Math.max(0, (localFrame - adStart) / 8));
  const adScale = adT > 0 ? 1.3 - 0.3 * Math.min(1, adT * 1.5) : 0;
  const adOpacity = adT > 0 ? Math.min(1, adT * 2) : 0;

  // Shake effect for S2.shakeFrames after ad lands
  const shakeStart = adStart;
  const shakeT = Math.max(0, Math.min(1, (localFrame - shakeStart) / S2.shakeFrames));
  const shakeX = shakeT > 0 && shakeT < 1 ? Math.sin(shakeT * 20) * 8 : 0;
  const shakeY = shakeT > 0 && shakeT < 1 ? Math.cos(shakeT * 20) * 8 : 0;

  // Countdown: 5, 4, 3 (one per beat = 15 frames)
  let countdownText = '5';
  if (isSilent) {
    countdownText = '3'; // Freeze on 3
  } else if (localFrame >= adStart + 15) {
    countdownText = '4';
  }
  if (localFrame >= adStart + 30) {
    countdownText = '3';
  }

  return (
    <Bg>
      <Center>
        <Phone screenBg={COLORS.bg}>
          {/* Drained home screen */}
          <HomeScreen drained={0.7} tagged={true} />

          {/* Tap feedback */}
          {localFrame >= tapStart && localFrame < tapStart + 30 && (
            <TapDot x={storeIconPos.x} y={storeIconPos.y} at={tapStart} frame={localFrame} />
          )}

          {/* Store sheet (slides up from bottom) */}
          {sheetSlideT > 0 && (
            <div
              style={{
                position: 'absolute',
                left: 0,
                top: sheetY,
                width: '100%',
                height: SCREEN_H * 0.5,
                background: '#FFFFFF',
                borderRadius: '24px 24px 0 0',
                padding: 24,
                boxSizing: 'border-box',
                display: 'flex',
                flexDirection: 'column',
                gap: 16,
                zIndex: 20,
              }}
            >
              <div
                style={{
                  fontSize: 16,
                  fontWeight: 600,
                  color: COLORS.text,
                  fontFamily: FONT,
                }}
              >
                Generic App
              </div>
              <div
                style={{
                  flex: 1,
                  borderRadius: 16,
                  background: '#F3F4F6',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 12,
                  color: COLORS.secondary,
                  fontFamily: FONT,
                }}
              >
                App preview
              </div>
              <div
                style={{
                  position: 'relative',
                  height: 44,
                  borderRadius: 12,
                  background: COLORS.blue,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 16,
                  fontWeight: 600,
                  color: '#FFFFFF',
                  fontFamily: FONT,
                }}
              >
                {S2.getLabel}
                {progressT > 0 && progressT < 1 && (
                  <div
                    style={{
                      position: 'absolute',
                      width: 24,
                      height: 24,
                      borderRadius: '50%',
                      border: `3px solid rgba(255,255,255,0.3)`,
                      borderTopColor: '#FFFFFF',
                      transform: `rotate(${localFrame * 12}deg)`,
                      right: 12,
                    }}
                  />
                )}
                {progressT >= 1 && (
                  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" style={{position: 'absolute', right: 12}}>
                    <path d="M17 6L8 15L3 10" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </div>
            </div>
          )}
        </Phone>

        {/* Account card (outside phone, floats above) */}
        {accountOpacity > 0 && (
          <div
            style={{
              position: 'absolute',
              left: `calc(50% - ${200}px)`,
              top: `calc(50% - ${240 / 2}px)`,
              width: 400,
              height: 240,
              background: '#FFFFFF',
              borderRadius: 20,
              padding: 24,
              boxSizing: 'border-box',
              display: 'flex',
              flexDirection: 'column',
              gap: 16,
              boxShadow: '0 20px 60px rgba(0,0,0,0.15)',
              transform: `scale(${accountScale}) rotate(-3deg)`,
              opacity: accountOpacity,
              zIndex: 30,
              fontFamily: FONT,
            }}
          >
            <div style={{fontSize: 18, fontWeight: 700, color: COLORS.text}}>
              {S2.accountTitle}
            </div>
            <input
              type="email"
              placeholder="Email"
              disabled
              style={{
                width: '100%',
                padding: 12,
                borderRadius: 8,
                border: `1px solid #E5E7EB`,
                fontSize: 14,
                fontFamily: FONT,
              }}
            />
            <input
              type="password"
              placeholder="Password"
              disabled
              style={{
                width: '100%',
                padding: 12,
                borderRadius: 8,
                border: `1px solid #E5E7EB`,
                fontSize: 14,
                fontFamily: FONT,
              }}
            />
            <button
              disabled
              style={{
                width: '100%',
                padding: 12,
                borderRadius: 8,
                background: COLORS.blue,
                color: '#FFFFFF',
                fontSize: 14,
                fontWeight: 600,
                border: 'none',
                fontFamily: FONT,
                cursor: 'pointer',
              }}
            >
              Sign up
            </button>
          </div>
        )}

        {/* Ad card (outside phone, floats above) */}
        {adOpacity > 0 && (
          <div
            style={{
              position: 'absolute',
              left: `calc(50% - ${140}px + ${shakeX}px)`,
              top: `calc(50% - ${100}px + ${shakeY}px)`,
              width: 280,
              height: 200,
              background: '#F9FAFB',
              borderRadius: 16,
              padding: 16,
              boxSizing: 'border-box',
              display: 'flex',
              flexDirection: 'column',
              gap: 12,
              boxShadow: '0 20px 60px rgba(0,0,0,0.1)',
              transform: `scale(${adScale}) rotate(4deg)`,
              opacity: adOpacity,
              zIndex: 31,
              fontFamily: FONT,
              border: `1px solid #E5E7EB`,
            }}
          >
            <div style={{fontSize: 12, fontWeight: 600, color: COLORS.secondary}}>
              {S2.adLabel}
            </div>
            <div
              style={{
                fontSize: 36,
                fontWeight: 800,
                color: COLORS.blue,
                textAlign: 'center',
              }}
            >
              {countdownText}
            </div>
            <div
              style={{
                fontSize: 13,
                color: COLORS.text,
                textAlign: 'center',
                flex: 1,
                display: 'flex',
                alignItems: 'flex-end',
                justifyContent: 'center',
              }}
            >
              Generic ad content here
            </div>
          </div>
        )}
      </Center>

    </Bg>
  );
};

