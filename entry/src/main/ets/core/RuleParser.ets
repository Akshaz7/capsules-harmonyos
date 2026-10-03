/**
 * On-device rule parser: turns common short requests into capsules without a model.
 * Returns null when no rule matches, so the caller can fall back to the model.
 *
 * Supported shapes (case-insensitive):
 * - timers:   "3 timers pasta 9 sauce 15 bread 6", "timer eggs 7", "pasta 9 min, sauce 15 min, bread 6 min"
 * - counter:  "count my squats", "count coffees", "pushup counter"
 * - schedule: "medication 8am and 8pm", "vitamins at 9:30am, 21:00"
 * - goal:     "water 8 glasses", "drink 8 glasses of water", "pushups goal 50" (schema v1: live progress)
 * - split:    "split 84 between 4", "split the bill 120.50 among 3 people" (schema v1: live bill split)
 * - checklist: "checklist for leaving home: keys, wallet, charger", "packing list: socks, charger"
 *
 * Note: schema v0 has no time-of-day reminder, so schedules become a checklist of doses.
 *
 * Requests that mention scoring, games, players, quizzes, converting, calculating, streaks or
 * "track ... and tell me" never match a rule: they need logic the templates cannot express.
 */
import {
  ButtonComponent,
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  DisplayComponent,
  InputComponent,
  Permission,
  SCHEMA_VERSION,
  StateVar,
  StepObject,
  TextComponent,
  TimerComponent,
  WhenComponent
} from './CapsuleTypes';

/** Requests with these words need logic (scores, games, quizzes, ...) and are left to the models. */
const SKIP_RULES: RegExp[] = [
  /\b(scor\w*|games?|players?|quiz\w*|convert\w*|calculat\w*|streaks?)\b/,
  /\btrack\w*\b.*\btell me\b/
];

/** Units a goal counter makes sense for; other "thing N unit" requests need "goal" or "target". */
const GOAL_UNITS: string[] = [
  'glass', 'glasses', 'cup', 'cups', 'page', 'pages', 'step', 'steps', 'km', 'minute', 'minutes', 'min', 'mins',
  'rep', 'reps'
];

/** Words around a timer's name that are not part of it: "laundry done in 55 minutes" -> "laundry". */
const TIMER_FILLER: string[] = [
  'done', 'in', 'ready', 'is', 'be', 'will', 'for', 'after', 'the', 'my', 'a', 'an', 'set', 'start', 'remind',
  'me', 'when', 'until', 'at', 'to', 'of', 'please'
];

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

function capsuleV1(id: string, name: string, state: Record<string, StateVar>, computed: Record<string, string> | null,
  ui: CapsuleComponent[]): Capsule {
  const c: Capsule = { schemaVersion: 1, id: id, name: name, permissions: [], ui: ui, state: state };
  if (computed !== null) {
    c.computed = computed;
  }
  return c;
}

function numberVar(initial: number): StateVar {
  return { type: 'number', initial: initial };
}

function display(t: string): DisplayComponent {
  return { type: 'display', text: t };
}

function numberInput(bind: string, label: string): InputComponent {
  return { type: 'input', bind: bind, kind: 'number', label: label };
}

function doButton(label: string, steps: StepObject[]): ButtonComponent {
  return { type: 'button', label: label, action: '', do: steps };
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
  hasUnit: boolean = false;
}

const MINUTE_UNIT: RegExp = /^(m|min|mins|minute|minutes)$/;

/**
 * Reads "label number [unit]" pairs, e.g. "pasta 9 min, sauce 15 min and bread 6".
 * Returns null if anything is left over or a number has no label.
 */
function timerSpecs(text: string): TimerSpec[] | null {
  const tokens = text.split(/[\s,;]+/).filter((t: string) => t.length > 0 && t !== 'and' && t !== '&');
  const specs: TimerSpec[] = [];
  let words: string[] = [];
  for (const token of tokens) {
    const num = token.match(/^(\d+(?:\.\d+)?)(m|min|mins|minutes?)?$/);
    if (num !== null) {
      // Strip filler around the name, unless nothing would be left ("4 timers a 1 b 2").
      let first = 0;
      let last = words.length;
      while (first < last && TIMER_FILLER.includes(words[first])) {
        first++;
      }
      while (last > first && TIMER_FILLER.includes(words[last - 1])) {
        last--;
      }
      if (first < last) {
        words = words.slice(first, last);
      } else if (words.length === 0) {
        return null;
      }
      const spec = new TimerSpec();
      spec.label = capitalize(words.join(' '));
      spec.minutes = parseFloat(num[1]);
      spec.hasUnit = num[2] !== undefined;
      if (spec.minutes <= 0) {
        return null;
      }
      specs.push(spec);
      words = [];
    } else if (MINUTE_UNIT.test(token) && words.length === 0 && specs.length > 0) {
      specs[specs.length - 1].hasUnit = true; // unit after the number
    } else {
      words.push(token);
    }
  }
  return words.length > 0 || specs.length === 0 ? null : specs;
}

/**
 * Timers. With a "timer(s)" keyword ("3 timers pasta 9 sauce 15", "timers: eggs 7") units are
 * optional and a leading count must match. Without it ("pasta 9 min, sauce 15 min") every
 * number needs a minute unit, so goals like "water 8 glasses" are left to their own rule.
 */
function parseTimers(req: string): Capsule | null {
  const m = req.match(/^(?:(\d+)\s+)?timers?\b[:\s,]*(.+)$/);
  let specs: TimerSpec[] | null;
  if (m !== null) {
    specs = timerSpecs(m[2]);
    if (specs === null || (m[1] !== undefined && parseInt(m[1], 10) !== specs.length)) {
      return null;
    }
  } else {
    specs = timerSpecs(req);
    if (specs === null || specs.some((t: TimerSpec) => !t.hasUnit)) {
      return null;
    }
  }
  if (specs.length === 2 && BREAK_LABEL.test(specs[0].label) !== BREAK_LABEL.test(specs[1].label)) {
    const ss = specs;
    return sequentialTimers(`timers-${slug(ss[0].label + ' ' + ss[1].label)}`, `${ss[0].label} and ${ss[1].label.toLowerCase()}`,
      ss[0], ss[1]);
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
  const name = labels.length === 1 ? labels[0] : `${labels.join(', ')} timers`;
  return capsule(`timers-${slug(labels.join(' '))}`, name, ['reminders'], ui);
}

/** A timer that follows another one (focus, then break): the two run one after the other, never together. */
const BREAK_LABEL: RegExp = /^(?:(?:short|long) )?(?:break|rest|pause)$/i;

/**
 * Two timers that take turns (Pomodoro): each "Start" button stops the other timer first, so starting the
 * break ends the focus timer and the reverse (v1 "do" steps). No "Start all".
 */
function sequentialTimers(id: string, name: string, first: TimerSpec, second: TimerSpec): Capsule {
  const ids = new Ids();
  const a: TimerComponent = { type: 'timer', id: ids.next(first.label), label: first.label, minutes: first.minutes };
  const b: TimerComponent = { type: 'timer', id: ids.next(second.label), label: second.label, minutes: second.minutes };
  const startA: ButtonComponent = {
    type: 'button', label: `Start ${a.label.toLowerCase()}`, action: '', do: [`stopTimer:${b.id}`, `startTimer:${a.id}`]
  };
  const startB: ButtonComponent = {
    type: 'button', label: `Start ${b.label.toLowerCase()}`, action: '', do: [`stopTimer:${a.id}`, `startTimer:${b.id}`]
  };
  const c: Capsule = { schemaVersion: 1, id: id, name: name, permissions: ['reminders'], ui: [a, b, startA, startB] };
  return c;
}

function timerSpec(label: string, minutes: number): TimerSpec {
  const t = new TimerSpec();
  t.label = label;
  t.minutes = minutes;
  t.hasUnit = true;
  return t;
}

/** "pomodoro", "pomodoro timer", "pomodoro 50 10", "pomodoro 50/10 min": focus then break. */
function parsePomodoro(req: string): Capsule | null {
  const m = req.match(/^(?:a |my )?pomodoro(?: timer)?(?: (\d+)(?: ?min\w*)?(?: ?[\/,+] ?| and | )(\d+)(?: ?min\w*)?)?$/);
  if (m === null) {
    return null;
  }
  const focus = m[1] !== undefined ? parseInt(m[1], 10) : 25;
  const rest = m[2] !== undefined ? parseInt(m[2], 10) : 5;
  if (focus <= 0 || rest <= 0) {
    return null;
  }
  return sequentialTimers('pomodoro', 'Pomodoro', timerSpec('Focus', focus), timerSpec('Break', rest));
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

/** A live goal: "{count} / 8 · {8 - count} to go", +1 and Reset, and a note when it is reached. */
function goalCapsule(thing: string, goal: number, unit: string): Capsule | null {
  if (goal <= 0) {
    return null;
  }
  const state: Record<string, StateVar> = {};
  state['count'] = numberVar(0);
  const reached: WhenComponent = { type: 'when', if: `count >= ${goal}`, show: [text('Goal reached!')] };
  const step: StepObject = { set: 'count', to: 'count + 1' };
  const reset: StepObject = { reset: 'count' };
  const ui: CapsuleComponent[] = [
    display(`{count} / ${goal} · {max(${goal} - count, 0)} to go`),
    reached,
    doButton(`+1 ${singular(unit)}`, [step]),
    doButton('Reset', [reset])
  ];
  return capsuleV1(`goal-${slug(thing)}`, capitalize(thing), state, null, ui);
}

function parseGoal(req: string): Capsule | null {
  const explicit = /\b(goal|target)\b/.test(req);
  const plain = req.replace(/\b(goal|target)\b(\s+of)?/g, ' ').replace(/\s+/g, ' ').trim();
  const fits = (unit: string): boolean => explicit || GOAL_UNITS.includes(unit);
  // "drink 8 glasses of water"
  let m = plain.match(/^(?:drink|eat|do|read|take|walk|run)?\s*(\d+)\s+([a-z]+)\s+of\s+([a-z][a-z ]*)$/);
  if (m !== null && fits(m[2])) {
    return goalCapsule(m[3].trim(), parseInt(m[1], 10), m[2]);
  }
  // "water 8 glasses", "pushups goal 50 reps"
  m = plain.match(/^([a-z][a-z ]*?)\s+(\d+)\s+([a-z]+)$/);
  if (m !== null && fits(m[3]) && !/\b(timers?|split|count)\b/.test(m[1])) {
    return goalCapsule(m[1].trim(), parseInt(m[2], 10), m[3]);
  }
  // "pushups goal 50"
  m = explicit ? plain.match(/^([a-z][a-z ]*?)\s+(\d+)$/) : null;
  if (m !== null) {
    return goalCapsule(m[1].trim(), parseInt(m[2], 10), 'times');
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
  // Live: both inputs start with the request's numbers and "each pays" follows any change.
  const state: Record<string, StateVar> = {};
  state['total'] = numberVar(total);
  state['people'] = numberVar(people);
  const computed: Record<string, string> = {};
  computed['each'] = 'if(people > 0, round(total / people, 2), 0)';
  const ui: CapsuleComponent[] = [
    numberInput('total', 'Total'), numberInput('people', 'People'), display('Each pays: {each}')
  ];
  return capsuleV1(`split-${slug(m[1])}-${people}`, `Split ${formatAmount(total)} between ${people}`, state, computed,
    ui);
}

const MAX_CHECKLIST_ITEMS: number = 20;

function parseChecklist(req: string): Capsule | null {
  // "checklist for leaving home: keys, wallet, charger", "packing list: a, b", "todo: a and b"
  let m = req.match(
    /^(?:an?\s+)?(?:check\s*list|to-?do(?:\s+list)?|packing\s+list|shopping\s+list|list)(?:\s+(?:for|of)\s+([^:]+?))?\s*:\s*(.+)$/);
  if (m === null) {
    // "checklist keys, wallet, charger" (needs at least one separator)
    m = req.match(/^()check\s*list\s+(.+(?:,|\band\b).+)$/);
  }
  if (m === null) {
    return null;
  }
  const items = m[2].split(/\s*(?:,|;|\band\b|&)\s*/)
    .map((t: string) => t.trim())
    .filter((t: string) => t.length > 0)
    .map((t: string) => capitalize(t));
  const unique = items.filter((t: string, i: number) => items.indexOf(t) === i);
  if (unique.length === 0 || unique.length > MAX_CHECKLIST_ITEMS) {
    return null;
  }
  const title = m[1] !== undefined && m[1].trim().length > 0 ? capitalize(m[1].trim()) : 'Checklist';
  const id = slug(title);
  const list: ChecklistComponent = { type: 'checklist', id: id, items: unique };
  return capsule(`checklist-${id}`, title, [], [list, button('Reset', `reset:${id}`)]);
}

/** Returns a capsule for a recognised request, or null. Output is meant to pass the validator. */
export function parseRequest(request: string): Capsule | null {
  const req = normalize(request);
  if (req.length === 0 || SKIP_RULES.some((p: RegExp) => p.test(req))) {
    return null;
  }
  const rules: ((r: string) => Capsule | null)[] = [
    parsePomodoro, parseTimers, parseSplit, parseChecklist, parseCounter, parseSchedule, parseGoal
  ];
  for (const rule of rules) {
    const result = rule(req);
    if (result !== null) {
      return result;
    }
  }
  return null;
}
