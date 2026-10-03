/**
 * Builds and pushes Harmoniser widget content. Used by the FormExtensionAbility, and by the
 * app (refreshCapsuleWidgets) whenever capsule state or the saved capsules change.
 */
import { common, Want } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule, Permission } from '../core/CapsuleTypes';
import {
  applyWidgetMessage, buildWidgetView, declaredAction, emptyView, GateFacts, parseWidgetMessage,
  pickCapsuleForNewWidget, SavedCapsule, WidgetView
} from '../core/WidgetModel';
import { Gatekeeper } from '../gatekeeper/Gatekeeper';
import { FormBinding, allBindings, getBinding, loadState, putBinding, saveState, savedCapsules } from './WidgetStore';

const DOMAIN = 0x0002;
const TAG = 'Harmoniser';
const GATE_STORE = 'gatekeeper';
export const FORM_NAME = 'harmoniser';
export const FORM_ABILITY = 'HarmoniserFormAbility';

/** A Gatekeeper reading the latest grants written by the app process. */
function freshGate(ctx: common.Context): Gatekeeper {
  try {
    const options: preferences.Options = { name: GATE_STORE };
    preferences.removePreferencesFromCacheSync(ctx, options);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'could not drop gatekeeper cache: %{public}s', (e as BusinessError).message);
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
  return buildWidgetView(capsule, loadState(ctx, capsule), gateFacts(gate, capsule, false), Date.now(), binding.wide);
}

export function bindingData(view: WidgetView): formBindingData.FormBindingData {
  const data: Record<string, string> = { 'view': JSON.stringify(view) };
  return formBindingData.createFormBindingData(data);
}

/**
 * The binding for a widget the launcher (re)adds. The launcher calls onAddForm again with the
 * same formId after an app update, so an existing binding is kept and only its size is updated.
 */
export function bindForm(ctx: common.Context, formId: string, wide: boolean): FormBinding {
  const existing = getBinding(ctx, formId);
  if (existing === null || existing.capsuleId.length === 0) {
    return bindNewForm(ctx, formId, wide);
  }
  if (existing.wide !== wide) {
    existing.wide = wide;
    putBinding(ctx, existing);
  }
  hilog.info(DOMAIN, TAG, 'form %{public}s keeps capsule %{public}s', formId, existing.capsuleId);
  return existing;
}

/** Binds a new widget to the most recent widget-suitable capsule (or none yet). */
export function bindNewForm(ctx: common.Context, formId: string, wide: boolean): FormBinding {
  const capsules = savedCapsules(ctx);
  const gate = freshGate(ctx);
  // Newest first, so a higher savedAt means more recent.
  const saved: SavedCapsule[] = capsules.map((c: Capsule, i: number): SavedCapsule => {
    const s: SavedCapsule = { capsule: c, savedAt: capsules.length - i };
    return s;
  });
  const chosen = pickCapsuleForNewWidget(saved, (id: string) => gate.isRemoved(id));
  const binding: FormBinding = { formId: formId, capsuleId: chosen === null ? '' : chosen.id, wide: wide };
  putBinding(ctx, binding);
  hilog.info(DOMAIN, TAG, 'form %{public}s -> capsule %{public}s', formId, binding.capsuleId);
  return binding;
}

export async function pushForm(ctx: common.Context, binding: FormBinding): Promise<void> {
  try {
    await formProvider.updateForm(binding.formId, bindingData(viewFor(ctx, binding)));
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}d %{public}s', binding.formId, err.code,
      err.message);
  }
}

/**
 * Refreshes every Harmoniser widget (or only those showing `capsuleId`). An empty widget picks
 * up the most recent widget-suitable capsule. Call after capsule state or the saved list changes.
 */
export async function refreshCapsuleWidgets(ctx: common.Context, capsuleId?: string): Promise<void> {
  for (const b of allBindings(ctx)) {
    if (capsuleId !== undefined && b.capsuleId !== capsuleId) {
      continue;
    }
    const binding = b.capsuleId.length === 0 ? bindNewForm(ctx, b.formId, b.wide) : b;
    await pushForm(ctx, binding);
  }
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
    } else if (action.length > 0 && !gate.allowAction(capsule, action)) {
      // Blocked and logged by the gatekeeper.
    } else {
      saveState(ctx, applyWidgetMessage(capsule, loadState(ctx, capsule), msg, Date.now()));
    }
  }
  // Every widget showing this capsule redraws, not just the one tapped.
  await refreshCapsuleWidgets(ctx, binding.capsuleId);
}

/** Opens the system page where the user can add the Harmoniser widget to the home screen (API 18+). */
export function openHarmoniserManager(bundleName: string): void {
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
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'openFormManager failed: %{public}d %{public}s', err.code, err.message);
  }
}
