import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PairedDevice } from './DeviceRelay';

const DOMAIN = 0x0001;
const TAG = 'DeviceStore';
const STORE = 'devices';
const LIST_KEY = 'paired';

/** Devices this install has paired (id and kind only), kept in the app's Preferences, never in git. */
export class DeviceStore {
  private prefs: preferences.Preferences | undefined = undefined;

  constructor(ctx: common.Context) {
    try {
      this.prefs = preferences.getPreferencesSync(ctx, { name: STORE } as preferences.Options);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'open failed: %{public}s', (e as BusinessError).message);
    }
  }

  all(): PairedDevice[] {
    try {
      const raw = (this.prefs?.getSync(LIST_KEY, '') ?? '') as string;
      return raw.length > 0 ? JSON.parse(raw) as PairedDevice[] : [];
    } catch (e) {
      return [];
    }
  }

  add(device: PairedDevice): PairedDevice[] {
    const next = this.all().filter((d: PairedDevice) => d.id !== device.id).concat([device]);
    this.write(next);
    return next;
  }

  remove(id: string): PairedDevice[] {
    const next = this.all().filter((d: PairedDevice) => d.id !== id);
    this.write(next);
    return next;
  }

  private write(list: PairedDevice[]): void {
    try {
      this.prefs?.putSync(LIST_KEY, JSON.stringify(list));
      this.prefs?.flush().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'flush failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save failed: %{public}s', (e as BusinessError).message);
    }
  }
}

/** "Wrist", "Browser" or "Device" for a paired device's kind. */
export function deviceName(d: PairedDevice): string {
  return d.kind === 'wrist' ? 'Wrist' : d.kind === 'web' ? 'Browser' : 'Device';
}
