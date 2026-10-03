/**
 * Provider-swappable LLM access. Pure logic: HTTP is injected through HttpTransport,
 * so providers can be unit-tested and the platform transport lives elsewhere.
 *
 * Config (entry/src/main/resources/rawfile/config.local.json, git-ignored, never committed):
 *   { "provider": "anthropic" | "openai", "apiKey": "...", "model": "...", "baseUrl": "https://...", "timeoutMs": 30000 }
 * "model", "baseUrl" and "timeoutMs" are optional for anthropic. "openai" means any
 * OpenAI-compatible chat completions endpoint and needs "model".
 */

export interface HttpResponse {
  status: number;
  body: string;
}

export interface HttpTransport {
  post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse>;
}

export type ProviderName = 'anthropic' | 'openai';

export interface ModelConfig {
  provider: ProviderName;
  apiKey: string;
  model: string;
  baseUrl: string;
  timeoutMs: number;
}

export interface ModelConfigResult {
  config?: ModelConfig;
  error?: string;
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface ModelProvider {
  /** Returns the model's text reply. Throws an Error with a clear, key-free message on failure. */
  complete(system: string, messages: ChatMessage[]): Promise<string>;
}

export const DEFAULT_ANTHROPIC_MODEL: string = 'claude-sonnet-5-5';
const DEFAULT_ANTHROPIC_URL: string = 'https://api.anthropic.com';
const DEFAULT_OPENAI_URL: string = 'https://api.openai.com/v1';
const DEFAULT_TIMEOUT_MS: number = 30000;
const MAX_TOKENS: number = 2048;

type JsonValue = Object | null | undefined;
type JsonRecord = Record<string, Object | null>;

function asRecord(v: JsonValue): JsonRecord | null {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v) ? v as JsonRecord : null;
}

function optString(obj: JsonRecord, key: string): string | null {
  const v: JsonValue = obj[key];
  return typeof v === 'string' && (v as string).trim().length > 0 ? (v as string).trim() : null;
}

/** Parses config.local.json text. Error messages never include the key. */
export function parseModelConfig(text: string): ModelConfigResult {
  let root: JsonValue;
  try {
    root = JSON.parse(text) as JsonValue;
  } catch (e) {
    return { error: 'config.local.json is not valid JSON' };
  }
  const obj = asRecord(root);
  if (obj === null) {
    return { error: 'config.local.json must be a JSON object' };
  }
  const provider = optString(obj, 'provider') ?? 'anthropic';
  if (provider !== 'anthropic' && provider !== 'openai') {
    return { error: `config.local.json: unknown provider "${provider}" (use "anthropic" or "openai")` };
  }
  const apiKey = optString(obj, 'apiKey');
  if (apiKey === null) {
    return { error: 'config.local.json: "apiKey" is missing' };
  }
  let model = optString(obj, 'model');
  if (model === null) {
    if (provider === 'openai') {
      return { error: 'config.local.json: "model" is required for provider "openai"' };
    }
    model = DEFAULT_ANTHROPIC_MODEL;
  }
  const baseUrl = (optString(obj, 'baseUrl') ?? (provider === 'openai' ? DEFAULT_OPENAI_URL : DEFAULT_ANTHROPIC_URL))
    .replace(/\/+$/, '');
  if (!baseUrl.startsWith('https://')) {
    return { error: 'config.local.json: "baseUrl" must start with https://' };
  }
  const t: JsonValue = obj['timeoutMs'];
  const timeoutMs = typeof t === 'number' && (t as number) > 0 ? t as number : DEFAULT_TIMEOUT_MS;
  const config: ModelConfig = {
    provider: provider as ProviderName, apiKey: apiKey, model: model, baseUrl: baseUrl, timeoutMs: timeoutMs
  };
  return { config: config };
}

/** Pulls a provider error message out of an error body, if there is one. */
function errorDetail(body: string): string {
  try {
    const obj = asRecord(JSON.parse(body) as JsonValue);
    const err = obj === null ? null : asRecord(obj['error']);
    const msg = err === null ? null : optString(err, 'message');
    if (msg !== null) {
      return msg.substring(0, 200);
    }
  } catch (e) {
    // not JSON
  }
  return body.substring(0, 200);
}

async function postJson(transport: HttpTransport, name: string, url: string, headers: Record<string, string>,
  body: string, timeoutMs: number): Promise<JsonRecord> {
  let resp: HttpResponse;
  try {
    resp = await transport.post(url, headers, body, timeoutMs);
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    throw new Error(`Could not reach ${name}: ${reason}`);
  }
  if (resp.status < 200 || resp.status >= 300) {
    throw new Error(`${name} returned HTTP ${resp.status}: ${errorDetail(resp.body)}`);
  }
  let parsed: JsonValue;
  try {
    parsed = JSON.parse(resp.body) as JsonValue;
  } catch (e) {
    throw new Error(`${name} returned a response that is not JSON`);
  }
  const obj = asRecord(parsed);
  if (obj === null) {
    throw new Error(`${name} returned an unexpected response`);
  }
  return obj;
}

interface AnthropicBody {
  model: string;
  max_tokens: number;
  system: string;
  messages: ChatMessage[];
}

/** Anthropic Messages API. */
export class AnthropicProvider implements ModelProvider {
  private config: ModelConfig;
  private transport: HttpTransport;

  constructor(config: ModelConfig, transport: HttpTransport) {
    this.config = config;
    this.transport = transport;
  }

  async complete(system: string, messages: ChatMessage[]): Promise<string> {
    const body: AnthropicBody = { model: this.config.model, max_tokens: MAX_TOKENS, system: system, messages: messages };
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'x-api-key': this.config.apiKey,
      'anthropic-version': '2023-06-01'
    };
    const obj = await postJson(this.transport, 'Anthropic', `${this.config.baseUrl}/v1/messages`, headers,
      JSON.stringify(body), this.config.timeoutMs);
    const content: JsonValue = obj['content'];
    if (!Array.isArray(content)) {
      throw new Error('Anthropic returned no content');
    }
    const parts: string[] = [];
    for (const block of content as JsonValue[]) {
      const b = asRecord(block);
      if (b !== null && b['type'] === 'text' && typeof b['text'] === 'string') {
        parts.push(b['text'] as string);
      }
    }
    if (parts.length === 0) {
      throw new Error('Anthropic returned no text');
    }
    return parts.join('');
  }
}

interface OpenAIMessage {
  role: string;
  content: string;
}

interface OpenAIBody {
  model: string;
  max_tokens: number;
  messages: OpenAIMessage[];
}

/** Any OpenAI-compatible /chat/completions endpoint. */
export class OpenAICompatibleProvider implements ModelProvider {
  private config: ModelConfig;
  private transport: HttpTransport;

  constructor(config: ModelConfig, transport: HttpTransport) {
    this.config = config;
    this.transport = transport;
  }

  async complete(system: string, messages: ChatMessage[]): Promise<string> {
    const all: OpenAIMessage[] = [{ role: 'system', content: system }];
    messages.forEach((m: ChatMessage) => {
      all.push({ role: m.role, content: m.content });
    });
    const body: OpenAIBody = { model: this.config.model, max_tokens: MAX_TOKENS, messages: all };
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'authorization': `Bearer ${this.config.apiKey}`
    };
    const obj = await postJson(this.transport, 'Model provider', `${this.config.baseUrl}/chat/completions`, headers,
      JSON.stringify(body), this.config.timeoutMs);
    const choices: JsonValue = obj['choices'];
    const first = Array.isArray(choices) && (choices as JsonValue[]).length > 0 ? asRecord((choices as JsonValue[])[0]) :
      null;
    const message = first === null ? null : asRecord(first['message']);
    const text = message === null ? null : optString(message, 'content');
    if (text === null) {
      throw new Error('Model provider returned no text');
    }
    return text;
  }
}

export function createProvider(config: ModelConfig, transport: HttpTransport): ModelProvider {
  return config.provider === 'openai' ? new OpenAICompatibleProvider(config, transport) :
    new AnthropicProvider(config, transport);
}
