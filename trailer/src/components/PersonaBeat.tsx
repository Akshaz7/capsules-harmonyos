import React from 'react';
import {AbsoluteFill, Sequence, useCurrentFrame} from 'remotion';
import {BoardFit, Center, FONT, Logo, Phone, SCREEN_H, SCREEN_W} from './common';
import {FootageVideo, hasFootage} from './Footage';
import {BOARDS} from '../boards';
import {POMODORO_RING} from '../boards/Pomodoro';
import {BEAT, COLORS, type BoardKey, type FootageKey, type Moment, type Persona} from '../timeline';
import {beatTimes} from '../lib/beat';
import {Easing, caretOn, countUp, lerp, pop, popStyle, typed} from '../lib/motion';

export type PersonaBeatProps = {
  name: string;
  role?: string;
  initials?: string[];
  prompt: string;
  durationInFrames: number;
  footage: FootageKey;
  board?: BoardKey;
  moment: Moment;
  whipIn?: boolean;
  whipOut?: boolean;
};

export const personaProps = (p: Persona, next?: Persona): PersonaBeatProps => ({
  name: p.name,
  role: p.role,
  initials: p.initials,
  prompt: p.prompt,
  durationInFrames: p.durationInFrames,
  footage: p.footage,
  board: p.board,
  moment: p.moment,
  whipIn: p.transitionIn === 'whip',
  whipOut: next?.transitionIn === 'whip',
});

const PHONE_X = 1290; // phone centre x
const BAR_W = 760;
const BAR_LEFT = 150;
const BAR_TOP = 600;

/** Giant outlined name filling the background. */
const GiantName: React.FC<{name: string; frame: number}> = ({name, frame}) => {
  // Long names wrap onto two lines so they never run under the phone.
  const lines = name.length > 8 && name.includes(' ') ? name.split(' ') : [name];
  const longest = Math.max(...lines.map((l) => l.length));
  const size = Math.min(300, 860 / (longest * 0.74));
  const drift = lerp(frame, [0, 200], [0, -50]);
  return (
    <div
      style={{
        position: 'absolute',
        left: BAR_LEFT - 20,
        top: BAR_TOP - 100 - size * 0.98 * lines.length,
        fontFamily: FONT,
        fontWeight: 800,
        fontSize: size,
        lineHeight: 1,
        letterSpacing: -4,
        // Stroke under a background-coloured fill hides the variable font's overlapping contours.
        color: '#F1F4FB',
        WebkitTextStroke: '6px rgba(47,91,255,0.35)',
        paintOrder: 'stroke fill',
        whiteSpace: 'nowrap',
        transform: `translateX(${drift}px)`,
        ...popStyle(frame, 0),
      }}
    >
      {lines.map((l) => (
        <div key={l}>{l}</div>
      ))}
    </div>
  );
};

const Initials: React.FC<{letters: string[]; frame: number}> = ({letters, frame}) => (
  <AbsoluteFill style={{flexDirection: 'row', gap: 40, left: BAR_LEFT - 10, top: BAR_TOP - 380}}>
    {letters.map((l, i) => (
      <div
        key={l}
        style={{
          width: 220,
          height: 220,
          borderRadius: 110,
          border: '3px solid rgba(47,91,255,0.28)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: FONT,
          fontWeight: 800,
          fontSize: 110,
          color: '#F1F4FB',
          WebkitTextStroke: '6px rgba(47,91,255,0.35)',
          paintOrder: 'stroke fill',
          ...popStyle(frame, i * 3),
        }}
      >
        {l}
      </div>
    ))}
  </AbsoluteFill>
);

/** Floating prompt bar; on send the words break into tiles that fly into the phone. */
const PromptBar: React.FC<{prompt: string; role?: string; frame: number; t: ReturnType<typeof beatTimes>}> = ({prompt, role, frame, t}) => {
  const shown = typed(prompt, frame, t.typeAt, t.typeDur);
  const sent = frame >= t.sendAt;
  const barIn = popStyle(frame, 0);
  const words = prompt.split(' ');
  // Approximate word x positions inside the bar (34px Manrope ~ 0.56em per char).
  let cx = 0;
  const wordPos = words.map((w) => {
    const x = cx;
    cx += (w.length + 1) * 34 * 0.56;
    return x;
  });
  const fly = lerp(frame, [t.sendAt, t.sendAt + 12], [0, 1], Easing.in(Easing.cubic));
  return (
    <>
      {role && (
        <div style={{position: 'absolute', left: BAR_LEFT + 6, top: BAR_TOP - 64, fontFamily: FONT, fontSize: 28, fontWeight: 600, color: COLORS.secondary, ...popStyle(frame, 2)}}>
          {role}
        </div>
      )}
      {!sent && (
        <div
          style={{
            position: 'absolute',
            left: BAR_LEFT,
            top: BAR_TOP,
            width: BAR_W,
            height: 96,
            borderRadius: 48,
            background: '#FFFFFF',
            boxShadow: '0 24px 60px rgba(27,34,54,0.14), 0 2px 6px rgba(27,34,54,0.06)',
            display: 'flex',
            alignItems: 'center',
            padding: '0 18px 0 36px',
            boxSizing: 'border-box',
            ...barIn,
          }}
        >
          <div style={{flex: 1, display: 'flex', justifyContent: shown.length > 36 ? 'flex-end' : 'flex-start', fontFamily: FONT, fontSize: 34, fontWeight: 600, color: COLORS.text, whiteSpace: 'nowrap', overflow: 'hidden', marginRight: 14}}>
            <span>{shown}</span>
            <span style={{display: 'inline-block', flexShrink: 0, alignSelf: 'center', width: 3, height: 40, marginLeft: 3, background: COLORS.blue, opacity: caretOn(frame) ? 1 : 0}} />
          </div>
          <div style={{width: 64, height: 64, borderRadius: 32, background: COLORS.blue, display: 'flex', alignItems: 'center', justifyContent: 'center', transform: `scale(${lerp(frame, [t.sendAt - 3, t.sendAt - 1, t.sendAt], [1, 0.9, 1])})`}}>
            <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 19V5M5 12l7-7 7 7" />
            </svg>
          </div>
        </div>
      )}
      {sent &&
        fly < 1 &&
        words.map((w, i) => {
          const sx = BAR_LEFT + 36 + wordPos[i];
          const sy = BAR_TOP + 24;
          const tx = PHONE_X - 60;
          const ty = 500;
          const d = Math.min(1, Math.max(0, fly * 1.3 - i * 0.06));
          return (
            <div
              key={i}
              style={{
                position: 'absolute',
                left: sx + (tx - sx) * d,
                top: sy + (ty - sy) * d - Math.sin(d * Math.PI) * 120,
                padding: '4px 14px',
                borderRadius: 14,
                background: i % 3 === 2 ? COLORS.orange : COLORS.blue,
                color: '#fff',
                fontFamily: FONT,
                fontWeight: 700,
                fontSize: 30,
                transform: `scale(${1 - 0.6 * d}) rotate(${(i % 2 ? 1 : -1) * 12 * d}deg)`,
                opacity: 1 - d * 0.4,
                whiteSpace: 'nowrap',
              }}
            >
              {w}
            </div>
          );
        })}
    </>
  );
};

/** Screen content: footage if recorded, else board, else placeholder. */
const Screen: React.FC<{p: PersonaBeatProps; frame: number; boardAt: number; tapAt: number}> = ({p, frame, boardAt, tapAt}) => {
  const f = frame - boardAt;
  if (f < 0) {
    // Building: shimmering capsule skeleton.
    const sh = lerp(frame, [boardAt - 12, boardAt], [0, 1]);
    return (
      <AbsoluteFill style={{background: 'linear-gradient(180deg, #DCE5FF 0px, #EEF2FB 200px, #F2F4F9 360px)', padding: 20}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 10, marginTop: 8, fontFamily: FONT, fontSize: 20, fontWeight: 700, color: COLORS.text}}>
          <Logo size={30} />
          Harmoniser
        </div>
        <div style={{marginTop: 22, height: SCREEN_H - 120, borderRadius: 28, background: 'rgba(255,255,255,0.9)', overflow: 'hidden', position: 'relative'}}>
          {[0, 1, 2, 3, 4].map((i) => (
            <div key={i} style={{margin: '22px 20px', height: i === 0 ? 40 : 64, borderRadius: 16, background: '#EEF2FF', opacity: Math.max(0, Math.min(1, sh * 5 - i))}} />
          ))}
          <div style={{position: 'absolute', top: 0, bottom: 0, width: 140, left: -140 + ((frame * 22) % 600), background: 'linear-gradient(90deg, rgba(255,255,255,0), rgba(255,255,255,0.9), rgba(255,255,255,0))'}} />
        </div>
      </AbsoluteFill>
    );
  }
  const build = pop(frame, boardAt);
  const style = {transform: `scale(${build.scale})`, opacity: build.opacity};
  if (hasFootage(p.footage)) {
    return (
      <AbsoluteFill style={style}>
        <Sequence from={boardAt} layout="none">
          <FootageVideo name={p.footage} />
        </Sequence>
      </AbsoluteFill>
    );
  }
  if (p.board) {
    const Board = BOARDS[p.board];
    return (
      <AbsoluteFill style={style}>
        <BoardFit>
          <Board f={f} tapAt={tapAt} />
        </BoardFit>
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={style}>
      <FootageVideo name={p.footage} />
    </AbsoluteFill>
  );
};

// ---------- Moments ----------

/** Thin line drawing of Kraków's skyline with Wawel Castle, drawing itself. */
const KrakowSkyline: React.FC<{progress: number}> = ({progress}) => {
  const d =
    'M0 820 L120 820 L120 760 L150 760 L150 700 L170 680 L190 700 L190 760 L260 760 L260 720 L300 720 L300 820 ' +
    'L360 820 L360 640 L380 600 L400 640 L400 690 L440 690 L440 560 L455 520 L470 560 L470 690 L520 690 L520 740 ' +
    // Wawel: walls, cathedral domes and towers
    'L560 740 L560 660 L600 660 L600 620 L640 620 L640 660 L700 660 L700 600 L720 560 L740 600 L740 660 ' +
    'Q770 600 800 660 L860 660 L860 580 L880 540 L900 580 L900 660 L960 660 L960 700 L1040 700 L1040 640 ' +
    'L1060 610 L1080 640 L1080 740 L1160 740 L1160 620 L1176 560 L1192 620 L1192 760 L1260 760 L1260 700 ' +
    'L1300 680 L1340 700 L1340 820 L1440 820 L1440 600 L1452 480 L1464 600 L1464 640 L1500 640 L1500 560 L1512 500 ' +
    'L1524 560 L1524 820 L1640 820 L1640 760 L1700 760 L1700 820 L1920 820';
  return (
    <svg width={1920} height={1080} viewBox="0 0 1920 1080" style={{position: 'absolute', inset: 0}}>
      <path d={d} fill="none" stroke={COLORS.blue} strokeOpacity={0.35} strokeWidth={3} strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - progress} />
      <path d="M0 860 Q480 830 960 860 T1920 860" fill="none" stroke={COLORS.blue} strokeOpacity={0.2} strokeWidth={2} pathLength={1} strokeDasharray={1} strokeDashoffset={1 - progress} />
    </svg>
  );
};

const TrackLanes: React.FC<{frame: number; countAt: number}> = ({frame, countAt}) => {
  const v = countUp(frame, countAt, 0, 6.21, 30);
  const shift = (frame * 18) % 240;
  return (
    <AbsoluteFill>
      <svg width={1920} height={1080} style={{position: 'absolute', inset: 0}}>
        {[0, 1, 2, 3, 4].map((i) => (
          <path key={i} d={`M-100 ${700 + i * 70} Q960 ${560 + i * 70} 2020 ${700 + i * 70}`} fill="none" stroke="#FF7A45" strokeOpacity={0.18} strokeWidth={4} strokeDasharray="120 120" strokeDashoffset={shift} />
        ))}
      </svg>
      <div style={{position: 'absolute', left: 70, top: 560, display: 'flex', fontFamily: FONT, fontWeight: 800, fontSize: 380, lineHeight: 1, color: 'rgba(255,122,69,0.2)', letterSpacing: -10}}>
        {/* Rolling digits: each digit scrolls vertically like an odometer. */}
        {v.toFixed(2).split('').map((ch, i) => {
          if (ch === '.') return <span key={i}>.</span>;
          const place = [1, 0, 0.1, 0.01][i];
          const pos = (v / place) % 10;
          return (
            <span key={i} style={{display: 'inline-block', height: 380, overflow: 'hidden', width: 232, position: 'relative'}}>
              <span style={{position: 'absolute', left: 0, top: -pos * 380}}>
                {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0].map((d, k) => (
                  <div key={k} style={{height: 380}}>{d}</div>
                ))}
              </span>
            </span>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const TennisBall: React.FC<{frame: number}> = ({frame}) => {
  const x = lerp(frame, [0, 90], [-80, 2000]);
  const ph = (frame % BEAT) / BEAT; // bounce every beat
  const y = 900 - Math.sin(ph * Math.PI) * 420;
  return (
    <div style={{position: 'absolute', left: x, top: y, width: 96, height: 96, borderRadius: 48, background: '#D7F04A', boxShadow: 'inset -8px -8px 0 rgba(0,0,0,0.08)', transform: `rotate(${frame * 12}deg)`}}>
      <svg width={96} height={96} viewBox="0 0 70 70">
        <path d="M10 18 Q35 35 10 54" fill="none" stroke="#fff" strokeWidth={4} />
        <path d="M60 18 Q35 35 60 54" fill="none" stroke="#fff" strokeWidth={4} />
      </svg>
    </div>
  );
};

const WaterWash: React.FC<{frame: number; at: number; dur: number}> = ({frame, at, dur}) => {
  const p = lerp(frame, [at, at + dur], [0, 1], Easing.in(Easing.quad));
  if (p <= 0) return null;
  const top = 1080 - p * 1240;
  const w = Math.sin(frame / 3) * 30;
  return (
    <svg width={1920} height={1080} style={{position: 'absolute', inset: 0}}>
      <path d={`M0 ${top + 40} Q480 ${top - 20 + w} 960 ${top + 40} T1920 ${top + 40} L1920 1080 L0 1080 Z`} fill="#6E94FF" opacity={0.55} />
      <path d={`M0 ${top + 80} Q480 ${top + 140 - w} 960 ${top + 80} T1920 ${top + 80} L1920 1080 L0 1080 Z`} fill={COLORS.blue} />
    </svg>
  );
};

export const PersonaBeat: React.FC<PersonaBeatProps> = (p) => {
  const frame = useCurrentFrame();
  const t = beatTimes({...p, id: '', from: 0, transitionIn: 'cut', voId: '', name: p.name} as Persona);
  const D = p.durationInFrames;

  // Whip pans in/out (first four beats).
  const whipIn = p.whipIn ? lerp(frame, [0, 7], [1, 0], Easing.out(Easing.cubic)) : 0;
  const whipOut = p.whipOut ? lerp(frame, [D - 6, D], [0, 1], Easing.in(Easing.cubic)) : 0;
  const x = whipIn * 1400 - whipOut * 1400;
  const blur = (whipIn + whipOut) * 40;

  // Phone transform per moment.
  let phoneTransform = '';
  let phoneOrigin = 'center';
  if (p.moment === 'dive') {
    const z = lerp(frame, [D - 16, D], [1, 14], Easing.in(Easing.cubic));
    const s = SCREEN_W / 390;
    phoneOrigin = `${12 + POMODORO_RING.x * s}px ${12 + 18 + POMODORO_RING.y * s}px`;
    phoneTransform = `scale(${z})`;
  }
  const phoneIn = pop(frame, 0);

  const phone = (
    <Phone style={{transform: `${phoneTransform}`, transformOrigin: phoneOrigin}}>
      <Screen p={p} frame={frame} boardAt={t.boardAt} tapAt={t.tapAt} />
    </Phone>
  );

  // Toast: the phone splits into four phones, each showing 30.00, tilting together.
  const toastAt = t.boardAt + 30;
  const split = p.moment === 'toast' ? lerp(frame, [toastAt, toastAt + 12], [0, 1], Easing.out(Easing.back(1.4))) : 0;
  const tilt = p.moment === 'toast' ? lerp(frame, [toastAt + 18, toastAt + 26, toastAt + 34], [0, 1, 0.6], Easing.inOut(Easing.quad)) : 0;

  return (
    <AbsoluteFill style={{background: COLORS.bg, overflow: 'hidden'}}>
      <AbsoluteFill style={{background: `linear-gradient(180deg, ${COLORS.glow} 0%, rgba(220,229,255,0) 33%)`}} />
      <AbsoluteFill style={{transform: `translateX(${x}px)`, filter: blur > 0.5 ? `blur(${blur}px)` : undefined}}>
        {p.moment === 'track' && <TrackLanes frame={frame} countAt={t.boardAt} />}
        {p.initials ? <Initials letters={p.initials} frame={frame} /> : <GiantName name={p.name} frame={frame} />}
        {p.moment === 'krakow' && <KrakowSkyline progress={lerp(frame, [t.boardAt - 10, t.boardAt + 80], [0, 1], Easing.inOut(Easing.quad))} />}
        {p.moment === 'tennis' && <TennisBall frame={frame} />}
        <PromptBar prompt={p.prompt} role={p.role} frame={frame} t={t} />
        <AbsoluteFill style={{left: PHONE_X - 960, alignItems: 'center', justifyContent: 'center'}}>
          {p.moment === 'toast' && split > 0 ? (
            <div style={{position: 'relative', width: 0, height: 0}}>
              {[-1.5, -0.5, 0.5, 1.5].map((k, i) => (
                <div
                  key={i}
                  style={{
                    position: 'absolute',
                    left: -215,
                    top: -465,
                    transform: `translateX(${k * 290 * split - 330 * split}px) scale(${1 - 0.42 * split}) rotate(${(-k * 8 + (k < 0 ? 10 : -10)) * tilt}deg)`,
                    transformOrigin: 'center bottom',
                  }}
                >
                  {phone}
                </div>
              ))}
            </div>
          ) : (
            <div style={{transform: `translateY(${phoneIn.y}px) scale(${phoneIn.scale})`, opacity: phoneIn.opacity}}>{phone}</div>
          )}
        </AbsoluteFill>
        {p.moment === 'water' && <WaterWash frame={frame} at={D - 24} dur={24} />}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const PhoneCenter = Center;
