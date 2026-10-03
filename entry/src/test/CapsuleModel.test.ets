import { describe, it, expect } from '@ohos/hypium';
import {
  createProvider, HttpResponse, HttpTransport, ModelConfig, parseModelConfig, DEFAULT_ANTHROPIC_MODEL
} from '../main/ets/core/ModelProvider';
import { CapsuleModel, extractJson, SYSTEM_PROMPT } from '../main/ets/core/CapsuleModel';

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
  });

  describe('CapsuleModel', () => {
    it('sends request plus schema to Anthropic and returns a validated capsule', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply('```json\n' + GOOD + '\n```')]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(r.origin).assertEqual('model');
      expect(r.capsule?.id).assertEqual('plants');
      expect(t.sent[0].url).assertEqual('https://api.anthropic.com/v1/messages');
      expect(t.sent[0].headers['x-api-key']).assertEqual('test-key');
      expect(t.sent[0].body).assertContain('track my plants');
      expect(t.sent[0].body).assertContain('Capsule schema v0');
      done();
    });

    it('works with an OpenAI-compatible provider', 0, async (done: Function) => {
      const t = new FakeTransport([openaiReply(GOOD)]);
      const r = await new CapsuleModel(createProvider(config('openai'), t)).generate('track my plants');
      expect(r.ok).assertTrue();
      expect(t.sent[0].url).assertEqual('https://api.openai.com/v1/chat/completions');
      expect(t.sent[0].headers['authorization']).assertEqual('Bearer test-key');
      done();
    });

    it('retries once with validator errors, then succeeds', 0, async (done: Function) => {
      const t = new FakeTransport([anthropicReply(BAD), anthropicReply(GOOD)]);
      const r = await new CapsuleModel(createProvider(config('anthropic'), t)).generate('plants');
      expect(r.ok).assertTrue();
      expect(t.sent.length).assertEqual(2);
      expect(t.sent[1].body).assertContain('needs permission');
      done();
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
