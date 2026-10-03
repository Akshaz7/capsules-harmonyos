/**
 * On-device capsule generation with the Cactus engine (cactus HAR, LFM2-VL-450M cq4).
 *
 * The small model does slot-filling only: it picks an intent kind and extracts a few slots
 * as one line of JSON. The capsule is then built deterministically (same shapes as
 * RuleParser) and must pass validateCapsule. Slots must be grounded in the request
 * (every word slot shares a word with it, every number appears in it), which rejects the
 * model copying the prompt's examples. One retry with the rejection reason fed back.
 * Measured on the 10 eval requests: 5/10 correct, 0 wrong-but-valid, 5 clean rejections.
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

// Sent in the user turn with the request last (scored better than a system message on LFM2-450M).
const SLOT_PROMPT: string =
  'Classify the request and extract its details. Reply with ONE line of JSON only, no prose, no code fences.\n' +
  'Pick exactly one kind:\n' +
  '{"kind":"timers","timers":[{"label":"Eggs","minutes":7}]}  for durations, one entry per timer\n' +
  '{"kind":"counter","label":"Pages"}  for counting things; add "goal":8,"unit":"glasses" when a target number is given\n' +
  '{"kind":"checklist","name":"Gym bag","items":["towel","bottle"]}  for lists of things\n' +
  '{"kind":"schedule","what":"Vitamins","times":["Morning","Night"]}  for things done at times of day\n' +
  '{"kind":"reminder","text":"Call mum"}  for remind me to do something\n' +
  '{"kind":"split","total":90,"people":3}  for splitting an amount\n' +
  '{"kind":"note","text":"..."}  only if nothing else fits\n' +
  'Examples:\n' +
  'eggs 7 and toast 3 -> {"kind":"timers","timers":[{"label":"Eggs","minutes":7},{"label":"Toast","minutes":3}]}\n' +
  'track pages I read -> {"kind":"counter","label":"Pages read"}\n' +
  'read 20 pages -> {"kind":"counter","label":"Pages","goal":20,"unit":"pages"}\n' +
  'gym bag: towel bottle shoes -> {"kind":"checklist","name":"Gym bag","items":["towel","bottle","shoes"]}\n' +
  'vitamins morning and night -> {"kind":"schedule","what":"Vitamins","times":["Morning","Night"]}\n' +
  'remind me to call mum -> {"kind":"reminder","text":"Call mum"}\n' +
  'share 90 by 3 -> {"kind":"split","total":90,"people":3}';

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

/** Returns the first {...} object in a reply, stripping fences or stray prose. */
function extractObject(reply: string): string {
  const s = reply.trim().replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
  const start = s.indexOf('{');
  const end = s.lastIndexOf('}');
  return start >= 0 && end > start ? s.substring(start, end + 1) : s;
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

function numberInRequest(n: number, request: string): boolean {
  return (request.match(/\d+(?:\.\d+)?/g) ?? []).some((m: string) => parseFloat(m) === n);
}

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
    if (!words(t).some((w: string) => requestWords.includes(w))) {
      return `"${t}" is not in the request; use the request's own words`;
    }
  }
  for (const n of numSlots) {
    if (!numberInRequest(n, request)) {
      return `the number ${n} is not in the request; use the request's own numbers`;
    }
  }
  return null;
}

/** Turns the model's slot reply into a capsule, or explains what was wrong with the reply. */
function buildFromReply(reply: string, request: string): BuildResult {
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
  const ungrounded = checkGrounding(obj, request);
  if (ungrounded !== null) {
    return { error: ungrounded };
  }
  switch (str(obj, 'kind')) {
    case 'timers':
      return buildTimers(obj);
    case 'counter':
      return buildCounter(obj);
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
      return { error: '"kind" must be one of timers, counter, checklist, schedule, reminder, split, note' };
  }
}

// ---- Provider ----

/** On-device capsule source. Construct once; call init() before generate(). */
export class CactusProvider implements CapsuleSource {
  private status: OnDeviceStatus = { ready: false, message: ON_DEVICE_NOT_INSTALLED };
  private initPromise: Promise<boolean> | null = null;

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

  /** Slot-filling + deterministic build + validateCapsule, with one retry on errors. */
  async generate(request: string): Promise<GenerateResult> {
    const req = request.trim();
    if (!this.status.ready) {
      return { ok: false, error: this.status.message, details: [] };
    }
    if (req.length === 0 || req.length > MAX_REQUEST_LENGTH) {
      return { ok: false, error: 'The request is empty or too long.', details: [] };
    }
    let prompt = `${SLOT_PROMPT}\nRequest: ${req} ->`;
    let lastError = '';
    let details: string[] = [];
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      let engine: EngineResponse;
      try {
        engine = JSON.parse(await complete(prompt, undefined, MAX_TOKENS)) as EngineResponse;
      } catch (e) {
        return { ok: false, error: 'The on-device model failed to run.', details: [] };
      }
      if (engine.success === false) {
        return { ok: false, error: `The on-device model failed: ${engine.error ?? 'unknown error'}`, details: [] };
      }
      const built = buildFromReply(engine.response ?? '', req);
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
      prompt = `${SLOT_PROMPT}\nYour previous reply was rejected: ${lastError}. Reply again with one line of JSON only.\n` +
        `Request: ${req} ->`;
    }
    return {
      ok: false,
      error: `The on-device model could not make this capsule (${lastError}).`,
      details: details
    };
  }
}
