import { describe, it, expect } from '@ohos/hypium';
import {
  createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig, parseModelConfigs, DEFAULT_ANTHROPIC_MODEL,
  DEFAULT_MISTRAL_MODEL
} from '../main/ets/core/ModelProvider';
import { CapsuleModel, extractJson, retryMessage, SYSTEM_PROMPT, V1_EXAMPLES } from '../main/ets/core/CapsuleModel';
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
      const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('track my plants');
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
      const r = await new CapsuleModel(createProvider(config('mistral'), t)).generate('track my plants');
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
      const r = await new CapsuleModel(createProvider(config('mistral'), t)).generate('track my plants');
      expect(r.ok).assertFalse();
      expect(r.error).assertContain('Mistral returned HTTP 401');
      done();
    });

    it('works with an OpenAI-compatible provider', 0, async (done: Function) => {
      const t = new FakeTransport([openaiReply(GOOD)]);
      const r = await new CapsuleModel(createProvider(config('openai'), t)).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(t.sent[0].url).assertEqual('https://api.openai.com/v1/chat/completions');
      expect(t.sent[0].headers['authorization']).assertEqual('Bearer test-key');
      expect(t.sent[0].body.includes('response_format')).assertFalse();
      done();
    });

    it('retries once with validator errors, then succeeds', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply(BAD), anthropicReply(GOOD)]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('plants');
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
      const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('plants');
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
      const m = new CapsuleModel(createProvider(config('anthropic'), t));
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
