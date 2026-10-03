import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule } from '../core';

const DOMAIN = 0x0001;
const TAG = 'CapsuleStore';
const STORE = 'capsules';
const ACTIVE_KEY = 'active';

/** Keeps the one active capsule so it survives an app restart. Undo deletes it. */
export class CapsuleStore {
  private prefs: preferences.Preferences;

  constructor(ctx: common.Context) {
    const options: preferences.Options = { name: STORE };
    this.prefs = preferences.getPreferencesSync(ctx, options);
  }

  load(): Capsule | undefined {
    try {
      const raw = this.prefs.getSync(ACTIVE_KEY, '') as string;
      return raw.length > 0 ? JSON.parse(raw) as Capsule : undefined;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load failed: %{public}s', (e as BusinessError).message);
      return undefined;
    }
  }

  save(capsule: Capsule): void {
    this.write(() => this.prefs.putSync(ACTIVE_KEY, JSON.stringify(capsule)));
  }

  remove(): void {
    this.write(() => this.prefs.deleteSync(ACTIVE_KEY));
  }

  private write(op: () => void): void {
    try {
      op();
      this.prefs.flush().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'flush failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'write failed: %{public}s', (e as BusinessError).message);
    }
  }
}
