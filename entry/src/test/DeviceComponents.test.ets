import { describe, it, expect } from '@ohos/hypium';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';
import { routeCapsule } from '../main/ets/core/CapsuleRouter';
import { parseRequest } from '../main/ets/core/RuleParser';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { batteryDetail, batteryValue, deviceKey, emptyReadout } from '../main/ets/capabilities/DeviceReadout';
import { TENNIS_CAPSULE } from '../main/ets/core/V1Fixtures';

function errorsOf(json: string): string {
  return validateCapsule(json).errors.join(' | ');
}

function valid(json: string): Capsule {
  const r = validateCapsule(json);
  expect(r.errors.join(' | ')).assertEqual('');
  return r.capsule as Capsule;
}

function capsuleWith(permissions: string, ui: string): string {
  return `{"schemaVersion":1,"id":"b","name":"B","permissions":${permissions},"ui":${ui}}`;
}

export default function deviceComponentsTest() {
  describe('Device components (battery)', () => {
    it('accepts a read-only battery reading that declares the battery permission', 0, () => {
      const c = valid(capsuleWith('["battery"]', '[{"type":"device","bind":"battery"}]'));
      expect(c.ui.length).assertEqual(1);
      const withLabel = valid(capsuleWith('["battery"]', '[{"type":"device","bind":"battery","label":"Phone"}]'));
      expect(withLabel.ui.length).assertEqual(1);
    });

    it('rejects an undeclared battery reading', 0, () => {
      expect(errorsOf(capsuleWith('[]', '[{"type":"device","bind":"battery"}]')))
        .assertContain('needs permission "battery"');
    });

    it('rejects unknown binds, extra fields and v0 use', 0, () => {
      expect(errorsOf(capsuleWith('["battery"]', '[{"type":"device","bind":"camera"}]'))).assertContain('bind');
      expect(errorsOf(capsuleWith('["battery"]', '[{"type":"device","bind":"battery","city":"krakow"}]')))
        .assertContain('unknown field "city"');
      expect(errorsOf('{"schemaVersion":0,"id":"b","name":"B","permissions":["battery"],"ui":' +
        '[{"type":"device","bind":"battery"}]}')).assertContain('"device" needs "schemaVersion": 1');
    });

    it('allows at most two readings per capsule', 0, () => {
      const two = capsuleWith('["battery"]',
        '[{"type":"device","bind":"battery"},{"type":"device","bind":"battery"}]');
      expect(validateCapsule(two).ok).assertTrue();
      const three = capsuleWith('["battery"]',
        '[{"type":"device","bind":"battery"},{"type":"device","bind":"battery"},{"type":"device","bind":"battery"}]');
      expect(errorsOf(three)).assertContain('max 2');
    });

    it('keeps every existing capsule valid', 0, () => {
      expect(validateCapsule(TENNIS_CAPSULE).ok).assertTrue();
    });

    it('builds "phone battery" without a model, and keeps it out of widgets', 0, () => {
      const c = parseRequest('phone battery');
      expect(c === null).assertFalse();
      const capsule = c as Capsule;
      expect(capsule.permissions.join()).assertEqual('battery');
      expect(validateCapsule(JSON.stringify(capsule)).ok).assertTrue();
      const route = routeCapsule(capsule);
      expect(route.widget).assertFalse();
      expect(route.reason).assertContain('readings');
    });

    it('formats the reading and its key', 0, () => {
      expect(batteryValue(72, false)).assertEqual('72%');
      expect(batteryValue(72, true)).assertEqual('72% · Charging');
      expect(batteryDetail(true)).assertEqual('Charging');
      expect(batteryDetail(false)).assertEqual('Not charging');
      expect(deviceKey({ type: 'device', bind: 'battery' })).assertEqual('battery');
      expect(emptyReadout().state).assertEqual('pending');
    });
  });
}
