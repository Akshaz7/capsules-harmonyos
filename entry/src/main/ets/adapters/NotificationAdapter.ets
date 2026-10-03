import { common } from '@kit.AbilityKit';
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

  async publish(title: string, text: string): Promise<boolean> {
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
