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
  Permission,
  TextComponent,
  TimerComponent
} from './CapsuleTypes';
import { parseAction, permissionForAction, permissionForComponent } from './CapsuleValidator';
import { routeCapsule } from './CapsuleRouter';

type JsonValue = Object | null | undefined;
type JsonRecord = Record<string, Object | null>;

// ---- Persisted state ----

/** endAt is the epoch ms when the timer ends; 0 means it is not running. */
export interface TimerRun {
  id: string;
  endAt: number;
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
}

export function initialState(capsule: Capsule): CapsuleState {
  const state: CapsuleState = { capsuleId: capsule.id, timers: [], counters: [], checklists: [] };
  capsule.ui.forEach((c: CapsuleComponent) => {
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
  });
  const counters = asArray(root['counters']);
  state.counters.forEach((c: CounterValue) => {
    const saved = findById(counters, c.id);
    const value: JsonValue = saved === null ? null : saved['value'];
    if (typeof value === 'number' && Number.isInteger(value as number) && (value as number) >= 0) {
      c.value = value as number;
    }
  });
  const lists = asArray(root['checklists']);
  state.checklists.forEach((l: ChecklistTicks) => {
    const saved = findById(lists, l.id);
    const checked = saved === null ? [] : asArray(saved['checked']);
    l.checked = l.checked.map((def: boolean, i: number) => i < checked.length && checked[i] === true ? true : def);
  });
  return state;
}

// ---- Widget messages (sent by the card through postCardAction) ----

export type WidgetOp = 'start' | 'increment' | 'toggle' | 'refresh';

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
  if (op !== 'start' && op !== 'increment' && op !== 'toggle' && op !== 'refresh') {
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
}

export type WidgetStatus = 'ok' | 'empty' | 'removed';

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
}

export interface GateFacts {
  /** Permissions the user granted this capsule. */
  granted: Permission[];
  /** True once the user answered the consent screen. */
  decided: boolean;
  /** True after Undo removed the capsule. */
  removed: boolean;
}

function row(kind: WidgetRowKind, id: string, label: string): WidgetRow {
  return {
    key: '', kind: kind, id: id, label: label, minutes: 0, endAt: 0, canStart: false, value: 0, canIncrement: false,
    items: []
  };
}

function permitted(p: Permission | null, granted: Permission[]): boolean {
  return p === null || granted.includes(p);
}

export const BLANK_WIDGET_MESSAGE: string = 'Tap to choose a capsule';

export function emptyView(wide: boolean): WidgetView {
  return {
    status: 'empty', capsuleId: '', title: 'Harmoniser', message: BLANK_WIDGET_MESSAGE,
    rows: [], wide: wide
  };
}

/**
 * Builds the card view. Only widget-suitable capsules are shown, and only components and
 * actions the gatekeeper allows: a component needing an ungranted permission is hidden, and a
 * start/+ control appears only if the capsule declares that action and its permission is granted.
 */
export function buildWidgetView(capsule: Capsule, state: CapsuleState, gate: GateFacts, now: number,
  wide: boolean): WidgetView {
  if (gate.removed) {
    return {
      status: 'removed', capsuleId: capsule.id, title: capsule.name, message: 'This capsule was removed.', rows: [],
      wide: wide
    };
  }
  const route = routeCapsule(capsule);
  if (!route.widget) {
    return {
      status: 'empty', capsuleId: capsule.id, title: capsule.name, message: route.reason, rows: [], wide: wide
    };
  }
  const rows: WidgetRow[] = [];
  let hidden = 0;
  capsule.ui.forEach((c: CapsuleComponent, i: number) => {
    if (c.type === 'button') {
      return; // buttons become the start/+ controls on their rows
    }
    if (!permitted(permissionForComponent(c), gate.granted)) {
      hidden++;
      return;
    }
    if (c.type === 'text') {
      const r = row('text', '', (c as TextComponent).text);
      r.key = `${i}:text:${r.label}`;
      rows.push(r);
    } else if (c.type === 'timer') {
      const t = c as TimerComponent;
      const r = row('timer', t.id, t.label);
      const run = state.timers.find((x: TimerRun) => x.id === t.id);
      r.minutes = t.minutes;
      r.endAt = run !== undefined ? run.endAt : 0;
      const action = declaredAction(capsule, { op: 'start', id: t.id, index: -1 });
      r.canStart = action !== null && permitted(permissionForAction({ kind: 'startTimer', arg: t.id }), gate.granted);
      r.key = `${i}:timer:${t.id}:${r.endAt}:${r.canStart}`;
      rows.push(r);
    } else if (c.type === 'counter') {
      const k = c as CounterComponent;
      const r = row('counter', k.id, k.label);
      const v = state.counters.find((x: CounterValue) => x.id === k.id);
      r.value = v !== undefined ? v.value : 0;
      const action = declaredAction(capsule, { op: 'increment', id: k.id, index: -1 });
      const parsed = action === null ? null : parseAction(action);
      r.canIncrement = parsed !== null && permitted(permissionForAction(parsed), gate.granted);
      r.key = `${i}:counter:${k.id}:${r.value}:${r.canIncrement}`;
      rows.push(r);
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
      r.key = `${i}:checklist:${l.id}:${r.items.map((x: WidgetCheckItem) => x.checked ? '1' : '0').join('')}`;
      rows.push(r);
    }
  });
  let message = '';
  if (hidden > 0) {
    message = gate.decided ? `${hidden} item${hidden === 1 ? '' : 's'} blocked by the gatekeeper.` :
      'Open the app to allow permissions.';
  }
  return { status: 'ok', capsuleId: capsule.id, title: capsule.name, message: message, rows: rows, wide: wide };
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

// ---- Which widget shows which capsule ----

/** One placed widget and the capsule it shows ('' = blank). */
export interface WidgetBindingFact {
  formId: string;
  capsuleId: string;
  wide: boolean;
  /** When the widget was added (ms). Missing on bindings saved before it was recorded: those count as oldest. */
  addedAt?: number;
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
    const next: WidgetBindingFact = { formId: b.formId, capsuleId: b.capsuleId, wide: b.wide, addedAt: b.addedAt };
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
