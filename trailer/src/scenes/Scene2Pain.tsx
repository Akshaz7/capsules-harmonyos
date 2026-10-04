import React from 'react';
import {useCurrentFrame, interpolate, Easing} from 'remotion';
import {SCENES, S2, COLORS, SILENT_BEAT, BEAT} from '../timeline';
import {Bg, Phone, Center, TapDot, FONT, SCREEN_W, SCREEN_H} from '../components/common';
import {HomeGrid, ICON, Wallpaper, iconIndex, iconPos} from '../components/Home';

export const Scene2Pain: React.FC = () => {
  // The silent beat freezes everything: clamp time to its first frame.
  const frame = Math.min(useCurrentFrame(), SILENT_BEAT.from - SCENES.pain.from);
  const F = (abs: number) => abs - SCENES.pain.from;
  const localFrame = frame; // Sequence-local already

  // Check if we're in silent beat (freeze)
  const isSilent = false;

  // Store tap at S2.storeTapAt
  const store = iconPos(iconIndex('Store'));
  const storeIconPos = {x: store.x + ICON / 2, y: store.y + ICON / 2};
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
  // Ticks one per beat so it reads 3 exactly when the silent beat freezes it.
  const tick = Math.max(0, Math.min(2, Math.floor((localFrame - (SILENT_BEAT.from - SCENES.pain.from - 2 * BEAT)) / BEAT)));
  const countdownText = String(S2.adCountdown[tick]);

  return (
    <Bg>
      <Center>
        <Phone screenBg={COLORS.bg}>
          {/* Drained home screen */}
          <Wallpaper />
          <HomeGrid drain={0.7} state={() => ({tag: 1})} />

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
                height: SCREEN_H * 0.55,
                background: '#FFFFFF',
                borderRadius: '24px 24px 0 0',
                padding: 20,
                boxSizing: 'border-box',
                display: 'flex',
                flexDirection: 'column',
                gap: 12,
                zIndex: 20,
              }}
            >
              {/* App tile with icon and info */}
              <div style={{display: 'flex', gap: 12, alignItems: 'center'}}>
                <div
                  style={{
                    width: 56,
                    height: 56,
                    borderRadius: 12,
                    background: COLORS.blue,
                    flexShrink: 0,
                  }}
                />
                <div style={{flex: 1}}>
                  <div style={{width: 140, height: 14, borderRadius: 7, background: '#D9DEE8'}} />
                  <div style={{width: 90, height: 10, marginTop: 8, borderRadius: 5, background: '#E6EAF1'}} />
                </div>
              </div>

              {/* Grey bars (generic preview) */}
              <div style={{display: 'flex', flexDirection: 'column', gap: 8}}>
                <div style={{height: 8, borderRadius: 4, background: '#E5E7EB'}} />
                <div style={{height: 8, borderRadius: 4, background: '#E5E7EB', width: '80%'}} />
                <div style={{height: 8, borderRadius: 4, background: '#E5E7EB', width: '60%'}} />
              </div>

              {/* Stars rating */}
              <div style={{display: 'flex', gap: 4, alignItems: 'center'}}>
                {[1, 2, 3, 4, 5].map((i) => (
                  <div
                    key={i}
                    style={{
                      fontSize: 16,
                      color: i <= 4 ? '#FBBF24' : '#E5E7EB',
                    }}
                  >
                    ★
                  </div>
                ))}
                <div style={{fontSize: 12, color: COLORS.secondary, fontFamily: FONT, marginLeft: 4}}>
                  4.2K
                </div>
              </div>

              <div style={{flex: 1}} />

              {/* Get button with progress ring */}
              <div
                style={{
                  position: 'relative',
                  height: 48,
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
                  <svg
                    width="28"
                    height="28"
                    viewBox="0 0 28 28"
                    style={{
                      position: 'absolute',
                      right: 12,
                      transform: `rotate(${(localFrame - progressStart) * 6}deg)`,
                    }}
                  >
                    <circle cx="14" cy="14" r="11" fill="none" stroke="rgba(255,255,255,0.3)" strokeWidth="2" />
                    <circle
                      cx="14"
                      cy="14"
                      r="11"
                      fill="none"
                      stroke="white"
                      strokeWidth="2"
                      strokeDasharray={`${69 * progressT} 69`}
                      strokeLinecap="round"
                      strokeDashoffset="-17.25"
                    />
                  </svg>
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
              left: `calc(50% - ${560 / 2}px)`,
              top: `calc(50% - ${360 / 2}px)`,
              width: 560,
              height: 360,
              background: '#FFFFFF',
              borderRadius: 24,
              padding: 32,
              boxSizing: 'border-box',
              display: 'flex',
              flexDirection: 'column',
              gap: 20,
              boxShadow: '0 40px 80px rgba(0,0,0,0.2)',
              transform: `scale(${accountScale * 1.45}) rotate(-3deg)`,
              opacity: accountOpacity,
              zIndex: 30,
              fontFamily: FONT,
            }}
          >
            <div style={{fontSize: 24, fontWeight: 700, color: COLORS.text}}>
              {S2.accountTitle}
            </div>
            <input
              type="email"
              placeholder="Email"
              disabled
              style={{
                width: '100%',
                padding: 14,
                borderRadius: 12,
                border: `1px solid #D1D5DB`,
                fontSize: 16,
                fontFamily: FONT,
                background: '#F9FAFB',
              }}
            />
            <input
              type="password"
              placeholder="Password"
              disabled
              style={{
                width: '100%',
                padding: 14,
                borderRadius: 12,
                border: `1px solid #D1D5DB`,
                fontSize: 16,
                fontFamily: FONT,
                background: '#F9FAFB',
              }}
            />
            <button
              disabled
              style={{
                width: '100%',
                padding: 14,
                borderRadius: 12,
                background: COLORS.blue,
                color: '#FFFFFF',
                fontSize: 16,
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
              left: `calc(50% - ${460 / 2}px + ${shakeX}px)`,
              top: `calc(50% - ${320 / 2}px + ${shakeY}px)`,
              width: 460,
              height: 320,
              background: '#F9FAFB',
              borderRadius: 20,
              padding: 24,
              boxSizing: 'border-box',
              display: 'flex',
              flexDirection: 'column',
              gap: 16,
              boxShadow: '0 40px 80px rgba(0,0,0,0.15)',
              transform: `scale(${adScale * 1.6}) rotate(4deg)`,
              opacity: adOpacity,
              zIndex: 31,
              fontFamily: FONT,
              border: `1px solid #E5E7EB`,
            }}
          >
            <div style={{alignSelf: 'flex-start', fontSize: 18, fontWeight: 700, color: '#FFFFFF', background: COLORS.text, padding: '4px 12px', borderRadius: 10}}>
              {S2.adLabel}
            </div>

            {/* Big countdown */}
            <div
              style={{
                fontSize: 120,
                fontWeight: 800,
                color: COLORS.blue,
                textAlign: 'center',
                lineHeight: 1,
              }}
            >
              {countdownText}
            </div>

            {/* Generic ad content: bars and dots */}
            <div style={{flex: 1, display: 'flex', flexDirection: 'column', gap: 10, justifyContent: 'flex-end'}}>
              <div style={{height: 6, borderRadius: 3, background: '#E5E7EB'}} />
              <div style={{height: 6, borderRadius: 3, background: '#E5E7EB', width: '85%'}} />
              <div style={{height: 6, borderRadius: 3, background: '#E5E7EB', width: '70%'}} />
            </div>
          </div>
        )}
      </Center>

    </Bg>
  );
};

