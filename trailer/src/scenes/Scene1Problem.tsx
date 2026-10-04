import React from 'react';
import {useCurrentFrame, Sequence, interpolate, Easing} from 'remotion';
import {SCENES, S1, COLORS, BEAT} from '../timeline';
import {Bg, Phone, Center, FONT, SCREEN_W, SCREEN_H} from '../components/common';
import {HomeScreen, getIconPositions} from '../components/HomeScreen';
import {pop, slide} from '../lib/motion';

export const Scene1Problem: React.FC = () => {
  const frame = useCurrentFrame();
  const F = (abs: number) => abs - SCENES.problem.from;

  // Rain timing: each beat (15 frames), one row lands
  const rainBeats = S1.rainBeats;
  const rainFrames = rainBeats * BEAT; // 60 frames total
  const rowLandFrames = BEAT; // each row lands in 15 frames
  const currentRainRow = Math.min(Math.floor(F(frame) / BEAT), rainBeats - 1);

  // Visible icons: one row per beat
  const visibleCount = Math.min(Math.floor(F(frame) / BEAT + 1) * 8, 24); // two rows per beat
  const visibleIcons = new Set<string>(
    Array.from({length: visibleCount}).map((_, i) => {
      const col = i % 4;
      const row = Math.floor(i / 4);
      return [
        'Timer', 'Timer+', 'Focus Timer', 'Tip', // row 0
        'Tip Pro', 'Packing', 'Notes', 'Music', // row 1
        'Mail', 'Maps', 'Weather', 'Store', // row 2
        'Radio', 'Cards', 'Steps', 'Bills', // row 3
        'Lists', 'Units', 'Files', 'Clock', // row 4
        'Calc', 'Chat', 'Gallery', 'Extras', // row 5
      ][row * 4 + col];
    })
  );

  // Pull back: scale from 2.2 to 1
  const pullBackT = interpolate(F(frame), [0, S1.pullBackAt], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const scale = 2.2 - pullBackT * 1.2;

  // Timer icons lift out at S1.timersAt
  const timerLiftT = Math.max(0, Math.min(1, (F(frame) - (S1.timersAt - SCENES.problem.from)) / 15));
  const timerLifted = timerLiftT > 0 ? new Set(S1.timerIcons) : new Set<string>();

  // Tip icons lift out at S1.tipsAt
  const tipLiftT = Math.max(0, Math.min(1, (F(frame) - (S1.tipsAt - SCENES.problem.from)) / 15));
  const tipLifted = tipLiftT > 0 ? new Set(S1.tipIcons) : new Set<string>();

  // Packing icon lifts out at S1.packingAt
  const packingLiftT = Math.max(0, Math.min(1, (F(frame) - (S1.packingAt - SCENES.problem.from)) / 15));
  const packingLifted = packingLiftT > 0 ? new Set([S1.packingIcon]) : new Set<string>();

  // All icons lifted
  const allLifted = new Set([...timerLifted, ...tipLifted, ...packingLifted]);

  // "Opened once." tag appears at S1.onceAt
  const onceT = Math.max(0, Math.min(1, (F(frame) - (S1.onceAt - SCENES.problem.from)) / 12));
  const tagged = onceT > 0;

  // Grayscale drain at S1.onceAt
  const drainT = Math.max(0, Math.min(1, (F(frame) - (S1.onceAt - SCENES.problem.from)) / 15));
  const drained = drainT * 0.7;

  // Big type behind phone: changes text based on timeline
  let bigTypeText = '';
  let bigTypeScale = 1;
  let bigTypeOpacity = 1;

  if (F(frame) >= S1.timersAt - SCENES.problem.from && F(frame) < S1.tipsAt - SCENES.problem.from) {
    bigTypeText = S1.bigType.timers;
    const t = (F(frame) - (S1.timersAt - SCENES.problem.from)) / 15;
    bigTypeOpacity = Math.min(1, t * 2);
  } else if (F(frame) >= S1.tipsAt - SCENES.problem.from && F(frame) < S1.packingAt - SCENES.problem.from) {
    bigTypeText = S1.bigType.tips;
    // Split-flap flip: rotate each character around its center
    const flipT = (F(frame) - (S1.tipsAt - SCENES.problem.from)) / 15;
    bigTypeScale = 0.95 + flipT * 0.05;
  } else if (F(frame) >= S1.packingAt - SCENES.problem.from && F(frame) < S1.onceAt - SCENES.problem.from) {
    bigTypeText = S1.bigType.packing;
    const t = (F(frame) - (S1.packingAt - SCENES.problem.from)) / 15;
    bigTypeScale = 0.95 + t * 0.05;
  } else if (F(frame) >= S1.onceAt - SCENES.problem.from) {
    bigTypeText = S1.bigType.once;
    const t = (F(frame) - (S1.onceAt - SCENES.problem.from)) / 15;
    bigTypeScale = 0.95 + Math.min(1, t) * 0.05;
  }

  return (
    <Bg white>
      <Center>
        <div
          style={{
            position: 'absolute',
            transform: `scale(${scale})`,
            transformOrigin: 'center',
            transition: 'transform 0.1s ease-out',
          }}
        >
          <Phone screenBg={COLORS.bg}>
            <HomeScreen visible={visibleIcons} lifted={allLifted} drained={drained} tagged={tagged} />
          </Phone>
        </div>
      </Center>

      {/* Big type behind the phone */}
      <div
        style={{
          position: 'absolute',
          left: '50%',
          top: '40%',
          transform: `translateX(-50%) translateY(-50%) scale(${bigTypeScale})`,
          fontSize: 260,
          fontWeight: 800,
          color: `rgba(227, 232, 244, ${bigTypeOpacity * 0.4})`,
          textAlign: 'center',
          fontFamily: FONT,
          whiteSpace: 'nowrap',
          zIndex: 0,
          pointerEvents: 'none',
        }}
      >
        {bigTypeText}
      </div>

      {/* Lifted 3D icons */}
      {Array.from(timerLifted).map((iconName) => (
        <Lifted3DIcon
          key={iconName}
          iconName={iconName}
          liftT={timerLiftT}
          phoneScale={scale}
          offset={{x: -120, y: -60}}
        />
      ))}
      {Array.from(tipLifted).map((iconName) => (
        <Lifted3DIcon
          key={iconName}
          iconName={iconName}
          liftT={tipLiftT}
          phoneScale={scale}
          offset={{x: 120, y: 40}}
        />
      ))}
      {Array.from(packingLifted).map((iconName) => (
        <Lifted3DIcon
          key={iconName}
          iconName={iconName}
          liftT={packingLiftT}
          phoneScale={scale}
          offset={{x: -80, y: 100}}
        />
      ))}
    </Bg>
  );
};

interface Lifted3DIconProps {
  iconName: string;
  liftT: number; // 0..1
  phoneScale: number;
  offset: {x: number; y: number};
}

const Lifted3DIcon: React.FC<Lifted3DIconProps> = ({iconName, liftT, phoneScale, offset}) => {
  const ICON_COLORS: Record<string, string> = {
    'Timer': '#FF7A45',
    'Timer+': '#2F5BFF',
    'Focus Timer': '#8B5CF6',
    'Tip': '#10B981',
    'Tip Pro': '#F59E0B',
    'Packing': '#EC4899',
  };

  const color = ICON_COLORS[iconName] || '#2F5BFF';
  const sz = 90;

  // Floating animation: rise and rotate
  const yFloat = -100 * liftT;
  const scaleFloat = 0.9 + 0.2 * liftT;
  const rotY = liftT * 25; // perspective rotation
  const shadowAlpha = liftT * 0.3;

  return (
    <div
      style={{
        position: 'absolute',
        left: `calc(50% + ${offset.x}px)`,
        top: `calc(50% + ${offset.y}px)`,
        transform: `
          translateX(-${sz / 2}px)
          translateY(-${sz / 2}px)
          translateY(${yFloat}px)
          scale(${scaleFloat})
          perspective(1200px)
          rotateY(${rotY}deg)
        `,
        width: sz,
        height: sz,
        borderRadius: 20,
        background: color,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        boxShadow: `0 ${20 * liftT}px ${40 * liftT}px rgba(0,0,0,${shadowAlpha})`,
        zIndex: 10,
      }}
    >
      <div
        style={{
          width: 50,
          height: 50,
          borderRadius: 10,
          background: 'rgba(255,255,255,0.2)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <svg width="32" height="32" viewBox="0 0 40 40" fill="none">
          <circle cx="20" cy="20" r="14" stroke="white" strokeWidth="2" />
          <line x1="20" y1="8" x2="20" y2="14" stroke="white" strokeWidth="2" strokeLinecap="round" />
          <line x1="20" y1="20" x2="26" y2="20" stroke="white" strokeWidth="2" strokeLinecap="round" />
        </svg>
      </div>
    </div>
  );
};

