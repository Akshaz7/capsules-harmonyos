import { describe, it, expect } from '@ohos/hypium';
import {
  dueTimeTriggers, motionTriggers, nextFireTime, runTrigger, triggerKey, TriggerGuard
} from '../main/ets/core/Triggers';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { initialState, StateValues } from '../main/ets/core/CapsuleProgram';
import { Capsule, Permission, Trigger } from '../main/ets/core/CapsuleTypes';

const CAPSULE: string = '{"schemaVersion":1,"id":"day","name":"Day","permissions":["reminders","motion","notifications"],' +
  '"state":{"n":{"type":"number","initial":5},"steps":{"type":"number","initial":0}},' +
  '"ui":[{"type":"display","text":"{n} {steps}"},{"type":"timer","id":"walk","label":"Walk","minutes":10}],' +
  '"triggers":[{"on":"time","at":"07:30","label":"Morning reset","do":[{"reset":"n"},"notify:Good morning"]},' +
  '{"on":"motion","do":[{"set":"steps","to":"steps + 1"},"startTimer:walk"]},' +
  '{"on":"time","at":"21:00","do":[{"set":"n","to":"n / 0"}]}]}';

class FakeGuard implements TriggerGuard {
  granted: Permission[] = ['reminders', 'motion', 'notifications'];
  blockedActions: string[] = [];
  asked: string[] = [];

  allowTrigger(capsule: Capsule, trigger: Trigger, permission: Permission): boolean {
    this.asked.push(`trigger:${permission}`);
    return this.granted.includes(permission);
  }

  allowAction(capsule: Capsule, action: string): boolean {
    this.asked.push(action);
    return !this.blockedActions.includes(action);
  }
}

function load(): Capsule {
  const r = validateCapsule(CAPSULE);
  expect(r.errors.join('\n')).assertEqual('');
  return r.capsule as Capsule;
}

/** Local time on 3-4 Oct 2026. */
function at(day: number, h: number, m: number): number {
  return new Date(2026, 9, day, h, m, 0, 0).getTime();
}

function changed(state: StateValues, n: number): StateValues {
  const s: StateValues = {};
  Object.keys(state).forEach((k: string) => {
    s[k] = state[k];
  });
  s['n'] = n;
  return s;
}

export default function triggersTest() {
  describe('Triggers runtime', () => {
    it('fires a daily time trigger once per day, never on the day it is first seen after its time', 0, () => {
      const c = load();
      const k = triggerKey('day', 0);
      const first = dueTimeTriggers(c, {}, at(3, 10, 0)); // capsule made at 10:00, trigger 07:30
      expect(first.indices.length).assertEqual(0);
      const before = dueTimeTriggers(c, first.lastRun, at(4, 7, 29));
      expect(before.indices.length).assertEqual(0);
      const due = dueTimeTriggers(c, before.lastRun, at(4, 7, 30));
      expect(due.indices.join()).assertEqual('0');
      expect(due.lastRun[k]).assertEqual(at(4, 7, 30));
      expect(dueTimeTriggers(c, due.lastRun, at(4, 12, 0)).indices.length).assertEqual(0);
    });

    it('runs a missed firing once when next checked, and counts from yesterday if seen before its time', 0, () => {
      const c = load();
      const k = triggerKey('day', 0);
      const missed: Record<string, number> = {};
      missed[k] = at(3, 7, 30);
      missed[triggerKey('day', 2)] = at(3, 21, 0);
      const late = dueTimeTriggers(c, missed, at(4, 22, 15));
      expect(late.indices.join()).assertEqual('0,2');
      expect(dueTimeTriggers(c, late.lastRun, at(4, 23, 0)).indices.length).assertEqual(0);
      const early = dueTimeTriggers(c, {}, at(4, 6, 0)); // made at 06:00: fires at 07:30 the same day
      expect(dueTimeTriggers(c, early.lastRun, at(4, 7, 30)).indices.join()).assertEqual('0');
    });

    it('computes the next firing time and lists motion triggers', 0, () => {
      const c = load();
      const triggers = c.triggers as Trigger[];
      expect(nextFireTime(triggers[0], at(4, 6, 0))).assertEqual(at(4, 7, 30));
      expect(nextFireTime(triggers[0], at(4, 7, 30))).assertEqual(at(5, 7, 30));
      expect(Number.isNaN(nextFireTime(triggers[1], at(4, 6, 0)))).assertTrue();
      expect(motionTriggers(c).join()).assertEqual('1');
    });

    it('runs steps and returns the v0 actions after the gatekeeper allows them', 0, () => {
      const c = load();
      const guard = new FakeGuard();
      const s = changed(initialState(c), 9);
      const morning = runTrigger(c, s, 0, guard);
      expect(morning.fired).assertTrue();
      expect(morning.state['n']).assertEqual(5);
      expect(morning.actions.join()).assertEqual('notify:Good morning');
      expect(guard.asked.join()).assertEqual('trigger:reminders,notify:Good morning');
      const moved = runTrigger(c, morning.state, 1, guard);
      expect(moved.state['steps']).assertEqual(1);
      expect(moved.actions.join()).assertEqual('startTimer:walk');
    });

    it('changes nothing when the gatekeeper blocks, the steps fail or the capsule was removed', 0, () => {
      const c = load();
      const s = changed(initialState(c), 9);
      const noMotion = new FakeGuard();
      noMotion.granted = ['reminders', 'notifications'];
      const r1 = runTrigger(c, s, 1, noMotion);
      expect(r1.fired).assertFalse();
      expect(r1.blocked).assertContain('needs permission "motion"');
      expect(r1.state['steps']).assertEqual(0);
      const noNotify = new FakeGuard();
      noNotify.blockedActions = ['notify:Good morning'];
      const r2 = runTrigger(c, s, 0, noNotify);
      expect(r2.fired).assertFalse();
      expect(r2.blocked).assertContain('notify:Good morning');
      expect(r2.state['n']).assertEqual(9);
      const r3 = runTrigger(c, s, 2, new FakeGuard());
      expect(r3.error).assertEqual('division by zero');
      expect(r3.state['n']).assertEqual(9);
      const r4 = runTrigger(c, s, 0, new FakeGuard(), true);
      expect(r4.fired).assertFalse();
      expect(r4.blocked).assertContain('removed');
      expect(runTrigger(c, s, 7, new FakeGuard()).error).assertContain('no trigger 7');
    });
  });
}
