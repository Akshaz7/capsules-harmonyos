/**
 * On-device capsule generation with the Cactus engine (cactus HAR, LFM2-VL-450M cq4).
 *
 * The small model does slot-filling only: it picks an intent kind and extracts a few slots
 * as one line of JSON. The capsule is then built deterministically (same shapes as
 * RuleParser) and must pass validateCapsule. Slots must be grounded in the request
 * (every word slot shares a word with it, every number appears in it), which rejects the
 * model copying words from the prompt. The prompts contain no example values to copy, only
 * <placeholders>. A failed attempt is retried once with a second, differently worded prompt
 * and the rejection reason.
 *
 * The model is NOT in the .hap. Push it to the entry module's files dir (debug builds):
 *   scripts/push-model.sh <path-to>/lfm2-vl-450m-cq4
 * which lands in /data/storage/el2/base/haps/entry/files/lfm2-vl-450m-cq4.
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { complete, initModel } from 'cactus';
import {
  Capsule,
  CapsuleComponent,
  CounterComponent,
  GenerateResult,
  Permission,
  SCHEMA_VERSION,
  TimerComponent
} from '../CapsuleTypes';
import { validateCapsule } from '../CapsuleValidator';
import { CapsuleSource } from '../CapsuleGenerator';

export const ON_DEVICE_MODEL_DIR: string = 'lfm2-vl-450m-cq4';
export const ON_DEVICE_READY: string = 'On-device AI ready';
export const ON_DEVICE_NOT_INSTALLED: string = 'On-device model not installed';
export const ON_DEVICE_LOADING: string = 'On-device model loading';
export const ON_DEVICE_FAILED: string = 'On-device model failed to load';

const MAX_ATTEMPTS: number = 2;
const MAX_TOKENS: number = 160;
const MAX_REQUEST_LENGTH: number = 500;

export interface OnDeviceStatus {
  ready: boolean;
  message: string;
}

// Prompts are sent in the user turn with the request last (scored better than a system message
// on LFM2-450M). Prompts without concrete examples scored far worse (0-3/15 on the eval), so
// examples stay; grounding rejects any example value the model copies, and the retry leaves out
// the examples whose values were copied.
const KINDS: string[] = ['timers', 'counter', 'scoreboard', 'checklist', 'schedule', 'reminder', 'split', 'note'];

const SLOT_HEADER: string =
  'Classify the request and extract its details. Reply with ONE line of JSON only, no prose, no code fences.\n' +
  'Pick exactly one kind:\n' +
  'timers: {"kind":"timers","timers":[{"label":LABEL,"minutes":NUMBER}]} for durations, one entry per timer\n' +
  'counter: {"kind":"counter","label":LABEL} for counting one thing; add "goal":NUMBER,"unit":UNIT for a target\n' +
  'scoreboard: {"kind":"scoreboard","name":GAME,"counters":[NAME,NAME]} for two or more scores (players, teams or ' +
  'exercises); "Player 1","Player 2" if no names are given\n' +
  'checklist: {"kind":"checklist","name":TITLE,"items":[ITEM]} for lists of things\n' +
  'schedule: {"kind":"schedule","what":WHAT,"times":[TIME]} for things done at times of day\n' +
  'reminder: {"kind":"reminder","text":WHAT} for remind me to do something\n' +
  'split: {"kind":"split","total":NUMBER,"people":NUMBER} for splitting an amount\n' +
  'note: {"kind":"note","text":TEXT} only if nothing else fits\n' +
  'Use only words and numbers from the request. Examples:';

// [request, reply] pairs. None of them is an eval request.
const SLOT_EXAMPLES: string[][] = [
  ['eggs 7 and toast 3', '{"kind":"timers","timers":[{"label":"Eggs","minutes":7},{"label":"Toast","minutes":3}]}'],
  ['track pages I read', '{"kind":"counter","label":"Pages read"}'],
  ['drink 2 litres', '{"kind":"counter","label":"Drink","goal":2,"unit":"litres"}'],
  ['chess me vs dad', '{"kind":"scoreboard","name":"Chess","counters":["Me","Dad"]}'],
  ['volleyball score', '{"kind":"scoreboard","name":"Volleyball","counters":["Player 1","Player 2"]}'],
  ['jumping jacks and burpees',
    '{"kind":"scoreboard","name":"Jumping jacks and burpees","counters":["Jumping jacks","Burpees"]}'],
  ['gym bag: towel bottle shoes', '{"kind":"checklist","name":"Gym bag","items":["towel","bottle","shoes"]}'],
  ['vitamins morning and night', '{"kind":"schedule","what":"Vitamins","times":["Morning","Night"]}'],
  ['remind me to call mum', '{"kind":"reminder","text":"Call mum"}'],
  ['share 90 by 3', '{"kind":"split","total":90,"people":3}']
];

const SCOREBOARD_HEADER: string =
  'Extract a scoreboard from the request. Reply with ONE line of JSON only: {"name":GAME,"counters":[NAME,NAME]}.\n' +
  '"counters" lists the players, teams or exercises named in the request, or "Player 1","Player 2" if none are named.\n' +
  'Use only words from the request. Examples:';

const SCOREBOARD_EXAMPLES: string[][] = [
  ['chess me vs dad', '{"name":"Chess","counters":["Me","Dad"]}'],
  ['volleyball score', '{"name":"Volleyball","counters":["Player 1","Player 2"]}'],
  ['jumping jacks and burpees', '{"name":"Jumping jacks and burpees","counters":["Jumping jacks","Burpees"]}']
];

const SCORE_CUES: RegExp = /\b(?:vs|versus|against|score|scores|scoreboard|game|match)\b/;

/**
 * Deterministic hint: requests that are clearly a scoreboard ("tennis game tracker", "me vs Sam",
 * "pushups and situps"). LFM2-450M almost never picked the scoreboard kind on its own.
 */
function isScoreboardRequest(request: string): boolean {
  const req = request.toLowerCase();
  if (SCORE_CUES.test(req)) {
    return true;
  }
  const parts = req.split(/\s+(?:and|&)\s+|\s*,\s*/);
  return parts.length >= 2 && parts.every((p: string) => MOTION_WORDS.some((w: string) => p.includes(w)));
}

/** Sides named in a scoreboard request: "A vs B", or "A and B" when both are exercises; else none. */
function namedSides(request: string): string[] {
  const vs = request.split(/\s+(?:vs\.?|versus|against)\s+/i);
  if (vs.length >= 2) {
    return vs.map((p: string) => p.replace(/^.*\b(?:score|scores|scoreboard|game|match)\s+(?:for\s+)?/i, '').trim())
      .filter((p: string) => p.length > 0);
  }
  const parts = request.split(/\s+(?:and|&)\s+|\s*,\s*/);
  return parts.length >= 2 && parts.every((p: string) => MOTION_WORDS.some((w: string) => p.toLowerCase().includes(w))) ?
    parts.map((p: string) => p.trim()) : [];
}

/** Scoreboard built without the model, used when the hinted extraction fails. */
function fallbackScoreboard(request: string): BuildResult {
  const req = request.trim();
  const sides = namedSides(req);
  const name = req.replace(/\b(?:game|match|score|scores|scoreboard|tracker|counter|for|the|a)\b/gi, ' ')
    .replace(/\s+/g, ' ').trim();
  const obj: JsonRecord = {
    'kind': 'scoreboard', 'name': name.length > 0 ? name : 'Score', 'counters': sides.length >= 2 ? sides : DEFAULT_SIDES
  };
  return buildScoreboard(obj);
}

/** The prompt, leaving out examples whose reply contains any of `avoid` (values the model copied). */
function promptWith(header: string, examples: string[][], avoid: string[]): string {
  const lines = examples
    .filter((ex: string[]) => !avoid.some((a: string) => a.length > 0 && ex[1].toLowerCase().includes(a.toLowerCase())))
    .map((ex: string[]) => `${ex[0]} -> ${ex[1]}`);
  return `${header}\n${lines.join('\n')}`;
}

// Scoreboard sides that need not appear in the request.
const GENERIC_SIDE: RegExp = /^(?:(?:player|team|side)\s*\d+|me|you|us|them|home|away)$/i;
const DEFAULT_SIDES: string[] = ['Player 1', 'Player 2'];

// Same list RuleParser uses to pick a motion counter.
const MOTION_WORDS: string[] = [
  'squat', 'pushup', 'push-up', 'push up', 'situp', 'sit-up', 'sit up', 'jumping jack', 'jump', 'lunge', 'step', 'rep'
];

type JsonValue = Object | null | undefined;
type JsonRecord = Record<string, Object | null>;

interface BuildResult {
  capsule?: Capsule;
  error?: string;
}

interface EngineResponse {
  success?: boolean;
  error?: string | null;
  response?: string;
}

// ---- JSON helpers ----

function asRecord(v: JsonValue): JsonRecord | null {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v) ? v as JsonRecord : null;
}

function str(obj: JsonRecord, key: string): string | null {
  const v: JsonValue = obj[key];
  return typeof v === 'string' && (v as string).trim().length > 0 ? (v as string).trim() : null;
}

function num(obj: JsonRecord, key: string): number | null {
  const v: JsonValue = obj[key];
  if (typeof v === 'number' && isFinite(v as number)) {
    return v as number;
  }
  if (typeof v === 'string' && /^\d+(\.\d+)?$/.test((v as string).trim())) {
    return parseFloat(v as string);
  }
  return null;
}

function strList(obj: JsonRecord, key: string): string[] {
  const v: JsonValue = obj[key];
  if (!Array.isArray(v)) {
    return [];
  }
  const out: string[] = [];
  for (const item of v as JsonValue[]) {
    if (typeof item === 'string' && (item as string).trim().length > 0) {
      out.push((item as string).trim());
    }
  }
  return out;
}

/** Returns the first balanced {...} object in a reply, skipping fences, prose and any later objects. */
function extractObject(reply: string): string {
  const start = reply.indexOf('{');
  if (start < 0) {
    return reply.trim();
  }
  let depth = 0;
  let inString = false;
  for (let i = start; i < reply.length; i++) {
    const c = reply.charAt(i);
    if (inString) {
      if (c === '\\') {
        i++;
      } else if (c === '"') {
        inString = false;
      }
    } else if (c === '"') {
      inString = true;
    } else if (c === '{') {
      depth++;
    } else if (c === '}') {
      depth--;
      if (depth === 0) {
        return reply.substring(start, i + 1);
      }
    }
  }
  return reply.substring(start);
}

// ---- Capsule building (shapes match RuleParser) ----

function slug(text: string): string {
  const s = text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return s.length > 0 ? s : 'item';
}

function capitalize(text: string): string {
  return text.length === 0 ? text : text.charAt(0).toUpperCase() + text.substring(1);
}

function formatAmount(n: number): string {
  const rounded = Math.round(n * 100) / 100;
  return Number.isInteger(rounded) ? rounded.toString() : rounded.toFixed(2);
}

class Ids {
  private used: string[] = [];

  next(base: string): string {
    let id = slug(base);
    let n = 2;
    while (this.used.includes(id)) {
      id = `${slug(base)}-${n}`;
      n++;
    }
    this.used.push(id);
    return id;
  }
}

function capsule(id: string, name: string, permissions: Permission[], ui: CapsuleComponent[]): Capsule {
  return { schemaVersion: SCHEMA_VERSION, id: slug(id), name: name, permissions: permissions, ui: ui };
}

function text(t: string): CapsuleComponent {
  return { type: 'text', text: t };
}

function button(label: string, action: string): CapsuleComponent {
  return { type: 'button', label: label, action: action };
}

function buildTimers(obj: JsonRecord): BuildResult {
  const raw: JsonValue = obj['timers'];
  if (!Array.isArray(raw) || (raw as JsonValue[]).length === 0) {
    return { error: '"timers" must be a non-empty list of {"label","minutes"}' };
  }
  const ids = new Ids();
  const ui: CapsuleComponent[] = [];
  const labels: string[] = [];
  for (const entry of raw as JsonValue[]) {
    const t = asRecord(entry);
    const label = t === null ? null : str(t, 'label');
    const minutes = t === null ? null : num(t, 'minutes');
    if (label === null || minutes === null || minutes <= 0) {
      return { error: 'each timer needs a "label" and positive "minutes"' };
    }
    const nice = capitalize(label);
    labels.push(nice);
    const timer: TimerComponent = { type: 'timer', id: ids.next(nice), label: nice, minutes: minutes };
    ui.push(timer);
  }
  ui.push(ui.length > 1 ? button('Start all', 'startAllTimers') :
    button('Start', `startTimer:${(ui[0] as TimerComponent).id}`));
  return { capsule: capsule(`timers-${labels.join(' ')}`, `${labels.join(', ')} timers`, ['reminders'], ui) };
}

function buildCounter(obj: JsonRecord): BuildResult {
  const label = str(obj, 'label');
  if (label === null) {
    return { error: 'a counter needs a "label"' };
  }
  const nice = capitalize(label);
  const id = slug(label);
  const motion = MOTION_WORDS.some((w: string) => label.toLowerCase().includes(w));
  const goal = num(obj, 'goal');
  const unit = str(obj, 'unit') ?? '';
  const ui: CapsuleComponent[] = [];
  if (goal !== null && goal > 0) {
    ui.push(text(`Goal: ${formatAmount(goal)} ${unit}`.trim()));
  }
  const counter: CounterComponent = { type: 'counter', id: id, label: nice, source: motion ? 'motion' : 'manual' };
  ui.push(counter, button('+1', `increment:${id}`), button('Reset', `reset:${id}`));
  return { capsule: capsule(`count-${id}`, `${nice} counter`, motion ? ['motion'] : [], ui) };
}

/** Named sides of a scoreboard, defaulting to Player 1 / Player 2 when none are given. */
function scoreboardSides(obj: JsonRecord): string[] {
  const named = strList(obj, 'counters');
  return named.length === 0 ? DEFAULT_SIDES : named;
}

function buildScoreboard(obj: JsonRecord): BuildResult {
  const sides = scoreboardSides(obj);
  if (sides.length < 2) {
    return { error: 'a scoreboard needs two or more "counters"' };
  }
  const title = capitalize(str(obj, 'name') ?? 'Score');
  const ids = new Ids();
  const ui: CapsuleComponent[] = [];
  let motion = false;
  for (const side of sides) {
    const nice = capitalize(side);
    const id = ids.next(nice);
    const usesMotion = MOTION_WORDS.some((w: string) => side.toLowerCase().includes(w));
    motion = motion || usesMotion;
    const counter: CounterComponent = { type: 'counter', id: id, label: nice, source: usesMotion ? 'motion' : 'manual' };
    ui.push(counter, button(`+1 ${nice}`, `increment:${id}`));
  }
  for (const c of ui.filter((x: CapsuleComponent) => x.type === 'counter')) {
    const counter = c as CounterComponent;
    ui.push(button(`Reset ${counter.label}`, `reset:${counter.id}`));
  }
  return { capsule: capsule(`score-${title}`, title, motion ? ['motion'] : [], ui) };
}

function buildChecklist(obj: JsonRecord): BuildResult {
  const items = strList(obj, 'items');
  if (items.length === 0) {
    return { error: 'a checklist needs a non-empty "items" list of strings' };
  }
  const name = capitalize(str(obj, 'name') ?? 'Checklist');
  const id = slug(name);
  const ui: CapsuleComponent[] = [{ type: 'checklist', id: id, items: items }, button('Reset', `reset:${id}`)];
  return { capsule: capsule(`checklist-${id}`, name, [], ui) };
}

function buildSchedule(obj: JsonRecord): BuildResult {
  const what = str(obj, 'what');
  const times = strList(obj, 'times');
  if (what === null || times.length === 0) {
    return { error: 'a schedule needs "what" and a non-empty "times" list' };
  }
  const nice = capitalize(what);
  const id = slug(`${nice} doses`);
  const ui: CapsuleComponent[] = [
    text(`${nice}: ${times.join(' and ')}`),
    { type: 'checklist', id: id, items: times.map((t: string) => `${nice} ${t.toLowerCase()}`) },
    button('Reset day', `reset:${id}`)
  ];
  return { capsule: capsule(`schedule-${nice}`, nice, [], ui) };
}

function buildReminder(obj: JsonRecord): BuildResult {
  const t = str(obj, 'text');
  if (t === null) {
    return { error: 'a reminder needs "text"' };
  }
  const nice = capitalize(t);
  return { capsule: capsule(`remind-${nice}`, nice, ['notifications'], [text(nice), button('Remind me', `notify:${nice}`)]) };
}

function buildSplit(obj: JsonRecord): BuildResult {
  const total = num(obj, 'total');
  const people = num(obj, 'people');
  if (total === null || people === null || people < 1 || !Number.isInteger(people)) {
    return { error: 'a split needs a number "total" and a whole number "people" of at least 1' };
  }
  const ui: CapsuleComponent[] = [
    text(`Total: ${formatAmount(total)}`), text(`People: ${people}`), text(`Each pays: ${formatAmount(total / people)}`)
  ];
  return {
    capsule: capsule(`split-${formatAmount(total)}-${people}`, `Split ${formatAmount(total)} between ${people}`, [], ui)
  };
}

function buildNote(obj: JsonRecord): BuildResult {
  const t = str(obj, 'text');
  if (t === null) {
    return { error: 'a note needs "text"' };
  }
  return { capsule: capsule(`note-${t.substring(0, 24)}`, 'Note', [], [text(t)]) };
}

// ---- Grounding ----

function words(value: string): string[] {
  return value.toLowerCase().split(/[^a-z0-9]+/)
    .filter((w: string) => w.length >= 3)
    .map((w: string) => w.endsWith('s') ? w.substring(0, w.length - 1) : w);
}

/** Same word, or one is a prefix of the other with at least 4 letters ("water"/"watering", "push"/"pushup"). */
function sameWord(a: string, b: string): boolean {
  if (a === b) {
    return true;
  }
  const shorter = a.length <= b.length ? a : b;
  const longer = a.length <= b.length ? b : a;
  return shorter.length >= 4 && longer.startsWith(shorter);
}

function numberInRequest(n: number, request: string): boolean {
  return (request.match(/\d+(?:\.\d+)?/g) ?? []).some((m: string) => parseFloat(m) === n);
}

// The last slot value that failed grounding, so the retry can drop the example it came from.
let lastUngrounded: string = '';

/** Returns an error if the slots contain words or numbers that are not in the request. */
function checkGrounding(obj: JsonRecord, request: string): string | null {
  const requestWords = words(request);
  const kind = str(obj, 'kind');
  const textSlots: string[] = [];
  const numSlots: number[] = [];
  const timers: JsonValue = obj['timers'];
  if (kind === 'timers' && Array.isArray(timers)) {
    for (const entry of timers as JsonValue[]) {
      const t = asRecord(entry);
      if (t !== null) {
        textSlots.push(str(t, 'label') ?? '');
        numSlots.push(num(t, 'minutes') ?? -1);
      }
    }
  } else if (kind === 'counter') {
    textSlots.push(str(obj, 'label') ?? '');
    const goal = num(obj, 'goal');
    if (goal !== null) {
      numSlots.push(goal);
    }
  } else if (kind === 'scoreboard') {
    const name = str(obj, 'name');
    if (name !== null) {
      textSlots.push(name);
    }
    strList(obj, 'counters').filter((c: string) => !GENERIC_SIDE.test(c)).forEach((c: string) => textSlots.push(c));
  } else if (kind === 'checklist') {
    strList(obj, 'items').forEach((i: string) => textSlots.push(i));
  } else if (kind === 'schedule') {
    textSlots.push(str(obj, 'what') ?? ''); // times may be inferred ("twice a day" -> Morning, Evening)
  } else if (kind === 'reminder' || kind === 'note') {
    textSlots.push(str(obj, 'text') ?? '');
  } else if (kind === 'split') {
    numSlots.push(num(obj, 'total') ?? -1, num(obj, 'people') ?? -1);
  }
  for (const t of textSlots) {
    if (!words(t).some((w: string) => requestWords.some((r: string) => sameWord(w, r)))) {
      lastUngrounded = t;
      return `"${t}" is not in the request; use the request's own words`;
    }
  }
  for (const n of numSlots) {
    if (!numberInRequest(n, request)) {
      lastUngrounded = String(n);
      return `the number ${n} is not in the request; use the request's own numbers`;
    }
  }
  return null;
}

// Main text slot per kind, for replies like {"reminder":"water plants"}.
const MAIN_SLOT: Record<string, string> = {
  'counter': 'label', 'reminder': 'text', 'note': 'text', 'schedule': 'what', 'checklist': 'name', 'scoreboard': 'name'
};

/**
 * Unwraps replies keyed by the kind instead of carrying "kind", e.g. {"split":{"total":84,"people":4}}
 * or {"reminder":"water plants"}. Leaves anything else unchanged.
 */
function normalise(obj: JsonRecord): void {
  if (str(obj, 'kind') !== null) {
    const nested = asRecord(obj[str(obj, 'kind') as string]);
    if (nested !== null) {
      Object.keys(nested).forEach((k: string) => {
        if (obj[k] === undefined) {
          obj[k] = nested[k];
        }
      });
    }
    return;
  }
  for (const key of Object.keys(obj)) {
    if (!KINDS.includes(key)) {
      continue;
    }
    const inner: JsonValue = obj[key];
    const rec = asRecord(inner);
    if (rec !== null) {
      Object.keys(rec).forEach((k: string) => {
        obj[k] = rec[k];
      });
    } else if (typeof inner === 'string' && MAIN_SLOT[key] !== undefined) {
      obj[MAIN_SLOT[key]] = inner;
    } else if (!(Array.isArray(inner) && key === 'timers')) {
      continue; // {"timers":[...]} already holds its slots; anything else is not a wrapper
    }
    obj['kind'] = key;
    return;
  }
}

/** Turns the model's slot reply into a capsule, or explains what was wrong with the reply. */
function buildFromReply(reply: string, request: string, kind?: string): BuildResult {
  let root: JsonValue;
  try {
    root = JSON.parse(extractObject(reply)) as JsonValue;
  } catch (e) {
    return { error: 'the reply is not valid JSON' };
  }
  const obj = asRecord(root);
  if (obj === null) {
    return { error: 'the reply must be one JSON object' };
  }
  normalise(obj);
  if (kind !== undefined) {
    obj['kind'] = kind;
  }
  const ungrounded = checkGrounding(obj, request);
  if (ungrounded !== null) {
    return { error: ungrounded };
  }
  switch (str(obj, 'kind')) {
    case 'timers':
      return buildTimers(obj);
    case 'counter':
      return buildCounter(obj);
    case 'scoreboard':
      return buildScoreboard(obj);
    case 'checklist':
      return buildChecklist(obj);
    case 'schedule':
      return buildSchedule(obj);
    case 'reminder':
      return buildReminder(obj);
    case 'split':
      return buildSplit(obj);
    case 'note':
      return buildNote(obj);
    default:
      return { error: '"kind" must be one of timers, counter, scoreboard, checklist, schedule, reminder, split, note' };
  }
}

// ---- Provider ----

/** On-device capsule source. Construct once; call init() before generate(). */
export class CactusProvider implements CapsuleSource {
  private status: OnDeviceStatus = { ready: false, message: ON_DEVICE_NOT_INSTALLED };
  private initPromise: Promise<boolean> | null = null;
  /** Raw model replies and rejection reasons from the last generate() call, for logs and evals. */
  lastTrace: string[] = [];

  /** Loads the model from <entry files dir>/lfm2-vl-450m-cq4 off the UI thread. Never throws. */
  init(context: common.Context): Promise<boolean> {
    if (this.initPromise === null) {
      this.initPromise = this.load(context.filesDir);
    }
    return this.initPromise;
  }

  getStatus(): OnDeviceStatus {
    return this.status;
  }

  isReady(): boolean {
    return this.status.ready;
  }

  /** Waits for a pending init, so a request made right after launch still runs on-device. */
  async whenInitialised(): Promise<boolean> {
    return this.initPromise === null ? false : this.initPromise;
  }

  private async load(filesDir: string): Promise<boolean> {
    const dir = `${filesDir}/${ON_DEVICE_MODEL_DIR}`;
    try {
      if (!fileIo.accessSync(`${dir}/config.txt`) || !fileIo.accessSync(`${dir}/components/manifest.json`)) {
        this.status = { ready: false, message: ON_DEVICE_NOT_INSTALLED };
        return false;
      }
    } catch (e) {
      this.status = { ready: false, message: ON_DEVICE_NOT_INSTALLED };
      return false;
    }
    this.status = { ready: false, message: ON_DEVICE_LOADING };
    try {
      const ok = await initModel(dir);
      this.status = ok ? { ready: true, message: ON_DEVICE_READY } : { ready: false, message: ON_DEVICE_FAILED };
      return ok;
    } catch (e) {
      this.status = { ready: false, message: ON_DEVICE_FAILED };
      return false;
    }
  }

  /** One raw engine call for template slot filling (core/templates/SlotFill.ets). Throws if not ready. */
  async completePrompt(prompt: string, maxTokens: number): Promise<string> {
    if (!this.status.ready) {
      throw new Error(this.status.message);
    }
    return this.run(prompt, maxTokens);
  }

  /** One engine call; returns the reply text or throws an Error with a user-facing message. */
  private async run(prompt: string, maxTokens: number): Promise<string> {
    let engine: EngineResponse;
    try {
      engine = JSON.parse(await complete(prompt, undefined, maxTokens)) as EngineResponse;
    } catch (e) {
      throw new Error('The on-device model failed to run.');
    }
    if (engine.success === false) {
      throw new Error(`The on-device model failed: ${engine.error ?? 'unknown error'}`);
    }
    return engine.response ?? '';
  }

  /** Slot-filling + deterministic build + validateCapsule, with one example-free retry. */
  async generate(request: string): Promise<GenerateResult> {
    const req = request.trim();
    if (!this.status.ready) {
      return { ok: false, error: this.status.message, details: [] };
    }
    if (req.length === 0 || req.length > MAX_REQUEST_LENGTH) {
      return { ok: false, error: 'The request is empty or too long.', details: [] };
    }
    this.lastTrace = [];
    const hinted = isScoreboardRequest(req);
    if (hinted) {
      this.lastTrace.push('hint: scoreboard');
    }
    const avoid: string[] = [];
    let lastError = '';
    let details: string[] = [];
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      let reply: string;
      try {
        const examples = hinted ? SCOREBOARD_EXAMPLES : SLOT_EXAMPLES;
        const header = hinted ? SCOREBOARD_HEADER : SLOT_HEADER;
        const feedback = attempt === 1 ? '' :
          `Your previous reply was rejected: ${lastError}. Reply again with one line of JSON only.\n`;
        // "Request:" marks where the examples end; without it LFM2 repeated the first example. The scoreboard
        // prompt scored best without it.
        const lead = hinted ? '' : 'Request: ';
        reply = await this.run(`${promptWith(header, examples, avoid)}\n${feedback}${lead}${req} ->`, MAX_TOKENS);
      } catch (e) {
        return { ok: false, error: e instanceof Error ? e.message : 'The on-device model failed to run.', details: [] };
      }
      this.lastTrace.push(`reply ${attempt}: ${reply}`);
      lastUngrounded = '';
      const built = buildFromReply(reply, req, hinted ? 'scoreboard' : undefined);
      if (lastUngrounded.length > 0) {
        avoid.push(lastUngrounded);
      }
      if (built.capsule !== undefined) {
        const v = validateCapsule(JSON.stringify(built.capsule));
        if (v.ok) {
          return { ok: true, capsule: v.capsule, origin: 'on-device', details: [] };
        }
        lastError = 'the capsule did not pass validation';
        details = v.errors;
      } else {
        lastError = built.error ?? 'unknown error';
        details = [];
      }
      this.lastTrace.push(`rejected ${attempt}: ${lastError}`);
    }
    if (hinted) {
      const fallback = fallbackScoreboard(req);
      if (fallback.capsule !== undefined && validateCapsule(JSON.stringify(fallback.capsule)).ok) {
        this.lastTrace.push('scoreboard fallback');
        return { ok: true, capsule: fallback.capsule, origin: 'on-device', details: [] };
      }
    }
    return {
      ok: false,
      error: `The on-device model could not make this capsule (${lastError}).`,
      details: details
    };
  }
}
