import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'AppSettings';
const STORE = 'settings';
const ALLOW_CLOUD_KEY = 'allowCloudFallback';

/** User settings, saved locally in Preferences. */
@ObservedV2
export class AppSettings {
  /** Off by default: requests stay on the device unless the user opts in. */
  @Trace allowCloud: boolean = false;
  private prefs: preferences.Preferences | undefined = undefined;

  load(ctx: common.Context): void {
    try {
      const options: preferences.Options = { name: STORE };
      this.prefs = preferences.getPreferencesSync(ctx, options);
      this.allowCloud = this.prefs.getSync(ALLOW_CLOUD_KEY, false) as boolean;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load failed: %{public}s', (e as BusinessError).message);
    }
  }

  setAllowCloud(value: boolean): void {
    this.allowCloud = value;
    try {
      this.prefs?.putSync(ALLOW_CLOUD_KEY, value);
      this.prefs?.flush().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'flush failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save failed: %{public}s', (e as BusinessError).message);
    }
  }
}
