import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'AppSettings';
const STORE = 'settings';
const AI_MODE_KEY = 'aiMode';
const ALLOW_NON_EU_KEY = 'allowNonEuProviders';
const CLOUD_NOTICE_KEY = 'cloudNoticeAccepted';

/** 'smart': rules and on-device first, Mistral (EU) when they can't. 'on-device': never the cloud. */
export type AiMode = 'smart' | 'on-device';

/** User settings, saved locally in Preferences. */
@ObservedV2
export class AppSettings {
  @Trace aiMode: AiMode = 'smart';
  /** Advanced: allow cloud providers outside the EU. Off by default. */
  @Trace allowNonEu: boolean = false;
  /** The user saw the one-time cloud notice and chose OK. */
  @Trace cloudNoticeAccepted: boolean = false;
  private prefs: preferences.Preferences | undefined = undefined;

  load(ctx: common.Context): void {
    try {
      const options: preferences.Options = { name: STORE };
      this.prefs = preferences.getPreferencesSync(ctx, options);
      this.aiMode = (this.prefs.getSync(AI_MODE_KEY, 'smart') as string) === 'on-device' ? 'on-device' : 'smart';
      this.allowNonEu = this.prefs.getSync(ALLOW_NON_EU_KEY, false) as boolean;
      this.cloudNoticeAccepted = this.prefs.getSync(CLOUD_NOTICE_KEY, false) as boolean;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load failed: %{public}s', (e as BusinessError).message);
    }
  }

  setAiMode(mode: AiMode): void {
    this.aiMode = mode;
    this.save(AI_MODE_KEY, mode);
  }

  setAllowNonEu(value: boolean): void {
    this.allowNonEu = value;
    this.save(ALLOW_NON_EU_KEY, value);
  }

  acceptCloudNotice(): void {
    this.cloudNoticeAccepted = true;
    this.save(CLOUD_NOTICE_KEY, true);
  }

  private save(key: string, value: preferences.ValueType): void {
    try {
      this.prefs?.putSync(key, value);
      this.prefs?.flush().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'flush failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save failed: %{public}s', (e as BusinessError).message);
    }
  }
}
