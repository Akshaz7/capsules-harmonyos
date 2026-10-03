/**
 * Provider-swappable LLM access. Pure logic: HTTP is injected through HttpTransport,
 * so providers can be unit-tested and the platform transport lives elsewhere.
 *
 * Config (config.local.json, git-ignored, never committed). One provider:
 *   { "provider": "anthropic" | "openai" | "mistral", "apiKey": "...", "model": "...", "baseUrl": "https://...",
 *     "timeoutMs": 30000 }
 * or several, with the one the app uses named in "default" (optional when there is only one):
 *   { "default": "mistral", "providers": { "mistral": { "apiKey": "..." }, "anthropic": { "apiKey": "..." } } }
 * "model", "baseUrl" and "timeoutMs" are optional for anthropic and mistral. "openai" means any
 * OpenAI-compatible chat completions endpoint and needs "model". "mistral" uses Mistral's
 * OpenAI-compatible endpoint with JSON output mode.
 */

import { CloudOrigin } from './CapsuleTypes';

export interface HttpResponse {
  status: number;
  body: string;
}

export interface HttpTransport {
  post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse>;
}

export type ProviderName = 'anthropic' | 'openai' | 'mistral';

export const PROVIDER_NAMES: ProviderName[] = ['anthropic', 'openai', 'mistral'];

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

/** Every provider in the config file; `default` is the one the app uses. */
export interface ModelConfigsResult {
  configs: ModelConfig[];
  defaultConfig?: ModelConfig;
  error?: string;
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface ModelProvider {
  /** Which provider this is; decides the EU routing policy and the capsule's origin. */
  readonly name: ProviderName;
  /** Returns the model's text reply. Throws an Error with a clear, key-free message on failure. */
  complete(system: string, messages: ChatMessage[]): Promise<string>;
}

export const DEFAULT_ANTHROPIC_MODEL: string = 'claude-sonnet-5-5';
const DEFAULT_ANTHROPIC_URL: string = 'https://api.anthropic.com';
const DEFAULT_OPENAI_URL: string = 'https://api.openai.com/v1';
/**
 * Mistral Medium 3.5 (v26.04), Mistral's newest generalist model. Which models a key may call depends on
 * its subscription tier (HTTP 403 tier_not_allowed, or a 0 requests/minute limit); set "model" in the
 * config to one the key allows, e.g. "ministral-14b-latest".
 */
export const DEFAULT_MISTRAL_MODEL: string = 'mistral-medium-latest';
const DEFAULT_MISTRAL_URL: string = 'https://api.mistral.ai/v1';
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

function defaultUrl(provider: ProviderName): string {
  if (provider === 'openai') {
    return DEFAULT_OPENAI_URL;
  }
  return provider === 'mistral' ? DEFAULT_MISTRAL_URL : DEFAULT_ANTHROPIC_URL;
}

function isProviderName(name: string): boolean {
  return PROVIDER_NAMES.includes(name as ProviderName);
}

/** Parses one provider's settings. `where` prefixes error messages. Errors never include the key. */
function parseProvider(obj: JsonRecord, provider: ProviderName, where: string): ModelConfigResult {
  const apiKey = optString(obj, 'apiKey');
  if (apiKey === null) {
    return { error: `${where}"apiKey" is missing` };
  }
  let model = optString(obj, 'model');
  if (model === null) {
    if (provider === 'openai') {
      return { error: `${where}"model" is required for provider "openai"` };
    }
    model = provider === 'mistral' ? DEFAULT_MISTRAL_MODEL : DEFAULT_ANTHROPIC_MODEL;
  }
  const baseUrl = (optString(obj, 'baseUrl') ?? defaultUrl(provider)).replace(/\/+$/, '');
  if (!baseUrl.startsWith('https://')) {
    return { error: `${where}"baseUrl" must start with https://` };
  }
  const t: JsonValue = obj['timeoutMs'];
  const timeoutMs = typeof t === 'number' && (t as number) > 0 ? t as number : DEFAULT_TIMEOUT_MS;
  const config: ModelConfig = {
    provider: provider, apiKey: apiKey, model: model, baseUrl: baseUrl, timeoutMs: timeoutMs
  };
  return { config: config };
}

function configsError(error: string): ModelConfigsResult {
  return { configs: [], error: error };
}

/**
 * Parses config.local.json text, in either the one-provider or the "providers" format.
 * Any invalid entry makes the whole file invalid, so a typo is never silently skipped.
 */
export function parseModelConfigs(text: string): ModelConfigsResult {
  let root: JsonValue;
  try {
    root = JSON.parse(text) as JsonValue;
  } catch (e) {
    return configsError('config.local.json is not valid JSON');
  }
  const obj = asRecord(root);
  if (obj === null) {
    return configsError('config.local.json must be a JSON object');
  }
  const unknown = (name: string): string =>
    `config.local.json: unknown provider "${name}" (use ${PROVIDER_NAMES.map((p: string) => `"${p}"`).join(', ')})`;
  if (obj['providers'] === undefined) {
    const provider = optString(obj, 'provider') ?? 'anthropic';
    if (!isProviderName(provider)) {
      return configsError(unknown(provider));
    }
    const one = parseProvider(obj, provider as ProviderName, 'config.local.json: ');
    if (one.config === undefined) {
      return configsError(one.error ?? 'config.local.json is invalid');
    }
    return { configs: [one.config], defaultConfig: one.config };
  }
  const providers = asRecord(obj['providers']);
  if (providers === null || Object.keys(providers).length === 0) {
    return configsError('config.local.json: "providers" must be an object with at least one provider');
  }
  const configs: ModelConfig[] = [];
  for (const name of Object.keys(providers)) {
    if (!isProviderName(name)) {
      return configsError(unknown(name));
    }
    const entry = asRecord(providers[name]);
    if (entry === null) {
      return configsError(`config.local.json: providers.${name} must be an object`);
    }
    const one = parseProvider(entry, name as ProviderName, `config.local.json: providers.${name}: `);
    if (one.config === undefined) {
      return configsError(one.error ?? 'config.local.json is invalid');
    }
    configs.push(one.config);
  }
  const named = optString(obj, 'default');
  if (named === null && configs.length > 1) {
    return configsError('config.local.json: "default" must name one of the providers');
  }
  const chosen = named === null ? configs[0] : configs.find((c: ModelConfig) => c.provider === named);
  if (chosen === undefined) {
    return configsError(`config.local.json: "default" is "${named}", which is not in "providers"`);
  }
  return { configs: configs, defaultConfig: chosen };
}

/** Parses config.local.json text and returns the default provider. Error messages never include the key. */
export function parseModelConfig(text: string): ModelConfigResult {
  const all = parseModelConfigs(text);
  return all.defaultConfig === undefined ? { error: all.error } : { config: all.defaultConfig };
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

/** Providers hosted in the EU. Only these are used for cloud requests without the "non-EU" setting. */
export function isEuProvider(name: ProviderName): boolean {
  return name === 'mistral';
}

/** The GenerateResult origin for capsules from this provider, e.g. "cloud-eu:mistral". */
export function cloudOrigin(name: ProviderName): CloudOrigin {
  if (name === 'mistral') {
    return 'cloud-eu:mistral';
  }
  return name === 'openai' ? 'cloud:openai' : 'cloud:anthropic';
}

/** Anthropic Messages API. */
export class AnthropicProvider implements ModelProvider {
  readonly name: ProviderName = 'anthropic';
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

interface ResponseFormat {
  type: string;
}

interface OpenAIBody {
  model: string;
  max_tokens: number;
  messages: OpenAIMessage[];
  response_format?: ResponseFormat;
}

/**
 * Any OpenAI-compatible /chat/completions endpoint. For Mistral it asks for JSON output mode
 * (response_format json_object), which needs the word "JSON" in the prompt; SYSTEM_PROMPT has it.
 */
export class OpenAICompatibleProvider implements ModelProvider {
  readonly name: ProviderName;
  private config: ModelConfig;
  private transport: HttpTransport;

  constructor(config: ModelConfig, transport: HttpTransport) {
    this.name = config.provider;
    this.config = config;
    this.transport = transport;
  }

  async complete(system: string, messages: ChatMessage[]): Promise<string> {
    const all: OpenAIMessage[] = [{ role: 'system', content: system }];
    messages.forEach((m: ChatMessage) => {
      all.push({ role: m.role, content: m.content });
    });
    const body: OpenAIBody = { model: this.config.model, max_tokens: MAX_TOKENS, messages: all };
    const mistral = this.config.provider === 'mistral';
    if (mistral) {
      body.response_format = { type: 'json_object' };
    }
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'authorization': `Bearer ${this.config.apiKey}`
    };
    const obj = await postJson(this.transport, mistral ? 'Mistral' : 'Model provider', `${this.config.baseUrl}/chat/completions`, headers,
      JSON.stringify(body), this.config.timeoutMs);
    const choices: JsonValue = obj['choices'];
    const first = Array.isArray(choices) && (choices as JsonValue[]).length > 0 ? asRecord((choices as JsonValue[])[0]) :
      null;
    const message = first === null ? null : asRecord(first['message']);
    const text = message === null ? null : optString(message, 'content');
    if (text === null) {
      throw new Error(`${mistral ? 'Mistral' : 'Model provider'} returned no text`);
    }
    return text;
  }
}

export function createProvider(config: ModelConfig, transport: HttpTransport): ModelProvider {
  return config.provider !== 'anthropic' ? new OpenAICompatibleProvider(config, transport) :
    new AnthropicProvider(config, transport);
}
