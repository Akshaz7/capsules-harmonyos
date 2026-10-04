import { describe, it, expect } from '@ohos/hypium';
import { validateCapsule, parseAction, permissionForAction } from '../main/ets/core/CapsuleValidator';
import { canSendToDevice, grantsWith, grantsWithout } from '../main/ets/core/Consent';
import { ParsedAction } from '../main/ets/core/CapsuleTypes';
import { CounterComponent, TimerComponent } from '../main/ets/core/CapsuleTypes';

const VALID: string = `{
  "schemaVersion": 0,
  "id": "pasta",
  "name": "Pasta night",
  "permissions": ["reminders", "motion", "notifications"],
  "ui": [
    { "type": "text", "text": "Dinner" },
    { "type": "timer", "id": "pasta", "label": "Pasta", "minutes": 9 },
    { "type": "counter", "id": "squats", "label": "Squats", "source": "motion" },
    { "type": "checklist", "id": "shop", "items": ["Basil", "Garlic"] },
    { "type": "number", "id": "guests", "label": "Guests" },
    { "type": "button", "label": "Start", "action": "startTimer:pasta" },
    { "type": "button", "label": "Start all", "action": "startAllTimers" },
    { "type": "button", "label": "+1", "action": "increment:squats" },
    { "type": "button", "label": "Reset", "action": "reset:squats" },
    { "type": "button", "label": "Ping", "action": "notify:Dinner is ready" }
  ]
}`;

function withUi(permissions: string, ui: string): string {
  return `{"schemaVersion":0,"id":"x","name":"X","permissions":${permissions},"ui":${ui}}`;
}

function errorsOf(json: string): string {
  return validateCapsule(json).errors.join('\n');
}

export default function capsuleValidatorTest() {
  describe('Permission "devices" (T4-13)', () => {
    it('accepts "devices" and sendToDevice with it; rejects sendToDevice without it and unknown permissions', 0, () => {
      const send = (perms: string): string =>
        `{"schemaVersion":0,"id":"d","name":"D","permissions":[${perms}],"ui":[{"type":"counter","id":"c",` +
          `"label":"Laps","source":"manual"},{"type":"button","label":"Show on watch","action":"sendToDevice"}]}`;
      expect(validateCapsule(send('"devices"')).errors.join(' | ')).assertEqual('');
      const missing = validateCapsule(send(''));
      expect(missing.ok).assertFalse();
      expect(missing.errors.join(' | ')).assertContain('needs permission "devices"');
      const unknown = validateCapsule(send('"devices","bluetooth"'));
      expect(unknown.errors.join(' | ')).assertContain('unknown permission "bluetooth"');
      expect(validateCapsule(send('"devices"').replace('"sendToDevice"', '"sendToDevice:watch"')).ok).assertFalse();
      const a = parseAction('sendToDevice') as ParsedAction;
      expect(`${a.kind} ${permissionForAction(a)}`).assertEqual('sendToDevice devices');
    });

    it('blocks a device send without consent, allows it after, and undo blocks it again', 0, () => {
      const none: string[] = ['reminders'];
      expect(canSendToDevice(none)).assertFalse();
      const allowed = grantsWith(none, 'devices');
      expect(canSendToDevice(allowed)).assertTrue();
      expect(grantsWith(allowed, 'devices').join()).assertEqual('reminders,devices'); // asked once, stored once
      expect(none.join()).assertEqual('reminders'); // input unchanged
      const undone = grantsWithout(allowed, 'devices');
      expect(canSendToDevice(undone)).assertFalse();
      expect(undone.join()).assertEqual('reminders');
    });
  });

  describe('CapsuleValidator', () => {
    it('accepts a valid capsule using every component and action', 0, () => {
      const r = validateCapsule(VALID);
      expect(r.errors.length).assertEqual(0);
      expect(r.ok).assertTrue();
      expect(r.capsule?.ui.length).assertEqual(10);
      expect((r.capsule?.ui[1] as TimerComponent).minutes).assertEqual(9);
      expect((r.capsule?.ui[2] as CounterComponent).source).assertEqual('motion');
    });

    it('rejects bad JSON', 0, () => {
      const r = validateCapsule('{"schemaVersion": 0, "id": ');
      expect(r.ok).assertFalse();
      expect(r.capsule).assertUndefined();
      expect(r.errors[0]).assertContain('not valid JSON');
    });

    it('rejects JSON that is not an object', 0, () => {
      expect(errorsOf('[1,2]')).assertContain('capsule must be a JSON object, got an array');
    });

    it('rejects an unknown component type', 0, () => {
      const errs = errorsOf(withUi('[]', '[{"type":"slider","id":"s","label":"S"}]'));
      expect(errs).assertContain('$.ui[0].type: unknown component type "slider"');
    });

    it('rejects an unknown action', 0, () => {
      const errs = errorsOf(withUi('[]', '[{"type":"button","label":"Go","action":"launchRocket:now"}]'));
      expect(errs).assertContain('$.ui[0].action: unknown action "launchRocket:now"');
    });

    it('rejects a component needing an unlisted permission', 0, () => {
      const errs = errorsOf(withUi('[]', '[{"type":"timer","id":"t","label":"T","minutes":5}]'));
      expect(errs).assertContain('timer "t" needs permission "reminders", which is not listed');
    });

    it('rejects a motion counter without the motion permission', 0, () => {
      const errs = errorsOf(withUi('["reminders"]', '[{"type":"counter","id":"c","label":"C","source":"motion"}]'));
      expect(errs).assertContain('needs permission "motion"');
      const ok = validateCapsule(withUi('[]', '[{"type":"counter","id":"c","label":"C","source":"manual"}]'));
      expect(ok.ok).assertTrue();
    });

    it('rejects an action needing an unlisted permission', 0, () => {
      const errs = errorsOf(withUi('[]', '[{"type":"button","label":"Ping","action":"notify:hi"}]'));
      expect(errs).assertContain('action "notify:hi" needs permission "notifications"');
    });

    it('rejects unknown and missing fields', 0, () => {
      const errs = errorsOf('{"schemaVersion":0,"id":"x","name":"X","ui":[],"script":"alert(1)"}');
      expect(errs).assertContain('$: unknown field "script"');
      expect(errs).assertContain('$: missing required field "permissions"');
      const compErrs = errorsOf(withUi('[]', '[{"type":"text","text":"hi","color":"red"}]'));
      expect(compErrs).assertContain('$.ui[0]: unknown field "color"');
    });

    it('rejects wrong schemaVersion, unknown permission and bad values', 0, () => {
      expect(errorsOf('{"schemaVersion":2,"id":"x","name":"X","permissions":[],"ui":[]}'))
        .assertContain('$.schemaVersion: must be 0 or 1');
      expect(errorsOf(withUi('["camera"]', '[]'))).assertContain('unknown permission "camera"');
      expect(errorsOf(withUi('["reminders"]', '[{"type":"timer","id":"t","label":"T","minutes":-1}]')))
        .assertContain('$.ui[0].minutes: must be a positive number');
      expect(errorsOf(withUi('[]', '[{"type":"checklist","id":"c","items":[]}]')))
        .assertContain('must contain at least one item');
    });

    it('rejects actions pointing at missing or wrong targets, and duplicate ids', 0, () => {
      expect(errorsOf(withUi('["reminders"]', '[{"type":"button","label":"Go","action":"startTimer:nope"}]')))
        .assertContain('refers to id "nope", which does not exist');
      expect(errorsOf(withUi('["reminders"]',
        '[{"type":"number","id":"n","label":"N"},{"type":"button","label":"Go","action":"startTimer:n"}]')))
        .assertContain('needs a timer, but "n" is a number');
      expect(errorsOf(withUi('[]', '[{"type":"number","id":"n","label":"A"},{"type":"number","id":"n","label":"B"}]')))
        .assertContain('$.ui[1].id: duplicate id "n"');
    });

    it('parses actions', 0, () => {
      expect(parseAction('startAllTimers')?.kind).assertEqual('startAllTimers');
      expect(parseAction('notify:a:b')?.arg).assertEqual('a:b');
      expect(parseAction('increment:')).assertNull();
      expect(parseAction('startAllTimers:x')).assertNull();
    });
  });
}
