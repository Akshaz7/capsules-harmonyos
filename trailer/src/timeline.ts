// Every timing, line and on-screen string for the trailer lives here.
// Frames are at 30 fps. One beat at 120 BPM = 15 frames.

export const FPS = 30;
export const WIDTH = 1920;
export const HEIGHT = 1080;
export const DURATION = 1950;
export const BEAT = 15;

export const SCENES = {
  problem: {from: 0, to: 210},
  pain: {from: 210, to: 345},
  turn: {from: 345, to: 495},
  people: {from: 495, to: 1005},
  options: {from: 1005, to: 1425},
  home: {from: 1425, to: 1545},
  native: {from: 1545, to: 1725},
  end: {from: 1725, to: 1950},
} as const;
export type SceneKey = keyof typeof SCENES;

// Music is muted here (absolute frames).
export const SILENT_BEAT = {from: 330, to: 345};
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
  {id: 's1-phone', scene: 'problem', at: 4, end: 46, text: 'This is your phone.'},
  {id: 's1-timers', scene: 'problem', at: 50, end: 86, text: 'Three timers.'},
  {id: 's1-tips', scene: 'problem', at: 90, end: 126, text: 'Two tip apps.'},
  {id: 's1-packing', scene: 'problem', at: 130, end: 166, text: 'One packing app.'},
  {id: 's1-once', scene: 'problem', at: 170, end: 206, text: 'Opened once.'},

  {id: 's2-download', scene: 'pain', at: 213, end: 269, text: 'Every job needs its own app.'},
  {id: 's2-account', scene: 'pain', at: 273, end: 307, text: 'Another account.'},
  {id: 's2-ad', scene: 'pain', at: 310, end: 344, text: 'Another ad.'},

  {id: 's3-meet', scene: 'turn', at: 348, end: 424, text: 'Meet Harmoniser, for HarmonyOS.', tts: 'Meet Harmoniser, for Harmony O S.'},
  {id: 's3-ask', scene: 'turn', at: 424, end: 490, text: "Don't search for an app. Ask."},

  {id: 'p-emma', scene: 'people', at: 499, end: 559, text: 'Emma has a geography test.'},
  {id: 'p-judge', scene: 'people', at: 579, end: 715, text: "A judge tried to break it. Tasks and Kraków's weather, in one.", tts: "A judge tried to break it. Tasks and Krah-koof's weather, in one."},
  {id: 'p-tyler', scene: 'people', at: 749, end: 813, text: 'Tyler runs a 10K. In miles.', tts: 'Tyler runs a ten K. In miles.'},
  {id: 'p-rose', scene: 'people', at: 839, end: 899, text: 'Grandma Rose: six of eight.'},
  {id: 'p-mike', scene: 'people', at: 929, end: 989, text: "Mike won. Here's the proof."},

  {id: 'o-phone', scene: 'options', at: 1009, end: 1075, text: 'Built on the phone. No account.'},
  {id: 'o-ai', scene: 'options', at: 1112, end: 1208, text: 'Bigger jobs use cloud AI. You choose.'},
  {id: 'o-market', scene: 'options', at: 1219, end: 1285, text: 'Start from the marketplace.'},
  {id: 'o-share', scene: 'options', at: 1324, end: 1400, text: 'Share a capsule as a file or QR.'},

  {id: 's5-pin', scene: 'home', at: 1429, end: 1499, text: 'Pin the ones you actually use.'},

  {id: 's6-native', scene: 'native', at: 1548, end: 1616, text: 'Built natively for HarmonyOS.', tts: 'Built natively for Harmony O S.'},
  {id: 's6-tap', scene: 'native', at: 1620, end: 1672, text: 'Tap them right there.'},
  {id: 's6-calendar', scene: 'native', at: 1676, end: 1726, text: 'Timers land in your calendar.'},

  {id: 's7-name', scene: 'end', at: 1728, end: 1762, text: 'Harmoniser.'},
  {id: 's7-tagline', scene: 'end', at: 1766, end: 1846, text: "Tiny apps you don't need to download."},
  {id: 's7-built', scene: 'end', at: 1850, end: 1912, text: 'Built for HarmonyOS.', tts: 'Built for Harmony O S.'},
];

export const vo = (id: string): VoLine => {
  const l = VO.find((v) => v.id === id);
  if (!l) throw new Error(`No VO line ${id}`);
  return l;
};

export const VOICE = {
  // Liam, "Energetic, Social Media Creator": light and snappy, serious but keen.
  defaultVoiceId: 'TX3LPaxmHKxFdv7VOQHJ',
  model: 'eleven_turbo_v2_5',
  settings: {stability: 0.4, similarity_boost: 0.75, style: 0.45, use_speaker_boost: true, speed: 1.05},
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
  captions: {timers: 'Three timers.', tips: 'Two tip apps.', packing: 'One packing app.', once: 'Opened once.'},
  tag: 'Opened once.',
};

// ---------- Scene 2 ----------
export const S2 = {
  storeTapAt: 215,
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
  cursorAt: 345,
  pullFrames: 7, // scene 2 is sucked into the cursor
  logoAt: 356, // cursor stretches into the logo
  wordmarkAt: 367,
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
  | 'widget-pin' | 'widget-pin-large' | 'widget-tap' | 'calendar'
  | 'options-phone' | 'options-ai' | 'options-market' | 'options-share';
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
  {id: 'emma', name: 'EMMA', role: 'student', prompt: 'quiz me on capital cities', from: 495, durationInFrames: 80, footage: 'emma', board: 'quiz', moment: 'quiz', transitionIn: 'cut', voId: 'p-emma'},
  {id: 'judge', name: 'A JUDGE', role: 'trying to break it', prompt: 'make me a task list and the weather for Kraków', from: 575, durationInFrames: 170, footage: 'judge', moment: 'krakow', transitionIn: 'whip', voId: 'p-judge'},
  {id: 'tyler', name: 'TYLER', role: 'runner', prompt: 'km to miles converter', from: 745, durationInFrames: 90, footage: 'tyler', board: 'converter', moment: 'track', transitionIn: 'whip', voId: 'p-tyler'},
  {id: 'rose', name: 'GRANDMA ROSE', prompt: 'water 8 glasses', from: 835, durationInFrames: 90, footage: 'rose', board: 'water', moment: 'water', transitionIn: 'cut', voId: 'p-rose'},
  {id: 'mike', name: 'MIKE', role: 'tennis player', prompt: 'tennis score, me vs Sam', from: 925, durationInFrames: 80, footage: 'mike', board: 'tennis', moment: 'tennis', transitionIn: 'cut', voId: 'p-mike'},
];

// ---------- Options (real app footage) ----------
export type OptionsBeat = {
  id: string;
  from: number;
  durationInFrames: number;
  footage: FootageKey;
  voId: string;
  caption: string;
  sub: string;
};

export const OPTIONS: OptionsBeat[] = [
  {id: 'phone', from: 1005, durationInFrames: 105, footage: 'options-phone', voId: 'o-phone', caption: 'Built on the phone', sub: 'No account. No internet.'},
  {id: 'ai', from: 1110, durationInFrames: 105, footage: 'options-ai', voId: 'o-ai', caption: 'Cloud AI, your choice', sub: 'EU-only is one switch.'},
  {id: 'market', from: 1215, durationInFrames: 105, footage: 'options-market', voId: 'o-market', caption: 'The marketplace', sub: 'Install with consent.'},
  {id: 'share', from: 1320, durationInFrames: 105, footage: 'options-share', voId: 'o-share', caption: 'Share a capsule', sub: 'File or QR code.'},
];

// Beat layout inside a PersonaBeat, as fractions/frames of the beat.
export const BEAT_LAYOUT = {
  typeStart: 4,
  typingShort: 14, // prompts up to SHORT_PROMPT chars
  typingLong: 22,
  shortPrompt: 24,
  sendHold: 2, // frames after typing before send
  flyFrames: 8, // tiles fly into the phone
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
  dropStart: 1437, // old icons drop off one row per beat from here
  widgetLand: [1469, 1475, 1491, 1497], // each widget folds down and snaps in (thunk)
  floodAt: 1509,
  widgets: [
    {kind: 'checklist', title: 'Chicken …', caption: '0 / 7 done', rows: ['Gather ingredients'], more: '+6 more'},
    {kind: 'timer', title: 'Pomodoro', label: 'Focus', caption: '50:00', action: 'Sta…', action2: 'Sta…'},
    {kind: 'goal', title: 'Water', label: 'Goal', caption: '6 / 8', action: '+1', action2: 'Edit'},
    {kind: 'score', title: 'Tennis', label: 'Games', caption: '3 – 2', action: 'Point', action2: 'Undo'},
  ],
  widgetLabel: 'Harmoniser',
};

// ---------- Scene 6 ----------
export const S6 = {
  label: 'ArkTS · ArkUI',
  codeFile: 'entry/src/main/ets/widget/pages/HarmoniserCard.ets',
  // Scene 6 is 180 frames: pin small, pin large, tap the widgets, calendar.
  pinAt: 0,
  largeAt: 58,
  tapAt: 116,
  calendarAt: 146,
};

// ---------- Scene 7 ----------
export const S7 = {
  shrinkTo: 1728,
  logoAt: 1728,
  taglineAt: vo('s7-tagline').at,
  taglineDark: 'Tiny apps',
  taglineBlue: "you don't need to download",
  builtAt: vo('s7-built').at,
  built: 'Built for HarmonyOS',
  tryStart: 1852,
  trySlot: 32, // each 'Try:' line types out one char at a time
  tries: ['Try: tennis scoreboard me vs Sam', 'Try: km to miles converter', 'Try: split dinner 120 between 4'],
  urlsAt: 1898,
  urls: ['github.com/Akshaz7/capsules-harmonyos', 'harmoniser.keanuc.net'],
  disclaimer: 'Some screens are design previews.',
};
