import { describe, it, expect } from '@ohos/hypium';
import { createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig } from '../main/ets/core/ModelProvider';
import { CapsuleModel, SYSTEM_PROMPT } from '../main/ets/core/CapsuleModel';
import {
  CapsuleSource, CLOUD_OFF, generateCapsuleWith, needsLogic, ON_DEVICE_ONLY
} from '../main/ets/core/CapsuleGenerator';
import { Capsule, GenerateResult } from '../main/ets/core/CapsuleTypes';

const GOOD: string =
  '{"schemaVersion":0,"id":"plants","name":"Plants","permissions":[],"ui":[{"type":"checklist","id":"p","items":["Fern"]}]}';

/** Answers like Anthropic or an OpenAI-compatible API (by URL), counts calls and keeps the bodies. */
class CountingTransport implements HttpTransport {
  calls: number = 0;
  bodies: string[] = [];
  private status: number;

  constructor(status?: number) {
    this.status = status ?? 200;
  }

  async post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse> {
    this.calls++;
    this.bodies.push(body);
    if (this.status !== 200) {
      return { status: this.status, body: '{"message":"down"}' };
    }
    const text = JSON.stringify(GOOD);
    return url.endsWith('/v1/messages') ? { status: 200, body: `{"content":[{"type":"text","text":${text}}]}` } :
      { status: 200, body: `{"choices":[{"message":{"role":"assistant","content":${text}}}]}` };
  }
}

function modelWith(t: HttpTransport, provider?: string): CapsuleModel {
  const config = parseModelConfig(`{"provider":"${provider ?? 'mistral'}","apiKey":"test-key","model":"m"}`)
    .config as ModelConfig;
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

function onDeviceFailing(): FakeOnDevice {
  return new FakeOnDevice({ ok: false, error: 'The on-device model is not sure.', details: [] });
}

const LOCAL: string =
  '{"schemaVersion":0,"id":"local","name":"Local","permissions":[],"ui":[{"type":"text","text":"hi"}]}';

/** Not matched by any rule, and needs no v1 logic. */
const PLAIN: string = 'track my plants';
/** Not matched by any rule, and needs v1 logic. */
const LOGIC: string = 'km to miles converter';

class OpenAIBodyMessage {
  role: string = '';
  content: string = '';
}

class OpenAIBodyShape {
  model: string = '';
  messages: OpenAIBodyMessage[] = [];
}

export default function capsuleGeneratorTest() {
  describe('CapsuleGenerator routing', () => {
    it('uses the rule parser first, without calling the on-device model or the cloud', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceReturning(LOCAL);
      const r = await generateCapsuleWith('count my squats', [modelWith(t)], '', local);
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('rules');
      expect(t.calls).assertEqual(0);
      expect(local.calls).assertEqual(0);
      done();
    });

    it('still serves rule requests with no config', 0, async (done: Function) => {
      const r = await generateCapsuleWith('split 84 between 4', []);
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('rules');
      done();
    });

    it('smart: sends logic requests to the EU cloud first, skipping on-device', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceReturning(LOCAL);
      const r = await generateCapsuleWith(LOGIC, [modelWith(t)], '', local);
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('cloud-eu:mistral');
      expect(t.calls).assertEqual(1);
      expect(local.calls).assertEqual(0);
      done();
    });

    it('smart: tries on-device first for plain requests and keeps them off the cloud', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceReturning(LOCAL);
      const r = await generateCapsuleWith(PLAIN, [modelWith(t)], '', local);
      expect(r.origin).assertEqual('on-device');
      expect(r.capsule?.id).assertEqual('local');
      expect(t.calls).assertEqual(0);
      done();
    });

    it('smart: falls back to the EU cloud when on-device fails', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceFailing();
      const r = await generateCapsuleWith(PLAIN, [modelWith(t)], '', local);
      expect(r.origin).assertEqual('cloud-eu:mistral');
      expect(local.calls).assertEqual(1);
      expect(t.calls).assertEqual(1);
      done();
    });

    it('smart: falls back to on-device when the cloud fails on a logic request', 0, async (done: Function) => {
      const t = new CountingTransport(500);
      const local = onDeviceReturning(LOCAL);
      const r = await generateCapsuleWith(LOGIC, [modelWith(t)], '', local);
      expect(r.origin).assertEqual('on-device');
      expect(t.calls).assertEqual(1);
      done();
    });

    it('reports the cloud error when both the cloud and on-device fail', 0, async (done: Function) => {
      const t = new CountingTransport(500);
      const r = await generateCapsuleWith(LOGIC, [modelWith(t)], '', onDeviceFailing());
      expect(r.ok).assertFalse();
      expect(r.error).assertContain('Mistral returned HTTP 500');
      done();
    });

    it('never uses a non-EU provider automatically', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceFailing();
      const r = await generateCapsuleWith(LOGIC, [modelWith(t, 'anthropic')], '', local);
      expect(r.ok).assertFalse();
      expect(t.calls).assertEqual(0);
      expect(local.calls).assertEqual(1);
      expect(r.error).assertContain('(anthropic) is outside the EU; allow non-EU providers in settings');
      done();
    });

    it('uses a non-EU provider when the settings allow it', 0, async (done: Function) => {
      const t = new CountingTransport();
      const r = await generateCapsuleWith(PLAIN, [modelWith(t, 'anthropic')], '', onDeviceFailing(),
        { allowNonEu: true });
      expect(r.origin).assertEqual('cloud:anthropic');
      expect(t.calls).assertEqual(1);
      done();
    });

    it('prefers the EU provider when both are configured', 0, async (done: Function) => {
      const nonEu = new CountingTransport();
      const eu = new CountingTransport();
      const r = await generateCapsuleWith(LOGIC, [modelWith(nonEu, 'anthropic'), modelWith(eu, 'mistral')], '', null,
        { allowNonEu: true });
      expect(r.origin).assertEqual('cloud-eu:mistral');
      expect(nonEu.calls).assertEqual(0);
      expect(eu.calls).assertEqual(1);
      done();
    });

    it('on-device-only mode never calls the cloud, even for logic requests', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceFailing();
      const r = await generateCapsuleWith(LOGIC, [modelWith(t)], '', local, { mode: 'on-device-only' });
      expect(r.ok).assertFalse();
      expect(t.calls).assertEqual(0);
      expect(local.calls).assertEqual(1);
      expect(r.error).assertContain(ON_DEVICE_ONLY);
      const ok = await generateCapsuleWith(PLAIN, [modelWith(t)], '', onDeviceReturning(LOCAL),
        { mode: 'on-device-only' });
      expect(ok.origin).assertEqual('on-device');
      done();
    });

    it('does not call the cloud when allowCloud is false', 0, async (done: Function) => {
      const t = new CountingTransport();
      const r = await generateCapsuleWith(LOGIC, [modelWith(t)], '', null, { allowCloud: false });
      expect(r.ok).assertFalse();
      expect(r.error).assertContain(CLOUD_OFF);
      expect(t.calls).assertEqual(0);
      done();
    });

    it('never returns an invalid on-device capsule', 0, async (done: Function) => {
      const bad = onDeviceReturning(
        '{"schemaVersion":0,"id":"bad","name":"Bad","permissions":[],"ui":[{"type":"timer","id":"t","label":"T","minutes":3}]}');
      const r = await generateCapsuleWith(PLAIN, [], '', bad);
      expect(r.ok).assertFalse();
      expect(r.capsule).assertUndefined();
      expect(r.error).assertContain('invalid capsule');
      done();
    });

    it('says the AI fallback is not configured, or why a broken config cannot be used', 0, async (done: Function) => {
      const r = await generateCapsuleWith(PLAIN, []);
      expect(r.error).assertEqual('No built-in rule understands this request. AI fallback not configured.');
      const broken = await generateCapsuleWith(PLAIN, [], 'config.local.json: "apiKey" is missing');
      expect(broken.error).assertContain('AI fallback unavailable: config.local.json: "apiKey" is missing');
      expect((await generateCapsuleWith('', [])).error).assertContain('empty');
      done();
    });

    it('sends only the request text to the cloud', 0, async (done: Function) => {
      const t = new CountingTransport();
      await generateCapsuleWith(LOGIC, [modelWith(t)], '', onDeviceReturning(LOCAL));
      const body = JSON.parse(t.bodies[0]) as OpenAIBodyShape;
      expect(body.messages.length).assertEqual(2);
      expect(body.messages[0].role).assertEqual('system');
      expect(body.messages[0].content).assertEqual(SYSTEM_PROMPT);
      expect(body.messages[1].role).assertEqual('user');
      expect(body.messages[1].content).assertEqual(`Request: ${LOGIC}`);
      expect(Object.keys(JSON.parse(t.bodies[0]) as Record<string, Object>).sort().join(','))
        .assertEqual('max_tokens,messages,model,response_format');
      done();
    });
  });

  describe('needsLogic', () => {
    it('flags maths, scoring, converting, conditions, inputs and lists', 0, () => {
      const logic = ['km to miles converter', 'darts for 3 players', 'quiz me on capitals', 'tip calculator',
        'split the bill between friends', 'tennis scoreboard', 'convert celsius to fahrenheit',
        'warn me if my budget is over 100', 'shopping list where I type items', 'what is 12 x 7', '20% discount'];
      logic.forEach((r: string) => {
        expect(needsLogic(r) ? r : `missed: ${r}`).assertEqual(r);
      });
    });

    it('leaves plain timers, counters and checklists to the device', 0, () => {
      const plain = ['Pomodoro: a 25 minute focus timer and a 5 minute break timer', 'count the glasses of water I drink',
        'packing list for a beach trip: sunscreen, towel, hat', 'habit streak for reading', 'track my plants',
        'egg timer 7 minutes'];
      plain.forEach((r: string) => {
        expect(needsLogic(r) ? `flagged: ${r}` : r).assertEqual(r);
      });
    });
  });
}
