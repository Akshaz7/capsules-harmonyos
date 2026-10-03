/**
 * Schema v1.1 triggers at runtime. Pure: the caller supplies the clock, motion events, the gatekeeper
 * (TriggerGuard) and storage for when each trigger last fired.
 *
 *   const due = dueTimeTriggers(capsule, lastRun, Date.now());     // daily "time" triggers that are due
 *   due.indices.forEach(i => { const r = runTrigger(capsule, state, i, guard); ... });
 *   save(due.lastRun);
 *   motionTriggers(capsule).forEach(i => runTrigger(capsule, state, i, guard));   // on a motion-start event
 *
 * runTrigger runs the steps all-or-nothing (like a button press) and returns the new v1 state plus the v0
 * actions to dispatch. The trigger's own permission and every v0 action must pass the guard first, or
 * nothing changes. A removed capsule never fires.
 */
import { ButtonComponent, Capsule, Permission, Trigger } from './CapsuleTypes';
import { applyActions, StateValues } from './CapsuleProgram';

/** The gatekeeper as triggers need it. Both methods log what they block. */
export interface TriggerGuard {
  /** Is the trigger's permission ("reminders" for time, "motion" for motion) declared and granted? */
  allowTrigger(capsule: Capsule, trigger: Trigger, permission: Permission): boolean;
  /** May this v0 action run (as the gatekeeper's allowAction)? */
  allowAction(capsule: Capsule, action: string): boolean;
}

export function permissionForTrigger(t: Trigger): Permission {
  return t.on === 'time' ? 'reminders' : 'motion';
}

/** Storage key for one trigger's last firing. */
export function triggerKey(capsuleId: string, index: number): string {
  return `${capsuleId}#${index}`;
}

function parseAt(at: string): number[] | null {
  const m = at.match(/^([01]\d|2[0-3]):([0-5]\d)$/);
  return m === null ? null : [parseInt(m[1], 10), parseInt(m[2], 10)];
}

/** Today's (local time) firing time of a "time" trigger, in ms; NaN for a bad time. */
export function scheduledOn(at: string, now: number): number {
  const hm = parseAt(at);
  if (hm === null) {
    return NaN;
  }
  const d = new Date(now);
  d.setHours(hm[0], hm[1], 0, 0);
  return d.getTime();
}

/** The next time (ms, local) a "time" trigger fires after `now`, e.g. to schedule a wake-up; NaN for motion. */
export function nextFireTime(t: Trigger, now: number): number {
  if (t.on !== 'time' || t.at === undefined) {
    return NaN;
  }
  const today = scheduledOn(t.at, now);
  if (today > now) {
    return today;
  }
  const d = new Date(today);
  d.setDate(d.getDate() + 1); // the same wall-clock time tomorrow, across DST changes
  return d.getTime();
}

export class DueTriggers {
  /** Indices into capsule.triggers that should fire now. */
  indices: number[] = [];
  /** The updated last-fired times (scheduled time, ms) to store. */
  lastRun: Record<string, number> = {};
}

/**
 * Daily "time" triggers that are due: today's time has passed and they have not fired for it yet. A trigger
 * seen for the first time only starts counting (so creating a capsule at 10:00 does not run its 07:30 trigger
 * at once); a missed firing runs once when next checked, never more than once per day.
 */
export function dueTimeTriggers(capsule: Capsule, lastRun: Record<string, number>, now: number): DueTriggers {
  const out = new DueTriggers();
  Object.keys(lastRun).forEach((k: string) => {
    out.lastRun[k] = lastRun[k];
  });
  (capsule.triggers ?? []).forEach((t: Trigger, i: number) => {
    if (t.on !== 'time' || t.at === undefined) {
      return;
    }
    const key = triggerKey(capsule.id, i);
    const today = scheduledOn(t.at, now);
    if (Number.isNaN(today)) {
      return;
    }
    const last = lastRun[key];
    if (last === undefined) {
      out.lastRun[key] = today <= now ? today : today - 24 * 60 * 60 * 1000;
      return;
    }
    if (today <= now && last < today) {
      out.indices.push(i);
      out.lastRun[key] = today;
    }
  });
  return out;
}

/** Indices of the capsule's "motion" triggers, to run when the user starts moving. */
export function motionTriggers(capsule: Capsule): number[] {
  const out: number[] = [];
  (capsule.triggers ?? []).forEach((t: Trigger, i: number) => {
    if (t.on === 'motion') {
      out.push(i);
    }
  });
  return out;
}

export class TriggerRun {
  /** True when the steps ran; `state` and `actions` are then the result. */
  fired: boolean = false;
  state: StateValues = {};
  /** v0 actions to dispatch, in order, after `fired` (already allowed by the guard). */
  actions: string[] = [];
  /** Why the guard blocked it ('' if it did not). Nothing changed. */
  blocked: string = '';
  /** A runtime error in the steps ('' if none). Nothing changed. */
  error: string = '';
}

/** Runs trigger `index` of `capsule` on `state`: guard first, then the steps all-or-nothing. */
export function runTrigger(capsule: Capsule, state: StateValues, index: number, guard: TriggerGuard,
  removed?: boolean): TriggerRun {
  const r = new TriggerRun();
  r.state = state;
  const t = (capsule.triggers ?? [])[index];
  if (t === undefined) {
    r.error = `no trigger ${index}`;
    return r;
  }
  if (removed === true) {
    r.blocked = 'the capsule was removed';
    return r;
  }
  const permission = permissionForTrigger(t);
  if (!guard.allowTrigger(capsule, t, permission)) {
    r.blocked = `the "${t.on}" trigger needs permission "${permission}"`;
    return r;
  }
  const standIn: ButtonComponent = { type: 'button', label: t.label ?? '', action: '', do: t.do };
  const applied = applyActions(capsule, state, standIn);
  if (!applied.ok) {
    r.error = applied.error ?? 'the trigger failed';
    return r;
  }
  for (const action of applied.actions) {
    if (!guard.allowAction(capsule, action)) {
      r.blocked = `action "${action}" is not allowed`;
      return r;
    }
  }
  r.fired = true;
  r.state = applied.state;
  r.actions = applied.actions;
  return r;
}
