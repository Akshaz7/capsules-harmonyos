/**
 * Daily reminders (T4-27): a capsule's daily "time" triggers that notify are mirrored as recurring calendar
 * events, so they ring while the app is closed. Pure: the calendar adapter and the app call these.
 */
import { ButtonStep, Capsule, Trigger } from './CapsuleTypes';

/** One recurring reminder. `key` names it in the calendar; it changes when the time or the text changes. */
export interface DailyReminder {
  key: string;
  /** "HH:MM", local time. */
  at: string;
  title: string;
  text: string;
}

/** Calendar identifiers of a capsule's reminders start with this (timers use "capsules:<id>:<timerId>"). */
export function reminderPrefix(capsuleId: string): string {
  return `capsules:${capsuleId}:daily:`;
}

function notifyText(steps: ButtonStep[]): string {
  const step = steps.find((s: ButtonStep) => typeof s === 'string' && (s as string).startsWith('notify:'));
  return step === undefined ? '' : (step as string).substring('notify:'.length).trim();
}

/** A short stable hash, so an edited text gets a new key (and the old event is replaced). */
function hash(text: string): string {
  let h = 5381;
  for (let i = 0; i < text.length; i++) {
    h = ((h * 33) ^ text.charCodeAt(i)) >>> 0;
  }
  return h.toString(36);
}

/**
 * The reminders a capsule needs: one per daily time trigger with a notify step, in trigger order, without
 * repeats (the same time and text twice is one reminder). Other triggers run only in the app.
 */
export function dailyReminders(capsule: Capsule): DailyReminder[] {
  const out: DailyReminder[] = [];
  (capsule.triggers ?? []).forEach((t: Trigger) => {
    const text = notifyText(t.do);
    if (t.on !== 'time' || t.at === undefined || text.length === 0) {
      return;
    }
    const key = `${reminderPrefix(capsule.id)}${t.at}:${hash(text)}`;
    if (!out.some((r: DailyReminder) => r.key === key)) {
      out.push({ key: key, at: t.at, title: text, text: capsule.name });
    }
  });
  return out;
}

/** The next local time `at` ("HH:MM") strictly after `now` (today or tomorrow), in epoch ms. */
export function nextOccurrence(at: string, now: number): number {
  const parts = at.split(':');
  const d = new Date(now);
  d.setHours(Number(parts[0]), Number(parts[1]), 0, 0);
  if (d.getTime() <= now) {
    d.setDate(d.getDate() + 1);
  }
  return d.getTime();
}

export class ReminderSync {
  /** Reminders to add (not in the calendar yet). */
  add: DailyReminder[] = [];
  /** Calendar identifiers to delete: no longer wanted, or a duplicate of one kept. */
  remove: string[] = [];
  /** Positions in `existing` of the events to delete (same order as `remove`). */
  removeAt: number[] = [];
}

/**
 * What to change so the calendar holds exactly `wanted` for this capsule: `existing` are the identifiers of
 * the capsule's reminder events found in the calendar (duplicates allowed). Never adds one that exists.
 */
export function planReminderSync(existing: string[], wanted: DailyReminder[]): ReminderSync {
  const plan = new ReminderSync();
  const kept: string[] = [];
  existing.forEach((id: string, i: number) => {
    if (wanted.some((r: DailyReminder) => r.key === id) && !kept.includes(id)) {
      kept.push(id);
    } else {
      plan.remove.push(id);
      plan.removeAt.push(i);
    }
  });
  plan.add = wanted.filter((r: DailyReminder) => !kept.includes(r.key));
  return plan;
}

/**
 * Whether the app itself shows a notify from a trigger: not for a daily time trigger whose reminder the
 * calendar rings (it would ring twice, or late after the app was closed). Buttons always notify in the app.
 */
export function notifiesInApp(trigger: Trigger | undefined, action: string, calendarReminders: boolean): boolean {
  if (!action.startsWith('notify:')) {
    return true;
  }
  return !(calendarReminders && trigger !== undefined && trigger.on === 'time');
}

/** A notification for notify:<text>: the capsule's name as the title, the text as the body. */
export interface NotificationContent {
  title: string;
  text: string;
}

const MAX_TITLE: number = 60;
const MAX_BODY: number = 200;

export function notificationContent(capsuleName: string, text: string): NotificationContent {
  const title = capsuleName.trim().length > 0 ? capsuleName.trim() : 'Harmoniser';
  const body = text.trim().length > 0 ? text.trim() : 'Reminder';
  return {
    title: title.length > MAX_TITLE ? `${title.substring(0, MAX_TITLE - 1)}…` : title,
    text: body.length > MAX_BODY ? `${body.substring(0, MAX_BODY - 1)}…` : body
  };
}

/** Launch parameters that open one capsule (a notification or widget tap): see pages/WidgetLaunch. */
export const OPEN_CAPSULE_ACTION: string = 'openCapsule';
