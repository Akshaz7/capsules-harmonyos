import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { calendarManager } from '@kit.CalendarKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DailyReminder, nextOccurrence, planReminderSync, reminderPrefix } from '../core/Reminders';

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
  /** In-flight schedule() calls by event identifier, so a quick pause/stop waits for the event to exist. */
  private scheduling: Map<string, Promise<number>> = new Map();

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  /** Asks for calendar access (once) and opens or creates the app's own calendar. */
  prepare(): Promise<boolean> {
    if (this.calendar) {
      return Promise.resolve(true);
    }
    // Several capsules may ask at start-up: share one request so the user sees one permission prompt.
    if (this.preparing === undefined) {
      this.preparing = this.openCalendar().finally(() => {
        this.preparing = undefined;
      });
    }
    return this.preparing;
  }

  private preparing: Promise<boolean> | undefined = undefined;

  private async openCalendar(): Promise<boolean> {
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
  schedule(capsuleId: string, timerId: string, label: string, seconds: number): Promise<number> {
    const key = `${ID_PREFIX}${capsuleId}:${timerId}`;
    const p = this.addTimerEvent(capsuleId, timerId, label, seconds);
    this.scheduling.set(key, p);
    p.finally(() => {
      if (this.scheduling.get(key) === p) {
        this.scheduling.delete(key);
      }
    });
    return p;
  }

  private async addTimerEvent(capsuleId: string, timerId: string, label: string, seconds: number): Promise<number> {
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

  /** Deletes the upcoming reminder of one timer (paused, stopped or reset). Returns how many events. */
  async cancelTimer(capsuleId: string, timerId: string): Promise<number> {
    const key = `${ID_PREFIX}${capsuleId}:${timerId}`;
    await this.scheduling.get(key)?.catch(() => -1);
    if (!(await this.prepare()) || !this.calendar) {
      return 0;
    }
    try {
      const now = Date.now();
      const events = await this.calendar.getEvents();
      const ids: number[] = [];
      events.forEach((ev: calendarManager.Event) => {
        if (ev.id !== undefined && ev.identifier === key && ev.startTime >= now) {
          ids.push(ev.id);
        }
      });
      if (ids.length > 0) {
        await this.calendar.deleteEvents(ids);
      }
      hilog.info(DOMAIN, TAG, 'cancelled %{public}d events for %{public}s/%{public}s', ids.length, capsuleId, timerId);
      return ids.length;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'cancelTimer failed: %{public}d %{public}s', err.code, err.message);
      return 0;
    }
  }

  /**
   * Makes the calendar hold exactly `wanted` for this capsule (T4-27): one recurring DAILY event per reminder,
   * whose reminder rings at the time even while the app is closed. Adds missing ones, deletes stale ones and
   * duplicates; calling it again changes nothing. Returns false if the calendar is not available.
   */
  async syncDailyReminders(capsuleId: string, wanted: DailyReminder[]): Promise<boolean> {
    if (wanted.length === 0 && !this.calendar) {
      return false; // nothing to add: do not ask for calendar access just to look for stale reminders
    }
    if (!(await this.prepare()) || !this.calendar) {
      return false;
    }
    try {
      const prefix = reminderPrefix(capsuleId);
      const events = (await this.calendar.getEvents()).filter((ev: calendarManager.Event) =>
        ev.id !== undefined && ev.identifier !== undefined && ev.identifier.startsWith(prefix));
      const plan = planReminderSync(events.map((ev: calendarManager.Event) => ev.identifier as string), wanted);
      // Stale reminders and extra copies of a kept one, by event id.
      const ids: number[] = plan.removeAt.map((i: number) => events[i].id as number);
      if (ids.length > 0) {
        await this.calendar.deleteEvents(ids);
      }
      for (const r of plan.add) {
        const start = nextOccurrence(r.at, Date.now());
        const rule: calendarManager.RecurrenceRule = { recurrenceFrequency: calendarManager.RecurrenceFrequency.DAILY };
        const event: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: r.title,
          description: r.text,
          startTime: start,
          endTime: start + EVENT_LENGTH_MS,
          reminderTime: [0],
          recurrenceRule: rule,
          identifier: r.key
        };
        await this.calendar.addEvent(event);
      }
      hilog.info(DOMAIN, TAG, 'daily reminders for %{public}s: +%{public}d -%{public}d', capsuleId, plan.add.length,
        ids.length);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'syncDailyReminders failed: %{public}d %{public}s', err.code, err.message);
      return false;
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
