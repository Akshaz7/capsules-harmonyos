import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MotionScope } from '../capabilities/MotionConsumers';

const DOMAIN = 0x0001;
const TAG = 'AppSettings';
const STORE = 'settings';
const AI_MODE_KEY = 'aiMode';
const ALLOW_NON_EU_KEY = 'allowNonEuProviders';
const LEGACY_CLOUD_NOTICE_KEY = 'cloudNoticeAccepted'; // boolean; only the Mistral notice existed then
const CLOUD_CONSENT_KEY = 'cloudConsentProvider';
const MOTION_SCOPE_KEY = 'motionScope';

/** 'smart': rules and on-device first, Mistral (EU) when they can't. 'on-device': never the cloud. */
export type AiMode = 'smart' | 'on-device';

/** User settings, saved locally in Preferences. */
@ObservedV2
export class AppSettings {
  @Trace aiMode: AiMode = 'smart';
  /** Allow cloud providers outside the EU (Claude for live capsules, T4-23). On by default. */
  @Trace allowNonEu: boolean = true;
  /** The cloud provider ('mistral', 'anthropic', ...) whose notice the user accepted; '' if none. */
  @Trace cloudConsentProvider: string = '';
  /** 'capsule': the sensor listens only while that capsule's page is open. 'app': any capsule in front. */
  @Trace motionScope: MotionScope = 'capsule';
  private prefs: preferences.Preferences | undefined = undefined;

  load(ctx: common.Context): void {
    try {
      const options: preferences.Options = { name: STORE };
      this.prefs = preferences.getPreferencesSync(ctx, options);
      this.aiMode = (this.prefs.getSync(AI_MODE_KEY, 'smart') as string) === 'on-device' ? 'on-device' : 'smart';
      this.allowNonEu = this.prefs.getSync(ALLOW_NON_EU_KEY, true) as boolean;
      this.cloudConsentProvider = this.prefs.getSync(CLOUD_CONSENT_KEY, '') as string;
      this.motionScope = (this.prefs.getSync(MOTION_SCOPE_KEY, 'capsule') as string) === 'app' ? 'app' : 'capsule';
      if (this.cloudConsentProvider.length === 0 && (this.prefs.getSync(LEGACY_CLOUD_NOTICE_KEY, false) as boolean)) {
        this.cloudConsentProvider = 'mistral';
      }
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

  setMotionScope(scope: MotionScope): void {
    this.motionScope = scope;
    this.save(MOTION_SCOPE_KEY, scope);
  }

  /** Consent is per provider: accepting Mistral (EU) does not cover a non-EU provider. */
  hasCloudConsent(provider: string): boolean {
    return provider.length > 0 && this.cloudConsentProvider === provider;
  }

  acceptCloudNotice(provider: string): void {
    this.cloudConsentProvider = provider;
    this.save(CLOUD_CONSENT_KEY, provider);
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
