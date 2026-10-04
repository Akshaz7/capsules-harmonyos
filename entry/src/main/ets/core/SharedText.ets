/**
 * Turns text shared into Harmoniser (share sheet) into a capsule without a model, when it is one of:
 *   bill    a chat or note with amounts ("Anna: I paid €45 for pizza") -> live v1 bill split
 *   recipe  cooking steps with durations ("Bake for 25 minutes")     -> one timer per timed step
 *   workout exercises ("3x10 squats", "plank 60s")                    -> checklist (+ timers for timed ones)
 *   list    bullet, numbered or comma-separated items                 -> checklist
 *   score   "Tom vs Ana" (a short note or a photo of one)            -> two-player scoreboard (bill first,
 *           score before the others)
 * Checked in that order. Anything else returns an error so the caller can try the cloud model.
 * Pure and deterministic; every capsule returned has passed the validator.
 */
import {
  ButtonComponent, Capsule, CapsuleComponent, ChecklistComponent, DisplayComponent, InputComponent, Permission,
  StateVar, StepObject, TextComponent, TimerComponent
} from './CapsuleTypes';
import { validateCapsuleObject } from './CapsuleValidator';
import { slug } from './RuleParser';
import { matchTemplateIn, TemplateLibrary } from './templates/TemplateLibrary';
import { CORE_TEMPLATES } from './templates/CoreTemplates';

export const MAX_SHARED_TEXT: number = 2000;
export const SHARED_TOO_LONG: string = `That text is too long to turn into a capsule (max ${MAX_SHARED_TEXT} characters).`;
export const SHARED_EMPTY: string = 'There is no text to turn into a capsule.';
export const SHARED_NOT_RECOGNISED: string = 'No recipe, bill, workout or list found in that text.';

export type SharedKind = 'recipe' | 'bill' | 'workout' | 'list' | 'score';

export interface SharedTextResult {
  ok: boolean;
  capsule?: Capsule;
  kind?: SharedKind;
  error?: string;
}

const MAX_TIMERS: number = 10;
const MAX_WORKOUT_TIMERS: number = 4;
const MAX_ITEMS: number = 20;
const MAX_ITEM_LENGTH: number = 80;
const MAX_TITLE_LENGTH: number = 40;

function capitalize(t: string): string {
  return t.length === 0 ? t : t.charAt(0).toUpperCase() + t.substring(1);
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function lines(text: string): string[] {
  return text.split(/\r?\n/).map((l: string) => l.trim()).filter((l: string) => l.length > 0);
}

/** A short first line that reads like a title ("Banana bread", "Leg day:"), or ''. */
function titleLine(text: string): string {
  const first = lines(text)[0] ?? '';
  const t = first.replace(/[:\s]+$/, '').replace(/^#+\s*/, '').trim();
  return t.length > 0 && t.length <= MAX_TITLE_LENGTH && !/\d/.test(t) && !/^[-*•]/.test(first) ? capitalize(t) : '';
}

function finish(capsule: Capsule, kind: SharedKind): SharedTextResult {
  const v = validateCapsuleObject(JSON.parse(JSON.stringify(capsule)) as Object);
  if (!v.ok || v.capsule === undefined) {
    return { ok: false, error: SHARED_NOT_RECOGNISED }; // a bug in an extractor; never return an invalid capsule
  }
  return { ok: true, capsule: v.capsule, kind: kind };
}

function button(label: string, action: string): ButtonComponent {
  return { type: 'button', label: label, action: action };
}

function text(t: string): TextComponent {
  return { type: 'text', text: t };
}

// ---- bill ----

const CURRENCY_BEFORE: RegExp = /([$€£])\s?(\d{1,6}(?:[.,]\d{1,2})?)/g;
const CURRENCY_AFTER: RegExp = /(\d{1,6}(?:[.,]\d{1,2})?)\s?(zł|zl|pln|eur|euros?|usd|dollars?|gbp|kr|chf|€|\$|£)(?![a-z])/gi;
const SPEAKER: RegExp = /^(?:\[[^\]]*\]\s*)?(?:\d{1,2}[:.]\d{2}\s*(?:-\s*)?)?([A-Z][\p{L}'.-]*(?: [A-Z][\p{L}'.-]*)?):\s+(.*)$/u;

function amountsIn(line: string): number[] {
  const out: number[] = [];
  const add = (raw: string): void => {
    const n = parseFloat(raw.replace(',', '.'));
    if (n > 0) {
      out.push(n);
    }
  };
  for (const m of line.matchAll(CURRENCY_BEFORE)) {
    add(m[2]);
  }
  for (const m of line.matchAll(CURRENCY_AFTER)) {
    add(m[1]);
  }
  return out;
}

/** A receipt line's label: the grand total, a subtotal, tax or tip, payment lines to ignore, or an item. */
type ReceiptRole = 'total' | 'subtotal' | 'vat' | 'tip' | 'payment' | 'item';

const TOTAL_LABEL: RegExp = /\b(grand total|total( due| to pay| amount)?|amount due|balance due|to pay|sum)\b/i;
const SUBTOTAL_LABEL: RegExp = /\b(sub-?\s?total|net)\b/i;
const VAT_LABEL: RegExp = /\b(vat|tax|ptu|gst|mwst|iva)\b/i;
const TIP_LABEL: RegExp = /\b(tip|gratuity|service( charge)?)\b/i;
const PAYMENT_LABEL: RegExp = /\b(cash|change|card|visa|mastercard|paid by|tendered|contactless|rounding)\b/i;
/** A bare price at the end of a receipt line: "Burger 12.50", "Pizza 12,50 A". */
const BARE_PRICE: RegExp = /(?:^|\s)(\d{1,5}[.,]\d{2})\s*[A-Z]?\s*$/;

function roleOf(line: string): ReceiptRole {
  if (SUBTOTAL_LABEL.test(line)) {
    return 'subtotal';
  }
  if (TOTAL_LABEL.test(line)) {
    return 'total';
  }
  if (VAT_LABEL.test(line)) {
    return 'vat';
  }
  if (TIP_LABEL.test(line)) {
    return 'tip';
  }
  return PAYMENT_LABEL.test(line) ? 'payment' : 'item';
}

/** Amounts on a line; on a receipt also a bare price at the end ("Burger 12.50"). */
function receiptAmounts(line: string, receipt: boolean): number[] {
  const found = amountsIn(line);
  if (found.length > 0 || !receipt) {
    return found;
  }
  const bare = line.match(BARE_PRICE);
  return bare !== null ? [parseFloat(bare[1].replace(',', '.'))] : [];
}

function billFrom(raw: string): Capsule | null {
  const all = lines(raw);
  const receipt = /\b(total|subtotal|vat|tax|tip|gratuity|receipt|invoice)\b/i.test(raw);
  const paid = new Map<string, number>();
  let sum = 0;
  let total = 0;
  let subtotal = 0;
  let vat = 0;
  let tip = 0;
  let found = 0;
  // OCR often puts a label and its amount on separate lines ("Total" then "€67.50"): a label line without an
  // amount gives its role to the next line that has one.
  let pending: ReceiptRole = 'item';
  all.forEach((line: string) => {
    const amounts = receiptAmounts(line, receipt);
    const own = roleOf(line);
    if (amounts.length === 0) {
      pending = own !== 'item' ? own : (/[a-z]{3}/i.test(line) ? 'item' : pending);
      return;
    }
    const role = own !== 'item' ? own : pending;
    pending = 'item';
    found += amounts.length;
    const lineSum = amounts.reduce((a: number, b: number) => a + b, 0);
    if (role === 'total') {
      total = Math.max(total, Math.max(...amounts)); // never added to the items
    } else if (role === 'subtotal') {
      subtotal = Math.max(subtotal, Math.max(...amounts));
    } else if (role === 'vat') {
      vat += Math.max(...amounts); // shown, not added again: prices and totals include it
    } else if (role === 'tip') {
      tip += Math.max(...amounts);
    } else if (role === 'item') {
      sum += lineSum;
      const who = line.match(SPEAKER);
      if (who !== null) {
        paid.set(who[1], (paid.get(who[1]) ?? 0) + lineSum);
      }
    }
  });
  const speakers = new Set<string>();
  all.forEach((line: string) => {
    const who = line.match(SPEAKER);
    if (who !== null) {
      speakers.add(who[1]);
    }
  });
  const talksMoney = receipt || /\b(split|owe|owes|paid|pay|bill|spent|cost|each|share)\b/i.test(raw);
  if (found === 0 || (speakers.size < 2 && !talksMoney)) {
    return null;
  }
  const said = raw.match(/\b(?:between|among|for|split (?:it )?(?:in|into)?)\s+(\d{1,2})\s*(?:people|persons|of us|ways)?\b/i) ??
    raw.match(/\b(\d{1,2})\s+(?:people|persons|of us|ways)\b/i);
  const people = said !== null ? parseInt(said[1], 10) : Math.max(speakers.size, 2);
  // The receipt's TOTAL wins; else the subtotal (or the items) plus the tip. VAT is never added on top.
  const amount = round2(total > 0 ? total : (subtotal > 0 ? subtotal : sum) + tip);
  if (people <= 0 || amount <= 0) {
    return null;
  }
  const state: Record<string, StateVar> = {};
  state['total'] = { type: 'number', initial: amount };
  state['people'] = { type: 'number', initial: people };
  const computed: Record<string, string> = {};
  computed['each'] = 'if(people > 0, round(total / people, 2), 0)';
  const total_: InputComponent = { type: 'input', bind: 'total', kind: 'number', label: 'Total' };
  const people_: InputComponent = { type: 'input', bind: 'people', kind: 'number', label: 'People' };
  const each: DisplayComponent = { type: 'display', text: 'Each pays: {each}' };
  const ui: CapsuleComponent[] = [total_, people_, each];
  const extras: string[] = [];
  if (vat > 0) {
    extras.push(`VAT ${round2(vat)}`);
  }
  if (tip > 0) {
    extras.push(`tip ${round2(tip)}`);
  }
  if (extras.length > 0) {
    ui.push(text(`Includes ${extras.join(' and ')}`));
  }
  if (paid.size > 0) {
    const parts: string[] = [];
    paid.forEach((v: number, k: string) => {
      parts.push(`${k} ${round2(v)}`);
    });
    ui.push(text(`Paid so far: ${parts.join(', ')}`));
  }
  return {
    schemaVersion: 1, id: 'shared-bill', name: titleLine(raw).length > 0 && amountsIn(all[0]).length === 0 &&
      !SPEAKER.test(all[0]) ? titleLine(raw) : 'Bill split', permissions: [], ui: ui, state: state, computed: computed
  };
}

// ---- recipe ----

const COOKING_VERBS: string[] = [
  'bake', 'boil', 'simmer', 'roast', 'fry', 'saute', 'sauté', 'cook', 'rest', 'knead', 'rise', 'prove', 'proof',
  'chill', 'marinate', 'steep', 'soak', 'grill', 'steam', 'toast', 'stir', 'whisk', 'mix', 'blend', 'cool',
  'freeze', 'microwave', 'poach', 'reduce', 'brown', 'sear', 'braise', 'stew', 'blanch', 'caramelize', 'heat',
  'preheat', 'leave', 'let', 'refrigerate', 'set', 'beat', 'fold'
];
/** Verbs that also appear outside kitchens (workouts, chats). */
const AMBIGUOUS_VERBS: string[] = ['rest', 'set', 'let', 'leave', 'mix', 'cool', 'heat', 'beat', 'fold', 'reduce', 'stir'];

/** Sets and reps ("3x10", "3 sets") or two exercise lines: workout text. */
function isWorkoutText(raw: string): boolean {
  const exercises = lines(raw).filter((l: string) => EXERCISE_WORDS.test(l)).length;
  return exercises >= 2 || (exercises >= 1 && /(\d+\s*[x×]\s*\d+|\bsets?\b|\breps?\b|\bworkout\b)/i.test(raw));
}

const DURATION: RegExp =
  /(\d+(?:[.,]\d+)?)(?:\s*(?:-|–|to)\s*(\d+(?:[.,]\d+)?))?\s*(hours?|hrs?|h|minutes?|mins?|min|m|seconds?|secs?|s)\b/i;

function minutesOf(m: RegExpMatchArray): number {
  const a = parseFloat(m[1].replace(',', '.'));
  const b = m[2] !== undefined ? parseFloat(m[2].replace(',', '.')) : a;
  const n = Math.max(a, b);
  const unit = m[3].toLowerCase();
  if (unit.startsWith('h')) {
    return n * 60;
  }
  if (unit.startsWith('s')) {
    return round2(n / 60);
  }
  return n;
}

/** Steps: lines, or sentences when the text is one paragraph. */
function steps(raw: string): string[] {
  return lines(raw).flatMap((l: string) => l.split(/(?<=[.!?])\s+(?=[A-Z])/)).map((s: string) => s.trim())
    .filter((s: string) => s.length > 0);
}

function recipeFrom(raw: string): Capsule | null {
  const lower = raw.toLowerCase();
  const strong = /\b(recipe|ingredients|oven|°c|°f|preheat|pan|pot|bake|boil|simmer|roast|fry|saute|sauté|grill|steam|knead)\b/
    .test(lower);
  // "rest", "set", "mix"... alone are not cooking: "3x10 squats, rest 60 s" is a workout (T4-18).
  const cooking = strong || COOKING_VERBS.some((v: string) => !AMBIGUOUS_VERBS.includes(v) &&
    new RegExp(`\\b${v}\\b`).test(lower));
  if (!cooking || (!strong && isWorkoutText(raw))) {
    return null;
  }
  const timers: TimerComponent[] = [];
  const used: string[] = [];
  steps(raw).forEach((step: string, i: number) => {
    const d = step.match(DURATION);
    if (d === null || timers.length >= MAX_TIMERS || /°|degrees|\bat \d/.test(step.substring(0, d.index ?? 0).slice(-12))) {
      return;
    }
    const minutes = minutesOf(d);
    if (minutes <= 0 || minutes > 24 * 60) {
      return;
    }
    const verb = COOKING_VERBS.find((v: string) => new RegExp(`\\b${v}\\b`, 'i').test(step));
    let label = verb !== undefined && verb !== 'let' && verb !== 'leave' && verb !== 'set' ? capitalize(verb) :
      `Step ${i + 1}`;
    let n = 2;
    const base = label;
    while (used.includes(label)) {
      label = `${base} ${n++}`;
    }
    used.push(label);
    timers.push({ type: 'timer', id: slug(label), label: label, minutes: minutes });
  });
  if (timers.length === 0) {
    return null;
  }
  const ui: CapsuleComponent[] = [];
  timers.forEach((t: TimerComponent) => {
    ui.push(t);
    ui.push(button(`Start ${t.label.toLowerCase()}`, `startTimer:${t.id}`));
  });
  const name = titleLine(raw);
  return {
    schemaVersion: 0, id: `shared-recipe-${slug(name.length > 0 ? name : 'timers')}`,
    name: name.length > 0 ? name : 'Recipe timers', permissions: ['reminders' as Permission], ui: ui
  };
}

// ---- workout ----

const EXERCISE_WORDS: RegExp =
  /\b(squats?|push-?ups?|pull-?ups?|sit-?ups?|crunch(es)?|lunges?|burpees?|planks?|deadlifts?|bench|curls?|jumping jacks?|sprints?|mountain climbers?|dips?|wall sits?|kettlebell|chin-?ups?|leg raises?)\b/i;
const REST: RegExp = /\brest(?:\s+for)?\s+(\d+(?:[.,]\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|min|m)\b/i;

const EXERCISES: RegExp =
  /\b(squats?|push-?ups?|pull-?ups?|sit-?ups?|crunch(es)?|lunges?|burpees?|planks?|deadlifts?|bench|press(es)?|curls?|rows?|jumping jacks?|run|jog|sprints?|mountain climbers?|dips?|stretch(es|ing)?|wall sits?|bridges?|kettlebell|skipping|jump rope|chin-?ups?|leg raises?|rest)\b/i;

class WorkoutItem {
  label: string = '';
  seconds: number = 0;
}

function workoutItem(line: string): WorkoutItem | null {
  const clean = line.replace(/^\s*(?:[-*•]|\d+[.)])\s*/, '').trim();
  if (!EXERCISES.test(clean) || clean.length > MAX_ITEM_LENGTH) {
    return null;
  }
  const item = new WorkoutItem();
  item.label = capitalize(clean.replace(/\s*[x×]\s*/g, '×'));
  const timed = clean.match(/(\d+(?:[.,]\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|min)\b/i);
  if (timed !== null && !/[x×]/.test(clean)) {
    const n = parseFloat(timed[1].replace(',', '.'));
    item.seconds = timed[2].toLowerCase().startsWith('m') ? n * 60 : n;
  }
  return item;
}

function workoutFrom(raw: string): Capsule | null {
  const all = lines(raw);
  const items = all.map((l: string) => workoutItem(l)).filter((w: WorkoutItem | null) => w !== null) as WorkoutItem[];
  const signal = /\b(workout|wod|sets?|reps?|circuit|training|exercises?)\b/i.test(raw);
  if (items.length < 2 && !(items.length === 1 && signal)) {
    return null;
  }
  const list: ChecklistComponent = {
    type: 'checklist', id: 'exercises', items: items.slice(0, MAX_ITEMS).map((w: WorkoutItem) => w.label)
  };
  const ui: CapsuleComponent[] = [list];
  const timers: TimerComponent[] = [];
  items.filter((w: WorkoutItem) => w.seconds > 0).forEach((w: WorkoutItem) => {
    const base = w.label.replace(/\s*\d+(?:[.,]\d+)?\s*(seconds?|secs?|s|minutes?|mins?|min)\b/i, '').trim();
    const label = base.length > 0 ? base : 'Interval';
    const id = slug(label);
    if (timers.length < MAX_WORKOUT_TIMERS && !timers.some((t: TimerComponent) => t.id === id)) {
      timers.push({ type: 'timer', id: id, label: label, minutes: round2(w.seconds / 60) });
    }
  });
  // "3x10 squats, rest 60 s": the rest is a timer inside the workout.
  const rest = raw.match(REST);
  if (rest !== null && !timers.some((t: TimerComponent) => t.id === 'rest') && timers.length < MAX_WORKOUT_TIMERS) {
    const n = parseFloat(rest[1].replace(',', '.'));
    const seconds = rest[2].toLowerCase().startsWith('m') ? n * 60 : n;
    timers.push({ type: 'timer', id: 'rest', label: 'Rest', minutes: round2(seconds / 60) });
  }
  timers.forEach((t: TimerComponent) => {
    ui.push(t);
    ui.push(button(`Start ${t.label.toLowerCase()}`, `startTimer:${t.id}`));
  });
  ui.push(button('Reset', 'reset:exercises'));
  const name = titleLine(raw);
  const permissions: Permission[] = timers.length > 0 ? ['reminders'] : [];
  return {
    schemaVersion: 0, id: `shared-workout-${slug(name.length > 0 ? name : 'workout')}`,
    name: name.length > 0 ? name : 'Workout', permissions: permissions, ui: ui
  };
}

// ---- score ----

const VERSUS: RegExp = /^\s*(?:([\p{L} -]{0,30}?)\s*:\s*)?(\p{Lu}[\p{L}'-]{0,20})\s+(?:vs\.?|v\.?|versus|against)\s+(\p{Lu}[\p{L}'-]{0,20})\b/u;
const SPORT: RegExp = /\b(tennis|squash|padel|badminton|ping ?pong|table tennis|darts|chess|pool|snooker|football|volleyball|basketball)\b/i;

/**
 * "Tom vs Ana" (OCR may break it over lines): a two-player scoreboard. A sport the bundled templates know
 * (tennis) uses its template; anything else gets plain points with a button per player.
 */
function scoreFrom(raw: string): Capsule | null {
  const joined = lines(raw).join(' ');
  if (joined.length > 80) {
    return null;
  }
  const m = joined.match(VERSUS);
  if (m === null || m[2].toLowerCase() === m[3].toLowerCase()) {
    return null;
  }
  const a = m[2];
  const b = m[3];
  const sport = joined.match(SPORT);
  if (sport !== null) {
    const t = matchTemplateIn(new TemplateLibrary(CORE_TEMPLATES), `${sport[1]} scoreboard ${a} vs ${b}`);
    if (t !== null) {
      return t.capsule;
    }
  }
  const state: Record<string, StateVar> = {};
  state['a'] = { type: 'number', initial: 0 };
  state['b'] = { type: 'number', initial: 0 };
  const score: DisplayComponent = { type: 'display', text: `Score {a} - {b}` };
  const names: TextComponent = text(`${a} vs ${b}`);
  const incA: StepObject = { set: 'a', to: 'a + 1' };
  const incB: StepObject = { set: 'b', to: 'b + 1' };
  const resetA: StepObject = { reset: 'a' };
  const resetB: StepObject = { reset: 'b' };
  const plusA: ButtonComponent = { type: 'button', label: `+1 ${a}`, action: '', do: [incA] };
  const plusB: ButtonComponent = { type: 'button', label: `+1 ${b}`, action: '', do: [incB] };
  const reset: ButtonComponent = {
    type: 'button', label: 'Reset', action: '', enabledIf: 'a + b > 0', do: [resetA, resetB]
  };
  return {
    schemaVersion: 1, id: `shared-score-${slug(`${a} ${b}`)}`, name: `${a} vs ${b}`, permissions: [], state: state,
    ui: [score, names, plusA, plusB, reset]
  };
}

// ---- list ----

function listFrom(raw: string): Capsule | null {
  const all = lines(raw);
  const bullet = /^(?:[-*•–]|\d+[.)]|\[[ xX]?\])\s+/;
  let items = all.filter((l: string) => bullet.test(l)).map((l: string) => l.replace(bullet, '').replace(bullet, ''));
  let title = '';
  if (items.length < 2) {
    // "Title:" then one item per line, or a single comma-separated line
    if (all.length >= 3 && all[0].endsWith(':')) {
      items = all.slice(1);
    } else if (all.length === 1 && all[0].split(',').length >= 3) {
      const parts = all[0].split(':');
      if (parts.length === 2) {
        title = parts[0];
      }
      items = parts[parts.length - 1].split(',');
    } else if (all.length >= 3 && all.every((l: string) => l.length <= MAX_ITEM_LENGTH / 2)) {
      items = all;
    }
  }
  items = items.map((t: string) => capitalize(t.trim().replace(/[.;]+$/, ''))).filter((t: string) => t.length > 0 &&
    t.length <= MAX_ITEM_LENGTH);
  const unique = items.filter((t: string, i: number) => items.indexOf(t) === i).slice(0, MAX_ITEMS);
  if (unique.length < 2) {
    return null;
  }
  const name = title.length > 0 ? capitalize(title.trim()) : (titleLine(raw).length > 0 && !unique.includes(
    titleLine(raw)) ? titleLine(raw) : 'List');
  const id = slug(name);
  const list: ChecklistComponent = { type: 'checklist', id: id, items: unique };
  return {
    schemaVersion: 0, id: `shared-list-${id}`, name: name, permissions: [], ui: [list, button('Reset', `reset:${id}`)]
  };
}

/** Builds a capsule from shared text, or explains why it cannot (empty, too long, not recognised). */
export function capsuleFromSharedText(raw: string): SharedTextResult {
  const t = raw.trim();
  if (t.length === 0) {
    return { ok: false, error: SHARED_EMPTY };
  }
  if (t.length > MAX_SHARED_TEXT) {
    return { ok: false, error: SHARED_TOO_LONG };
  }
  const bill = billFrom(t);
  if (bill !== null) {
    return finish(bill, 'bill');
  }
  const score = scoreFrom(t);
  if (score !== null) {
    return finish(score, 'score');
  }
  const recipe = recipeFrom(t);
  if (recipe !== null) {
    return finish(recipe, 'recipe');
  }
  const workout = workoutFrom(t);
  if (workout !== null) {
    return finish(workout, 'workout');
  }
  const list = listFrom(t);
  if (list !== null) {
    return finish(list, 'list');
  }
  return { ok: false, error: SHARED_NOT_RECOGNISED };
}
