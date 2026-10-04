// Every timing, line and on-screen string for the trailer lives here.
// Frames are at 30 fps. One beat at 120 BPM = 15 frames.

export const FPS = 30;
export const WIDTH = 1920;
export const HEIGHT = 1080;
export const DURATION = 1950;
export const BEAT = 15;

export const SCENES = {
  problem: {from: 0, to: 240},
  pain: {from: 240, to: 390},
  turn: {from: 390, to: 540},
  people: {from: 540, to: 1410},
  home: {from: 1410, to: 1560},
  native: {from: 1560, to: 1740},
  end: {from: 1740, to: 1950},
} as const;
export type SceneKey = keyof typeof SCENES;

// Music is muted here (absolute frames).
export const SILENT_BEAT = {from: 375, to: 390};
// Music ducks to this level under voice, with fades of this many frames.
export const DUCK_LEVEL = 0.25;
export const DUCK_FADE = 6;
export const MUSIC_VOLUME = 0.8;
export const VO_VOLUME = 1;
export const SFX_VOLUME = 0.5;

export type VoLine = {
  id: string;
  scene: SceneKey;
  /** Absolute frame the voice starts. */
  at: number;
  /** Absolute frame the slot ends (next line or scene end). */
  end: number;
  /** On-screen / script text. */
  text: string;
  /** Respelled text sent to TTS, if different. */
  tts?: string;
};

export const VO: VoLine[] = [
  {id: 's1-phone', scene: 'problem', at: 6, end: 44, text: 'This is your phone.'},
  {id: 's1-timers', scene: 'problem', at: 44, end: 86, text: 'Three timer apps.'},
  {id: 's1-tips', scene: 'problem', at: 86, end: 132, text: 'Two tip calculators.'},
  {id: 's1-packing', scene: 'problem', at: 132, end: 192, text: 'A packing app from one trip.'},
  {id: 's1-once', scene: 'problem', at: 192, end: 240, text: 'All opened once.'},

  {id: 's2-download', scene: 'pain', at: 242, end: 310, text: 'Every little job means another download.'},
  {id: 's2-account', scene: 'pain', at: 310, end: 346, text: 'Another account.'},
  {id: 's2-ad', scene: 'pain', at: 346, end: 385, text: 'Another ad.'},

  {id: 's3-meet', scene: 'turn', at: 390, end: 452, text: 'Meet Harmoniser, for HarmonyOS.', tts: 'Meet Harmoniser, for Harmony O S.'},
  {id: 's3-ask', scene: 'turn', at: 452, end: 540, text: "Don't search for an app. Ask for one."},

  {id: 'p-emma', scene: 'people', at: 546, end: 660, text: "Emma's got a geography test tomorrow."},
  {id: 'p-judge', scene: 'people', at: 666, end: 870, text: "A judge tried to break it with this. It planned the day around Kraków's forecast.", tts: "A judge tried to break it with this. It planned the day around Krah-koof's forecast."},
  {id: 'p-tyler', scene: 'people', at: 876, end: 990, text: "Tyler's running a 10K. He only thinks in miles.", tts: "Tyler's running a ten K. He only thinks in miles."},
  {id: 'p-friends', scene: 'people', at: 996, end: 1110, text: 'Four friends. One bill. Zero arguments.'},
  {id: 'p-olivia', scene: 'people', at: 1114, end: 1200, text: 'Olivia works in fifty-minute sprints.'},
  {id: 'p-rose', scene: 'people', at: 1204, end: 1320, text: "Grandma Rose promised eight glasses. She's getting there."},
  {id: 'p-mike', scene: 'people', at: 1324, end: 1410, text: "Mike says he won. Now there's proof."},

  {id: 's5-pin', scene: 'home', at: 1418, end: 1560, text: 'Seven apps. Pin the ones you actually use.'},

  {id: 's6-native', scene: 'native', at: 1562, end: 1622, text: 'Built natively for HarmonyOS.', tts: 'Built natively for Harmony O S.'},
  {id: 's6-tap', scene: 'native', at: 1622, end: 1666, text: 'Tap them right there.'},
  {id: 's6-calendar', scene: 'native', at: 1666, end: 1740, text: 'Timers land in your calendar.'},

  {id: 's7-name', scene: 'end', at: 1748, end: 1782, text: 'Harmoniser.'},
  {id: 's7-tagline', scene: 'end', at: 1782, end: 1858, text: "Tiny apps you don't need to download."},
  {id: 's7-built', scene: 'end', at: 1858, end: 1950, text: 'Built for HarmonyOS.', tts: 'Built for Harmony O S.'},
];

export const vo = (id: string): VoLine => {
  const l = VO.find((v) => v.id === id);
  if (!l) throw new Error(`No VO line ${id}`);
  return l;
};

export const VOICE = {
  defaultVoiceId: 'nPczCjzI2devNBz1zQrb',
  model: 'eleven_multilingual_v2',
  settings: {stability: 0.45, similarity_boost: 0.8, style: 0.3, use_speaker_boost: true},
  maxSpeed: 1.1,
};

export const MUSIC = {
  positive: 'minimal tech keynote, 120 BPM, punchy sub bass, crisp claps, glassy synth plucks, bright and confident',
  negative: 'vocals, orchestral, festival EDM, lo-fi',
  sections: [
    {name: 'intro', ms: 8000, styles: 'sparse pulse, building'},
    {name: 'tension', ms: 5000, styles: 'builds harder'},
    {name: 'drop', ms: 5000, styles: 'main beat lands near the start'},
    {name: 'groove', ms: 29000, styles: 'full and punchy'},
    {name: 'lift', ms: 5000, styles: 'lift'},
    {name: 'native', ms: 6000, styles: 'cleaner, still driving'},
    {name: 'outro', ms: 7000, styles: 'a big hit, then rings out'},
  ],
};

export const SFX = {
  whoosh: 'short airy whoosh transition, clean, modern UI',
  pop: 'soft short UI pop, bubbly, clean',
  thunk: 'soft muted thunk, object landing on a table, short',
  ticks: 'quiet laptop keyboard typing ticks, short burst',
};

export const COLORS = {
  bg: '#F2F4F9',
  glow: '#DCE5FF',
  navy: '#0F1528',
  blue: '#2F5BFF',
  orange: '#FF7A45',
  text: '#1B2236',
  secondary: '#5B6478',
  chipBg: '#EEF2FF',
  chipText: '#2A47C7',
};

// ---------- Scene 1 ----------
export const S1 = {
  rainBeats: 4, // icons rain for 4 beats from frame 0
  pullBackAt: 20,
  timersAt: vo('s1-timers').at,
  tipsAt: vo('s1-tips').at,
  packingAt: vo('s1-packing').at,
  onceAt: vo('s1-once').at,
  timerIcons: ['Timer', 'Timer+', 'Focus Timer'],
  tipIcons: ['Tip', 'Tip Pro'],
  packingIcon: 'Packing',
  bigType: {timers: '3 timer apps', tips: '2 tip calculators', packing: '1 packing app', once: 'Opened once.'},
  tag: 'Opened once.',
};

// ---------- Scene 2 ----------
export const S2 = {
  storeTapAt: 248,
  getLabel: 'Get',
  accountAt: vo('s2-account').at,
  accountTitle: 'Create account',
  adAt: vo('s2-ad').at,
  adLabel: 'Ad · 5s',
  adCountdown: [5, 4, 3],
  shakeFrames: 6,
};

// ---------- Scene 3 ----------
export const S3 = {
  cursorAt: 390,
  pullFrames: 7, // scene 2 is sucked into the cursor
  logoAt: 401, // cursor stretches into the logo
  wordmarkAt: 412,
  // the sub line and the two lines below land on their spoken words (src/lib/cues.ts)
  wordmark: 'Harmoniser',
  sub: 'for HarmonyOS',
  line1: "Don't search for an app.",
  line2: 'Ask for one.',
};

// ---------- Scene 4 ----------
export type BoardKey = 'quiz' | 'converter' | 'split' | 'pomodoro' | 'water' | 'tennis';
export type FootageKey =
  | 'judge' | 'emma' | 'tyler' | 'friends' | 'olivia' | 'rose' | 'mike'
  | 'widget-pin' | 'widget-tap' | 'calendar';
export type Moment = 'quiz' | 'krakow' | 'track' | 'toast' | 'dive' | 'water' | 'tennis';

export type Persona = {
  id: string;
  name: string; // giant outlined name ('' = initials circles)
  role?: string;
  initials?: string[];
  prompt: string;
  from: number;
  durationInFrames: number;
  footage: FootageKey;
  board?: BoardKey;
  moment: Moment;
  transitionIn: 'whip' | 'cut';
  voId: string;
};

export const PERSONAS: Persona[] = [
  {id: 'emma', name: 'EMMA', role: 'student', prompt: 'quiz me on capital cities', from: 540, durationInFrames: 120, footage: 'emma', board: 'quiz', moment: 'quiz', transitionIn: 'cut', voId: 'p-emma'},
  {id: 'judge', name: 'A JUDGE', role: 'trying to break it', prompt: 'create a to-do list using the weather in Kraków', from: 660, durationInFrames: 210, footage: 'judge', moment: 'krakow', transitionIn: 'whip', voId: 'p-judge'},
  {id: 'tyler', name: 'TYLER', role: 'runner', prompt: 'km to miles converter', from: 870, durationInFrames: 120, footage: 'tyler', board: 'converter', moment: 'track', transitionIn: 'whip', voId: 'p-tyler'},
  {id: 'friends', name: '', initials: ['A', 'B', 'C', 'D'], prompt: 'split 120 between 4', from: 990, durationInFrames: 120, footage: 'friends', board: 'split', moment: 'toast', transitionIn: 'whip', voId: 'p-friends'},
  {id: 'olivia', name: 'OLIVIA', role: 'designer', prompt: 'pomodoro 50/10', from: 1110, durationInFrames: 90, footage: 'olivia', board: 'pomodoro', moment: 'dive', transitionIn: 'cut', voId: 'p-olivia'},
  {id: 'rose', name: 'GRANDMA ROSE', prompt: 'water 8 glasses', from: 1200, durationInFrames: 120, footage: 'rose', board: 'water', moment: 'water', transitionIn: 'cut', voId: 'p-rose'},
  {id: 'mike', name: 'MIKE', role: 'tennis player', prompt: 'tennis score, me vs Sam', from: 1320, durationInFrames: 90, footage: 'mike', board: 'tennis', moment: 'tennis', transitionIn: 'cut', voId: 'p-mike'},
];

// Beat layout inside a PersonaBeat, as fractions/frames of the beat.
export const BEAT_LAYOUT = {
  typeStart: 4,
  typingShort: 24, // prompts up to SHORT_PROMPT chars
  typingLong: 36,
  shortPrompt: 24,
  sendHold: 4, // frames after typing before send
  flyFrames: 12, // tiles fly into the phone
  // tap happens this many frames after the board appears
  tapDelay: 14,
};

export const BOARD_STRINGS = {
  madeOnPhone: 'Made on your phone · no internet',
  madeByRules: 'Made by rules',
  quiz: {title: 'Capital cities quiz', correct: 'Correct'},
  converter: {title: 'Kilometres to miles'},
  split: {title: 'Split 120 between 4', each: '30.00'},
  pomodoro: {title: 'Pomodoro', focus: 50, rest: 10},
  water: {title: 'Water'},
  tennis: {title: 'Tennis: Me vs Sam', advantage: 'Advantage you'},
};

// ---------- Scene 5 ----------
export const S5 = {
  dropStart: 1425, // old icons drop off one row per beat from here
  widgetLand: [1466, 1472, 1488, 1494], // each widget folds down and snaps in (thunk)
  floodAt: 1500,
  widgets: [
    {kind: 'checklist', title: 'Checklist', caption: '0 / 3 done'},
    {kind: 'timer', title: 'Pomodoro', caption: '50:00'},
    {kind: 'goal', title: 'Water', caption: '6 / 8'},
    {kind: 'score', title: 'Tennis', caption: 'Games 3 – 2'},
  ],
  widgetLabel: 'Harmoniser',
};

// ---------- Scene 6 ----------
export const S6 = {
  label: 'ArkTS · ArkUI',
  codeFile: 'entry/src/main/ets/widget/pages/HarmoniserCard.ets',
  pinUntil: vo('s6-tap').at,
  tapAt: vo('s6-tap').at,
  calendarAt: vo('s6-calendar').at,
};

// ---------- Scene 7 ----------
export const S7 = {
  shrinkTo: 1752,
  logoAt: 1752,
  taglineAt: vo('s7-tagline').at,
  taglineDark: 'Tiny apps',
  taglineBlue: "you don't need to download",
  builtAt: vo('s7-built').at,
  built: 'Built for HarmonyOS',
  tryStart: 1838,
  trySlot: 37, // each 'Try:' line types for 36 frames, one char at a time
  tries: ['Try: tennis scoreboard me vs Sam', 'Try: km to miles converter', 'Try: split dinner 120 between 4'],
  urlsAt: 1880,
  urls: ['github.com/Akshaz7/capsules-harmonyos', 'harmoniser-web.vercel.app'],
  disclaimer: 'Some screens are design previews.',
};
