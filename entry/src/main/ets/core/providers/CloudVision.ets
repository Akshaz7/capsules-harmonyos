/**
 * Photo -> capsule. Pure logic: the image bytes come in as an ImageInput and HTTP goes through HttpTransport,
 * so this file runs in unit tests and in scripts/eval-images.mjs as well as on the device.
 *
 * Policy (same consent rules as text, see CapsuleGenerator.ets):
 *   1. On device (unless cloudOnly): LFM2-VL reads the photo; the text it reads goes through the shared-text
 *      converters (recipe, bill, workout, list), otherwise through grounded on-device slot-filling.
 *   2. If that fails: mode "on-device-only" stops here. allowCloud false returns needsCloud (when a usable
 *      cloud provider is configured) so the app can ask first; nothing has left the device.
 *   3. Cloud: the photo is sent to the chosen provider (EU first; non-EU only with allowNonEu), which
 *      transcribes it; the cloud capsule model builds from the transcript (shared-text converters as fallback).
 */
import { GenerateResult } from '../CapsuleTypes';
import { CapsuleModel } from '../CapsuleModel';
import { AI_NOT_CONFIGURED, CLOUD_OFF, GenerateMode, GenerateOptions, ON_DEVICE_ONLY, pickCloud } from '../CapsuleGenerator';
import { capsuleFromSharedText, MAX_SHARED_TEXT } from '../SharedText';
import { cloudOrigin, HttpResponse, HttpTransport, ModelConfig } from '../ModelProvider';

export const IMAGE_NOT_READABLE: string = 'That photo could not be opened.';
export const MAX_IMAGE_BYTES: number = 5 * 1024 * 1024;
export const IMAGE_TOO_LARGE: string = 'That photo is too large (max 5 MB).';
export const IMAGE_UNSUPPORTED: string = 'Only JPEG, PNG and WebP photos are supported.';
export const IMAGE_NOT_UNDERSTOOD: string = 'Could not make a capsule from that photo.';

/** A photo the app can read: a file path (for the on-device model) plus lazy base64 (for the cloud). */
export interface ImageInput {
  path: string;
  mime: string;
  readBase64: () => string;
}

/** The on-device model (CactusProvider): reads a photo to text, and fills slots for a text request. */
export interface OnDeviceImageReader {
  whenInitialised(): Promise<boolean>;
  isReady(): boolean;
  readImage(imagePath: string): Promise<string>;
  generate(request: string): Promise<GenerateResult>;
}

/** Image MIME type from the file extension, or '' if unsupported. */
export function imageMime(path: string): string {
  const ext = path.toLowerCase().split('.').pop() ?? '';
  if (ext === 'jpg' || ext === 'jpeg') {
    return 'image/jpeg';
  }
  if (ext === 'png') {
    return 'image/png';
  }
  return ext === 'webp' ? 'image/webp' : '';
}

/** What the cloud provider is asked to do with the photo. */
export const VISION_PROMPT: string =
  'Transcribe the useful text in this photo, one line per item, step or row, keeping names, amounts, times and ' +
  'dates exactly as written (for example "Pierogi 24.50 zł", "Boil the pasta for 9 minutes"). Start with the ' +
  'heading or title if there is one. If the photo has no text, describe in one sentence what it shows. Reply ' +
  'with the text only, no comments.';

/** What the cloud capsule model is asked when the transcript matches no built-in converter. */
export function photoRequest(transcript: string): string {
  return `Make a capsule from this photo the user took. The text in the photo:\n"""\n${transcript.trim()}\n"""`;
}

// ---- Cloud vision request bodies (provider formats) ----

interface AnthropicImageSource {
  type: string;
  media_type: string;
  data: string;
}

interface AnthropicBlock {
  type: string;
  text?: string;
  source?: AnthropicImageSource;
}

interface AnthropicVisionMessage {
  role: string;
  content: AnthropicBlock[];
}

interface AnthropicVisionBody {
  model: string;
  max_tokens: number;
  messages: AnthropicVisionMessage[];
}

interface ImageUrl {
  url: string;
}

interface OpenAIBlock {
  type: string;
  text?: string;
  image_url?: ImageUrl;
}

interface OpenAIVisionMessage {
  role: string;
  content: OpenAIBlock[];
}

interface OpenAIVisionBody {
  model: string;
  max_tokens: number;
  messages: OpenAIVisionMessage[];
}

type JsonValue = Object | null | undefined;
type JsonRecord = Record<string, Object | null>;

function asRecord(v: JsonValue): JsonRecord | null {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v) ? v as JsonRecord : null;
}

const VISION_MAX_TOKENS: number = 1024;
const VISION_MIN_TIMEOUT_MS: number = 60000;

/**
 * Sends the photo to the provider in `config` and returns its transcript. Throws an Error with a clear,
 * key-free message on failure.
 */
export async function describeImage(config: ModelConfig, transport: HttpTransport, image: ImageInput): Promise<string> {
  const data = image.readBase64();
  const anthropic = config.provider === 'anthropic';
  const name = anthropic ? 'Anthropic' : config.provider === 'mistral' ? 'Mistral' : 'Model provider';
  let url: string;
  let body: string;
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (anthropic) {
    url = `${config.baseUrl}/v1/messages`;
    headers['x-api-key'] = config.apiKey;
    headers['anthropic-version'] = '2023-06-01';
    const b: AnthropicVisionBody = {
      model: config.model, max_tokens: VISION_MAX_TOKENS, messages: [{ role: 'user', content: [
        { type: 'image', source: { type: 'base64', media_type: image.mime, data: data } },
        { type: 'text', text: VISION_PROMPT }
      ] }]
    };
    body = JSON.stringify(b);
  } else {
    url = `${config.baseUrl}/chat/completions`;
    headers['authorization'] = `Bearer ${config.apiKey}`;
    const b: OpenAIVisionBody = {
      model: config.model, max_tokens: VISION_MAX_TOKENS, messages: [{ role: 'user', content: [
        { type: 'text', text: VISION_PROMPT },
        { type: 'image_url', image_url: { url: `data:${image.mime};base64,${data}` } }
      ] }]
    };
    body = JSON.stringify(b);
  }
  let resp: HttpResponse;
  try {
    resp = await transport.post(url, headers, body, Math.max(config.timeoutMs, VISION_MIN_TIMEOUT_MS));
  } catch (e) {
    throw new Error(`Could not reach ${name}: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (resp.status < 200 || resp.status >= 300) {
    throw new Error(`${name} could not read the photo (HTTP ${resp.status})`);
  }
  let obj: JsonRecord | null = null;
  try {
    obj = asRecord(JSON.parse(resp.body) as JsonValue);
  } catch (e) {
    obj = null;
  }
  if (obj === null) {
    throw new Error(`${name} returned an unexpected response`);
  }
  const parts: string[] = [];
  if (anthropic) {
    const content: JsonValue = obj['content'];
    if (Array.isArray(content)) {
      for (const block of content as JsonValue[]) {
        const blk = asRecord(block);
        if (blk !== null && blk['type'] === 'text' && typeof blk['text'] === 'string') {
          parts.push(blk['text'] as string);
        }
      }
    }
  } else {
    const choices: JsonValue = obj['choices'];
    const first = Array.isArray(choices) && (choices as JsonValue[]).length > 0 ? asRecord((choices as JsonValue[])[0]) :
      null;
    const message = first === null ? null : asRecord(first['message']);
    if (message !== null && typeof message['content'] === 'string') {
      parts.push(message['content'] as string);
    }
  }
  const text = parts.join('').trim();
  if (text.length === 0) {
    throw new Error(`${name} returned no text for the photo`);
  }
  return text;
}

// ---- Pipeline ----

/** On-device: read the photo, then the shared-text converters, then grounded slot-filling on what was read. */
export async function onDeviceFromImage(image: ImageInput, reader: OnDeviceImageReader): Promise<GenerateResult> {
  let text: string;
  try {
    text = (await reader.readImage(image.path)).trim();
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : IMAGE_NOT_UNDERSTOOD, details: [] };
  }
  if (text.length === 0) {
    return { ok: false, error: IMAGE_NOT_UNDERSTOOD, details: [] };
  }
  const shared = capsuleFromSharedText(text.substring(0, MAX_SHARED_TEXT));
  if (shared.ok && shared.capsule !== undefined) {
    return { ok: true, capsule: shared.capsule, origin: 'on-device', details: [] };
  }
  return reader.generate(text.substring(0, 500));
}

/** Cloud: the provider transcribes the photo; the cloud capsule model builds from it, the converters as fallback. */
async function cloudFromImage(image: ImageInput, model: CapsuleModel, config: ModelConfig,
  transport: HttpTransport): Promise<GenerateResult> {
  let text: string;
  try {
    text = await describeImage(config, transport, image);
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : IMAGE_NOT_UNDERSTOOD, details: [] };
  }
  // The capsule model first: the shared-text converters misread some transcripts (a receipt with only "TOTAL"
  // becomes a checklist, a workout with "rest" becomes recipe timers). If the model fails or refuses (small
  // models sometimes call a bare transcript "not an app"), the converter result is the fallback.
  const built = await model.generate(photoRequest(text.substring(0, MAX_SHARED_TEXT)), MAX_SHARED_TEXT + 200);
  if (built.ok) {
    return built;
  }
  const shared = capsuleFromSharedText(text.substring(0, MAX_SHARED_TEXT));
  if (shared.ok && shared.capsule !== undefined) {
    return { ok: true, capsule: shared.capsule, origin: cloudOrigin(config.provider), details: [] };
  }
  return built;
}

/**
 * Photo -> validated capsule under the policy above. `cloud` and `configs` are the configured providers in the
 * same order (default first); `transport` is null when no cloud is configured.
 */
export async function generateFromImageWith(image: ImageInput, onDevice: OnDeviceImageReader | null,
  cloud: CapsuleModel[], configs: ModelConfig[], transport: HttpTransport | null,
  options?: GenerateOptions): Promise<GenerateResult> {
  let onDeviceError = '';
  if (options?.cloudOnly !== true && onDevice !== null) {
    if (await onDevice.whenInitialised() && onDevice.isReady()) {
      const local = await onDeviceFromImage(image, onDevice);
      if (local.ok) {
        return local;
      }
      onDeviceError = local.error ?? '';
    }
  }
  const mode: GenerateMode = options?.mode ?? 'smart';
  const allowNonEu = options?.allowNonEu ?? false;
  if (mode === 'on-device-only') {
    return { ok: false, error: `${IMAGE_NOT_UNDERSTOOD} ${ON_DEVICE_ONLY}`, details: onDeviceError.length > 0 ?
      [onDeviceError] : [] };
  }
  const chosen = pickCloud(cloud, allowNonEu);
  if (options?.allowCloud === false) {
    return { ok: false, error: `${IMAGE_NOT_UNDERSTOOD} ${CLOUD_OFF}`, details: [], needsCloud: chosen !== null };
  }
  const config = chosen === null ? undefined : configs.find((c: ModelConfig) => c.provider === chosen.providerName);
  if (chosen === null || config === undefined || transport === null) {
    const why = cloud.length > 0 ? `The configured cloud provider (${cloud[0].providerName}) is outside the EU.` :
      AI_NOT_CONFIGURED;
    return { ok: false, error: `${IMAGE_NOT_UNDERSTOOD} ${why}`, details: onDeviceError.length > 0 ? [onDeviceError] :
      [] };
  }
  return cloudFromImage(image, chosen, config, transport);
}
