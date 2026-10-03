import { describe, it, expect } from '@ohos/hypium';
import { createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig } from '../main/ets/core/ModelProvider';
import { CapsuleModel, PLAN_PROMPT, SYSTEM_PROMPT } from '../main/ets/core/CapsuleModel';
import {
  CapsuleSource, CLOUD_OFF, generateCapsuleWith, generateFromSharedTextWith, needsLogic, ON_DEVICE_ONLY, pickCloud
} from '../main/ets/core/CapsuleGenerator';
import { SHARED_TOO_LONG } from '../main/ets/core/SharedText';
import { Capsule, GenerateResult } from '../main/ets/core/CapsuleTypes';

const GOOD: string =
  '{"schemaVersion":0,"id":"plants","name":"Plants","permissions":[],"ui":[{"type":"checklist","id":"p","items":["Fern"]}]}';

/** Answers like Anthropic or an OpenAI-compatible API (by URL), counts calls and keeps the bodies. */
class CountingTransport implements HttpTransport {
  calls: number = 0;
  bodies: string[] = [];
  private status: number;
  private reply: string;

  constructor(status?: number, reply?: string) {
    this.status = status ?? 200;
    this.reply = reply ?? GOOD;
  }

  async post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse> {
    this.calls++;
    this.bodies.push(body);
    if (this.status !== 200) {
      return { status: this.status, body: '{"message":"down"}' };
    }
    const text = JSON.stringify(this.reply);
    return url.endsWith('/v1/messages') ? { status: 200, body: `{"content":[{"type":"text","text":${text}}]}` } :
      { status: 200, body: `{"choices":[{"message":{"role":"assistant","content":${text}}}]}` };
  }
}

/** Routing tests count one call per cloud generation, so they skip the plan and self-check calls. */
function modelWith(t: HttpTransport, provider?: string, planAndCheck?: boolean): CapsuleModel {
  const config = parseModelConfig(`{"provider":"${provider ?? 'mistral'}","apiKey":"test-key","model":"m"}`)
    .config as ModelConfig;
  return new CapsuleModel(createProvider(config, t), { planAndCheck: planAndCheck ?? false });
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

    it('smart: "tennis game tracker" goes to Mistral first, never to the on-device templates', 0,
      async (done: Function) => {
        const t = new CountingTransport();
        const local = onDeviceReturning(LOCAL);
        const r = await generateCapsuleWith('tennis game tracker', [modelWith(t)], '', local);
        expect(r.origin).assertEqual('cloud-eu:mistral');
        expect(local.calls).assertEqual(0);
        expect(t.calls).assertEqual(1);
        done();
      });

    it('smart: says needsCloud instead of a simplified on-device capsule when the cloud is not allowed yet', 0,
      async (done: Function) => {
        const t = new CountingTransport();
        const local = onDeviceReturning(LOCAL);
        const r = await generateCapsuleWith('tennis game tracker', [modelWith(t)], '', local, { allowCloud: false });
        expect(r.ok).assertFalse();
        expect(r.needsCloud).assertTrue();
        expect(r.error).assertContain('needs Cloud AI (mistral, EU)');
        expect(local.calls).assertEqual(0);
        expect(t.calls).assertEqual(0);
        done();
      });

    it('smart: plain requests with the cloud not allowed still use on-device, without needsCloud', 0,
      async (done: Function) => {
        const t = new CountingTransport();
        const r = await generateCapsuleWith(PLAIN, [modelWith(t)], '', onDeviceReturning(LOCAL), { allowCloud: false });
        expect(r.origin).assertEqual('on-device');
        expect(r.needsCloud).assertUndefined();
        expect(t.calls).assertEqual(0);
        done();
      });

    it('logic requests use on-device as best effort when no usable cloud exists', 0, async (done: Function) => {
      const none = await generateCapsuleWith('tennis game tracker', [], '', onDeviceReturning(LOCAL),
        { allowCloud: false });
      expect(none.origin).assertEqual('on-device');
      expect(none.needsCloud).assertUndefined();
      const t = new CountingTransport();
      const nonEu = await generateCapsuleWith('tennis game tracker', [modelWith(t, 'anthropic')], '',
        onDeviceReturning(LOCAL), { allowCloud: false });
      expect(nonEu.origin).assertEqual('on-device');
      expect(t.calls).assertEqual(0);
      done();
    });

    it('cloudOnly skips rules and on-device but keeps the cloud policy', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceReturning(LOCAL);
      // A rule would match and on-device would succeed: cloudOnly still asks the cloud.
      const r = await generateCapsuleWith('count my squats', [modelWith(t)], '', local, { cloudOnly: true });
      expect(r.origin).assertEqual('cloud-eu:mistral');
      expect(t.calls).assertEqual(1);
      expect(local.calls).assertEqual(0);
      const nonEu = new CountingTransport();
      const blocked = await generateCapsuleWith(PLAIN, [modelWith(nonEu, 'anthropic')], '', local, { cloudOnly: true });
      expect(blocked.ok).assertFalse();
      expect(blocked.error).assertContain('outside the EU');
      const allowed = await generateCapsuleWith(PLAIN, [modelWith(nonEu, 'anthropic')], '', local,
        { cloudOnly: true, allowNonEu: true });
      expect(allowed.origin).assertEqual('cloud:anthropic');
      const off = await generateCapsuleWith(PLAIN, [modelWith(t)], '', local, { cloudOnly: true, allowCloud: false });
      expect(off.error).assertEqual(CLOUD_OFF);
      const deviceOnly = await generateCapsuleWith(PLAIN, [modelWith(t)], '', local,
        { cloudOnly: true, mode: 'on-device-only' });
      expect(deviceOnly.error).assertEqual(ON_DEVICE_ONLY);
      expect((await generateCapsuleWith(PLAIN, [], '', local, { cloudOnly: true })).error)
        .assertEqual('AI fallback not configured.');
      expect(t.calls).assertEqual(1);
      expect(local.calls).assertEqual(0);
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
      const r = await generateCapsuleWith(PLAIN, [modelWith(t)], '', null, { allowCloud: false });
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

    it('sends only the request text to the cloud, in every step', 0, async (done: Function) => {
      const t = new CountingTransport();
      await generateCapsuleWith(LOGIC, [modelWith(t, 'mistral', true)], '', onDeviceReturning(LOCAL));
      // GOOD has no "plan", so this run is plan -> capsule (no self-check without a plan).
      expect(t.bodies.length).assertEqual(2);
      t.bodies.forEach((raw: string, i: number) => {
        const body = JSON.parse(raw) as OpenAIBodyShape;
        expect(body.messages[0].role).assertEqual('system');
        expect(body.messages[0].content).assertEqual(i === 0 ? PLAN_PROMPT : SYSTEM_PROMPT);
        expect(body.messages[1].role).assertEqual('user');
        expect(body.messages[1].content).assertEqual(`Request: ${LOGIC}`);
        expect(body.messages.length).assertEqual(2);
        expect(Object.keys(JSON.parse(raw) as Record<string, Object>).sort().join(','))
          .assertEqual('max_tokens,messages,model,response_format');
      });
      done();
    });
  });

  describe('CapsuleGenerator refusals', () => {
    it('"asdf" ends in an error from the cloud, not a capsule', 0, async (done: Function) => {
      const t = new CountingTransport(200, '{"error": "not an app"}');
      const r = await generateCapsuleWith('asdf', [modelWith(t, 'mistral', true)], '', onDeviceFailing());
      expect(r.ok).assertFalse();
      expect(r.capsule).assertUndefined();
      expect(r.failure).assertEqual('not-an-app');
      done();
    });

    it('does not fall back to on-device after the cloud reports unsupported capabilities', 0,
      async (done: Function) => {
        const t = new CountingTransport(200, '{"unsupported": ["contacts", "SMS"]}');
        const local = onDeviceReturning(LOCAL);
        const r = await generateCapsuleWith('text my contacts happy birthday', [modelWith(t, 'mistral', true)], '',
          local);
        expect(r.failure).assertEqual('unsupported');
        expect((r.unsupported ?? []).join(',')).assertEqual('contacts,SMS');
        expect(local.calls).assertEqual(0);
        expect(t.calls).assertEqual(1);
        done();
      });
  });

  describe('Active cloud provider (BUG-3)', () => {
    it('names the provider smart mode would use', 0, () => {
      const t = new CountingTransport();
      const anthropicOnly = [modelWith(t, 'anthropic')];
      expect(pickCloud(anthropicOnly, false)).assertNull();
      expect(pickCloud(anthropicOnly, true)?.providerName).assertEqual('anthropic');
      const both = [modelWith(t, 'anthropic'), modelWith(t, 'mistral')];
      expect(pickCloud(both, false)?.providerName).assertEqual('mistral');
      expect(pickCloud(both, true)?.providerName).assertEqual('mistral');
      expect(pickCloud([], true)).assertNull();
    });
  });

  describe('Shared text routing', () => {
    it('uses the built-in extractors first, without calling the cloud', 0, async (done: Function) => {
      const t = new CountingTransport();
      const r = await generateFromSharedTextWith('Shopping:\n- milk\n- eggs', [modelWith(t)]);
      expect(r.origin).assertEqual('rules');
      expect(t.calls).assertEqual(0);
      done();
    });

    it('sends unrecognised text to the EU cloud as a quoted request, up to 2000 characters', 0,
      async (done: Function) => {
        const t = new CountingTransport();
        const text = 'Grandma says the garden needs looking after while she travels. ' + 'x'.repeat(900);
        const r = await generateFromSharedTextWith(text, [modelWith(t)]);
        expect(r.origin).assertEqual('cloud-eu:mistral');
        expect(t.calls).assertEqual(1);
        expect(t.bodies[0]).assertContain('Make a capsule from this text the user shared with the app');
        expect(t.bodies[0]).assertContain('Grandma says the garden');
        done();
      });

    it('keeps the cloud policy and the length limit', 0, async (done: Function) => {
      const t = new CountingTransport();
      const long = await generateFromSharedTextWith('a'.repeat(2001), [modelWith(t)]);
      expect(long.error).assertEqual(SHARED_TOO_LONG);
      const deviceOnly = await generateFromSharedTextWith(PLAIN, [modelWith(t)], { mode: 'on-device-only' });
      expect(deviceOnly.error).assertContain(ON_DEVICE_ONLY);
      const off = await generateFromSharedTextWith(PLAIN, [modelWith(t)], { allowCloud: false });
      expect(off.needsCloud).assertTrue();
      const nonEu = await generateFromSharedTextWith(PLAIN, [modelWith(t, 'anthropic')]);
      expect(nonEu.error).assertContain('outside the EU');
      expect(t.calls).assertEqual(0);
      done();
    });
  });

  describe('needsLogic', () => {
    it('flags maths, scoring, converting, conditions, inputs and lists', 0, () => {
      const logic = ['km to miles converter', 'darts for 3 players', 'quiz me on capitals', 'tip calculator',
        'split the bill between friends', 'tennis scoreboard', 'convert celsius to fahrenheit',
        'warn me if my budget is over 100', 'shopping list where I type items', 'what is 12 x 7', '20% discount',
        'tennis game tracker', 'football match score', 'chess game tracker', 'keep track of points in our card game',
        'cost per person for the trip', 'habit streak for reading', 'how many days in a row did I run',
        'track my weight and tell me if I gained', 'flashcards for Spanish', 'inches to cm', 'basketball for 2 teams',
        'text my contacts happy birthday', 'show the weather', 'take a photo every day', 'email me a summary'];
      logic.forEach((r: string) => {
        expect(needsLogic(r) ? r : `missed: ${r}`).assertEqual(r);
      });
    });

    it('leaves plain timers, counters and checklists to the device', 0, () => {
      const plain = ['Pomodoro: a 25 minute focus timer and a 5 minute break timer', 'count the glasses of water I drink',
        'packing list for a beach trip: sunscreen, towel, hat', 'track my plants', 'egg timer 7 minutes',
        'beep when the tea is ready in 4 minutes', 'count push-ups', 'a 2 minute plank timer that notifies me',
        'morning routine checklist: shower, coffee, emails', 'count my steps while I walk'];
      plain.forEach((r: string) => {
        expect(needsLogic(r) ? `flagged: ${r}` : r).assertEqual(r);
      });
    });
  });
}
