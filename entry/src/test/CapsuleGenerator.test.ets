import { describe, it, expect } from '@ohos/hypium';
import { createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig } from '../main/ets/core/ModelProvider';
import { CapsuleModel, PLAN_PROMPT, SYSTEM_PROMPT } from '../main/ets/core/CapsuleModel';
import {
  CapsuleSource, CLOUD_OFF, generateCapsuleWith, generateFromSharedTextWith, LocalSources, needsLogic,
  ON_DEVICE_ONLY, pickCloud
} from '../main/ets/core/CapsuleGenerator';
import { TemplateLibrary } from '../main/ets/core/templates/TemplateLibrary';
import { MarketReply, MarketTransport } from '../main/ets/core/templates/MarketMatch';
import { SHARED_TOO_LONG } from '../main/ets/core/SharedText';
import { isNotEnglish, UNSUPPORTED_LANGUAGE } from '../main/ets/core/Language';
import { Capsule, GenerateResult } from '../main/ets/core/CapsuleTypes';
import { BuildStage } from '../main/ets/core/BuildStage';
import { CORE_TEMPLATES } from '../main/ets/core/templates/CoreTemplates';

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

/** Counts marketplace GETs; an empty result keeps the routing outcome unchanged. */
class CountingMarket implements MarketTransport {
  calls: number = 0;

  async get(url: string, timeoutMs: number): Promise<MarketReply> {
    this.calls++;
    return { status: 200, body: '{"capsules":[]}' };
  }
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

/** Records the stages as "name" or "name:provider". */
class StageLog {
  stages: string[] = [];

  listener(): (s: BuildStage) => void {
    return (s: BuildStage): void => {
      this.stages.push(s.provider !== undefined ? `${s.name}:${s.provider}` : s.name);
    };
  }
}

function throwingListener(s: BuildStage): void {
  throw new Error('the UI broke');
}

export default function capsuleGeneratorTest() {
  describe('Build stages (T4-25)', () => {
    it('reports a rules hit: rules, validating, done', 0, async (done: Function) => {
      const log = new StageLog();
      const local: LocalSources = { library: new TemplateLibrary(CORE_TEMPLATES) };
      const r = await generateCapsuleWith('count my squats', [], '', null, { onStage: log.listener() }, local);
      expect(r.ok).assertTrue();
      expect(log.stages.join(',')).assertEqual('rules,validating,done');
      done();
    });

    it('reports a template hit: rules, template, marketplace, done', 0, async (done: Function) => {
      const log = new StageLog();
      const local: LocalSources = {
        library: new TemplateLibrary(CORE_TEMPLATES),
        market: { baseUrl: 'https://m.example', transport: new CountingMarket() }
      };
      const r = await generateCapsuleWith('tennis scoreboard me vs Sam', [], '', null, { onStage: log.listener() },
        local);
      expect(r.origin).assertEqual('template');
      expect(log.stages.join(',')).assertEqual('rules,template,marketplace,done');
      done();
    });

    it('reports a cloud build with its provider, and the retry when the first reply is invalid', 0,
      async (done: Function) => {
        const log = new StageLog();
        const r = await generateCapsuleWith(PLAIN, [modelWith(new CountingTransport())], '', onDeviceFailing(),
          { onStage: log.listener() });
        expect(r.ok).assertTrue();
        expect(log.stages.join(',')).assertEqual('rules,on-device,cloud:mistral,validating,done');
        const bad = new StageLog();
        const f = await generateCapsuleWith(PLAIN, [modelWith(new CountingTransport(200, '{"nope":1}'))], '', null,
          { onStage: bad.listener() });
        expect(f.ok).assertFalse();
        expect(bad.stages.join(',')).assertEqual('rules,cloud:mistral,validating,retrying,validating,failed');
        done();
      });

    it('never lets the listener break the build, and sends no request text', 0, async (done: Function) => {
      const r = await generateCapsuleWith('count my squats', [], '', null, { onStage: throwingListener });
      expect(r.ok).assertTrue();
      const log = new StageLog();
      await generateCapsuleWith(PLAIN, [modelWith(new CountingTransport())], '', null, { onStage: log.listener() });
      expect(log.stages.join(',').includes('plants')).assertFalse();
      const cached = new StageLog();
      await generateCapsuleWith('xyzzy', [], '', null, { onStage: cached.listener() });
      expect(cached.stages[cached.stages.length - 1]).assertEqual('failed');
      done();
    });
  });


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

    it('on-device-only mode never searches the marketplace', 0, async (done: Function) => {
      const market = new CountingMarket();
      const local: LocalSources = {
        library: new TemplateLibrary([]),
        market: { baseUrl: 'https://m.example', transport: market }
      };
      const r = await generateCapsuleWith(PLAIN, [], '', onDeviceFailing(), { mode: 'on-device-only' }, local);
      expect(market.calls).assertEqual(0);
      expect(r.ok).assertFalse();
      done();
    });

    it('smart mode still searches the marketplace for unmatched requests', 0, async (done: Function) => {
      const market = new CountingMarket();
      const local: LocalSources = {
        library: new TemplateLibrary([]),
        market: { baseUrl: 'https://m.example', transport: market }
      };
      const r = await generateCapsuleWith(PLAIN, [], '', onDeviceFailing(), undefined, local);
      expect(market.calls).assertEqual(1);
      expect(r.ok).assertFalse();
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

  describe('Refusals only for clear runtime actions (T4-6)', () => {
    it('does not treat cameras, photos, the internet, files or news as unsupported', 0, () => {
      ['cooking timers from a photo of the recipe', 'remind me to charge the camera', 'read the news at 8am',
        'internet bill due on the 5th', 'back up my files on sunday', 'weather check every morning'].forEach((r: string) => {
        expect(needsLogic(r) ? `flagged: ${r}` : r).assertEqual(r);
      });
    });

    it('still sends SMS, calls, contacts, email, browsing and payments to the cloud plan step', 0, () => {
      ['send an sms to mum at 8', 'make a phone call every evening', 'read my contacts', 'send emails to the team',
        'browse the shop for me', 'take payments for lemonade'].forEach((r: string) => {
        expect(needsLogic(r) ? r : `missed: ${r}`).assertEqual(r);
      });
    });

    it('the plan prompt lists only those runtime actions; no prompt mentions other languages', 0, () => {
      expect(PLAN_PROMPT).assertContain('The only things capsules cannot do are these runtime actions: send SMS, make phone');
      expect(PLAN_PROMPT.includes('the camera or microphone')).assertFalse();
      expect(PLAN_PROMPT.includes('any language')).assertFalse();
      expect(SYSTEM_PROMPT.includes('any language')).assertFalse();
    });

    it('the prompt makes timers that take turns stop each other (BUG-10)', 0, () => {
      expect(SYSTEM_PROMPT).assertContain('"Start break" with\n  "do": ["stopTimer:focus", "startTimer:break"]');
      expect(SYSTEM_PROMPT).assertContain('"Start focus" with "do": ["stopTimer:break", "startTimer:focus"]');
    });
  });

  describe('English-only gate (T4-11)', () => {
    const CHINESE = '根据照片做菜，帮我设置计时器';
    const POLISH = 'licznik pompek na dziś, żółw';

    it('catches Chinese, Polish and other scripts', 0, () => {
      [CHINESE, POLISH, 'makaron 9 minut, sos 15 minut', 'minutnik 10 minut', 'przypomnij mi o lekach',
        'Zażółć gęślą jaźń', '在菜店买东西单。let me add items', 'тренировка 20 минут', 'تذكير بشرب الماء',
        '타이머 10분'].forEach((r: string) => {
        expect(isNotEnglish(r) ? r : `missed: ${r}`).assertEqual(r);
      });
    });

    it('lets English through, with accents in names and emoji', 0, () => {
      ['timer 10 minutes', 'café menu', "Zoë's chores", '💧 water 8 glasses 🥤', 'pomodoro', 'tennis game tracker',
        'pasta 9 min, sauce 15 min', 'count my squats', 'naïve crème brûlée timer 12 min', '🍝🍝🍝', '22 + 7'
      ].forEach((r: string) => {
        expect(isNotEnglish(r) ? `flagged: ${r}` : r).assertEqual(r);
      });
    });

    it('Chinese and Polish return the code and exact message, and no provider is called', 0, async (done: Function) => {
      for (const text of [CHINESE, POLISH]) {
        const t = new CountingTransport();
        const local = onDeviceReturning(LOCAL);
        const r = await generateCapsuleWith(text, [modelWith(t)], '', local, { allowNonEu: true });
        expect(r.ok).assertFalse();
        expect(r.failure).assertEqual(UNSUPPORTED_LANGUAGE);
        expect(r.error).assertEqual("Harmoniser understands English for now. Try: 'timer 10 minutes'.");
        expect(r.capsule === undefined).assertTrue();
        expect(t.calls).assertEqual(0);
        expect(local.calls).assertEqual(0);
        const cloudOnly = await generateCapsuleWith(text, [modelWith(t)], '', local, { cloudOnly: true });
        expect(cloudOnly.failure).assertEqual(UNSUPPORTED_LANGUAGE);
        const shared = await generateFromSharedTextWith(text, [modelWith(t)]);
        expect(shared.failure).assertEqual(UNSUPPORTED_LANGUAGE);
        expect(t.calls).assertEqual(0);
      }
      done();
    });

    it('English requests are still built', 0, async (done: Function) => {
      const t = new CountingTransport();
      for (const text of ['timer 10 minutes', '💧 water 8 glasses 🥤']) {
        const r = await generateCapsuleWith(text, [modelWith(t)], '', onDeviceReturning(LOCAL));
        expect(r.ok ? text : `${text}: ${r.error}`).assertEqual(text);
      }
      for (const text of ['café menu', "Zoë's chores"]) {
        const r = await generateCapsuleWith(text, [modelWith(t)], '', onDeviceReturning(LOCAL));
        expect(r.failure === undefined ? text : `${text}: ${r.failure}`).assertEqual(text);
      }
      done();
    });
  });

  describe('Photos and receipts (vision path)', () => {
    it('are not treated as unsupported capabilities', 0, () => {
      ['photo diary checklist', 'remind me to photograph the meter', 'keep my receipts in order'].forEach((r: string) => {
        expect(needsLogic(r) ? `flagged: ${r}` : r).assertEqual(r);
      });
      expect(PLAN_PROMPT).assertContain('A request that mentions a photo, the camera, a recipe from the internet');
      expect(PLAN_PROMPT.includes('files or photos')).assertFalse();
    });

    it('a receipt request reaches the cloud plan and is built, not refused', 0, async (done: Function) => {
      const t = new CountingTransport();
      const local = onDeviceFailing();
      const r = await generateCapsuleWith('split this receipt between 3 of us', [modelWith(t)], '', local);
      expect(r.ok).assertTrue();
      expect(r.failure).assertUndefined();
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
        'text my contacts happy birthday', 'browse websites for deals', 'pay my bills on time', 'email me a summary'];
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
