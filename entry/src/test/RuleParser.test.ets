import { describe, it, expect } from '@ohos/hypium';
import { parseRequest } from '../main/ets/core/RuleParser';
import { initialState, renderTemplate, setInput, applyActions, StateValues } from '../main/ets/core/CapsuleProgram';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import {
  ButtonComponent, Capsule, CapsuleComponent, ChecklistComponent, CounterComponent, DisplayComponent, InputComponent,
  TextComponent, TimerComponent
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

/** "Label: step, step" for each button with v1 "do" steps. */
function sequenceButtons(c: Capsule): string[] {
  return c.ui.filter((x: CapsuleComponent) => x.type === 'button' && (x as ButtonComponent).do !== undefined)
    .map((x: CapsuleComponent) => `${(x as ButtonComponent).label}: ${((x as ButtonComponent).do ?? []).join(', ')}`);
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

    it('tracks a water goal live: "{count} / 8 · {8 - count} to go"', 0, () => {
      const c = parseValid('water 8 glasses');
      expect(c.schemaVersion).assertEqual(1);
      expect(c.name).assertEqual('Water');
      const progress = (c.ui[0] as DisplayComponent).text;
      let s: StateValues = initialState(c);
      expect(renderTemplate(c, s, progress)).assertEqual('0 / 8 · 8 to go');
      const plus = c.ui[2] as ButtonComponent;
      expect(plus.label).assertEqual('+1 glass');
      for (let i = 0; i < 3; i++) {
        s = applyActions(c, s, plus).state;
      }
      expect(renderTemplate(c, s, progress)).assertEqual('3 / 8 · 5 to go');
      for (let i = 0; i < 6; i++) {
        s = applyActions(c, s, plus).state;
      }
      expect(renderTemplate(c, s, progress)).assertEqual('9 / 8 · 0 to go');
      s = applyActions(c, s, c.ui[3] as ButtonComponent).state;
      expect(renderTemplate(c, s, progress)).assertEqual('0 / 8 · 8 to go');
      expect(parseValid('drink 8 glasses of water').id).assertEqual('goal-water');
      expect(parseValid('read 20 pages').name).assertEqual('Read');
      expect(parseValid('pushups goal 50').id).assertEqual('goal-pushups');
    });

    it('only makes goals for progress units or an explicit goal', 0, () => {
      expect(parseRequest('cars 3 colours')).assertNull();
      expect(parseValid('cars target 3 colours').id).assertEqual('goal-cars');
    });

    it('leaves scoring, games, quizzes, converting, calculating and streaks to the models', 0, () => {
      const skipped = ['darts score for 3 players', 'quiz me on 3 capitals', 'tennis game 3 sets',
        'convert 5 km', 'calculate 84 between 4', 'reading streak 30 days', 'count my score',
        'track my weight 80 kg and tell me', 'board game 4 players'];
      skipped.forEach((r: string) => {
        expect(parseRequest(r) === null ? r : `matched: ${r}`).assertEqual(r);
      });
    });

    it('splits a bill live, prefilled with the request numbers', 0, () => {
      const c = parseValid('split 84 between 4');
      expect(c.schemaVersion).assertEqual(1);
      expect((c.ui[0] as InputComponent).bind).assertEqual('total');
      expect((c.ui[1] as InputComponent).bind).assertEqual('people');
      const each = (c.ui[2] as DisplayComponent).text;
      let s: StateValues = initialState(c);
      expect(renderTemplate(c, s, each)).assertEqual('Each pays: 21');
      s = setInput(c, s, 'people', '3').state;
      expect(renderTemplate(c, s, each)).assertEqual('Each pays: 28');
      s = setInput(c, s, 'total', '100').state;
      expect(renderTemplate(c, s, each)).assertEqual('Each pays: 33.33');
      const d = parseValid('Split the bill 120.50 among 3 people.');
      expect(renderTemplate(d, initialState(d), (d.ui[2] as DisplayComponent).text)).assertEqual('Each pays: 40.17');
      expect(parseRequest('split 84 between 0')).assertNull();
    });

    it('strips filler from a single timer and names it after the timer', 0, () => {
      const c = parseValid('laundry done in 55 minutes');
      expect(timerSummary(c)).assertEqual('Laundry 55');
      expect(c.name).assertEqual('Laundry');
      expect(parseValid('timer boiled eggs 7 min').name).assertEqual('Boiled eggs');
      expect(parseValid('tea ready in 4 min').name).assertEqual('Tea');
      expect(parseValid('pasta 9 min, sauce 15 min').name).assertEqual('Pasta, Sauce timers');
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
    it('pomodoro: starting the break stops focus and the reverse (BUG-10)', 0, () => {
      const c = parseValid('pomodoro');
      expect(c.schemaVersion).assertEqual(1);
      expect(timerSummary(c)).assertEqual('Focus 25|Break 5');
      expect(JSON.stringify(sequenceButtons(c))).assertEqual(JSON.stringify([
        'Start focus: stopTimer:break, startTimer:focus', 'Start break: stopTimer:focus, startTimer:break'
      ]));
      expect(c.ui.some((x: CapsuleComponent) => x.type === 'button' && (x as ButtonComponent).action === 'startAllTimers'))
        .assertFalse();
      expect(timerSummary(parseValid('pomodoro 50/10 min'))).assertEqual('Focus 50|Break 10');
      const pressed = applyActions(c, initialState(c), c.ui[3] as ButtonComponent);
      expect(pressed.ok).assertTrue();
      expect(pressed.actions.join(', ')).assertEqual('stopTimer:focus, startTimer:break');
    });

    it('focus and break timers take turns; other timer pairs still start together', 0, () => {
      const c = parseValid('work 50 min, rest 10 min');
      expect(JSON.stringify(sequenceButtons(c))).assertEqual(JSON.stringify([
        'Start work: stopTimer:rest, startTimer:work', 'Start rest: stopTimer:work, startTimer:rest'
      ]));
      expect(sequenceButtons(parseValid('timers focus 25 short break 5')).length).assertEqual(2);
      const pasta = parseValid('pasta 9 min, sauce 15 min');
      expect(sequenceButtons(pasta).length).assertEqual(0);
      expect(pasta.ui.some((x: CapsuleComponent) => (x as ButtonComponent).action === 'startAllTimers')).assertTrue();
    });
  });
}
