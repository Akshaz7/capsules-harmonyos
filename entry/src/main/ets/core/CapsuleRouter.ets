/**
 * Decides whether a capsule can live on the home screen as a widget or only in the app.
 * Counted over all components (rows flattened). Checklists of any length fit: the card shows the first
 * items and "+N more".
 * Schema v0 widget-suitable: only timer/counter/checklist/text/button (in rows too), no number inputs, at most
 * 3 text lines, 3 buttons and 3 timers/counters/checklists.
 * Schema v1 (state, computed or "do" buttons) widget-suitable when it fits a card: at most 3 display/text
 * lines, at most 3 buttons, at most 2 timers/counters/checklists, and no inputs or lists (they need typing).
 */
import { ButtonComponent, Capsule, CapsuleComponent } from './CapsuleTypes';
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
const V1_INPUT_TYPES: string[] = ['number', 'input', 'list'];

function isV1(capsule: Capsule): boolean {
  return capsule.schemaVersion === 1 || capsule.state !== undefined || capsule.computed !== undefined ||
    allComponents(capsule.ui).some((c: CapsuleComponent) => c.type === 'button' &&
      ((c as ButtonComponent).do !== undefined || (c as ButtonComponent).enabledIf !== undefined));
}

/** A v1 capsule fits a card when its lines, buttons and parts are few and nothing needs typing. */
function routeV1(capsule: Capsule): CapsuleRoute {
  const all = allComponents(capsule.ui);
  const count = (types: string[]): number => all.filter((c: CapsuleComponent) => types.includes(c.type)).length;
  const typed = all.find((c: CapsuleComponent) => V1_INPUT_TYPES.includes(c.type));
  if (typed !== undefined) {
    return { widget: false, reason: `App only: ${typed.type} components need typing, which widgets cannot do.` };
  }
  const lines = count(['display', 'text']);
  if (lines > MAX_WIDGET_LINES) {
    return { widget: false, reason: `App only: ${lines} lines of text (a widget fits at most ${MAX_WIDGET_LINES}).` };
  }
  const buttons = count(['button']);
  if (buttons > MAX_WIDGET_BUTTONS) {
    return { widget: false, reason: `App only: ${buttons} buttons (a widget fits at most ${MAX_WIDGET_BUTTONS}).` };
  }
  const parts = count(['timer', 'counter', 'checklist']);
  if (parts > MAX_WIDGET_PARTS) {
    return { widget: false, reason: `App only: ${parts} timers, counters or checklists (a widget fits at most ${MAX_WIDGET_PARTS}).` };
  }
  return { widget: true, reason: `Widget-suitable: ${lines} lines, ${buttons} buttons (schema v1).` };
}

/** A v0 capsule fits a card when its parts, text lines and buttons are few (rows are flattened). */
function routeV0(capsule: Capsule): CapsuleRoute {
  const all = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type !== 'row');
  for (const c of all) {
    if (c.type === 'number') {
      return { widget: false, reason: 'App only: number inputs are not supported on widgets.' };
    }
    if (!WIDGET_TYPES.includes(c.type)) {
      return { widget: false, reason: `App only: ${c.type} components are not supported on widgets.` };
    }
  }
  const count = (type: string): number => all.filter((c: CapsuleComponent) => c.type === type).length;
  const parts = count('timer') + count('counter') + count('checklist');
  if (parts > MAX_V0_PARTS) {
    return { widget: false, reason: `App only: ${parts} timers, counters or checklists (a widget fits at most ${MAX_V0_PARTS}).` };
  }
  if (count('text') > MAX_WIDGET_LINES) {
    return { widget: false, reason: `App only: ${count('text')} lines of text (a widget fits at most ${MAX_WIDGET_LINES}).` };
  }
  if (count('button') > MAX_WIDGET_BUTTONS) {
    return { widget: false, reason: `App only: ${count('button')} buttons (a widget fits at most ${MAX_WIDGET_BUTTONS}).` };
  }
  const types = all.map((c: CapsuleComponent) => c.type).join(', ');
  return { widget: true, reason: `Widget-suitable: ${all.length} components (${types}).` };
}

export interface CapsuleRoute {
  widget: boolean;
  /** Why the capsule is or is not widget-suitable. */
  reason: string;
}

export function routeCapsule(capsule: Capsule): CapsuleRoute {
  if (capsule.ui.length === 0) {
    return { widget: false, reason: 'App only: the capsule has no components.' };
  }
  if (usesMotion(capsule)) {
    return {
      widget: false,
      reason: 'App only: motion counters and triggers run while the capsule is open in the app.'
    };
  }
  const readings: number = allComponents(capsule.ui).filter((c: CapsuleComponent) => c.type === 'device').length;
  if (readings > 0) {
    return {
      widget: false,
      reason: 'App only: live readings such as the battery are shown in the app.'
    };
  }
  if (isV1(capsule)) {
    return routeV1(capsule);
  }
  return routeV0(capsule);
}
