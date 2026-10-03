import { describe, it, expect } from '@ohos/hypium';
import { parseRequest } from '../main/ets/core/RuleParser';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import {
  ButtonComponent, Capsule, CapsuleComponent, ChecklistComponent, CounterComponent, TextComponent, TimerComponent
} from '../main/ets/core/CapsuleTypes';

function parseValid(request: string): Capsule {
  const c = parseRequest(request);
  expect(c === null).assertFalse();
  const v = validateCapsule(JSON.stringify(c));
  expect(v.errors.join('\n')).assertEqual('');
  return c as Capsule;
}

function timerSummary(c: Capsule): string {
  return c.ui.filter((x: CapsuleComponent) => x.type === 'timer')
    .map((x: CapsuleComponent) => `${(x as TimerComponent).label} ${(x as TimerComponent).minutes}`).join('|');
}

export default function ruleParserTest() {
  describe('RuleParser', () => {
    it('makes three timers and a start-all button', 0, () => {
      const c = parseValid('3 timers pasta 9 sauce 15 bread 6');
      expect(c.permissions.join(',')).assertEqual('reminders');
      expect(c.ui.length).assertEqual(4);
      const t = c.ui[1] as TimerComponent;
      expect(t.label).assertEqual('Sauce');
      expect(t.minutes).assertEqual(15);
      expect((c.ui[3] as ButtonComponent).action).assertEqual('startAllTimers');
    });

    it('handles timer variants and rejects a wrong count', 0, () => {
      const one = parseValid('Timer boiled eggs 7 min');
      expect((one.ui[0] as TimerComponent).label).assertEqual('Boiled eggs');
      expect((one.ui[1] as ButtonComponent).action).assertEqual('startTimer:boiled-eggs');
      expect(parseRequest('2 timers pasta 9 sauce 15 bread 6')).assertNull();
    });

    it('accepts timers with commas and "min" and no keyword (README example)', 0, () => {
      const c = parseValid('pasta 9 min, sauce 15 min, bread 6 min');
      expect(timerSummary(c)).assertEqual('Pasta 9|Sauce 15|Bread 6');
      expect(c.permissions.join(',')).assertEqual('reminders');
      expect((c.ui[3] as ButtonComponent).action).assertEqual('startAllTimers');
    });

    it('accepts "mins", "minutes", "m" and units attached to the number', 0, () => {
      expect(timerSummary(parseValid('pasta 9 mins, sauce 15 minutes, bread 6m'))).assertEqual('Pasta 9|Sauce 15|Bread 6');
      expect(timerSummary(parseValid('pasta 9min, sauce 15min'))).assertEqual('Pasta 9|Sauce 15');
    });

    it('accepts "and" between timers', 0, () => {
      expect(timerSummary(parseValid('pasta 9 min and sauce 15 min'))).assertEqual('Pasta 9|Sauce 15');
      expect(timerSummary(parseValid('pasta 9 min, sauce 15 min and bread 6 min'))).assertEqual('Pasta 9|Sauce 15|Bread 6');
    });

    it('accepts an optional "N timers" prefix with any of these phrasings', 0, () => {
      expect(timerSummary(parseValid('3 timers: pasta 9 min, sauce 15 min, bread 6 min')))
        .assertEqual('Pasta 9|Sauce 15|Bread 6');
      expect(timerSummary(parseValid('timers pasta 9, sauce 15 and bread 6'))).assertEqual('Pasta 9|Sauce 15|Bread 6');
      expect(parseRequest('2 timers pasta 9 min, sauce 15 min, bread 6 min')).assertNull();
    });

    it('makes a single timer from "label for N minutes"', 0, () => {
      const c = parseValid('boiled eggs for 7 minutes');
      expect(timerSummary(c)).assertEqual('Boiled eggs 7');
      expect((c.ui[1] as ButtonComponent).action).assertEqual('startTimer:boiled-eggs');
    });

    it('does not treat unit-less numbers as timers without the keyword', 0, () => {
      expect(parseRequest('pasta 9, sauce 15')).assertNull();
      expect(parseValid('water 8 glasses').id).assertEqual('goal-water');
      expect(parseRequest('pasta 9 min, sauce')).assertNull();
    });

    it('counts squats with the motion sensor', 0, () => {
      const c = parseValid('count my squats');
      const counter = c.ui[0] as CounterComponent;
      expect(counter.source).assertEqual('motion');
      expect(c.permissions.join(',')).assertEqual('motion');
      expect((c.ui[1] as ButtonComponent).action).assertEqual('increment:squats');
    });

    it('counts non-exercise things manually', 0, () => {
      const c = parseValid('count coffees');
      expect((c.ui[0] as CounterComponent).source).assertEqual('manual');
      expect(c.permissions.length).assertEqual(0);
    });

    it('turns a medication schedule into a dose checklist', 0, () => {
      const c = parseValid('medication 8am and 8pm');
      const list = c.ui[1] as ChecklistComponent;
      expect(list.items.join('|')).assertEqual('Medication 8:00 AM|Medication 8:00 PM');
      expect((c.ui[0] as TextComponent).text).assertEqual('Medication at 8:00 AM and 8:00 PM');
      expect(parseValid('vitamins at 9:30am, 21:00').ui.length).assertEqual(3);
    });

    it('tracks a water goal', 0, () => {
      const c = parseValid('water 8 glasses');
      expect((c.ui[0] as TextComponent).text).assertEqual('Goal: 8 glasses');
      expect((c.ui[2] as ButtonComponent).label).assertEqual('+1 glass');
      const d = parseValid('drink 8 glasses of water');
      expect((d.ui[1] as CounterComponent).id).assertEqual('water');
    });

    it('splits a bill', 0, () => {
      const c = parseValid('split 84 between 4');
      expect((c.ui[2] as TextComponent).text).assertEqual('Each pays: 21');
      const d = parseValid('Split the bill 100 among 3 people.');
      expect((d.ui[2] as TextComponent).text).assertEqual('Each pays: 33.33');
      expect(parseRequest('split 84 between 0')).assertNull();
    });

    it('makes a checklist from a list of items', 0, () => {
      const c = parseValid('checklist for leaving home: keys, wallet, charger');
      expect(c.name).assertEqual('Leaving home');
      const list = c.ui[0] as ChecklistComponent;
      expect(list.items.join('|')).assertEqual('Keys|Wallet|Charger');
      expect((c.ui[1] as ButtonComponent).action).assertEqual('reset:leaving-home');
      expect((parseValid('packing list: socks; charger and passport').ui[0] as ChecklistComponent).items.length)
        .assertEqual(3);
      expect(parseValid('checklist milk, eggs').name).assertEqual('Checklist');
      expect(parseRequest('checklist for nothing:')).assertNull();
    });

    it('returns null for requests it does not understand', 0, () => {
      expect(parseRequest('')).assertNull();
      expect(parseRequest('plan a trip to Kraków with my friends')).assertNull();
      expect(parseRequest('timers')).assertNull();
    });
  });
}
