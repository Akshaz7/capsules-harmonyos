import { describe, it, expect } from '@ohos/hypium';
import { ambiguousTimes, parseTimes } from '../main/ets/core/templates/TemplateLibrary';
import { parseRequest } from '../main/ets/core/RuleParser';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { generateCapsuleWith } from '../main/ets/core/CapsuleGenerator';
import { UNSUPPORTED_LANGUAGE } from '../main/ets/core/Language';
import { Capsule, Trigger } from '../main/ets/core/CapsuleTypes';
import { routeCapsule } from '../main/ets/core/CapsuleRouter';

function times(c: Capsule): string {
  return (c.triggers ?? []).map((t: Trigger) => `${t.on}@${t.at ?? ''}`).join(',');
}

const CLOUD_WITH_TRIGGERS: string = '{"schemaVersion":1,"id":"vitamins","name":"Vitamins",' +
  '"permissions":["reminders","notifications"],"ui":[{"type":"checklist","id":"doses","items":["Morning","Evening"]}],' +
  '"triggers":[{"on":"time","at":"08:00","do":["notify:Time for vitamins"],"label":"Vitamins at 08:00"},' +
  '{"on":"time","at":"20:00","do":["notify:Time for vitamins"],"label":"Vitamins at 20:00"}]}';

export default function timeTriggersTest() {
  describe('Time phrases become daily time triggers (T4-16)', () => {
    it('reads 12h and 24h times, am/pm, morning/evening and several times', 0, () => {
      expect(parseTimes('remind me at 7pm').join()).assertEqual('19:00');
      expect(parseTimes('stretch every morning at 8').join()).assertEqual('08:00');
      expect(parseTimes('walk the dog every evening at 7').join()).assertEqual('19:00');
      expect(parseTimes('vitamins 8am and 8pm').join()).assertEqual('08:00,20:00');
      expect(parseTimes('call mum at 19:30').join()).assertEqual('19:30');
      expect(parseTimes('drink water twice a day at 9 and 21').join()).assertEqual('09:00,21:00');
      expect(parseTimes('meds at 8, 14 and 20').join()).assertEqual('08:00,14:00,20:00');
      expect(parseTimes('at 12am').join()).assertEqual('00:00');
    });

    it('invents no time: no time phrase, no trigger', 0, () => {
      expect(parseTimes('timer 10 minutes').length).assertEqual(0);
      expect(parseTimes('split 84 between 4').length).assertEqual(0);
      expect(parseTimes('pizza for 4 and 2 kids').length).assertEqual(0);
      expect(parseTimes('tea at 4 minutes').length).assertEqual(0);
      expect(times(parseRequest('tea 4 min') as Capsule)).assertEqual('');
      expect(times(parseRequest('count my squats') as Capsule)).assertEqual('');
    });

    it('reads a bare "at 8" as 08:00 and flags it', 0, () => {
      expect(parseTimes('water the plants at 8').join()).assertEqual('08:00');
      expect(ambiguousTimes('water the plants at 8').join()).assertEqual('08:00');
      expect(ambiguousTimes('water the plants at 8pm').length).assertEqual(0);
      expect(ambiguousTimes('every morning at 8').length).assertEqual(0);
      expect(ambiguousTimes('call at 19:30').length).assertEqual(0);
    });

    it('the rule parser adds one valid notify trigger per time; the card stays v0', 0, () => {
      const meds = parseRequest('medication 8am and 8pm') as Capsule;
      expect(times(meds)).assertEqual('time@08:00,time@20:00');
      expect(meds.schemaVersion).assertEqual(1);
      expect(meds.permissions.includes('reminders') && meds.permissions.includes('notifications')).assertTrue();
      expect(validateCapsule(JSON.stringify(meds)).errors.join(' | ')).assertEqual('');
      expect(routeCapsule(meds).widget).assertTrue();
    });

    it('a cloud capsule with time triggers passes the validator', 0, () => {
      expect(validateCapsule(CLOUD_WITH_TRIGGERS).errors.join(' | ')).assertEqual('');
      const noPerm = CLOUD_WITH_TRIGGERS.replace('"reminders","notifications"', '"notifications"');
      expect(validateCapsule(noPerm).ok).assertFalse();
    });

    it('notes a bare time, and runs the English-only gate first', 0, async (done: Function) => {
      const r = await generateCapsuleWith('medication at 8', [], '', null);
      expect(r.ok).assertTrue();
      expect(times(r.capsule as Capsule)).assertEqual('time@08:00');
      expect(r.details.join()).assertContain('8pm');
      const pl = await generateCapsuleWith('przypomnij mi o lekach o 20:00', [], '', null);
      expect(pl.failure).assertEqual(UNSUPPORTED_LANGUAGE);
      done();
    });
  });
}
