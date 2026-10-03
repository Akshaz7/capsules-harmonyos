import { describe, it, expect } from '@ohos/hypium';
import { createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig } from '../main/ets/core/ModelProvider';
import { CapsuleModel } from '../main/ets/core/CapsuleModel';
import { generateCapsuleWith } from '../main/ets/core/CapsuleGenerator';

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
      expect(r.origin).assertEqual('model');
      expect(t.calls).assertEqual(1);
      done();
    });

    it('returns a clear error when no rule matches and there is no model', 0, async (done: Function) => {
      const r = await generateCapsuleWith('track my plants', null, 'config.local.json not found in resources/rawfile');
      expect(r.ok).assertFalse();
      expect(r.error).assertContain('No built-in rule understands this request');
      expect(r.error).assertContain('config.local.json not found');
      expect((await generateCapsuleWith('', null)).error).assertContain('empty');
      done();
    });
  });
}
