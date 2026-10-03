/**
 * Preferences storage for the Harmoniser widget. The FormExtensionAbility runs in its own
 * process and preferences are cached per process, so every read drops the cache first.
 *
 * Reads (never writes) the app's stores:
 *   "capsules"   key "saved" (newest-first Capsule[]) or legacy key "active" (one Capsule)
 *   "gatekeeper" through the Gatekeeper class
 * Owns:
 *   "harmoniser_widgets" key "form:<formId>" -> FormBinding JSON, key "seen" -> capsule ids already seen
 *   "capsule_state"      key "state:<capsuleId>" -> CapsuleState JSON
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule } from '../core/CapsuleTypes';
import { validateCapsuleObject } from '../core/CapsuleValidator';
import { CapsuleState, initialState, parseState, WidgetBindingFact } from '../core/WidgetModel';

const DOMAIN = 0x0002;
const TAG = 'WidgetStore';
const APP_CAPSULES = 'capsules';
const APP_SAVED_KEY = 'saved';
const APP_LEGACY_KEY = 'active';
const WIDGETS = 'harmoniser_widgets';
const STATE = 'capsule_state';
const FORM_PREFIX = 'form:';

/** formId -> capsule ('' = blank) and size; the same shape the core assignment logic uses. */
export type FormBinding = WidgetBindingFact;

function fresh(ctx: common.Context, name: string): preferences.Preferences {
  const options: preferences.Options = { name: name };
  preferences.removePreferencesFromCacheSync(ctx, options);
  return preferences.getPreferencesSync(ctx, options);
}

function errorText(e: Object): string {
  return (e as BusinessError).message ?? String(e);
}

/** Saved capsules from the app, newest first. Each one is re-validated before use. */
export function savedCapsules(ctx: common.Context): Capsule[] {
  try {
    const prefs = fresh(ctx, APP_CAPSULES);
    let raw = prefs.getSync(APP_SAVED_KEY, '') as string;
    if (raw.length === 0) {
      const legacy = prefs.getSync(APP_LEGACY_KEY, '') as string;
      raw = legacy.length > 0 ? `[${legacy}]` : '[]';
    }
    const list = JSON.parse(raw) as Object[];
    const out: Capsule[] = [];
    list.forEach((item: Object) => {
      const v = validateCapsuleObject(item);
      if (v.ok && v.capsule !== undefined) {
        out.push(v.capsule);
      }
    });
    return out;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'savedCapsules failed: %{public}s', errorText(e));
    return [];
  }
}

export function getBinding(ctx: common.Context, formId: string): FormBinding | null {
  try {
    const raw = fresh(ctx, WIDGETS).getSync(FORM_PREFIX + formId, '') as string;
    return raw.length > 0 ? JSON.parse(raw) as FormBinding : null;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'getBinding failed: %{public}s', errorText(e));
    return null;
  }
}

export function allBindings(ctx: common.Context): FormBinding[] {
  const out: FormBinding[] = [];
  try {
    const all = fresh(ctx, WIDGETS).getAllSync() as Record<string, Object>;
    Object.keys(all).forEach((key: string) => {
      if (key.startsWith(FORM_PREFIX)) {
        out.push(JSON.parse(all[key] as string) as FormBinding);
      }
    });
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'allBindings failed: %{public}s', errorText(e));
  }
  return out;
}

const SEEN_KEY = 'seen';

/** Capsule ids the widgets have already seen, or null before the first sync. */
export function loadSeen(ctx: common.Context): string[] | null {
  try {
    const raw = fresh(ctx, WIDGETS).getSync(SEEN_KEY, '') as string;
    return raw.length > 0 ? JSON.parse(raw) as string[] : null;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'loadSeen failed: %{public}s', errorText(e));
    return null;
  }
}

export function saveSeen(ctx: common.Context, seen: string[]): void {
  try {
    const prefs = fresh(ctx, WIDGETS);
    prefs.putSync(SEEN_KEY, JSON.stringify(seen));
    prefs.flushSync();
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'saveSeen failed: %{public}s', errorText(e));
  }
}

export function putBinding(ctx: common.Context, binding: FormBinding): void {
  try {
    const prefs = fresh(ctx, WIDGETS);
    prefs.putSync(FORM_PREFIX + binding.formId, JSON.stringify(binding));
    prefs.flushSync();
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'putBinding failed: %{public}s', errorText(e));
  }
}

export function removeBinding(ctx: common.Context, formId: string): void {
  try {
    const prefs = fresh(ctx, WIDGETS);
    prefs.deleteSync(FORM_PREFIX + formId);
    prefs.flushSync();
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'removeBinding failed: %{public}s', errorText(e));
  }
}

export function loadState(ctx: common.Context, capsule: Capsule): CapsuleState {
  try {
    const raw = fresh(ctx, STATE).getSync(`state:${capsule.id}`, '') as string;
    return raw.length > 0 ? parseState(capsule, raw) : initialState(capsule);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'loadState failed: %{public}s', errorText(e));
    return initialState(capsule);
  }
}

export function saveState(ctx: common.Context, state: CapsuleState): void {
  try {
    const prefs = fresh(ctx, STATE);
    prefs.putSync(`state:${state.capsuleId}`, JSON.stringify(state));
    prefs.flushSync();
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'saveState failed: %{public}s', errorText(e));
  }
}
