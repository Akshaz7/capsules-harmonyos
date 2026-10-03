import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule, StateValues } from '../core';

const DOMAIN = 0x0001;
const TAG = 'CapsuleStore';
const STORE = 'capsules';
const LIST_KEY = 'saved';
const LEGACY_ACTIVE_KEY = 'active';

/** Saved (approved) capsules, newest first. Survives restarts; Undo removes one. */
export class CapsuleStore {
  private prefs: preferences.Preferences;

  constructor(ctx: common.Context) {
    const options: preferences.Options = { name: STORE };
    this.prefs = preferences.getPreferencesSync(ctx, options);
  }

  all(): Capsule[] {
    try {
      const raw = this.prefs.getSync(LIST_KEY, '') as string;
      if (raw.length > 0) {
        return JSON.parse(raw) as Capsule[];
      }
      // One-time migration from the single-capsule store.
      const legacy = this.prefs.getSync(LEGACY_ACTIVE_KEY, '') as string;
      return legacy.length > 0 ? [JSON.parse(legacy) as Capsule] : [];
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load failed: %{public}s', (e as BusinessError).message);
      return [];
    }
  }

  /** Adds or replaces the capsule with the same id, then puts it first. */
  add(capsule: Capsule): Capsule[] {
    const next = [capsule].concat(this.all().filter((c: Capsule) => c.id !== capsule.id));
    this.write(next);
    return next;
  }

  /** How the capsule was made ('rules', 'on-device', 'cloud-eu:mistral', 'imported', ...); '' if unknown. */
  origin(capsuleId: string): string {
    try {
      return this.prefs.getSync(`origin:${capsuleId}`, '') as string;
    } catch (e) {
      return '';
    }
  }

  /** The request text the capsule was made from; '' if unknown (imported or saved before this was kept). */
  request(capsuleId: string): string {
    try {
      return this.prefs.getSync(`request:${capsuleId}`, '') as string;
    } catch (e) {
      return '';
    }
  }

  setRequest(capsuleId: string, request: string): void {
    try {
      this.prefs.putSync(`request:${capsuleId}`, request);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setRequest failed: %{public}s', (e as BusinessError).message);
    }
  }

  /** Whether the "Add to home screen" how-to was already shown for this capsule. */
  hintSeen(capsuleId: string): boolean {
    try {
      return this.prefs.getSync(`hintSeen:${capsuleId}`, false) as boolean;
    } catch (e) {
      return false;
    }
  }

  setHintSeen(capsuleId: string): void {
    try {
      this.prefs.putSync(`hintSeen:${capsuleId}`, true);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setHintSeen failed: %{public}s', (e as BusinessError).message);
    }
  }

  setOrigin(capsuleId: string, origin: string): void {
    try {
      this.prefs.putSync(`origin:${capsuleId}`, origin);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setOrigin failed: %{public}s', (e as BusinessError).message);
    }
  }

  /** Saved schema v1 state values for a capsule, as plain JSON; {} if none. */
  values(capsuleId: string): StateValues {
    try {
      const raw = this.prefs.getSync(`values:${capsuleId}`, '') as string;
      return raw.length > 0 ? JSON.parse(raw) as StateValues : {};
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load values failed: %{public}s', (e as BusinessError).message);
      return {};
    }
  }

  setValues(capsuleId: string, values: StateValues): void {
    try {
      this.prefs.putSync(`values:${capsuleId}`, JSON.stringify(values));
      this.prefs.flush().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'flush failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save values failed: %{public}s', (e as BusinessError).message);
    }
  }

  remove(capsuleId: string): Capsule[] {
    try {
      this.prefs.deleteSync(`origin:${capsuleId}`);
      this.prefs.deleteSync(`values:${capsuleId}`);
      this.prefs.deleteSync(`request:${capsuleId}`);
      this.prefs.deleteSync(`hintSeen:${capsuleId}`);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'delete origin failed: %{public}s', (e as BusinessError).message);
    }
    const next = this.all().filter((c: Capsule) => c.id !== capsuleId);
    this.write(next);
    return next;
  }

  private write(list: Capsule[]): void {
    try {
      this.prefs.putSync(LIST_KEY, JSON.stringify(list));
      this.prefs.deleteSync(LEGACY_ACTIVE_KEY);
      this.prefs.flush().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'flush failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'write failed: %{public}s', (e as BusinessError).message);
    }
  }
}
