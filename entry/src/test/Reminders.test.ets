import { describe, it, expect } from '@ohos/hypium';
import {
  dailyReminders, DailyReminder, nextOccurrence, notifiesInApp, planReminderSync, reminderPrefix
} from '../main/ets/core/Reminders';
import { CapsuleRuntime, Notifier } from '../main/ets/renderer/CapsuleRuntime';
import { TriggerGuard } from '../main/ets/core/Triggers';
import { parseRequest } from '../main/ets/core/RuleParser';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { ButtonComponent, Capsule, Permission, Trigger } from '../main/ets/core/CapsuleTypes';

const MIXED: string = '{"schemaVersion":1,"id":"plants","name":"Plants","permissions":["reminders","notifications"],' +
  '"state":{"watered":{"type":"number","initial":0}},"ui":[{"type":"display","text":"Watered {watered}"},' +
  '{"type":"button","label":"Ping","action":"notify:Water now"}],"triggers":[' +
  '{"on":"time","at":"08:00","do":["notify:Water the plants"]},' +
  '{"on":"time","at":"08:00","do":["notify:Water the plants"]},' +
  '{"on":"time","at":"21:00","do":[{"reset":"watered"}]},' +
  '{"on":"time","at":"19:30","do":[{"set":"watered","to":"watered + 1"},"notify:Evening check"]}]}';

function load(json: string): Capsule {
  const r = validateCapsule(json);
  expect(r.errors.join('\n')).assertEqual('');
  return r.capsule as Capsule;
}

function keys(rs: DailyReminder[]): string {
  return rs.map((r: DailyReminder) => `${r.at} ${r.title}`).join(' | ');
}

class Collect implements Notifier {
  shown: string[] = [];

  notify(capsuleId: string, text: string): void {
    this.shown.push(text);
  }
}

class AllowAll implements TriggerGuard {
  allowTrigger(capsule: Capsule, trigger: Trigger, permission: Permission): boolean {
    return true;
  }

  allowAction(capsule: Capsule, action: string): boolean {
    return true;
  }
}

export default function remindersTest() {
  describe('Daily reminders (T4-27)', () => {
    it('mirrors each daily notify trigger once; other triggers stay in the app', 0, () => {
      const plants = load(MIXED);
      const rs = dailyReminders(plants);
      expect(keys(rs)).assertEqual('08:00 Water the plants | 19:30 Evening check');
      expect(rs[0].text).assertEqual('Plants');
      expect(rs.every((r: DailyReminder) => r.key.startsWith(reminderPrefix('plants')))).assertTrue();
      const meds = parseRequest('medication 8am and 8pm') as Capsule;
      expect(dailyReminders(meds).map((r: DailyReminder) => r.at).join()).assertEqual('08:00,20:00');
      expect(dailyReminders(parseRequest('tea 4 min') as Capsule).length).assertEqual(0);
    });

    it('a changed time or text gets a new key, so the old event is replaced', 0, () => {
      const a = dailyReminders(load(MIXED))[0].key;
      const b = dailyReminders(load(MIXED.replace('"at":"08:00","do":["notify:Water the plants"]},' +
        '{"on":"time","at":"08:00"', '"at":"08:00","do":["notify:Water the ferns"]},{"on":"time","at":"08:00"')))[0].key;
      const c = dailyReminders(load(MIXED.split('08:00').join('07:00')))[0].key;
      expect(a === b || a === c || b === c).assertFalse();
    });

    it('syncs without duplicates: adds what is missing, deletes stale ones and extra copies', 0, () => {
      const wanted = dailyReminders(load(MIXED));
      const first = planReminderSync([], wanted);
      expect(`${first.add.length} ${first.remove.length}`).assertEqual('2 0');
      const again = planReminderSync(wanted.map((r: DailyReminder) => r.key), wanted);
      expect(`${again.add.length} ${again.remove.length}`).assertEqual('0 0'); // idempotent
      const dup = planReminderSync([wanted[0].key, wanted[0].key, 'capsules:plants:daily:06:00:x'], wanted);
      expect(dup.removeAt.join()).assertEqual('1,2');
      expect(keys(dup.add)).assertEqual('19:30 Evening check');
      const gone = planReminderSync(wanted.map((r: DailyReminder) => r.key), []);
      expect(`${gone.add.length} ${gone.removeAt.join()}`).assertEqual('0 0,1'); // capsule lost its triggers
    });

    it('finds the next local occurrence: later today, else tomorrow', 0, () => {
      const morning = new Date(2026, 9, 4, 7, 0, 0, 0).getTime();
      expect(nextOccurrence('08:00', morning)).assertEqual(new Date(2026, 9, 4, 8, 0, 0, 0).getTime());
      const late = new Date(2026, 9, 4, 22, 0, 0, 0).getTime();
      expect(nextOccurrence('08:00', late)).assertEqual(new Date(2026, 9, 5, 8, 0, 0, 0).getTime());
      const exact = new Date(2026, 9, 4, 8, 0, 0, 0).getTime();
      expect(nextOccurrence('08:00', exact)).assertEqual(new Date(2026, 9, 5, 8, 0, 0, 0).getTime());
    });

    it('notify reaches the notifier; mirrored time triggers do not notify twice', 0, () => {
      const plants = load(MIXED);
      const rt = new CapsuleRuntime(plants);
      const sink = new Collect();
      rt.notifier = sink;
      rt.press(plants.ui[1] as ButtonComponent);
      expect(sink.shown.join()).assertEqual('Water now'); // a button always notifies
      rt.fireTrigger(3, new AllowAll());
      expect(sink.shown.join()).assertEqual('Water now,Evening check'); // no calendar yet: the app notifies
      rt.calendarReminders = true;
      rt.fireTrigger(3, new AllowAll());
      expect(sink.shown.length).assertEqual(2); // the calendar rings it
      expect(rt.values['watered']).assertEqual(2); // the trigger's other steps still ran
      expect(notifiesInApp(undefined, 'notify:x', true)).assertTrue();
      expect(notifiesInApp((plants.triggers ?? [])[0], 'startTimer:x', true)).assertTrue();
    });
  });
}
