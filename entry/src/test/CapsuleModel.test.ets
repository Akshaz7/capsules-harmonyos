import { describe, it, expect } from '@ohos/hypium';
import {
  createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig, parseModelConfigs, DEFAULT_ANTHROPIC_MODEL,
  DEFAULT_MISTRAL_MODEL
} from '../main/ets/core/ModelProvider';
import {
  CapsuleModel, CapsuleModelOptions, extractJson, NOT_AN_APP, parsePlan, parsePlanReply, parseSelfCheck, PLAN_PROMPT,
  refusalIn, retryMessage, SYSTEM_PROMPT, V1_EXAMPLES
} from '../main/ets/core/CapsuleModel';
import { validateCapsule } from '../main/ets/core/CapsuleValidator';

const GOOD: string =
  '{"schemaVersion":0,"id":"plants","name":"Plants","permissions":[],"ui":[{"type":"checklist","id":"p","items":["Fern"]}]}';
const BAD: string =
  '{"schemaVersion":0,"id":"plants","name":"Plants","permissions":[],"ui":[{"type":"timer","id":"t","label":"T","minutes":3}]}';

class SentRequest {
  url: string = '';
  headers: Record<string, string> = {};
  body: string = '';
}

/** Replies with the given responses in order, and records what was sent. */
class FakeTransport implements HttpTransport {
  sent: SentRequest[] = [];
  private replies: HttpResponse[];
  private failWith: string;

  constructor(replies: HttpResponse[], failWith?: string) {
    this.replies = replies;
    this.failWith = failWith ?? '';
  }

  async post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse> {
    const r = new SentRequest();
    r.url = url;
    r.headers = headers;
    r.body = body;
    this.sent.push(r);
    if (this.failWith.length > 0) {
      throw new Error(this.failWith);
    }
    const next = this.replies.shift();
    return next ?? { status: 500, body: 'no more replies' };
  }
}

/** Tests of the single capsule pass (validation, retry, extraction) skip the plan and self-check calls. */
const ONE_PASS: CapsuleModelOptions = { planAndCheck: false };

const PLAN: string = '{"plan":["Show a checklist of plants","One item: Fern"]}';
/** A valid capsule that the self-check might return as a revision. */
const REVISED: string =
  '{"schemaVersion":0,"id":"plants","name":"My plants","permissions":[],"ui":[{"type":"checklist","id":"p","items":["Fern","Ivy"]}]}';

function anthropicReply(text: string): HttpResponse {
  return { status: 200, body: `{"content":[{"type":"text","text":${JSON.stringify(text)}}]}` };
}

function openaiReply(text: string): HttpResponse {
  return { status: 200, body: `{"choices":[{"message":{"role":"assistant","content":${JSON.stringify(text)}}}]}` };
}

function config(provider: string): ModelConfig {
  const r = parseModelConfig(`{"provider":"${provider}","apiKey":"test-key","model":"m-1"}`);
  return r.config as ModelConfig;
}

export default function capsuleModelTest() {
  describe('ModelConfig', () => {
    it('parses config and applies defaults', 0, () => {
      const r = parseModelConfig('{"apiKey":"k"}');
      expect(r.config?.provider).assertEqual('anthropic');
      expect(r.config?.model).assertEqual(DEFAULT_ANTHROPIC_MODEL);
      expect(r.config?.baseUrl).assertEqual('https://api.anthropic.com');
    });

    it('reports config errors without leaking the key', 0, () => {
      expect(parseModelConfig('nope').error).assertContain('not valid JSON');
      expect(parseModelConfig('{}').error).assertContain('"apiKey" is missing');
      expect(parseModelConfig('{"provider":"x","apiKey":"secret"}').error).assertContain('unknown provider');
      expect(parseModelConfig('{"provider":"openai","apiKey":"secret"}').error).assertContain('"model" is required');
      const http = parseModelConfig('{"apiKey":"secret","baseUrl":"http://evil"}').error ?? '';
      expect(http).assertContain('https://');
      expect(http.includes('secret')).assertFalse();
    });

    it('defaults Mistral to its API and a JSON-mode model', 0, () => {
      const r = parseModelConfig('{"provider":"mistral","apiKey":"k"}');
      expect(r.config?.provider).assertEqual('mistral');
      expect(r.config?.model).assertEqual(DEFAULT_MISTRAL_MODEL);
      expect(r.config?.baseUrl).assertEqual('https://api.mistral.ai/v1');
    });

    it('reads several providers and picks the default', 0, () => {
      const text = '{"default":"mistral","providers":{"anthropic":{"apiKey":"a"},' +
        '"mistral":{"apiKey":"m","model":"mistral-small-latest"}}}';
      const all = parseModelConfigs(text);
      expect(all.error === undefined).assertTrue();
      expect(all.configs.map((c: ModelConfig) => c.provider).join(',')).assertEqual('anthropic,mistral');
      expect(all.defaultConfig?.provider).assertEqual('mistral');
      expect(all.defaultConfig?.model).assertEqual('mistral-small-latest');
      const one = parseModelConfig(text);
      expect(one.config?.provider).assertEqual('mistral');
      expect(one.config?.apiKey).assertEqual('m');
      expect(parseModelConfig('{"providers":{"anthropic":{"apiKey":"a"}}}').config?.provider).assertEqual('anthropic');
    });

    it('rejects a bad multi-provider config without leaking keys', 0, () => {
      const errorOf = (text: string): string => parseModelConfigs(text).error ?? '';
      expect(errorOf('{"providers":{"anthropic":{"apiKey":"a"},"mistral":{"apiKey":"m"}}}'))
        .assertContain('"default" must name one of the providers');
      expect(errorOf('{"default":"openai","providers":{"mistral":{"apiKey":"m"}}}'))
        .assertContain('"default" is "openai", which is not in "providers"');
      expect(errorOf('{"providers":{"mistral":{"model":"x"}}}')).assertContain('providers.mistral: "apiKey" is missing');
      expect(errorOf('{"providers":{"gemini":{"apiKey":"secret"}}}')).assertContain('unknown provider "gemini"');
      expect(errorOf('{"providers":{}}')).assertContain('at least one provider');
      const bad = errorOf('{"default":"mistral","providers":{"mistral":{"apiKey":"secret","baseUrl":"http://x"}}}');
      expect(bad).assertContain('https://');
      expect(bad.includes('secret')).assertFalse();
      expect(parseModelConfigs('{"providers":{"mistral":{"apiKey":"m"}},"default":"mistral"}').configs.length)
        .assertEqual(1);
    });
  });

  describe('CapsuleModel', () => {
    it('teaches schema v1 with two valid example capsules', 0, () => {
      expect(V1_EXAMPLES.length).assertEqual(2);
      V1_EXAMPLES.forEach((json: string) => {
        expect(validateCapsule(json).errors.join('\n')).assertEqual('');
        expect(SYSTEM_PROMPT).assertContain(json);
      });
      expect(SYSTEM_PROMPT).assertContain('"schemaVersion": 1');
    });

    it('sends request plus schema to Anthropic and returns a validated capsule', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply('```json\n' + GOOD + '\n```')]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t), ONE_PASS).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('cloud:anthropic');
      expect(r.capsule?.id).assertEqual('plants');
      expect(t.sent[0].url).assertEqual('https://api.anthropic.com/v1/messages');
      expect(t.sent[0].headers['x-api-key']).assertEqual('test-key');
      expect(t.sent[0].body).assertContain('track my plants');
      expect(t.sent[0].body).assertContain('Capsule schema (v0, plus v1');
      done();
    });

    it('calls Mistral chat completions with JSON output mode', 0, async (done: Function) => {
      const t = new FakeTransport([openaiReply(GOOD)]);
      const r = await new CapsuleModel(createProvider(config('mistral'), t), ONE_PASS).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('cloud-eu:mistral');
      expect(t.sent[0].url).assertEqual('https://api.mistral.ai/v1/chat/completions');
      expect(t.sent[0].headers['authorization']).assertEqual('Bearer test-key');
      expect(t.sent[0].body).assertContain('"response_format":{"type":"json_object"}');
      expect(t.sent[0].body).assertContain('"model":"m-1"');
      expect(t.sent[0].body).assertContain('JSON');
      done();
    });

    it('reports Mistral HTTP errors by name', 0, async (done: Function) => {
      const t = new FakeTransport([{ status: 401, body: '{"message":"Unauthorized"}' }]);
      const r = await new CapsuleModel(createProvider(config('mistral'), t), ONE_PASS).generate('track my plants');
      expect(r.ok).assertFalse();
      expect(r.error).assertContain('Mistral returned HTTP 401');
      done();
    });

    it('plans, writes the capsule from the plan, then self-checks it', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply(PLAN), anthropicReply(GOOD), anthropicReply('{"complete": true}')]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(r.capsule?.name).assertEqual('Plants');
      expect(r.origin).assertEqual('cloud:anthropic');
      expect(t.sent.length).assertEqual(3);
      expect(t.sent[0].body).assertContain(JSON.stringify(PLAN_PROMPT).slice(1, -1));
      expect(t.sent[1].body).assertContain('Plan (implement every point):\\n1. Show a checklist of plants\\n2. One item: Fern');
      expect(t.sent[2].body).assertContain('Check that capsule against every point of the plan');
      done();
    });

    it('uses the self-check revision when it is valid', 0, async (done: Function) => {
      const revision = `{"complete": false, "missing": ["Ivy"], "capsule": ${REVISED}}`;
      const t = new FakeTransport([openaiReply(PLAN), openaiReply(GOOD), openaiReply(revision)]);
      const r = await new CapsuleModel(createProvider(config('mistral'), t)).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(r.capsule?.name).assertEqual('My plants');
      expect(r.origin).assertEqual('cloud-eu:mistral');
      done();
    });

    it('keeps the valid capsule when the revision is invalid or the check fails', 0, async (done: Function) => {
      const bad = `{"complete": false, "capsule": ${BAD}}`;
      const t1 = new FakeTransport([anthropicReply(PLAN), anthropicReply(GOOD), anthropicReply(bad)]);
      const r1 = await new CapsuleModel(createProvider(config('anthropic'), t1)).generate('track my plants');
      expect(r1.ok).assertTrue();
      expect(r1.capsule?.name).assertEqual('Plants');
      const t2 = new FakeTransport([anthropicReply(PLAN), anthropicReply(GOOD), { status: 500, body: 'down' }]);
      const r2 = await new CapsuleModel(createProvider(config('anthropic'), t2)).generate('track my plants');
      expect(r2.ok).assertTrue();
      expect(r2.capsule?.name).assertEqual('Plants');
      done();
    });

    it('retries with validator errors after planning, and skips the check without a plan', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply(PLAN), anthropicReply(BAD), anthropicReply(GOOD),
        anthropicReply('{"complete": true}')]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('plants');
      expect(r.ok).assertTrue();
      expect(t.sent.length).assertEqual(4);
      expect(t.sent[2].body).assertContain('The validator rejected that capsule');
      const noPlan = new FakeTransport([anthropicReply('no plan here'), anthropicReply(GOOD)]);
      const r2 = await new CapsuleModel(createProvider(config('anthropic'), noPlan)).generate('plants');
      expect(r2.ok).assertTrue();
      expect(noPlan.sent.length).assertEqual(2);
      done();
    });

    it('parses plans and self-check replies defensively', 0, () => {
      expect(parsePlan('```json\n{"plan":["a"," b ",3,""]}\n```').join('|')).assertEqual('a|b');
      expect(parsePlan('{"plan":["1","2","3","4","5","6","7","8","9"]}').length).assertEqual(8);
      expect(parsePlan('nonsense').length).assertEqual(0);
      expect(parseSelfCheck('{"complete": true}')).assertNull();
      expect(parseSelfCheck('{"complete": false}')).assertNull();
      expect(parseSelfCheck(`{"complete": false, "capsule": ${REVISED}}`)).assertContain('My plants');
      expect(parseSelfCheck('garbage')).assertNull();
    });

    it('returns an error, not a capsule, for nonsense like "asdf"', 0, async (done: Function) => {
      const t = new FakeTransport([openaiReply('{"error": "asdf is not an app request"}')]);
      const r = await new CapsuleModel(createProvider(config('mistral'), t)).generate('asdf');
      expect(r.ok).assertFalse();
      expect(r.capsule).assertUndefined();
      expect(r.failure).assertEqual('not-an-app');
      expect(r.error).assertEqual(NOT_AN_APP);
      expect(r.details.join()).assertContain('asdf is not an app request');
      expect(t.sent.length).assertEqual(1);
      const onePass = new FakeTransport([openaiReply('{"error": "gibberish"}')]);
      const r2 = await new CapsuleModel(createProvider(config('mistral'), onePass), ONE_PASS).generate('asdf');
      expect(r2.failure).assertEqual('not-an-app');
      expect(onePass.sent.length).assertEqual(1);
      done();
    });

    it('lists unsupported capabilities from the plan step instead of building a weaker capsule', 0,
      async (done: Function) => {
        const t = new FakeTransport([anthropicReply(
          '{"unsupported": ["contacts", "SMS"], "message": "Capsules cannot read contacts or send texts."}')]);
        const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('text all my contacts happy new year');
        expect(r.ok).assertFalse();
        expect(r.failure).assertEqual('unsupported');
        expect((r.unsupported ?? []).join('|')).assertEqual('contacts|SMS');
        expect(r.error).assertEqual("Capsules can't do this: it needs contacts, SMS.");
        expect(t.sent.length).assertEqual(1);
        expect(t.sent[0].body).assertContain('runtime actions: send SMS, make phone calls, read');
        done();
      });

    it('reads plan replies: plan, unsupported or error', 0, () => {
      expect(parsePlanReply('{"plan":["a"]}').plan.join()).assertEqual('a');
      const u = parsePlanReply('{"unsupported":["camera",""," payments "],"message":"no camera"}');
      expect(u.unsupported.join('|')).assertEqual('camera|payments');
      expect(u.plan.length).assertEqual(0);
      expect(u.message).assertEqual('no camera');
      expect(parsePlanReply('{"error":"nonsense"}').notAnApp).assertTrue();
      expect(parsePlanReply('{"plan":["a"],"error":"x"}').notAnApp).assertFalse();
      expect(refusalIn('{"error":"nope"}')).assertEqual('nope');
      expect(refusalIn('{"schemaVersion":0,"error":"x","ui":[]}')).assertNull();
      expect(refusalIn('not json')).assertNull();
    });

    it('says when Claude spent all output tokens thinking', 0, async (done: Function) => {
      const thinking: HttpResponse = { status: 200, body: '{"content":[{"type":"thinking","thinking":""}],"stop_reason":"max_tokens"}' };
      const r = await new CapsuleModel(createProvider(config('anthropic'), new FakeTransport([thinking])), ONE_PASS)
        .generate('track my plants');
      expect(r.error).assertContain('Anthropic ran out of output tokens before answering');
      done();
    });

    it('works with an OpenAI-compatible provider', 0, async (done: Function) => {
      const t = new FakeTransport([openaiReply(GOOD)]);
      const r = await new CapsuleModel(createProvider(config('openai'), t), ONE_PASS).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(t.sent[0].url).assertEqual('https://api.openai.com/v1/chat/completions');
      expect(t.sent[0].headers['authorization']).assertEqual('Bearer test-key');
      expect(t.sent[0].body.includes('response_format')).assertFalse();
      done();
    });

    it('retries once with validator errors, then succeeds', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply(BAD), anthropicReply(GOOD)]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t), ONE_PASS).generate('plants');
      expect(r.ok).assertTrue();
      expect(t.sent.length).assertEqual(2);
      expect(t.sent[1].body).assertContain('needs permission');
      expect(t.sent[1].body).assertContain(JSON.stringify(retryMessage(validateCapsule(BAD).errors)).slice(1, -1));
      done();
    });

    it('quotes every validator error verbatim in the retry message', 0, () => {
      const errors = validateCapsule('{"schemaVersion":1,"id":"x","name":"X","permissions":[],' +
        '"state":{"score-p1":{"type":"number","initial":0}},"computed":{"a":"xs[0]"},"ui":[]}').errors;
      expect(errors.length).assertEqual(2);
      const msg = retryMessage(errors);
      errors.forEach((e: string) => {
        expect(msg).assertContain(`- "${e}"`);
      });
      expect(msg).assertContain('Reply with the corrected capsule JSON only.');
    });

    it('spells out the v1 name and expression rules', 0, () => {
      expect(SYSTEM_PROMPT).assertContain('No hyphens');
      expect(SYSTEM_PROMPT).assertContain('no [ ] indexing');
      expect(SYSTEM_PROMPT).assertContain('if, min, max, round, abs, len');
    });

    it('never returns an invalid capsule', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply(BAD), anthropicReply('sorry, I cannot')]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t), ONE_PASS).generate('plants');
      expect(r.ok).assertFalse();
      expect(r.capsule).assertUndefined();
      expect(r.error).assertContain('did not produce a valid capsule');
      expect(r.details[0]).assertContain('not valid JSON');
      done();
    });

    it('reports HTTP and network errors clearly', 0, async (done: Function) => {
      const unauthorized: HttpResponse = { status: 401, body: '{"type":"error","error":{"message":"invalid x-api-key"}}' };
      const r1 = await new CapsuleModel(createProvider(config('anthropic'), new FakeTransport([unauthorized])))
        .generate('plants');
      expect(r1.error).assertContain('HTTP 401: invalid x-api-key');
      const r2 = await new CapsuleModel(createProvider(config('anthropic'), new FakeTransport([], 'timeout')))
        .generate('plants');
      expect(r2.error).assertContain('Could not reach Anthropic: timeout');
      done();
    });

    it('rejects empty and overlong requests without calling the model', 0, async (done: Function) => {
      const t = new FakeTransport([]);
      const m = new CapsuleModel(createProvider(config('anthropic'), t), ONE_PASS);
      expect((await m.generate('  ')).error).assertContain('empty');
      expect((await m.generate('x'.repeat(501))).error).assertContain('too long');
      expect(t.sent.length).assertEqual(0);
      done();
    });

    it('extracts JSON from fenced or chatty replies', 0, () => {
      expect(extractJson('```json\n{"a":1}\n```')).assertEqual('{"a":1}');
      expect(extractJson('Here you go: {"a":{"b":2}} enjoy')).assertEqual('{"a":{"b":2}}');
      expect(SYSTEM_PROMPT).assertContain('startAllTimers');
    });
  });
}
