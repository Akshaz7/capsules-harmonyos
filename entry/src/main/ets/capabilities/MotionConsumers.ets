/**
 * Pure policy for who may receive shake events. The adapters own the sensor; the page decides, from the
 * user's scope setting and each capsule's grant, which capsules are active consumers right now.
 */

import { Capsule, CapsuleComponent, CounterComponent, Trigger } from '../core/CapsuleTypes';
import { allComponents } from '../core/CapsuleProgram';

/** 'capsule': only while that capsule's page is open. 'app': any capsule while Harmoniser is in front. */
export type MotionScope = 'capsule' | 'app';

export interface MotionConsumer {
  capsuleId: string;
  /** Counters that count shakes. */
  counterIds: string[];
  /** Indices into capsule.triggers of the motion triggers. */
  triggerIndices: number[];
}

/** Ids of the capsule's motion counters, in component order. */
export function motionCounterIds(capsule: Capsule): string[] {
  const out: string[] = [];
  allComponents(capsule.ui).forEach((c: CapsuleComponent) => {
    if (c.type === 'counter' && (c as CounterComponent).source === 'motion') {
      out.push((c as CounterComponent).id);
    }
  });
  return out;
}

/** Indices of the capsule's motion triggers. */
export function motionTriggerIndices(capsule: Capsule): number[] {
  const out: number[] = [];
  (capsule.triggers ?? []).forEach((t: Trigger, i: number) => {
    if (t.on === 'motion') {
      out.push(i);
    }
  });
  return out;
}

export function usesMotion(capsule: Capsule): boolean {
  return motionCounterIds(capsule).length > 0 || motionTriggerIndices(capsule).length > 0;
}

/**
 * The capsules that may receive shake events now: they use motion, the user allowed it for that capsule,
 * and the scope setting says they are active ('capsule' needs the open page, 'app' needs the foreground).
 */
export function activeMotionConsumers(capsules: Capsule[], scope: MotionScope, openId: string,
  allowed: (capsule: Capsule) => boolean): MotionConsumer[] {
  const out: MotionConsumer[] = [];
  capsules.forEach((capsule: Capsule) => {
    if (scope === 'capsule' && capsule.id !== openId) {
      return;
    }
    if (!usesMotion(capsule) || !allowed(capsule)) {
      return;
    }
    out.push({
      capsuleId: capsule.id,
      counterIds: motionCounterIds(capsule),
      triggerIndices: motionTriggerIndices(capsule)
    });
  });
  return out;
}
