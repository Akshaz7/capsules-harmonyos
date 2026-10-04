import { describe, it, expect } from '@ohos/hypium';
import { routeCapsule } from '../main/ets/core/CapsuleRouter';
import { parseRequest } from '../main/ets/core/RuleParser';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { TENNIS_CAPSULE } from '../main/ets/core/V1Fixtures';

function fromRules(request: string): Capsule {
  const c = parseRequest(request);
  expect(c === null).assertFalse();
  return c as Capsule;
}

function fromJson(ui: string): Capsule {
  const r = validateCapsule(`{"schemaVersion":0,"id":"x","name":"X","permissions":["reminders"],"ui":${ui}}`);
  expect(r.errors.join('\n')).assertEqual('');
  return r.capsule as Capsule;
}

export default function capsuleRouterTest() {
  describe('CapsuleRouter', () => {
    it('routes the v0 rule-parser examples to widgets', 0, () => {
      const requests = ['3 timers pasta 9 sauce 15 bread 6', 'count my squats', 'medication 8am and 8pm'];
      requests.forEach((req: string) => {
        const route = routeCapsule(fromRules(req));
        expect(`${req}: ${route.widget}`).assertEqual(`${req}: true`);
        expect(`${route.reason} ${route.condensed}`).assertContain('fit the card. false');
      });
    });

    it('puts the v1 goal counter on widgets; the bill split (inputs) goes on condensed (T4-15/T4-19)', 0, () => {
      expect(routeCapsule(fromRules('water 8 glasses')).widget).assertTrue();
      const split = routeCapsule(fromRules('split 84 between 4'));
      expect(`${split.widget} ${split.condensed}`).assertEqual('true true');
      expect(split.reason).assertContain('edited in the app');
    });

    it('condenses capsules with more than 3 timers, counters or checklists (T4-19)', 0, () => {
      const route = routeCapsule(fromRules('4 timers a 1 b 2 c 3 d 4'));
      expect(`${route.widget} ${route.condensed}`).assertEqual('true true');
      expect(route.reason).assertEqual('Widget, condensed: 4 timers, counters or checklists (the card shows 3).');
    });

    it('keeps a capsule with nothing a card can draw (only a number input) in the app', 0, () => {
      const route = routeCapsule(fromJson('[{"type":"number","id":"n","label":"Guests"}]'));
      expect(route.widget).assertFalse();
      expect(route.reason).assertContain('inputs');
      const counted = routeCapsule(fromJson('[{"type":"number","id":"n","label":"Guests"},' +
        '{"type":"counter","id":"c","label":"Seated","source":"manual"}]'));
      expect(`${counted.widget} ${counted.condensed}`).assertEqual('true true');
    });

    it('fits checklists of any length: the card shows the first items and +N more (T4-20)', 0, () => {
      const seven = routeCapsule(fromJson('[{"type":"checklist","id":"c","items":["1","2","3","4","5","6","7"]}]'));
      expect(seven.widget).assertTrue();
      const twelve = '["1","2","3","4","5","6","7","8","9","10","11","12"]';
      expect(routeCapsule(fromJson(`[{"type":"checklist","id":"c","items":${twelve}}]`)).widget).assertTrue();
    });

    it('fits a cloud-style packing list: a title, two headings and two checklists (5 components) (T4-20)', 0, () => {
      const packing = fromJson('[{"type":"text","text":"Flying from Scotland"},{"type":"text","text":"Clothes"},' +
        '{"type":"checklist","id":"clothes","items":["Jumper","Rain jacket","Socks","Boots"]},' +
        '{"type":"text","text":"Documents"},{"type":"checklist","id":"docs","items":["Passport","Boarding pass","Wallet"]}]');
      const route = routeCapsule(packing);
      expect(route.reason).assertEqual('Widget: all 5 components fit the card.');
      expect(route.widget).assertTrue();
      const tooWordy = fromJson('[{"type":"text","text":"a"},{"type":"text","text":"b"},{"type":"text","text":"c"},' +
        '{"type":"text","text":"d"},{"type":"checklist","id":"x","items":["1"]}]');
      expect(routeCapsule(tooWordy).reason).assertEqual('Widget, condensed: 4 lines (the card shows 3).');
    });

    it('sends an empty capsule to the app', 0, () => {
      expect(routeCapsule(fromJson('[]')).widget).assertFalse();
    });

    it('v1 capsules fit a widget in full with at most 3 lines, 3 buttons and 2 parts; more is condensed', 0, () => {
      const v1 = (ui: string): Capsule => {
        const r = validateCapsule(`{"schemaVersion":1,"id":"x","name":"X","permissions":["reminders"],` +
          `"state":{"n":{"type":"number","initial":0}},"ui":${ui}}`);
        expect(r.errors.join('\n')).assertEqual('');
        return r.capsule as Capsule;
      };
      const tennis = validateCapsule(TENNIS_CAPSULE).capsule as Capsule;
      expect(routeCapsule(tennis).widget).assertTrue(); // 3 displays (one inside "when"), 3 buttons
      expect(routeCapsule(fromRules('pomodoro')).widget).assertTrue();
      const d = '{"type":"display","text":"{n}"}';
      const b = '{"type":"button","label":"+","do":[{"set":"n","to":"n + 1"}]}';
      expect(routeCapsule(v1(`[${d},${d},${d},${b},${b},${b}]`)).widget).assertTrue();
      const fourLines = routeCapsule(v1(`[${d},{"type":"row","items":[${d},${d}]},{"type":"when","if":"n > 1","show":[${d}]}]`));
      expect(fourLines.reason).assertEqual('Widget, condensed: 4 lines (the card shows 3).');
      expect(routeCapsule(v1(`[${d},${b},${b},${b},${b}]`)).reason).assertContain('4 buttons');
      const t = (id: string): string => `{"type":"timer","id":"${id}","label":"T","minutes":1}`;
      expect(routeCapsule(v1(`[${t('a')},${t('b')},${t('c')}]`)).condensed).assertTrue();
      expect(routeCapsule(v1('[{"type":"input","bind":"n","kind":"number","label":"N"}]')).widget).assertFalse();
      expect(routeCapsule(v1(`[{"type":"input","bind":"n","kind":"number","label":"N"},${d}]`)).condensed).assertTrue();
    });
  });
}
