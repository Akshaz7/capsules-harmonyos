/**
 * Pure logic for the Harmoniser home-screen widget: persisted capsule state, the view the
 * widget card draws, and how widget taps map onto schema actions. No platform APIs.
 */
import {
  ButtonComponent,
  Capsule,
  CapsuleComponent,
  ChecklistComponent,
  CounterComponent,
  DisplayComponent,
  Permission,
  RowComponent,
  TextComponent,
  TimerComponent,
  Trigger,
  WhenComponent
} from './CapsuleTypes';
import { parseAction, permissionForAction, permissionForComponent } from './CapsuleValidator';
import { routeCapsule } from './CapsuleRouter';
import {
  allComponents, applyActions, initialState as initialValues, isEnabled, isShown, renderTemplate, restoreState, StateValues
} from './CapsuleProgram';

type JsonValue = Object | null | undefined;
type JsonRecord = Record<string, Object | null>;

// ---- Persisted state ----

/** endAt is the epoch ms when the timer ends; 0 means it is not running. */
export interface TimerRun {
  id: string;
  endAt: number;
  /** ms left when a widget tap paused it (pauseTimer); startTimer resumes from here. Absent otherwise. */
  pausedLeft?: number;
}

export interface CounterValue {
  id: string;
  value: number;
}

export interface ChecklistTicks {
  id: string;
  checked: boolean[];
}

export interface CapsuleState {
  capsuleId: string;
  timers: TimerRun[];
  counters: CounterValue[];
  checklists: ChecklistTicks[];
  /** Schema v1 state values, shared by the app and the widget. Absent for v0 capsules. */
  values?: StateValues;
}

function isV1(capsule: Capsule): boolean {
  return capsule.schemaVersion === 1 || capsule.state !== undefined || capsule.computed !== undefined;
}

export function initialState(capsule: Capsule): CapsuleState {
  // No v1 values here: until the app or a widget tap saves them, the app's own store has the latest ones.
  const state: CapsuleState = { capsuleId: capsule.id, timers: [], counters: [], checklists: [] };
  allComponents(capsule.ui).forEach((c: CapsuleComponent) => {
    if (c.type === 'timer') {
      state.timers.push({ id: (c as TimerComponent).id, endAt: 0 });
    } else if (c.type === 'counter') {
      state.counters.push({ id: (c as CounterComponent).id, value: 0 });
    } else if (c.type === 'checklist') {
      const list = c as ChecklistComponent;
      state.checklists.push({ id: list.id, checked: list.items.map((): boolean => false) });
    }
  });
  return state;
}

function asRecord(v: JsonValue): JsonRecord | null {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v) ? v as JsonRecord : null;
}

function asArray(v: JsonValue): JsonValue[] {
  return Array.isArray(v) ? v as JsonValue[] : [];
}

function findById(list: JsonValue[], id: string): JsonRecord | null {
  for (const item of list) {
    const r = asRecord(item);
    if (r !== null && r['id'] === id) {
      return r;
    }
  }
  return null;
}

/**
 * Restores saved state for a capsule. Anything missing, malformed or for another capsule
 * falls back to the initial state, so a bad record can never break the widget.
 */
export function parseState(capsule: Capsule, json: string): CapsuleState {
  const state = initialState(capsule);
  let root: JsonRecord | null = null;
  try {
    root = asRecord(JSON.parse(json) as JsonValue);
  } catch (e) {
    return state;
  }
  if (root === null || root['capsuleId'] !== capsule.id) {
    return state;
  }
  const timers = asArray(root['timers']);
  state.timers.forEach((t: TimerRun) => {
    const saved = findById(timers, t.id);
    const endAt: JsonValue = saved === null ? null : saved['endAt'];
    if (typeof endAt === 'number' && Number.isFinite(endAt as number) && (endAt as number) >= 0) {
      t.endAt = endAt as number;
    }
    const left: JsonValue = saved === null ? null : saved['pausedLeft'];
    if (t.endAt === 0 && typeof left === 'number' && Number.isFinite(left as number) && (left as number) > 0) {
      t.pausedLeft = left as number;
    }
  });
  const counters = asArray(root['counters']);
  state.counters.forEach((c: CounterValue) => {
    const saved = findById(counters, c.id);
    const value: JsonValue = saved === null ? null : saved['value'];
    if (typeof value === 'number' && Number.isInteger(value as number) && (value as number) >= 0) {
      c.value = value as number;
    }
  });
  const values = asRecord(root['values']);
  if (values !== null && isV1(capsule)) {
    state.values = restoreState(capsule, values as StateValues);
  }
  const lists = asArray(root['checklists']);
  state.checklists.forEach((l: ChecklistTicks) => {
    const saved = findById(lists, l.id);
    const checked = saved === null ? [] : asArray(saved['checked']);
    l.checked = l.checked.map((def: boolean, i: number) => i < checked.length && checked[i] === true ? true : def);
  });
  return state;
}

// ---- Widget messages (sent by the card through postCardAction) ----

/** 'press': a v1 button (index among all the capsule's buttons) whose "do" steps run on the widget. */
export type WidgetOp = 'start' | 'increment' | 'toggle' | 'refresh' | 'press';

export interface WidgetMessage {
  op: WidgetOp;
  id: string;
  index: number;
}

/** Parses the onFormEvent message. Returns null for anything unexpected. */
export function parseWidgetMessage(json: string): WidgetMessage | null {
  let r: JsonRecord | null = null;
  try {
    r = asRecord(JSON.parse(json) as JsonValue);
  } catch (e) {
    return null;
  }
  if (r === null) {
    return null;
  }
  const op: JsonValue = r['op'];
  const id: JsonValue = r['id'];
  const index: JsonValue = r['index'];
  if (op !== 'start' && op !== 'increment' && op !== 'toggle' && op !== 'refresh' && op !== 'press') {
    return null;
  }
  return {
    op: op as WidgetOp,
    id: typeof id === 'string' ? id as string : '',
    index: typeof index === 'number' && Number.isInteger(index as number) ? index as number : -1
  };
}

function hasButton(capsule: Capsule, action: string): boolean {
  return capsule.ui.some((c: CapsuleComponent) => c.type === 'button' && (c as ButtonComponent).action === action);
}

function component(capsule: Capsule, type: string, id: string): CapsuleComponent | undefined {
  return capsule.ui.find((c: CapsuleComponent) => c.type === type && (c as TimerComponent).id === id);
}

/**
 * The schema action a widget tap stands for, if the capsule itself declares it:
 * "start" needs a startTimer:<id> or startAllTimers button, "increment" an increment:<id> button.
 * Returns '' for taps that are not actions (toggle, refresh) and null if the tap is not allowed.
 * The caller must still ask the gatekeeper about the returned action.
 */
export function declaredAction(capsule: Capsule, msg: WidgetMessage): string | null {
  switch (msg.op) {
    case 'start':
      return component(capsule, 'timer', msg.id) !== undefined &&
        (hasButton(capsule, `startTimer:${msg.id}`) || hasButton(capsule, 'startAllTimers')) ? `startTimer:${msg.id}` :
        null;
    case 'increment':
      return component(capsule, 'counter', msg.id) !== undefined && hasButton(capsule, `increment:${msg.id}`) ?
        `increment:${msg.id}` : null;
    case 'press': {
      const b = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type === 'button')[msg.index];
      return b !== undefined ? '' : null; // its actions are checked one by one in pressWidgetButton
    }
    case 'toggle': {
      const list = component(capsule, 'checklist', msg.id);
      return list !== undefined && msg.index >= 0 && msg.index < (list as ChecklistComponent).items.length ? '' : null;
    }
    default:
      return '';
  }
}

/** Applies an already-approved widget message. Returns a new state; the input is not changed. */
export function applyWidgetMessage(capsule: Capsule, state: CapsuleState, msg: WidgetMessage,
  now: number): CapsuleState {
  const next: CapsuleState = JSON.parse(JSON.stringify(state)) as CapsuleState;
  if (msg.op === 'start') {
    const c = component(capsule, 'timer', msg.id);
    const run = next.timers.find((t: TimerRun) => t.id === msg.id);
    if (c !== undefined && run !== undefined && !(run.endAt > now)) {
      run.endAt = now + Math.round((c as TimerComponent).minutes * 60) * 1000;
    }
  } else if (msg.op === 'increment') {
    const counter = next.counters.find((v: CounterValue) => v.id === msg.id);
    if (counter !== undefined) {
      counter.value += 1;
    }
  } else if (msg.op === 'toggle') {
    const list = next.checklists.find((l: ChecklistTicks) => l.id === msg.id);
    if (list !== undefined && msg.index >= 0 && msg.index < list.checked.length) {
      list.checked[msg.index] = !list.checked[msg.index];
    }
  }
  return next;
}

// ---- v1 buttons on the widget ----

export class PressResult {
  /** True when the steps ran; `state` is then the new state to save. */
  ok: boolean = false;
  state: CapsuleState = { capsuleId: '', timers: [], counters: [], checklists: [] };
  /** The v0 actions the steps produced (already allowed and applied to timers/counters). */
  actions: string[] = [];
  /** Why the gatekeeper blocked it, or why it could not run ('' when ok). Nothing changed. */
  blocked: string = '';
  error: string = '';
}

/** Applies one allowed v0 action to the widget state (timers, counters). Other actions need the app. */
export function applyV0Action(capsule: Capsule, state: CapsuleState, action: string, now: number): void {
  const a = parseAction(action);
  if (a === null) {
    return;
  }
  const lengthMs = (id: string): number => {
    const t = allComponents(capsule.ui).find((c: CapsuleComponent) => c.type === 'timer' &&
      (c as TimerComponent).id === id);
    return t === undefined ? 0 : Math.round((t as TimerComponent).minutes * 60) * 1000;
  };
  const start = (run: TimerRun): void => {
    if (run.endAt > now) {
      return; // already running
    }
    run.endAt = now + (run.pausedLeft !== undefined && run.pausedLeft > 0 ? run.pausedLeft : lengthMs(run.id));
    run.pausedLeft = undefined;
  };
  const run = state.timers.find((t: TimerRun) => t.id === a.arg);
  if (a.kind === 'startAllTimers') {
    state.timers.forEach(start);
  } else if (a.kind === 'startTimer' && run !== undefined) {
    start(run);
  } else if (a.kind === 'pauseTimer' && run !== undefined && run.endAt > now) {
    run.pausedLeft = run.endAt - now;
    run.endAt = 0;
  } else if (a.kind === 'stopTimer' && run !== undefined) {
    run.endAt = 0;
    run.pausedLeft = undefined;
  } else if (a.kind === 'resetTimer' && run !== undefined) {
    const wasRunning = run.endAt > now;
    run.pausedLeft = undefined;
    run.endAt = wasRunning ? now + lengthMs(run.id) : 0;
  } else if (a.kind === 'increment' || a.kind === 'reset') {
    const counter = state.counters.find((v: CounterValue) => v.id === a.arg);
    if (counter !== undefined) {
      counter.value = a.kind === 'increment' ? counter.value + 1 : 0;
    }
  }
}

/**
 * A v1 button tapped on the widget: runs its "do" steps (all-or-nothing, like in the app), asks `allow`
 * (the gatekeeper) about every v0 action the steps produce, then applies them. A disabled button, a removed
 * capsule or a blocked action changes nothing.
 */
export function pressWidgetButton(capsule: Capsule, state: CapsuleState, index: number, now: number,
  allow: (action: string) => boolean): PressResult {
  const r = new PressResult();
  r.state = state;
  const button = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type === 'button')[index];
  if (button === undefined) {
    r.error = `no button ${index}`;
    return r;
  }
  const values = state.values ?? initialValues(capsule);
  const applied = applyActions(capsule, values, button as ButtonComponent);
  if (!applied.ok) {
    r.error = applied.error ?? 'the button failed';
    return r;
  }
  for (const action of applied.actions) {
    if (!allow(action)) {
      r.blocked = `action "${action}" is not allowed`;
      return r;
    }
  }
  const next: CapsuleState = JSON.parse(JSON.stringify(state)) as CapsuleState;
  if (isV1(capsule)) {
    next.values = applied.state;
  }
  applied.actions.forEach((a: string) => applyV0Action(capsule, next, a, now));
  r.ok = true;
  r.state = next;
  r.actions = applied.actions;
  return r;
}

// ---- What the card draws ----

export type WidgetRowKind = 'text' | 'timer' | 'counter' | 'checklist';

export interface WidgetCheckItem {
  index: number;
  text: string;
  checked: boolean;
}

/** One visible component. Fields that do not apply to the kind keep their defaults. */
export interface WidgetRow {
  key: string;
  kind: WidgetRowKind;
  id: string;
  label: string;
  minutes: number;
  endAt: number;
  canStart: boolean;
  value: number;
  canIncrement: boolean;
  items: WidgetCheckItem[];
  /** Checklists: the items not ticked yet, in order. The card shows only these (ticked ones are hidden). */
  open: WidgetCheckItem[];
}

/**
 * How the card arranges itself:
 *  counter / timer / checklist  one v0 component fills the card (big number, ring, tick list);
 *  goal       a v1 "N / goal" display: big number, progress ring and the first button as a round +;
 *  logic      other v1 capsules: up to 3 big display values (a "Games 2 - 1" line becomes two scores) and buttons;
 *  rows       several v0 components, one per row;
 *  message    blank, removed or app-only: icon and one line.
 */
export type WidgetLayout = 'counter' | 'goal' | 'timer' | 'checklist' | 'logic' | 'rows' | 'message';

/** The capsule icon (a system symbol chosen by the card). */
export type WidgetIcon = 'counter' | 'goal' | 'timer' | 'checklist' | 'logic' | 'text' | 'blank';

/** One v1 display line: plain text, or a score line "label left - right" drawn as two big numbers. */
export interface WidgetDisplay {
  key: string;
  kind: 'line' | 'score';
  text: string;
  label: string;
  left: string;
  right: string;
}

/** One v1 button. Index = position among the capsule's buttons (all levels), for T4-14's tap handling. */
export interface WidgetButton {
  index: number;
  label: string;
  enabled: boolean;
}

export type WidgetStatus = 'ok' | 'empty' | 'removed';

/** Card sizes: s = 1x2 (compact), m = 2x2, w = 2x4 (wide), l = 4x4 (large). */
export type CardSize = 's' | 'm' | 'w' | 'l';

/** formInfo.FormDimension -> card size (Dimension_1_2 = 1, 2_2 = 2, 2_4 = 3, 4_4 = 4; anything else 2x2). */
export function sizeForDimension(dimension: number): CardSize {
  return dimension === 1 ? 's' : (dimension === 3 ? 'w' : (dimension === 4 ? 'l' : 'm'));
}

/** The layouts that use the extra width/height (more items, side-by-side columns). */
export function isWideSize(size: CardSize): boolean {
  return size === 'w' || size === 'l';
}

export interface WidgetView {
  status: WidgetStatus;
  capsuleId: string;
  title: string;
  /** A short note under the title, e.g. why items are hidden. Empty when there is nothing to say. */
  message: string;
  rows: WidgetRow[];
  wide: boolean;
  /** The widget this view is for; a blank widget sends it when tapped, to choose a capsule. */
  formId?: string;
  layout: WidgetLayout;
  icon: WidgetIcon;
  /** The widget's palette slot (stable per widget) and its accent colour. */
  colorTag: number;
  accent: string;
  /** Small text under the hero: a checklist's "2 / 3 done", a goal's "5 to go", a capsule's text line. */
  caption: string;
  /** Layout "goal": the current value and the goal (progress = value / goal). */
  value: number;
  goal: number;
  displays: WidgetDisplay[];
  buttons: WidgetButton[];
  /** The widget's size (set by the service from its binding; 'm'/'w' from `wide` until then). */
  size: CardSize;
  /** One line for the compact 1x2 card: the main value or status, e.g. "3", "3 / 8", "25:00", "2 / 5 done". */
  summary: string;
}

export interface GateFacts {
  /** Permissions the user granted this capsule. */
  granted: Permission[];
  /** True once the user answered the consent screen. */
  decided: boolean;
  /** True after Undo removed the capsule. */
  removed: boolean;
}

/** Accent colours, one per widget (colorTag = index). Mid-tone so they read on light and dark cards. */
export const WIDGET_PALETTE: string[] = ['#0A59F7', '#ED6F21', '#2DA44E', '#8A5CF5', '#E84D6E', '#00A3B4'];

export function accentFor(colorTag: number): string {
  const n = WIDGET_PALETTE.length;
  return WIDGET_PALETTE[((Math.floor(colorTag) % n) + n) % n];
}

/** A new widget's colorTag: the first palette slot no other widget uses, else one derived from the formId. */
export function pickColorTag(used: number[], formId: string): number {
  for (let i = 0; i < WIDGET_PALETTE.length; i++) {
    if (!used.includes(i)) {
      return i;
    }
  }
  return stableColorTag(formId);
}

/** The colorTag for a widget saved before colorTags existed: derived from its formId, so it never changes. */
export function stableColorTag(formId: string): number {
  let h = 0;
  for (let i = 0; i < formId.length; i++) {
    h = (h * 31 + formId.charCodeAt(i)) % 1000003;
  }
  return h % WIDGET_PALETTE.length;
}

/** Sets the widget's colour on a view. */
export function withColor(view: WidgetView, colorTag: number): WidgetView {
  view.colorTag = colorTag;
  view.accent = accentFor(colorTag);
  return view;
}

function row(kind: WidgetRowKind, id: string, label: string): WidgetRow {
  return {
    key: '', kind: kind, id: id, label: label, minutes: 0, endAt: 0, canStart: false, value: 0, canIncrement: false,
    items: [], open: []
  };
}

function permitted(p: Permission | null, granted: Permission[]): boolean {
  return p === null || granted.includes(p);
}

export const BLANK_WIDGET_MESSAGE: string = 'Tap to choose a capsule';

function baseView(status: WidgetStatus, capsuleId: string, title: string, message: string, wide: boolean): WidgetView {
  return {
    status: status, capsuleId: capsuleId, title: title, message: message, rows: [], wide: wide, layout: 'message',
    icon: 'blank', colorTag: 0, accent: accentFor(0), caption: '', value: 0, goal: 0, displays: [], buttons: [],
    size: wide ? 'w' : 'm', summary: message
  };
}

export function emptyView(wide: boolean): WidgetView {
  return baseView('empty', '', 'Harmoniser', BLANK_WIDGET_MESSAGE, wide);
}

/** The v0 row for one component, or null when it is not drawn (buttons, v1-only types). */
function v0Row(capsule: Capsule, c: CapsuleComponent, i: number, state: CapsuleState, gate: GateFacts): WidgetRow | null {
  if (c.type === 'text') {
    const r = row('text', '', (c as TextComponent).text);
    r.key = `${i}:text:${r.label}`;
    return r;
  } else if (c.type === 'timer') {
    const t = c as TimerComponent;
    const r = row('timer', t.id, t.label);
    const run = state.timers.find((x: TimerRun) => x.id === t.id);
    r.minutes = t.minutes;
    r.endAt = run !== undefined ? run.endAt : 0;
    const action = declaredAction(capsule, { op: 'start', id: t.id, index: -1 });
    r.canStart = action !== null && permitted(permissionForAction({ kind: 'startTimer', arg: t.id }), gate.granted);
    r.key = `${i}:timer:${t.id}:${r.endAt}:${r.canStart}`;
    return r;
  } else if (c.type === 'counter') {
    const k = c as CounterComponent;
    const r = row('counter', k.id, k.label);
    const v = state.counters.find((x: CounterValue) => x.id === k.id);
    r.value = v !== undefined ? v.value : 0;
    const action = declaredAction(capsule, { op: 'increment', id: k.id, index: -1 });
    const parsed = action === null ? null : parseAction(action);
    r.canIncrement = parsed !== null && permitted(permissionForAction(parsed), gate.granted);
    r.key = `${i}:counter:${k.id}:${r.value}:${r.canIncrement}`;
    return r;
  } else if (c.type === 'checklist') {
    const l = c as ChecklistComponent;
    const r = row('checklist', l.id, '');
    const ticks = state.checklists.find((x: ChecklistTicks) => x.id === l.id);
    r.items = l.items.map((text: string, n: number): WidgetCheckItem => {
      const item: WidgetCheckItem = {
        index: n, text: text, checked: ticks !== undefined && n < ticks.checked.length ? ticks.checked[n] : false
      };
      return item;
    });
    r.open = r.items.filter((x: WidgetCheckItem) => !x.checked);
    r.key = `${i}:checklist:${l.id}:${r.items.map((x: WidgetCheckItem) => x.checked ? '1' : '0').join('')}`;
    return r;
  }
  return null;
}

function iconFor(kind: WidgetRowKind): WidgetIcon {
  return kind === 'timer' ? 'timer' : (kind === 'counter' ? 'counter' : (kind === 'checklist' ? 'checklist' : 'text'));
}

function doneCaption(r: WidgetRow): string {
  const done = r.items.filter((x: WidgetCheckItem) => x.checked).length;
  return `${done} / ${r.items.length} done`;
}

/** Picks the layout for v0 rows: one main component fills the card, text rows become the caption. */
function arrangeV0(view: WidgetView): void {
  const main = view.rows.filter((r: WidgetRow) => r.kind !== 'text');
  const texts = view.rows.filter((r: WidgetRow) => r.kind === 'text');
  if (main.length === 0) {
    view.layout = 'rows';
    view.icon = 'text';
    return;
  }
  view.icon = iconFor(main[0].kind);
  if (main.length === 1 && texts.length <= 1) {
    view.layout = main[0].kind === 'timer' ? 'timer' : (main[0].kind === 'counter' ? 'counter' : 'checklist');
    view.caption = main[0].kind === 'checklist' ? doneCaption(main[0]) : (texts.length > 0 ? texts[0].label : '');
  } else {
    view.layout = 'rows';
    const lists = main.filter((r: WidgetRow) => r.kind === 'checklist');
    view.caption = main.length === 1 && lists.length === 1 ? doneCaption(lists[0]) : '';
  }
}

const GOAL_LINE: RegExp = /^\s*(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)\s*(.*)$/;
const SCORE_LINE: RegExp = /^(.*?)\s*(\S{1,4})\s+[-–:]\s+(\S{1,4})$/;

/** A display line; "Games 2 - 1" or "15 - 30" becomes a score line. */
export function displayFor(key: string, text: string): WidgetDisplay {
  const d: WidgetDisplay = { key: key, kind: 'line', text: text, label: '', left: '', right: '' };
  const m = text.match(SCORE_LINE);
  if (m !== null && m[1].length <= 24) {
    d.kind = 'score';
    d.label = m[1].trim();
    d.left = m[2];
    d.right = m[3];
  }
  return d;
}

/** The shown v1 components in order: "when" blocks only when their condition holds, rows flattened. */
function shownComponents(capsule: Capsule, values: StateValues, list: CapsuleComponent[], out: CapsuleComponent[]): void {
  list.forEach((c: CapsuleComponent) => {
    if (c.type === 'when') {
      if (isShown(capsule, values, c as WhenComponent)) {
        shownComponents(capsule, values, (c as WhenComponent).show, out);
      }
    } else if (c.type === 'row') {
      shownComponents(capsule, values, (c as RowComponent).items, out);
    } else {
      out.push(c);
    }
  });
}

/** v1 card: display values rendered from the state, the capsule's buttons, and any v0 timers/counters/lists. */
function buildLogicView(capsule: Capsule, state: CapsuleState, values: StateValues, gate: GateFacts,
  wide: boolean): WidgetView {
  const view = baseView('ok', capsule.id, capsule.name, '', wide);
  const buttons = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type === 'button');
  const shown: CapsuleComponent[] = [];
  shownComponents(capsule, values, capsule.ui, shown);
  // Live display values first (scores, results), the capsule's static text lines after them: a card that
  // only fits one line shows what changes, not the instructions.
  const lines: string[] = [];
  const texts: string[] = [];
  shown.forEach((c: CapsuleComponent, i: number) => {
    if (c.type === 'display') {
      lines.push(renderTemplate(capsule, values, (c as DisplayComponent).text));
    } else if (c.type === 'text') {
      texts.push((c as TextComponent).text);
    } else if (c.type === 'button') {
      const b = c as ButtonComponent;
      view.buttons.push({ index: buttons.indexOf(c), label: b.label, enabled: isEnabled(capsule, values, b) });
    } else if (permitted(permissionForComponent(c), gate.granted)) {
      const r = v0Row(capsule, c, i, state, gate);
      if (r !== null) {
        view.rows.push(r);
      }
    }
  });
  texts.forEach((t: string) => lines.push(t));
  const goal = lines.length > 0 && view.rows.length === 0 ? lines[0].match(GOAL_LINE) : null;
  if (goal !== null && parseFloat(goal[2]) > 0) {
    view.layout = 'goal';
    view.icon = 'goal';
    view.value = parseFloat(goal[1]);
    view.goal = parseFloat(goal[2]);
    const rest = goal[3].replace(/^[\s·•,\-–:|]+/, '').trim();
    view.caption = lines.length > 1 ? lines[1] : rest;
    if (lines.length > 1 && rest.length > 0) {
      view.caption = `${rest} · ${lines[1]}`;
    }
  } else {
    view.layout = 'logic';
    view.icon = view.rows.some((r: WidgetRow) => r.kind === 'timer') ? 'timer' : 'logic';
    view.displays = lines.map((t: string, n: number) => displayFor(`${n}:${t}`, t));
  }
  return view;
}

function clock(ms: number): string {
  const total = Math.max(Math.ceil(ms / 1000), 0);
  const m = Math.floor(total / 60);
  const sec = total % 60;
  return `${m}:${sec < 10 ? '0' : ''}${sec}`;
}

/** The compact (1x2) card's one line: the main value or status of the view's layout. */
export function summaryLine(view: WidgetView, now: number): string {
  const first = view.rows.find((r: WidgetRow) => r.kind !== 'text');
  if (view.layout === 'goal') {
    return `${view.value} / ${view.goal}`;
  }
  if (view.layout === 'logic' && view.displays.length > 0) {
    const d = view.displays[0];
    return d.kind === 'score' ? `${d.label.length > 0 ? d.label + ' ' : ''}${d.left} – ${d.right}` : d.text;
  }
  if (first === undefined) {
    return view.message;
  }
  if (first.kind === 'counter') {
    return `${first.value}`;
  }
  if (first.kind === 'timer') {
    return first.endAt > now ? `${clock(first.endAt - now)} left` : (first.endAt > 0 ? 'Done' : clock(first.minutes * 60000));
  }
  const done = first.items.filter((i: WidgetCheckItem) => i.checked).length;
  return done === first.items.length ? 'All done' : `${done} / ${first.items.length} done`;
}

/**
 * Builds the card view. Only widget-suitable capsules are shown, and only components and
 * actions the gatekeeper allows: a component needing an ungranted permission is hidden, and a
 * start/+ control appears only if the capsule declares that action and its permission is granted.
 * `values` are the capsule's saved v1 state values (used for v1 capsules only).
 */
export function buildWidgetView(capsule: Capsule, state: CapsuleState, gate: GateFacts, now: number,
  wide: boolean, values?: StateValues): WidgetView {
  if (gate.removed) {
    return baseView('removed', capsule.id, capsule.name, 'This capsule was removed.', wide);
  }
  const route = routeCapsule(capsule);
  if (!route.widget) {
    // Not drawn on the card: the name, why (for motion, which only runs in the open app) and a tap into the app.
    const motion = allComponents(capsule.ui).some((c: CapsuleComponent) => c.type === 'counter' &&
      (c as CounterComponent).source === 'motion') || (capsule.triggers ?? []).some((t: Trigger) => t.on === 'motion');
    const why = motion ? 'Counts motion only while the capsule is open. Tap to open.' : 'Tap to open';
    const v = baseView('empty', capsule.id, capsule.name, why, wide);
    v.icon = capsule.schemaVersion === 1 ? 'logic' : 'blank';
    return v;
  }
  let view: WidgetView;
  if (isV1(capsule)) {
    // The shared widget state has the latest values; the app's own store is the fallback for older capsules.
    view = buildLogicView(capsule, state, state.values ?? restoreState(capsule, values ?? {}), gate, wide);
  } else {
    view = baseView('ok', capsule.id, capsule.name, '', wide);
    allComponents(capsule.ui).forEach((c: CapsuleComponent, i: number) => { // rows flattened
      if (c.type === 'button' || c.type === 'row') {
        return; // buttons become the start/+ controls on their rows
      }
      if (!permitted(permissionForComponent(c), gate.granted)) {
        return;
      }
      const r = v0Row(capsule, c, i, state, gate);
      if (r !== null) {
        view.rows.push(r);
      }
    });
    arrangeV0(view);
  }
  view.summary = summaryLine(view, now);
  const hidden = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type !== 'button' &&
    !permitted(permissionForComponent(c), gate.granted)).length;
  if (hidden > 0) {
    view.message = gate.decided ? `${hidden} item${hidden === 1 ? '' : 's'} blocked by the gatekeeper.` :
      'Open the app to allow permissions.';
  }
  return view;
}

// ---- Which capsule a new widget shows ----

export interface SavedCapsule {
  capsule: Capsule;
  savedAt: number;
}

/** The most recently saved widget-suitable capsule that has not been removed, or null. */
export function pickCapsuleForNewWidget(saved: SavedCapsule[], isRemoved: (capsuleId: string) => boolean): Capsule |
  null {
  let best: SavedCapsule | null = null;
  for (const s of saved) {
    if (routeCapsule(s.capsule).widget && !isRemoved(s.capsule.id) && (best === null || s.savedAt > best.savedAt)) {
      best = s;
    }
  }
  return best === null ? null : best.capsule;
}

// ---- "Add to home screen": the capsule the next new widget shows ----

/** Set by the capsule screen's "Add to home screen" right before the system's add-widget page opens. */
export interface PendingCapsule {
  capsuleId: string;
  /** When it was set (ms). */
  at: number;
}

/** A pending capsule older than this is ignored (the user left the add-widget page without adding). */
export const PENDING_TTL_MS: number = 3 * 60 * 1000;

/**
 * The capsule a newly added widget shows: the pending one if it is recent and still available, else none
 * ('' = blank, "Tap to choose a capsule"). Never "the latest capsule".
 */
export function capsuleForNewWidget(pending: PendingCapsule | null, now: number,
  isAvailable: (capsuleId: string) => boolean): string {
  if (pending === null || pending.capsuleId.length === 0 || now - pending.at > PENDING_TTL_MS || now < pending.at) {
    return '';
  }
  return isAvailable(pending.capsuleId) ? pending.capsuleId : '';
}

// ---- Which widget shows which capsule ----

/** One placed widget and the capsule it shows ('' = blank). */
export interface WidgetBindingFact {
  formId: string;
  capsuleId: string;
  wide: boolean;
  /** When the widget was added (ms). Missing on bindings saved before it was recorded: those count as oldest. */
  addedAt?: number;
  /** The widget's palette slot (see WIDGET_PALETTE). Missing on older bindings: use stableColorTag(formId). */
  colorTag?: number;
  /** The widget's size. Missing on older bindings: 'w' when wide, else 'm' (see sizeOfBinding). */
  size?: CardSize;
}

export function sizeOfBinding(b: WidgetBindingFact): CardSize {
  return b.size ?? (b.wide ? 'w' : 'm');
}

export class AssignmentPlan {
  /** Every binding after the plan, in widget order. */
  bindings: WidgetBindingFact[] = [];
  /** formIds whose capsule changed and must be redrawn and saved. */
  changed: string[] = [];
  /** Capsule ids seen so far; a saved capsule not in here is new. */
  seen: string[] = [];
}

/** Widgets in the order they were added (form ids are not ordered, so addedAt decides; formId breaks ties). */
function widgetOrder(a: WidgetBindingFact, b: WidgetBindingFact): number {
  const byTime = (a.addedAt ?? 0) - (b.addedAt ?? 0);
  if (byTime !== 0) {
    return byTime;
  }
  return a.formId < b.formId ? -1 : (a.formId > b.formId ? 1 : 0);
}

/**
 * Keeps widgets in step with the saved capsules:
 *  1. A widget whose capsule is no longer saved (or was removed) goes blank ("Tap to choose a capsule").
 *  2. Each new widget-suitable capsule (not seen before, not shown anywhere) fills the first blank widget,
 *     oldest new capsule first.
 * `saved` is newest first. With `seen` null (first run) every saved capsule counts as already seen, so
 * existing capsules are not pushed onto widgets the user left blank.
 */
export function planWidgetAssignments(bindings: WidgetBindingFact[], saved: Capsule[], seen: string[] | null,
  isRemoved: (capsuleId: string) => boolean): AssignmentPlan {
  const plan = new AssignmentPlan();
  const alive = saved.filter((c: Capsule) => !isRemoved(c.id));
  const aliveIds = alive.map((c: Capsule) => c.id);
  const known = seen ?? saved.map((c: Capsule) => c.id);
  const sorted = bindings.slice().sort(widgetOrder);
  sorted.forEach((b: WidgetBindingFact) => {
    const next: WidgetBindingFact = {
      formId: b.formId, capsuleId: b.capsuleId, wide: b.wide, addedAt: b.addedAt, colorTag: b.colorTag, size: b.size
    };
    if (next.capsuleId.length > 0 && !aliveIds.includes(next.capsuleId)) {
      next.capsuleId = '';
      plan.changed.push(next.formId);
    }
    plan.bindings.push(next);
  });
  const shown = plan.bindings.map((b: WidgetBindingFact) => b.capsuleId);
  const fresh = alive.filter((c: Capsule) => !known.includes(c.id) && !shown.includes(c.id) && routeCapsule(c).widget)
    .reverse(); // oldest new capsule first
  fresh.forEach((c: Capsule) => {
    const blank = plan.bindings.find((b: WidgetBindingFact) => b.capsuleId.length === 0);
    if (blank !== undefined) {
      blank.capsuleId = c.id;
      if (!plan.changed.includes(blank.formId)) {
        plan.changed.push(blank.formId);
      }
    }
  });
  const all = known.concat(saved.map((c: Capsule) => c.id));
  plan.seen = all.filter((id: string, i: number) => all.indexOf(id) === i && saved.some((c: Capsule) => c.id === id));
  return plan;
}

/** The first blank widget in the order widgets were added, or null. */
export function firstBlank(bindings: WidgetBindingFact[]): WidgetBindingFact | null {
  const blank = bindings.slice().sort(widgetOrder).find((b: WidgetBindingFact) => b.capsuleId.length === 0);
  return blank ?? null;
}
