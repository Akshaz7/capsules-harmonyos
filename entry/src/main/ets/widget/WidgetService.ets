/**
 * Builds and pushes Harmoniser widget content. Used by the FormExtensionAbility, and by the
 * app (refreshCapsuleWidgets) whenever capsule state or the saved capsules change.
 *
 * Widget assignment API for the app:
 *   listWidgets(ctx)                          every placed widget: formId, capsuleId (null = blank), size
 *   firstBlankWidget(ctx)                     the first blank widget, or null
 *   assignCapsuleToWidget(ctx, formId, id)    show a capsule on a widget now (null clears it)
 * refreshCapsuleWidgets also keeps assignments in step: a new widget-suitable capsule fills the first
 * blank widget, and a widget whose capsule was removed goes back to "Tap to choose a capsule".
 * A blank widget, when tapped, opens EntryAbility with parameters
 *   { source: 'harmoniser', action: 'chooseCapsule', formId: '<formId>' }.
 */
import { common, Want } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule, Permission } from '../core/CapsuleTypes';
import { restoreState } from '../core/CapsuleProgram';
import {
  accentFor, applyWidgetMessage, buildWidgetView, declaredAction, emptyView, firstBlank, GateFacts, parseWidgetMessage,
  capsuleForNewWidget, CardSize, isWideSize, pickColorTag, sizeOfBinding, pressWidgetButton, planWidgetAssignments, stableColorTag, WidgetView, withColor
} from '../core/WidgetModel';
import { Gatekeeper } from '../gatekeeper/Gatekeeper';
import {
  FormBinding, allBindings, getBinding, isFormProcess, loadSeen, loadState, putBinding, saveSeen, saveState,
  savedCapsules, savedValues, savePending, peekPending, clearPending
} from './WidgetStore';

const DOMAIN = 0x0002;
const TAG = 'Harmoniser';
const GATE_STORE = 'gatekeeper';
export const FORM_NAME = 'harmoniser';
export const FORM_ABILITY = 'HarmoniserFormAbility';
/** Want parameters a tapped blank widget sends to EntryAbility. */
export const WIDGET_SOURCE = 'harmoniser';
export const CHOOSE_CAPSULE_ACTION = 'chooseCapsule';

export type WidgetSize = '1x2' | '2x2' | '2x4' | '4x4';

const SIZE_NAMES: Record<CardSize, WidgetSize> = { 's': '1x2', 'm': '2x2', 'w': '2x4', 'l': '4x4' };

export interface WidgetInfo {
  formId: string;
  /** null when the widget is blank ("Tap to choose a capsule"). */
  capsuleId: string | null;
  size: WidgetSize;
  /** The widget's stable accent slot (WIDGET_PALETTE index), shown as its colour and a dot on the card. */
  colorTag: number;
  /** The accent colour of colorTag ("#RRGGBB"), for the dot in the app's widget list. */
  accent: string;
  /** The capsule's name; '' when blank. */
  capsuleName: string;
  /** Preview: the card's one-line summary ("3 / 8", "4:59 left", "All done"); '' when blank. */
  preview: string;
}

/**
 * A Gatekeeper with the latest grants. In the form process the app's writes are re-read from disk; in the
 * app process the cached store already has them (dropping it would lose a grant that is not flushed yet).
 */
function freshGate(ctx: common.Context): Gatekeeper {
  if (isFormProcess()) {
    try {
      const options: preferences.Options = { name: GATE_STORE };
      preferences.removePreferencesFromCacheSync(ctx, options);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not drop gatekeeper cache: %{public}s', (e as BusinessError).message);
    }
  }
  return new Gatekeeper(ctx);
}

function gateFacts(gate: Gatekeeper, capsule: Capsule, removedFromApp: boolean): GateFacts {
  const granted = gate.grants(capsule.id).filter((p: string) => capsule.permissions.includes(p as Permission));
  return {
    granted: granted as Permission[],
    decided: gate.hasDecided(capsule.id),
    removed: removedFromApp || gate.isRemoved(capsule.id)
  };
}

/** The view for one widget, from the latest saved capsules, state and grants. */
export function viewFor(ctx: common.Context, binding: FormBinding): WidgetView {
  const v = viewForCapsule(ctx, binding);
  v.formId = binding.formId;
  v.size = sizeOfBinding(binding);
  return withColor(v, colorTagOf(binding));
}

function viewForCapsule(ctx: common.Context, binding: FormBinding): WidgetView {
  const capsules = savedCapsules(ctx);
  const capsule = capsules.find((c: Capsule) => c.id === binding.capsuleId);
  const gate = freshGate(ctx);
  if (capsule === undefined) {
    if (binding.capsuleId.length === 0) {
      return emptyView(binding.wide);
    }
    const v = emptyView(binding.wide);
    v.status = 'removed';
    v.capsuleId = binding.capsuleId;
    v.message = 'This capsule was removed.';
    return v;
  }
  return buildWidgetView(capsule, loadState(ctx, capsule), gateFacts(gate, capsule, false), Date.now(), binding.wide,
    savedValues(ctx, capsule.id));
}

/** The widget's colour slot: saved when it was added, or derived from its formId for older widgets. */
export function colorTagOf(binding: FormBinding): number {
  return binding.colorTag ?? stableColorTag(binding.formId);
}

export function bindingData(view: WidgetView): formBindingData.FormBindingData {
  const data: Record<string, string> = { 'view': JSON.stringify(view) };
  return formBindingData.createFormBindingData(data);
}

/**
 * The binding for a widget the launcher (re)adds. The launcher calls onAddForm again with the
 * same formId after an app update, so an existing binding (blank or not, with its addedAt) is kept
 * and only its size is updated.
 */
export function bindForm(ctx: common.Context, formId: string, size: CardSize): FormBinding {
  const existing = getBinding(ctx, formId);
  if (existing === null) {
    return bindNewForm(ctx, formId, size);
  }
  if (existing.size !== size) {
    existing.size = size;
    existing.wide = isWideSize(size);
    putBinding(ctx, existing);
  }
  hilog.info(DOMAIN, TAG, 'form %{public}s keeps %{public}s', formId,
    existing.capsuleId.length > 0 ? existing.capsuleId : '(blank)');
  return existing;
}

/**
 * Binds a new widget to the capsule whose "Add to home screen" was tapped (the pending capsule, kept for the
 * system's preview widgets and the real one until it is on a widget or expires).
 * Without one the widget starts blank ("Tap to choose a capsule"); it never takes "the latest capsule".
 */
export function bindNewForm(ctx: common.Context, formId: string, size: CardSize): FormBinding {
  const capsules = savedCapsules(ctx);
  const gate = freshGate(ctx);
  const pending = peekPending(ctx); // previews and the real widget all show it (see peekPending)
  const chosen = capsuleForNewWidget(pending, Date.now(),
    (id: string) => capsules.some((c: Capsule) => c.id === id) && !gate.isRemoved(id));
  const used = allBindings(ctx).map((b: FormBinding) => colorTagOf(b));
  const binding: FormBinding = {
    formId: formId, capsuleId: chosen, wide: isWideSize(size), addedAt: Date.now(),
    colorTag: pickColorTag(used, formId), size: size
  };
  if (chosen.length > 0) {
    const seen = loadSeen(ctx) ?? [];
    if (!seen.includes(chosen)) {
      saveSeen(ctx, seen.concat([chosen]));
    }
  }
  putBinding(ctx, binding);
  hilog.info(DOMAIN, TAG, 'new form %{public}s -> capsule %{public}s (pending %{public}s)', formId,
    binding.capsuleId.length > 0 ? binding.capsuleId : '(blank)', pending === null ? 'none' : pending.capsuleId);
  return binding;
}

/** The capsule newly added widgets show for the next few minutes (see PENDING_TTL_MS and clearPendingFor). */
export function setPendingCapsule(ctx: common.Context, capsuleId: string): void {
  savePending(ctx, { capsuleId: capsuleId, at: Date.now() });
  hilog.info(DOMAIN, TAG, 'pending capsule for the next new widget: %{public}s', capsuleId);
}

/** Clears the pending capsule once a widget shows it (the button calls this when it sees the widget). */
export function clearPendingFor(ctx: common.Context, capsuleId: string): void {
  const pending = peekPending(ctx);
  if (pending !== null && pending.capsuleId === capsuleId) {
    clearPending(ctx);
    hilog.info(DOMAIN, TAG, 'pending capsule %{public}s is on a widget now; cleared', capsuleId);
  }
}

/** What "Add to home screen" did: already shown, filled a blank widget, opened the add-widget page, or neither. */
export type AddToHomeResult = 'already' | 'filled' | 'opened' | 'manual';

/**
 * "Add to home screen" for one capsule (the one open on screen, passed explicitly):
 *  already on a widget -> 'already'; a blank widget exists -> it shows this capsule ('filled');
 *  else this capsule becomes pending and the system's add-widget page opens ('opened'), so the widget the
 *  user adds shows it. 'manual' when that page cannot open (show the long-press steps).
 */
export async function addCapsuleToHomeScreen(ctx: common.UIAbilityContext, capsuleId: string):
  Promise<AddToHomeResult> {
  const widgets = listWidgets(ctx);
  if (widgets.some((w: WidgetInfo) => w.capsuleId === capsuleId)) {
    return 'already';
  }
  const blank = firstBlankWidget(ctx);
  if (blank !== null && await assignCapsuleToWidget(ctx, blank.formId, capsuleId)) {
    return 'filled';
  }
  setPendingCapsule(ctx, capsuleId);
  return openHarmoniserManager(ctx.abilityInfo.bundleName) ? 'opened' : 'manual';
}

export async function pushForm(ctx: common.Context, binding: FormBinding): Promise<void> {
  try {
    const view = viewFor(ctx, binding);
    await formProvider.updateForm(binding.formId, bindingData(view));
    hilog.info(DOMAIN, TAG, 'updated form %{public}s: %{public}s %{public}s, %{public}d rows (%{public}s)',
      binding.formId, view.status, binding.capsuleId.length > 0 ? binding.capsuleId : '(blank)', view.rows.length,
      isFormProcess() ? 'widget process' : 'app process');
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}d %{public}s', binding.formId, err.code,
      err.message);
  }
}

/**
 * Applies planWidgetAssignments to the stored bindings: blanks widgets whose capsule is gone (new capsules are
 * never put on widgets by themselves, T4-12). Returns all bindings and the formIds that changed.
 */
function syncAssignments(ctx: common.Context): SyncResult {
  const gate = freshGate(ctx);
  const plan = planWidgetAssignments(allBindings(ctx), savedCapsules(ctx), loadSeen(ctx),
    (id: string) => gate.isRemoved(id));
  plan.bindings.forEach((b: FormBinding) => {
    if (plan.changed.includes(b.formId)) {
      putBinding(ctx, b);
      hilog.info(DOMAIN, TAG, 'form %{public}s now shows %{public}s', b.formId, b.capsuleId.length > 0 ? b.capsuleId :
        '(blank)');
    }
  });
  saveSeen(ctx, plan.seen);
  return { bindings: plan.bindings, changed: plan.changed };
}

interface SyncResult {
  bindings: FormBinding[];
  changed: string[];
}

/**
 * Refreshes Harmoniser widgets after capsule state or the saved list changes: first keeps assignments in
 * step (see syncAssignments), then redraws every widget whose assignment changed plus every widget showing
 * `capsuleId` (or all widgets when it is omitted).
 */
export async function refreshCapsuleWidgets(ctx: common.Context, capsuleId?: string): Promise<void> {
  const sync = syncAssignments(ctx);
  for (const b of sync.bindings) {
    if (capsuleId === undefined || b.capsuleId === capsuleId || sync.changed.includes(b.formId)) {
      await pushForm(ctx, b);
    }
  }
}

function infoOf(ctx: common.Context, b: FormBinding): WidgetInfo {
  const blank = b.capsuleId.length === 0;
  const view = blank ? null : viewFor(ctx, b);
  return {
    formId: b.formId, capsuleId: blank ? null : b.capsuleId, size: SIZE_NAMES[sizeOfBinding(b)],
    colorTag: colorTagOf(b), accent: accentFor(colorTagOf(b)), capsuleName: view !== null ? view.title : '',
    preview: view !== null ? (view.summary ?? '') : ''
  };
}

/** Every placed Harmoniser widget, in the order they were added, with assignments brought up to date. */
export function listWidgets(ctx: common.Context): WidgetInfo[] {
  return syncAssignments(ctx).bindings.map((b: FormBinding) => infoOf(ctx, b));
}

/** The first blank widget (in the order widgets were added), or null if every widget shows a capsule. */
export function firstBlankWidget(ctx: common.Context): WidgetInfo | null {
  const blank = firstBlank(syncAssignments(ctx).bindings);
  return blank === null ? null : infoOf(ctx, blank as FormBinding);
}

/**
 * Shows `capsuleId` on widget `formId` and redraws it immediately; null makes the widget blank again.
 * Returns false (and changes nothing) if the widget does not exist, or the capsule is not saved, was
 * removed. Every capsule can be shown (one that does not fit the card shows its name and "Open in app").
 */
export async function assignCapsuleToWidget(ctx: common.Context, formId: string, capsuleId: string | null):
  Promise<boolean> {
  const binding = getBinding(ctx, formId);
  if (binding === null) {
    hilog.warn(DOMAIN, TAG, 'assign: no widget %{public}s', formId);
    return false;
  }
  if (capsuleId !== null) {
    const capsule = savedCapsules(ctx).find((c: Capsule) => c.id === capsuleId);
    if (capsule === undefined || freshGate(ctx).isRemoved(capsuleId)) {
      hilog.warn(DOMAIN, TAG, 'assign: capsule %{public}s cannot go on a widget', capsuleId);
      return false;
    }
  }
  binding.capsuleId = capsuleId ?? '';
  putBinding(ctx, binding);
  const seen = loadSeen(ctx) ?? [];
  if (capsuleId !== null && !seen.includes(capsuleId)) {
    saveSeen(ctx, seen.concat([capsuleId]));
  }
  hilog.info(DOMAIN, TAG, 'assign: form %{public}s -> %{public}s', formId, capsuleId ?? '(blank)');
  await pushForm(ctx, binding);
  return true;
}

/** Handles a tap sent by the card with postCardAction 'message'. */
export async function handleWidgetMessage(ctx: common.Context, formId: string, message: string): Promise<void> {
  const binding = getBinding(ctx, formId);
  const msg = parseWidgetMessage(message);
  hilog.info(DOMAIN, TAG, 'message for form %{public}s: %{public}s', formId, message);
  if (binding === null || msg === null) {
    hilog.warn(DOMAIN, TAG, 'ignored message for form %{public}s', formId);
    return;
  }
  const capsule = savedCapsules(ctx).find((c: Capsule) => c.id === binding.capsuleId);
  if (capsule !== undefined && msg.op !== 'refresh') {
    const action = declaredAction(capsule, msg);
    const gate = freshGate(ctx);
    if (action === null || gate.isRemoved(capsule.id)) {
      hilog.warn(DOMAIN, TAG, 'tap %{public}s on %{public}s is not declared by the capsule', msg.op, capsule.id);
    } else if (msg.op === 'press') {
      // A v1 button: its "do" steps run here with core's interpreter; every v0 action passes the gatekeeper.
      const state = loadState(ctx, capsule);
      if (state.values === undefined && capsule.state !== undefined) {
        state.values = restoreState(capsule, savedValues(ctx, capsule.id)); // not shared yet: start from the app's
      }
      const r = pressWidgetButton(capsule, state, msg.index, Date.now(),
        (a: string) => gate.allowAction(capsule, a));
      if (r.ok) {
        saveState(ctx, r.state);
        hilog.info(DOMAIN, TAG, 'button %{public}d on %{public}s ran: %{public}s', msg.index, capsule.id,
          r.actions.length > 0 ? r.actions.join(', ') : 'state only');
      } else {
        hilog.warn(DOMAIN, TAG, 'button %{public}d on %{public}s did nothing: %{public}s', msg.index, capsule.id,
          r.blocked.length > 0 ? r.blocked : r.error);
      }
    } else if (action.length > 0 && !gate.allowAction(capsule, action)) {
      // Blocked and logged by the gatekeeper.
    } else {
      const state = loadState(ctx, capsule);
      if (state.values === undefined && capsule.state !== undefined) {
        state.values = restoreState(capsule, savedValues(ctx, capsule.id)); // a task list: start from the app's
      }
      saveState(ctx, applyWidgetMessage(capsule, state, msg, Date.now()));
    }
  }
  // Every widget showing this capsule redraws, not just the one tapped.
  await refreshCapsuleWidgets(ctx, binding.capsuleId);
}

/** Opens the system page where the user can add the Harmoniser widget to the home screen (API 18+). */
export function openHarmoniserManager(bundleName: string): boolean {
  const want: Want = {
    bundleName: bundleName,
    abilityName: FORM_ABILITY,
    parameters: {
      'ohos.extra.param.key.form_dimension': 2,
      'ohos.extra.param.key.form_name': FORM_NAME,
      'ohos.extra.param.key.module_name': 'entry'
    }
  };
  try {
    formProvider.openFormManager(want);
    return true;
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'openFormManager failed: %{public}d %{public}s', err.code, err.message);
    return false;
  }
}
