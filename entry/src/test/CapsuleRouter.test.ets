import { describe, it, expect } from '@ohos/hypium';
import { routeCapsule } from '../main/ets/core/CapsuleRouter';
import { parseRequest } from '../main/ets/core/RuleParser';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { Capsule } from '../main/ets/core/CapsuleTypes';

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
        expect(route.reason).assertContain('Widget-suitable');
      });
    });

    it('keeps the live v1 goal and bill split in the app', 0, () => {
      ['water 8 glasses', 'split 84 between 4'].forEach((req: string) => {
        const route = routeCapsule(fromRules(req));
        expect(`${req}: ${route.widget}`).assertEqual(`${req}: false`);
        expect(route.reason).assertContain('schema v1');
      });
    });

    it('sends capsules with more than 4 components to the app', 0, () => {
      const route = routeCapsule(fromRules('4 timers a 1 b 2 c 3 d 4'));
      expect(route.widget).assertFalse();
      expect(route.reason).assertEqual('App only: 5 components (a widget fits at most 4).');
    });

    it('sends capsules with number inputs to the app', 0, () => {
      const route = routeCapsule(fromJson('[{"type":"number","id":"n","label":"Guests"}]'));
      expect(route.widget).assertFalse();
      expect(route.reason).assertContain('number inputs');
    });

    it('allows checklists up to 6 items, not 7', 0, () => {
      expect(routeCapsule(fromJson('[{"type":"checklist","id":"c","items":["1","2","3","4","5","6"]}]')).widget)
        .assertTrue();
      const seven = routeCapsule(fromJson('[{"type":"checklist","id":"c","items":["1","2","3","4","5","6","7"]}]'));
      expect(seven.widget).assertFalse();
      expect(seven.reason).assertContain('7 items');
    });

    it('sends an empty capsule to the app', 0, () => {
      expect(routeCapsule(fromJson('[]')).widget).assertFalse();
    });

    it('sends schema v1 capsules to the app', 0, () => {
      const v1 = (extra: string, ui: string): Capsule => {
        const r = validateCapsule(`{"schemaVersion":1,"id":"x","name":"X","permissions":[]${extra},"ui":${ui}}`);
        expect(r.errors.join('\n')).assertEqual('');
        return r.capsule as Capsule;
      };
      const route = routeCapsule(v1(',"state":{"n":{"type":"number","initial":0}}', '[{"type":"text","text":"a"}]'));
      expect(route.widget).assertFalse();
      expect(route.reason).assertContain('state');
      expect(routeCapsule(v1('', '[{"type":"button","label":"Hi","do":["reset:k"]},{"type":"counter","id":"k","label":"K","source":"manual"}]')).widget).assertFalse();
      expect(routeCapsule(v1('', '[{"type":"display","text":"{1 + 1}"}]')).widget).assertFalse();
    });
  });
}
