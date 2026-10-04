import { common, Want, wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'NotificationAdapter';

/** Publishes app notifications (notificationManager). Works while the app process is alive. */
export class NotificationAdapter {
  private ctx: common.UIAbilityContext;
  private nextId: number = 1;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async ensureEnabled(): Promise<boolean> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return true;
      }
      await notificationManager.requestEnableNotification(this.ctx);
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'enable notifications failed: %{public}d %{public}s', err.code, err.message);
      return false;
    }
  }

  /** What a tap on the notification does: reopen the app on this capsule (T4-27). */
  private async openCapsuleAgent(capsuleId: string): Promise<WantAgent | undefined> {
    const want: Want = {
      bundleName: this.ctx.abilityInfo.bundleName,
      abilityName: 'EntryAbility',
      parameters: { source: 'harmoniser', action: 'openCapsule', capsuleId: capsuleId }
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    try {
      return await wantAgent.getWantAgent(info);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'no tap action: %{public}d %{public}s', err.code, err.message);
      return undefined;
    }
  }

  /** `capsuleId`: tapping the notification opens that capsule. */
  async publish(title: string, text: string, capsuleId?: string): Promise<boolean> {
    if (!(await this.ensureEnabled())) {
      return false;
    }
    const request: notificationManager.NotificationRequest = {
      id: this.nextId++,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: text }
      }
    };
    if (capsuleId !== undefined && capsuleId.length > 0) {
      request.wantAgent = await this.openCapsuleAgent(capsuleId);
    }
    try {
      await notificationManager.publish(request);
      hilog.info(DOMAIN, TAG, 'published "%{public}s"', title);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'publish failed: %{public}d %{public}s', err.code, err.message);
      return false;
    }
  }
}
