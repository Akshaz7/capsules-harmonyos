/**
 * On-device rule parser: turns common short requests into capsules without a model.
 * Returns null when no rule matches, so the caller can fall back to the model.
 *
 * Supported shapes (case-insensitive):
 * - timers:   "3 timers pasta 9 sauce 15 bread 6", "timer eggs 7"
 * - counter:  "count my squats", "count coffees", "pushup counter"
 * - schedule: "medication 8am and 8pm", "vitamins at 9:30am, 21:00"
 * - goal:     "water 8 glasses", "drink 8 glasses of water"
 * - split:    "split 84 between 4", "split the bill 120.50 among 3 people"
 *
 * Note: schema v0 has no time-of-day reminder, so schedules become a checklist of doses.
 */
import {
  ButtonComponent,
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  Permission,
  SCHEMA_VERSION,
  TextComponent,
  TimerComponent
} from './CapsuleTypes';

const MOTION_WORDS: string[] = [
  'squat', 'pushup', 'push-up', 'push up', 'situp', 'sit-up', 'sit up', 'jumping jack', 'jump', 'lunge', 'step', 'rep'
];

const TIME_PATTERN: string = '(?:\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)|\\d{1,2}:\\d{2})';

function normalize(request: string): string {
  return request.toLowerCase().replace(/\s+/g, ' ').trim().replace(/[.!?]+$/, '').trim();
}

export function slug(text: string): string {
  const s = text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return s.length > 0 ? s : 'item';
}

function capitalize(text: string): string {
  return text.length === 0 ? text : text.charAt(0).toUpperCase() + text.substring(1);
}

function singular(word: string): string {
  if (word.endsWith('sses') || word.endsWith('ches') || word.endsWith('shes')) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s') && !word.endsWith('ss')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

function formatAmount(n: number): string {
  const rounded = Math.round(n * 100) / 100;
  return Number.isInteger(rounded) ? rounded.toString() : rounded.toFixed(2);
}

/** Allocates unique ids within one capsule. */
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
  return { schemaVersion: SCHEMA_VERSION, id: id, name: name, permissions: permissions, ui: ui };
}

function text(t: string): TextComponent {
  return { type: 'text', text: t };
}

function button(label: string, action: string): ButtonComponent {
  return { type: 'button', label: label, action: action };
}

class TimerSpec {
  label: string = '';
  minutes: number = 0;
}

function parseTimers(req: string): Capsule | null {
  const m = req.match(/^(?:(\d+)\s+)?timers?\b[:\s,]*(.+)$/);
  if (m === null) {
    return null;
  }
  const expected = m[1] !== undefined ? parseInt(m[1], 10) : -1;
  const tokens = m[2].split(/[\s,]+/).filter((t: string) => t.length > 0 && t !== 'and' && t !== '&');
  const specs: TimerSpec[] = [];
  let words: string[] = [];
  for (const token of tokens) {
    const num = token.match(/^(\d+(?:\.\d+)?)(?:m|min|mins|minutes?)?$/);
    if (num !== null) {
      if (words.length === 0) {
        return null;
      }
      const spec = new TimerSpec();
      spec.label = capitalize(words.join(' '));
      spec.minutes = parseFloat(num[1]);
      if (spec.minutes <= 0) {
        return null;
      }
      specs.push(spec);
      words = [];
    } else if (/^(m|min|mins|minutes?|for)$/.test(token) && words.length === 0) {
      continue; // unit after a number, or "for"
    } else {
      words.push(token);
    }
  }
  if (words.length > 0 || specs.length === 0 || (expected >= 0 && expected !== specs.length)) {
    return null;
  }
  const ids = new Ids();
  const ui: CapsuleComponent[] = specs.map((s: TimerSpec): CapsuleComponent => {
    const t: TimerComponent = { type: 'timer', id: ids.next(s.label), label: s.label, minutes: s.minutes };
    return t;
  });
  if (specs.length > 1) {
    ui.push(button('Start all', 'startAllTimers'));
  } else {
    ui.push(button('Start', `startTimer:${(ui[0] as TimerComponent).id}`));
  }
  const labels = specs.map((s: TimerSpec) => s.label);
  return capsule(`timers-${slug(labels.join(' '))}`, `${labels.join(', ')} timers`, ['reminders'], ui);
}

function counterCapsule(thing: string): Capsule {
  const usesMotion = MOTION_WORDS.some((w: string) => thing.includes(w));
  const id = slug(thing);
  const label = capitalize(thing);
  const counter: CounterComponent = { type: 'counter', id: id, label: label, source: usesMotion ? 'motion' : 'manual' };
  const ui: CapsuleComponent[] = [counter, button('+1', `increment:${id}`), button('Reset', `reset:${id}`)];
  return capsule(`count-${id}`, `${label} counter`, usesMotion ? ['motion'] : [], ui);
}

function parseCounter(req: string): Capsule | null {
  let m = req.match(/^count(?:\s+(?:my|the|all|how many))?\s+([a-z][a-z -]*)$/);
  if (m === null) {
    m = req.match(/^([a-z][a-z -]*?)\s+counter$/);
  }
  return m === null ? null : counterCapsule(m[1].trim());
}

function formatTime(raw: string): string {
  const m = raw.replace(/\s+/g, '').match(/^(\d{1,2})(?::(\d{2}))?(am|pm)?$/);
  if (m === null) {
    return raw;
  }
  const minutes = m[2] !== undefined ? m[2] : '00';
  return m[3] !== undefined ? `${parseInt(m[1], 10)}:${minutes} ${m[3].toUpperCase()}` : `${m[1]}:${minutes}`;
}

function parseSchedule(req: string): Capsule | null {
  const re = new RegExp(`^([a-z][a-z ]*?)\\s+(?:at\\s+)?(${TIME_PATTERN}(?:\\s*(?:,|and|&)\\s*${TIME_PATTERN})*)$`);
  const m = req.match(re);
  if (m === null) {
    return null;
  }
  const what = capitalize(m[1].trim());
  const times = (m[2].match(new RegExp(TIME_PATTERN, 'g')) ?? []).map((t: string) => formatTime(t));
  if (times.length === 0) {
    return null;
  }
  const id = slug(`${what} doses`);
  const list: ChecklistComponent = { type: 'checklist', id: id, items: times.map((t: string) => `${what} ${t}`) };
  const ui: CapsuleComponent[] = [text(`${what} at ${times.join(' and ')}`), list, button('Reset day', `reset:${id}`)];
  return capsule(`schedule-${slug(what)}`, what, [], ui);
}

function goalCapsule(thing: string, goal: number, unit: string): Capsule {
  const id = slug(thing);
  const label = `${capitalize(thing)} (${unit})`;
  const counter: CounterComponent = { type: 'counter', id: id, label: label, source: 'manual' };
  const ui: CapsuleComponent[] = [
    text(`Goal: ${goal} ${unit}`), counter, button(`+1 ${singular(unit)}`, `increment:${id}`), button('Reset', `reset:${id}`)
  ];
  return capsule(`goal-${id}`, capitalize(thing), [], ui);
}

function parseGoal(req: string): Capsule | null {
  // "drink 8 glasses of water"
  let m = req.match(/^(?:drink|eat|do|read|take)?\s*(\d+)\s+([a-z]+)\s+of\s+([a-z][a-z ]*)$/);
  if (m !== null) {
    return goalCapsule(m[3].trim(), parseInt(m[1], 10), m[2]);
  }
  // "water 8 glasses"
  m = req.match(/^([a-z][a-z ]*?)\s+(\d+)\s+([a-z]+)$/);
  if (m !== null && !/\b(timers?|split|count)\b/.test(m[1])) {
    return goalCapsule(m[1].trim(), parseInt(m[2], 10), m[3]);
  }
  return null;
}

function parseSplit(req: string): Capsule | null {
  const m = req.match(
    /^split\s+(?:the\s+)?(?:bill\s+)?(?:of\s+)?[$€£]?(\d+(?:\.\d+)?)\s*(?:zł|pln|eur|usd)?\s+(?:between|among|amongst|by|into|with|in)\s+(\d+)(?:\s+(?:people|persons|ways|friends))?$/);
  if (m === null) {
    return null;
  }
  const total = parseFloat(m[1]);
  const people = parseInt(m[2], 10);
  if (people <= 0) {
    return null;
  }
  const ui: CapsuleComponent[] = [
    text(`Total: ${formatAmount(total)}`), text(`People: ${people}`), text(`Each pays: ${formatAmount(total / people)}`)
  ];
  return capsule(`split-${slug(m[1])}-${people}`, `Split ${formatAmount(total)} between ${people}`, [], ui);
}

/** Returns a capsule for a recognised request, or null. Output is meant to pass the validator. */
export function parseRequest(request: string): Capsule | null {
  const req = normalize(request);
  if (req.length === 0) {
    return null;
  }
  const rules: ((r: string) => Capsule | null)[] = [parseTimers, parseSplit, parseCounter, parseSchedule, parseGoal];
  for (const rule of rules) {
    const result = rule(req);
    if (result !== null) {
      return result;
    }
  }
  return null;
}
