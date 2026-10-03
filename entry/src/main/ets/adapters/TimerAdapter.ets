import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { calendarManager } from '@kit.CalendarKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'TimerAdapter';
const PERMISSIONS: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
const ID_PREFIX = 'capsules:';
// Length of the calendar event that carries a timer. Only its start time matters.
const EVENT_LENGTH_MS = 60 * 1000;

/**
 * Schedules capsule timers as system calendar events whose reminder fires at the event
 * start, so they ring even after the app is closed.
 *
 * Calendar Kit replaces reminderAgentManager here: on phones, agent reminders need an
 * AppGallery Connect capability grant, and without it publishReminder fails with
 * 1700002 (limit 0). Each event's identifier is "capsules:<capsuleId>:<timerId>", so
 * cancelForCapsule() can find the events again after a restart.
 */
export class TimerAdapter {
  private ctx: common.UIAbilityContext;
  private calendar: calendarManager.Calendar | undefined = undefined;
  private account: calendarManager.CalendarAccount = {
    name: 'Harmoniser',
    type: calendarManager.CalendarType.LOCAL,
    displayName: 'Harmoniser'
  };

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  /** Asks for calendar access (once) and opens or creates the app's own calendar. */
  async prepare(): Promise<boolean> {
    if (this.calendar) {
      return true;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(this.ctx, PERMISSIONS);
      if (result.authResults.some((r: number) => r !== 0)) {
        hilog.warn(DOMAIN, TAG, 'calendar permission denied');
        return false;
      }
      const mgr = calendarManager.getCalendarManager(this.ctx);
      try {
        this.calendar = await mgr.getCalendar(this.account);
      } catch (e) {
        this.calendar = await mgr.createCalendar(this.account);
      }
      const config: calendarManager.CalendarConfig = { enableReminder: true };
      await this.calendar.setConfig(config);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'prepare failed: %{public}d %{public}s', err.code, err.message);
      this.calendar = undefined;
      return false;
    }
  }

  /** Adds an event that reminds at now + seconds. Returns the event id, or -1 on failure. */
  async schedule(capsuleId: string, timerId: string, label: string, seconds: number): Promise<number> {
    if (!(await this.prepare()) || !this.calendar) {
      hilog.error(DOMAIN, TAG, 'timer %{public}s not scheduled', timerId);
      return -1;
    }
    const start = Date.now() + Math.max(1, Math.round(seconds)) * 1000;
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: `${label} is done`,
      startTime: start,
      endTime: start + EVENT_LENGTH_MS,
      reminderTime: [0],
      identifier: `${ID_PREFIX}${capsuleId}:${timerId}`
    };
    try {
      const eventId = await this.calendar.addEvent(event);
      hilog.info(DOMAIN, TAG, 'scheduled event %{public}d for %{public}s/%{public}s in %{public}ds',
        eventId, capsuleId, timerId, Math.round(seconds));
      return eventId;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'addEvent failed: %{public}d %{public}s', err.code, err.message);
      return -1;
    }
  }

  /** Deletes every event this app scheduled for the given capsule. Returns how many. */
  async cancelForCapsule(capsuleId: string): Promise<number> {
    if (!(await this.prepare()) || !this.calendar) {
      return 0;
    }
    try {
      const prefix = `${ID_PREFIX}${capsuleId}:`;
      const events = await this.calendar.getEvents();
      const ids: number[] = [];
      events.forEach((ev: calendarManager.Event) => {
        if (ev.id !== undefined && ev.identifier !== undefined && ev.identifier.startsWith(prefix)) {
          ids.push(ev.id);
        }
      });
      if (ids.length > 0) {
        await this.calendar.deleteEvents(ids);
      }
      hilog.info(DOMAIN, TAG, 'cancelled %{public}d events for %{public}s', ids.length, capsuleId);
      return ids.length;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'cancelForCapsule failed: %{public}d %{public}s', err.code, err.message);
      return 0;
    }
  }
}
