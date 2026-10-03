import { Capsule, nextFireTime, Trigger } from '../core';

/** "Every day at 07:30" / "When you start moving". */
export function triggerWhen(t: Trigger): string {
  return t.on === 'time' ? `Every day at ${t.at ?? '--:--'}` : 'When you start moving';
}

/** The trigger's own label, else what it does in plain words. */
export function triggerTitle(t: Trigger): string {
  const label = (t.label ?? '').trim();
  return label.length > 0 ? label : t.on === 'time' ? 'Daily' : 'On the move';
}

/** "Next: today 07:30" / "Next: tomorrow 07:30" for time triggers; '' for motion or a bad time. */
export function triggerNext(t: Trigger, now: number): string {
  const next = nextFireTime(t, now);
  if (Number.isNaN(next)) {
    return '';
  }
  const day = new Date(now).getDate() === new Date(next).getDate() ? 'today' : 'tomorrow';
  return `Next: ${day} ${t.at}`;
}

/** "HH:MM" for a picked hour and minute. */
export function formatAt(hour: number, minute: number): string {
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${pad(hour)}:${pad(minute)}`;
}

/** A copy of `capsule` with its triggers replaced. */
export function withTriggers(capsule: Capsule, triggers: Trigger[]): Capsule {
  const copy: Capsule = {
    schemaVersion: capsule.schemaVersion,
    id: capsule.id,
    name: capsule.name,
    permissions: capsule.permissions,
    ui: capsule.ui,
    state: capsule.state,
    computed: capsule.computed,
    triggers: triggers
  };
  return copy;
}

/** Trigger `index` with a new daily time. */
export function retimed(capsule: Capsule, index: number, at: string): Capsule {
  const triggers = (capsule.triggers ?? []).map((t: Trigger, i: number) => {
    if (i !== index) {
      return t;
    }
    const changed: Trigger = { on: t.on, at: at, do: t.do, label: t.label };
    return changed;
  });
  return withTriggers(capsule, triggers);
}

/** Without trigger `index`. */
export function withoutTrigger(capsule: Capsule, index: number): Capsule {
  return withTriggers(capsule, (capsule.triggers ?? []).filter((t: Trigger, i: number) => i !== index));
}
