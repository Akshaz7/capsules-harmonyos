/**
 * Decides whether a capsule can live on the home screen as a widget or only in the app.
 * Widget-suitable: at most 4 components, only timer/counter/checklist/text/button,
 * checklists with at most 6 items, and no number inputs.
 */
import { ButtonComponent, Capsule, CapsuleComponent, ChecklistComponent } from './CapsuleTypes';

export const MAX_WIDGET_COMPONENTS: number = 4;
export const MAX_WIDGET_CHECKLIST_ITEMS: number = 6;
const WIDGET_TYPES: string[] = ['timer', 'counter', 'checklist', 'text', 'button'];

export interface CapsuleRoute {
  widget: boolean;
  /** Why the capsule is or is not widget-suitable. */
  reason: string;
}

export function routeCapsule(capsule: Capsule): CapsuleRoute {
  if (capsule.ui.length === 0) {
    return { widget: false, reason: 'App only: the capsule has no components.' };
  }
  if (capsule.ui.length > MAX_WIDGET_COMPONENTS) {
    return {
      widget: false,
      reason: `App only: ${capsule.ui.length} components (a widget fits at most ${MAX_WIDGET_COMPONENTS}).`
    };
  }
  if (capsule.state !== undefined || capsule.computed !== undefined) {
    return { widget: false, reason: 'App only: schema v1 state and computed values run in the app.' };
  }
  for (const c of capsule.ui) {
    if (c.type === 'button' && ((c as ButtonComponent).do !== undefined || (c as ButtonComponent).enabledIf !== undefined)) {
      return { widget: false, reason: 'App only: schema v1 button steps run in the app.' };
    }
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
