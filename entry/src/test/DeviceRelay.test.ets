import { describe, it, expect } from '@ohos/hypium';
import {
  cutUtf8, DeviceState, isAllowedRelayUrl, isOffline, isStaleState, normalizePairCode, pairCodeFromQr,
  parseDeviceState, payloadFor, relayErrorMessage, claimErrorText, SimulatedDeviceRelay, DevicePayload
} from '../main/ets/adapters/DeviceRelay';
import { isValidInstallToken, toBase64Url, TOKEN_HEADER } from '../main/ets/adapters/InstallToken';
import { Capsule } from '../main/ets/core/CapsuleTypes';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';

function capsule(json: string): Capsule {
  const v = validateCapsule(json);
  expect(v.errors.join('; ')).assertEqual('');
  return v.capsule as Capsule;
}

function bytes(text: string): Uint8Array {
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    out[i] = text.charCodeAt(i);
  }
  return out;
}

export default function deviceRelayTest() {
  describe('DeviceRelay + InstallToken (T3-15)', () => {
    it('install token: base64url, 43 chars from 32 bytes, header name', 0, () => {
      expect(toBase64Url(bytes('f'))).assertEqual('Zg');
      expect(toBase64Url(bytes('fo'))).assertEqual('Zm8');
      expect(toBase64Url(bytes('foo'))).assertEqual('Zm9v');
      const edge = new Uint8Array([0xfb, 0xff]);
      expect(toBase64Url(edge)).assertEqual('-_8');
      const t = toBase64Url(new Uint8Array(32).fill(200));
      expect(t.length).assertEqual(43);
      expect(isValidInstallToken(t)).assertTrue();
      expect(isValidInstallToken('550e8400-e29b-41d4-a716-446655440000')).assertFalse(); // a UUID is not enough
      expect(isValidInstallToken('abc+def/' + 'x'.repeat(40))).assertFalse();
      expect(TOKEN_HEADER).assertEqual('X-Harmoniser-Token');
    });

    it('pair codes: QR URL with /pair?code=, typed phrases, anything else is not a code', 0, () => {
      expect(pairCodeFromQr('https://harmoniser-web.vercel.app/pair?code=brave-otter-lamp')).assertEqual('brave-otter-lamp');
      expect(pairCodeFromQr('http://localhost:8090/pair/?code=Brave-Otter-Lamp')).assertEqual('brave-otter-lamp');
      expect(pairCodeFromQr('https://example.com/other?code=brave-otter-lamp')).assertEqual('');
      expect(pairCodeFromQr('https://example.com/pair')).assertEqual('');
      expect(pairCodeFromQr('{"schemaVersion":0,"id":"x"}')).assertEqual('');
      expect(normalizePairCode('Brave Otter LAMP')).assertEqual('brave-otter-lamp');
      expect(normalizePairCode('  brave - otter  lamp ')).assertEqual('brave-otter-lamp');
      expect(normalizePairCode('brave-otter')).assertEqual('');
      expect(normalizePairCode('brave-otter-lamp-x')).assertEqual('');
      expect(normalizePairCode('brave-0tter-lamp')).assertEqual('');
    });

    it('labels are cut to 47 UTF-8 bytes, never inside a character', 0, () => {
      expect(cutUtf8('Pasta', 47)).assertEqual('Pasta');
      expect(cutUtf8('a'.repeat(60), 47).length).assertEqual(47);
      const cut = cutUtf8('ż'.repeat(30), 47); // 2 bytes each
      expect(cut).assertEqual('ż'.repeat(23));
      expect(cutUtf8('😀😀😀😀😀😀😀😀😀😀😀😀', 47)).assertEqual('😀'.repeat(11)); // 4 bytes each
    });

    it('payload: first timer, else first counter; numbers within limits; nothing else', 0, () => {
      const tea = capsule('{"schemaVersion":0,"id":"tea","name":"Tea","permissions":["reminders"],' +
        '"ui":[{"type":"timer","id":"t","label":"Tea","minutes":3}]}');
      const p = payloadFor(tea) as DevicePayload;
      expect(p.type).assertEqual('timer');
      expect(p.label).assertEqual('Tea');
      expect(p.seconds).assertEqual(180);
      expect(p.count === undefined).assertTrue();
      expect(Object.keys(p).sort().join(',')).assertEqual('label,seconds,type');
      const reps = capsule('{"schemaVersion":0,"id":"r","name":"Reps","permissions":[],' +
        '"ui":[{"type":"counter","id":"c","label":"Pull-ups","source":"manual"}]}');
      const c = payloadFor(reps, 1234567) as DevicePayload;
      expect(c.type).assertEqual('counter');
      expect(c.count).assertEqual(999999);
      expect((payloadFor(reps, -3) as DevicePayload).count).assertEqual(0);
      const list = capsule('{"schemaVersion":0,"id":"l","name":"List","permissions":[],' +
        '"ui":[{"type":"checklist","id":"k","items":["a"]}]}');
      expect(payloadFor(list) === null).assertTrue();
    });

    it('state: parse, stale versions ignored, offline after 15 s, error shape', 0, () => {
      const s = parseDeviceState('{"type":"counter","label":"Pull-ups","count":7,"seconds":0,"remaining_seconds":0,' +
        '"running":false,"done":false,"motion":false,"version":7,"last_seen_ms_ago":1200}') as DeviceState;
      expect(s.count).assertEqual(7);
      expect(isStaleState(s, 8)).assertTrue();
      expect(isStaleState(s, 7)).assertFalse();
      expect(isOffline(s)).assertFalse();
      s.last_seen_ms_ago = 15001;
      expect(isOffline(s)).assertTrue();
      expect(parseDeviceState('not json') === null).assertTrue();
      expect(parseDeviceState('{"type":"timer"}') === null).assertTrue();
      expect(relayErrorMessage(400, '{"error":{"code":"bad_capsule","message":"label too long"}}'))
        .assertEqual('label too long');
      expect(relayErrorMessage(0, '')).assertEqual('The relay did not answer');
      expect(claimErrorText(429, '')).assertEqual('Too many tries. Wait a minute and try again.');
    });

    it('relay URLs: https, or http only to this machine', 0, () => {
      expect(isAllowedRelayUrl('https://harmoniser-web.vercel.app')).assertTrue();
      expect(isAllowedRelayUrl('http://localhost:8090')).assertTrue();
      expect(isAllowedRelayUrl('http://10.0.2.2:8090/')).assertTrue();
      expect(isAllowedRelayUrl('http://example.com')).assertFalse();
      expect(isAllowedRelayUrl('')).assertFalse();
    });

    it('simulated relay: claim, send, increment, versions', 0, async () => {
      const relay = new SimulatedDeviceRelay();
      expect(relay.simulated).assertTrue();
      expect((await relay.claim('nope')).error !== undefined).assertTrue();
      const claimed = await relay.claim('brave otter lamp');
      expect(claimed.device?.id ?? '').assertEqual('sim-device');
      const v1 = await relay.send('sim-device', { type: 'counter', label: 'Reps', count: 2 });
      await relay.action('sim-device', 'increment');
      const st = await relay.state('sim-device') as DeviceState;
      expect(st.count).assertEqual(3);
      expect(st.version).assertEqual(v1);
      const v2 = await relay.send('sim-device', { type: 'timer', label: 'Tea', seconds: 180 });
      expect(v2 > v1).assertTrue();
    });
  });
}
