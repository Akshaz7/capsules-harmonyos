/**
 * Decides whether a capsule can live on the home screen as a widget or only in the app.
 * Schema v0 widget-suitable: at most 4 components, only timer/counter/checklist/text/button,
 * checklists with at most 6 items, and no number inputs.
 * Schema v1 (state, computed or "do" buttons) widget-suitable when it fits a card: at most 3 display/text
 * lines, at most 3 buttons, at most 2 timers/counters/checklists, and no inputs or lists (they need typing).
 */
import { ButtonComponent, Capsule, CapsuleComponent, ChecklistComponent, CounterComponent } from './CapsuleTypes';
import { allComponents } from './CapsuleProgram';
import { usesMotion } from '../capabilities/MotionConsumers';

export const MAX_WIDGET_COMPONENTS: number = 4;
export const MAX_WIDGET_CHECKLIST_ITEMS: number = 6;
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
  const long = all.find((c: CapsuleComponent) => c.type === 'checklist' &&
    (c as ChecklistComponent).items.length > MAX_WIDGET_CHECKLIST_ITEMS);
  if (long !== undefined) {
    return { widget: false, reason: `App only: checklist has more than ${MAX_WIDGET_CHECKLIST_ITEMS} items.` };
  }
  return { widget: true, reason: `Widget-suitable: ${lines} lines, ${buttons} buttons (schema v1).` };
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
  if (capsule.ui.length > MAX_WIDGET_COMPONENTS) {
    return {
      widget: false,
      reason: `App only: ${capsule.ui.length} components (a widget fits at most ${MAX_WIDGET_COMPONENTS}).`
    };
  }
  for (const c of capsule.ui) {
    if (c.type === 'number') {
      return { widget: false, reason: 'App only: number inputs are not supported on widgets.' };
    }
    if (!WIDGET_TYPES.includes(c.type)) {
      return { widget: false, reason: `App only: ${c.type} components are not supported on widgets.` };
    }
    if (c.type === 'checklist') {
      const items = (c as ChecklistComponent).items.length;
      if (items > MAX_WIDGET_CHECKLIST_ITEMS) {
        return {
          widget: false,
          reason: `App only: checklist has ${items} items (a widget fits at most ${MAX_WIDGET_CHECKLIST_ITEMS}).`
        };
      }
    }
  }
  const types = capsule.ui.map((c: CapsuleComponent) => c.type).join(', ');
  return { widget: true, reason: `Widget-suitable: ${capsule.ui.length} components (${types}).` };
}
