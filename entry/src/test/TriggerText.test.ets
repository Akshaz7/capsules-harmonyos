import { describe, it, expect } from '@ohos/hypium';
import { formatAt, retimed, triggerNext, triggerTitle, triggerWhen, withoutTrigger } from '../main/ets/pages/TriggerText';
import { Capsule, Trigger } from '../main/ets/core/CapsuleTypes';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';

const WATER_JSON = '{"schemaVersion":1,"id":"water","name":"Water","permissions":["reminders"],' +
  '"state":{"glasses":{"type":"number","initial":0}},"ui":[{"type":"display","text":"Glasses: {glasses}"}],' +
  '"triggers":[{"on":"time","at":"07:30","do":[{"set":"glasses","to":"0"}],"label":"Morning reset"},' +
  '{"on":"time","at":"21:00","do":[{"set":"glasses","to":"0"}]}]}';
const WATER: Capsule = validateCapsule(WATER_JSON).capsule as Capsule;

function at(h: number, m: number): number {
  const d = new Date(2026, 9, 3, h, m, 0, 0);
  return d.getTime();
}

export default function triggerTextTest() {
  describe('TriggerText (T3-4)', () => {
    it('describes time and motion triggers', 0, () => {
      const t: Trigger = { on: 'time', at: '07:30', do: [], label: 'Morning reset' };
      const m: Trigger = { on: 'motion', do: [] };
      expect(triggerWhen(t)).assertEqual('Every day at 07:30');
      expect(triggerWhen(m)).assertEqual('When you start moving');
      expect(triggerTitle(t)).assertEqual('Morning reset');
      expect(triggerTitle(m)).assertEqual('On the move');
    });

    it('says today or tomorrow for the next run', 0, () => {
      const t: Trigger = { on: 'time', at: '07:30', do: [] };
      expect(triggerNext(t, at(6, 0))).assertEqual('Next: today 07:30');
      expect(triggerNext(t, at(9, 0))).assertEqual('Next: tomorrow 07:30');
      expect(triggerNext({ on: 'motion', do: [] }, at(9, 0))).assertEqual('');
    });

    it('formats picked times as HH:MM', 0, () => {
      expect(formatAt(7, 5)).assertEqual('07:05');
      expect(formatAt(23, 59)).assertEqual('23:59');
      expect(formatAt(0, 0)).assertEqual('00:00');
    });

    it('retimes and removes triggers; the result still validates', 0, () => {
      const moved = retimed(WATER, 0, '06:45');
      expect((moved.triggers ?? [])[0].at).assertEqual('06:45');
      expect((moved.triggers ?? [])[0].label).assertEqual('Morning reset');
      expect((moved.triggers ?? [])[1].at).assertEqual('21:00');
      expect(validateCapsule(JSON.stringify(moved)).ok).assertTrue();
      const fewer = withoutTrigger(WATER, 0);
      expect((fewer.triggers ?? []).length).assertEqual(1);
      expect((fewer.triggers ?? [])[0].at).assertEqual('21:00');
      expect(validateCapsule(JSON.stringify(fewer)).ok).assertTrue();
      expect((WATER.triggers ?? [])[0].at).assertEqual('07:30'); // the original is untouched
    });
  });
}
