/**
 * Decides how a capsule appears on a home-screen widget: in full, or condensed (T4-19).
 * Counted over all components (rows flattened). Checklists of any length fit: the card shows the first
 * items and "+N more".
 * Schema v0 fits in full with only timer/counter/checklist/text/button (in rows too), no number inputs, at most
 * 3 text lines, 3 buttons and 3 timers/counters/checklists.
 * Schema v1 (state, computed or "do" buttons) fits a card in full with at most 3 display/text lines, 3 buttons,
 * 2 timers/counters/checklists and no inputs, lists or readings. Anything more is shown condensed (T4-19).
 */
import { ButtonComponent, Capsule, CapsuleComponent, DeviceComponent, InputComponent } from './CapsuleTypes';
import { allComponents } from './CapsuleProgram';
import { usesMotion } from '../capabilities/MotionConsumers';

/** Kept for callers of the old v0 rule; v0 now counts parts, lines and buttons like v1 (see routeV0). */
export const MAX_WIDGET_COMPONENTS: number = 4;
/** Checklist items the wide card shows before "+N more" (no longer a limit on what fits). */
export const MAX_WIDGET_CHECKLIST_ITEMS: number = 6;
const MAX_V0_PARTS: number = 3;
const WIDGET_TYPES: string[] = ['timer', 'counter', 'checklist', 'text', 'button'];
export const MAX_WIDGET_LINES: number = 3;
export const MAX_WIDGET_BUTTONS: number = 3;
const MAX_WIDGET_PARTS: number = 2;
/** What a card can draw: anything else (readings, inputs, lists) is left to the app. */
const CARD_TYPES: string[] = ['timer', 'counter', 'checklist', 'text', 'button', 'display'];
const V1_INPUT_TYPES: string[] = ['number', 'input', 'list'];

const V1_ONLY_TYPES: string[] = ['display', 'input', 'list', 'when', 'device'];

/**
 * True when the capsule uses v1 features a card draws differently: state, computed values, v1 components or
 * "do"/"enabledIf" buttons. "schemaVersion": 1 alone does not count: a v0-shaped capsule that only gained time
 * triggers (T4-16) keeps its v0 card.
 */
export function usesV1Features(capsule: Capsule): boolean {
  return capsule.state !== undefined || capsule.computed !== undefined ||
    allComponents(capsule.ui).some((c: CapsuleComponent) => V1_ONLY_TYPES.includes(c.type) || (c.type === 'button' &&
      ((c as ButtonComponent).do !== undefined || (c as ButtonComponent).enabledIf !== undefined)));
}

function isV1(capsule: Capsule): boolean {
  return usesV1Features(capsule);
}

/**
 * A task list (T4-23): one list, any text inputs (to add items in the app), at most one weather reading and
 * nothing else that needs typing or a live reading. The rules "Tasks and weather" capsule and the live Claude
 * one. The card shows the list (tap an item to finish it); the weather card and the typing stay in the app.
 */
export function isTaskList(capsule: Capsule): boolean {
  const all = allComponents(capsule.ui);
  const lists = all.filter((c: CapsuleComponent) => c.type === 'list').length;
  const devices = all.filter((c: CapsuleComponent) => c.type === 'device');
  const typing = all.filter((c: CapsuleComponent) => c.type === 'number' ||
    (c.type === 'input' && (c as InputComponent).kind !== 'text'));
  return lists === 1 && typing.length === 0 && devices.length <= 1 &&
    devices.every((c: CapsuleComponent) => (c as DeviceComponent).bind === 'weather');
}

/** What a full card cannot draw: too many lines, buttons or parts, inputs, live readings or other components. */
function overflowV1(capsule: Capsule): string {
  const all = allComponents(capsule.ui);
  const count = (types: string[]): number => all.filter((c: CapsuleComponent) => types.includes(c.type)).length;
  const typed = all.find((c: CapsuleComponent) => V1_INPUT_TYPES.includes(c.type));
  if (typed !== undefined) {
    return `${typed.type} components are edited in the app`;
  }
  if (count(['device']) > 0) {
    return 'live readings are shown in the app';
  }
  if (count(['display', 'text']) > MAX_WIDGET_LINES) {
    return `${count(['display', 'text'])} lines (the card shows ${MAX_WIDGET_LINES})`;
  }
  if (count(['button']) > MAX_WIDGET_BUTTONS) {
    return `${count(['button'])} buttons (the card shows ${MAX_WIDGET_BUTTONS})`;
  }
  if (count(['timer', 'counter', 'checklist']) > MAX_WIDGET_PARTS) {
    return `${count(['timer', 'counter', 'checklist'])} timers, counters or checklists (the card shows ${MAX_WIDGET_PARTS})`;
  }
  return '';
}

function overflowV0(capsule: Capsule): string {
  const all = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type !== 'row');
  const odd = all.find((c: CapsuleComponent) => !WIDGET_TYPES.includes(c.type));
  if (odd !== undefined) {
    return odd.type === 'number' ? 'number inputs are edited in the app' : `${odd.type} components are shown in the app`;
  }
  const count = (type: string): number => all.filter((c: CapsuleComponent) => c.type === type).length;
  const parts = count('timer') + count('counter') + count('checklist');
  if (parts > MAX_V0_PARTS) {
    return `${parts} timers, counters or checklists (the card shows ${MAX_V0_PARTS})`;
  }
  if (count('text') > MAX_WIDGET_LINES) {
    return `${count('text')} lines (the card shows ${MAX_WIDGET_LINES})`;
  }
  if (count('button') > MAX_WIDGET_BUTTONS) {
    return `${count('button')} buttons (the card shows ${MAX_WIDGET_BUTTONS})`;
  }
  return '';
}

export interface CapsuleRoute {
  widget: boolean;
  /** Why the capsule is or is not widget-suitable. */
  reason: string;
  /** True when the card shows a condensed view (the top values and buttons; "Open for more"). */
  condensed?: boolean;
}

/**
 * Every capsule with components fits a widget (T4-19): one that a card cannot draw in full gets a condensed
 * view (top 3 values, up to 3 buttons, "Open for more" / "Open to edit values"). Off widgets: motion capsules
 * (they count while the capsule is open) and capsules with nothing a card can draw (only live readings).
 */
export function routeCapsule(capsule: Capsule): CapsuleRoute {
  if (capsule.ui.length === 0) {
    return { widget: false, reason: 'The capsule has no components yet.' };
  }
  if (usesMotion(capsule)) {
    return { widget: false, reason: 'Counts motion only while the capsule is open, so it stays in the app.' };
  }
  const drawable = allComponents(capsule.ui).filter((c: CapsuleComponent) => CARD_TYPES.includes(c.type)).length;
  if (drawable === 0) {
    return { widget: false, reason: 'Nothing here fits a card: live readings and inputs are shown in the app.' };
  }
  if (isV1(capsule) && isTaskList(capsule)) {
    return { widget: true, condensed: false, reason: 'Widget: a task list (add tasks in the app).' };
  }
  const over = isV1(capsule) ? overflowV1(capsule) : overflowV0(capsule);
  if (over.length > 0) {
    return { widget: true, condensed: true, reason: `Widget, condensed: ${over}.` };
  }
  const n = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type !== 'row').length;
  return { widget: true, condensed: false, reason: `Widget: all ${n} components fit the card.` };
}
