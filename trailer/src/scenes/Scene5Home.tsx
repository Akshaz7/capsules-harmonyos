import React from 'react';
import {useCurrentFrame, interpolate, Easing} from 'remotion';
import {SCENES, S5, COLORS, BEAT} from '../timeline';
import {Bg, Phone, Center, FONT, SCREEN_W, SCREEN_H} from '../components/common';
import {HomeScreen} from '../components/HomeScreen';

export const Scene5Home: React.FC = () => {
  const frame = useCurrentFrame();
  const F = (abs: number) => abs - SCENES.home.from;
  const localFrame = frame; // Sequence-local already

  // Icons drop off one row per beat starting at S5.dropStart
  const dropStart = S5.dropStart - SCENES.home.from;
  const rowsToShow = 6 - Math.floor((localFrame - dropStart) / BEAT);
  const visibleIcons = new Set<string>(
    Array.from({length: Math.max(0, rowsToShow * 4)}).map((_, i) => {
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

  // Row drop offsets (falling and fading)
  const rowDropOffsets: number[] = Array.from({length: 6}).map((_, row) => {
    const rowDropStart = dropStart + row * BEAT;
    if (localFrame < rowDropStart) return 0;
    const dropT = Math.min(1, (localFrame - rowDropStart) / 12);
    const fallDist = dropT * (SCREEN_H + 100);
    return fallDist;
  });

  // Grayscale drain reverses (color floods back) at S5.floodAt
  const floodStart = S5.floodAt - SCENES.home.from;
  const floodT = interpolate(localFrame, [floodStart, floodStart + 20], [0.7, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

  // Widgets fold down (rotateX from -90 to 0) starting at S5.widgetsAt
  const widgetsStart = S5.widgetsAt - SCENES.home.from;
  const widgets = S5.widgets.map((w, idx) => {
    const appearAt = widgetsStart + idx * 8;
    const appearT = Math.min(1, Math.max(0, (localFrame - appearAt) / 8));
    return {...w, appearT};
  });

  // Glow swell
  const glowIntensity = interpolate(floodT, [0, 1], [0.4, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

  return (
    <Bg>
      <Center>
        <div style={{position: 'relative'}}>
          {/* Glow effect */}
          {glowIntensity > 0 && (
            <div
              style={{
                position: 'absolute',
                top: '-20%',
                left: '50%',
                transform: 'translateX(-50%)',
                width: 600,
                height: 400,
                background: `radial-gradient(circle, ${COLORS.glow}${Math.floor(glowIntensity * 255).toString(16).padStart(2, '0')} 0%, transparent 70%)`,
                filter: 'blur(60px)',
                pointerEvents: 'none',
                zIndex: -1,
              }}
            />
          )}

          <Phone screenBg={COLORS.bg}>
            {/* Home screen with dropping icons */}
            <HomeScreen drained={floodT} tagged={true} rowDropOffsets={rowDropOffsets} visible={visibleIcons} />

            {/* Widgets grid (simplified 2x2) */}
            <div
              style={{
                position: 'absolute',
                inset: 12,
                display: 'grid',
                gridTemplateColumns: 'repeat(2, 1fr)',
                gap: 12,
                pointerEvents: 'none',
              }}
            >
              {widgets.map((widget, idx) => (
                <Widget key={idx} widget={widget} />
              ))}
            </div>
          </Phone>
        </div>
      </Center>
    </Bg>
  );
};

interface WidgetData {
  kind: string;
  title: string;
  caption: string;
  appearT: number;
}

const Widget: React.FC<{widget: WidgetData}> = ({widget}) => {
  const {kind, title, caption, appearT} = widget;

  // Fold animation: rotateX from -90 to 0
  const rotX = (1 - appearT) * -90;

  // Choose icon color based on widget type
  let iconColor = COLORS.blue;
  if (kind === 'timer') iconColor = '#FF7A45';
  if (kind === 'goal') iconColor = '#10B981';
  if (kind === 'score') iconColor = '#8B5CF6';

  return (
    <div
      style={{
        perspective: '1200px',
        transformStyle: 'preserve-3d',
      }}
    >
      <div
        style={{
          background: '#F4F5F8',
          borderRadius: 28,
          padding: 16,
          display: 'flex',
          flexDirection: 'column',
          gap: 12,
          aspectRatio: '1 / 1',
          justifyContent: 'space-between',
          boxShadow: appearT > 0 ? `0 ${appearT * 12}px ${appearT * 24}px rgba(0,0,0,0.08)` : 'none',
          transform: `rotateX(${rotX}deg) scale(${0.9 + appearT * 0.1})`,
          transformStyle: 'preserve-3d',
          opacity: Math.max(0.3, appearT),
          transition: 'all 0.1s ease-out',
          fontFamily: FONT,
          minHeight: 120,
        }}
      >
        {/* Icon */}
        <div
          style={{
            width: 48,
            height: 48,
            borderRadius: '50%',
            background: iconColor,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: '#FFFFFF',
            fontSize: 24,
            fontWeight: 600,
          }}
        >
          {kind === 'checklist' && '✓'}
          {kind === 'timer' && '◶'}
          {kind === 'goal' && '+'}
          {kind === 'score' && '★'}
        </div>

        {/* Title and Caption */}
        <div style={{flex: 1, display: 'flex', flexDirection: 'column', gap: 4}}>
          <div style={{fontSize: 13, fontWeight: 600, color: COLORS.text}}>
            {title}
          </div>
          <div style={{fontSize: 12, fontWeight: 500, color: COLORS.secondary}}>
            {caption}
          </div>
        </div>

        {/* Label */}
        <div
          style={{
            fontSize: 10,
            fontWeight: 500,
            color: COLORS.secondary,
            textAlign: 'right',
          }}
        >
          {S5.widgetLabel}
        </div>
      </div>
    </div>
  );
};

