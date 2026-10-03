import { describe, it, expect } from '@ohos/hypium';
import { createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig } from '../main/ets/core/ModelProvider';
import { CapsuleModel } from '../main/ets/core/CapsuleModel';
import { CapsuleSource, generateCapsuleWith } from '../main/ets/core/CapsuleGenerator';
import { Capsule, GenerateResult } from '../main/ets/core/CapsuleTypes';

const GOOD: string =
  '{"schemaVersion":0,"id":"plants","name":"Plants","permissions":[],"ui":[{"type":"checklist","id":"p","items":["Fern"]}]}';

class CountingTransport implements HttpTransport {
  calls: number = 0;

  async post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse> {
    this.calls++;
    return { status: 200, body: `{"content":[{"type":"text","text":${JSON.stringify(GOOD)}}]}` };
  }
}

function modelWith(t: HttpTransport): CapsuleModel {
  const config = parseModelConfig('{"apiKey":"test-key"}').config as ModelConfig;
  return new CapsuleModel(createProvider(config, t));
}

/** A stand-in on-device source that returns a fixed result and counts calls. */
class FakeOnDevice implements CapsuleSource {
  calls: number = 0;
  private result: GenerateResult;

  constructor(result: GenerateResult) {
    this.result = result;
  }

  async generate(request: string): Promise<GenerateResult> {
    this.calls++;
    return this.result;
  }
}

function onDeviceReturning(json: string): FakeOnDevice {
  const capsule = JSON.parse(json) as Capsule;
  return new FakeOnDevice({ ok: true, capsule: capsule, origin: 'on-device', details: [] });
}

const LOCAL: string =
  '{"schemaVersion":0,"id":"local","name":"Local","permissions":[],"ui":[{"type":"text","text":"hi"}]}';

export default function capsuleGeneratorTest() {
  describe('CapsuleGenerator', () => {
    it('uses the rule parser first, without calling the model', 0, async (done: Function) => {
      const t = new CountingTransport();
      const r = await generateCapsuleWith('count my squats', modelWith(t));
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('rules');
      expect(t.calls).assertEqual(0);
      done();
    });

    it('falls back to the model when no rule matches', 0, async (done: Function) => {
      const t = new CountingTransport();
      const r = await generateCapsuleWith('track my plants', modelWith(t));
      expect(r.origin).assertEqual('cloud');
      expect(t.calls).assertEqual(1);
      done();
    });

    it('says the AI fallback is not configured when there is no config', 0, async (done: Function) => {
      const r = await generateCapsuleWith('track my plants', null);
      expect(r.ok).assertFalse();
      expect(r.error).assertEqual('No built-in rule understands this request. AI fallback not configured.');
      done();
    });

    it('still serves rule requests with no config', 0, async (done: Function) => {
      const r = await generateCapsuleWith('split 84 between 4', null);
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('rules');
      done();
    });

    it('explains why a broken config cannot be used', 0, async (done: Function) => {
      const r = await generateCapsuleWith('track my plants', null, 'config.local.json: "apiKey" is missing');
      expect(r.error).assertContain('AI fallback unavailable: config.local.json: "apiKey" is missing');
      expect((await generateCapsuleWith('', null)).error).assertContain('empty');
      done();
    });
    it('uses the on-device source before the cloud model', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceReturning(LOCAL);
      const r = await generateCapsuleWith('track my plants', modelWith(t), '', local);
      expect(r.origin).assertEqual('on-device');
      expect(r.capsule?.id).assertEqual('local');
      expect(t.calls).assertEqual(0);
      done();
    });

    it('skips the on-device source when a rule matches', 0, async (done: Function) => {
      const local = onDeviceReturning(LOCAL);
      const r = await generateCapsuleWith('count coffees', null, '', local);
      expect(r.origin).assertEqual('rules');
      expect(local.calls).assertEqual(0);
      done();
    });

    it('falls back to the cloud when the on-device source fails', 0, async (done: Function) => {
      const t = new CountingTransport();
      const failing = new FakeOnDevice({ ok: false, error: 'not sure', details: [] });
      const r = await generateCapsuleWith('track my plants', modelWith(t), '', failing);
      expect(r.origin).assertEqual('cloud');
      expect(t.calls).assertEqual(1);
      done();
    });

    it('never returns an invalid on-device capsule', 0, async (done: Function) => {
      const bad = onDeviceReturning(
        '{"schemaVersion":0,"id":"bad","name":"Bad","permissions":[],"ui":[{"type":"timer","id":"t","label":"T","minutes":3}]}');
      const r = await generateCapsuleWith('track my plants', null, '', bad);
      expect(r.ok).assertFalse();
      expect(r.capsule).assertUndefined();
      expect(r.error).assertContain('invalid capsule');
      done();
    });

    it('does not call the cloud when allowCloud is false', 0, async (done: Function) => {
      const t = new CountingTransport();
      const r = await generateCapsuleWith('track my plants', modelWith(t), '', null, { allowCloud: false });
      expect(r.ok).assertFalse();
      expect(r.error).assertContain('Cloud AI is turned off.');
      expect(t.calls).assertEqual(0);
      done();
    });
  });
}
