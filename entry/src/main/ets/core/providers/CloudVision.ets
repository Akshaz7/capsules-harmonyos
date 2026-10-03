/**
 * Photo -> capsule. Pure logic: the image bytes come in as an ImageInput and HTTP goes through HttpTransport,
 * so this file runs in unit tests and in scripts/eval-images.mjs as well as on the device.
 *
 * Policy (same consent rules as text, see CapsuleGenerator.ets):
 *   1. On device (unless cloudOnly): system OCR (Core Vision Kit) reads the text in the photo. The text goes
 *      through the shared-text converters (recipe, bill, workout, list), then the normal local text pipeline
 *      (rules, built-in templates, on-device model). Made this way, the capsule never touched the internet:
 *      origin "template" (badge "Made on your phone · no internet") or "on-device".
 *   2. OCR found text but nothing local could build it: only that text (not the photo) goes to the cloud
 *      capsule model, if the cloud may be used.
 *   3. OCR found no text: LFM2-VL would read the photo (off, see CactusProvider ON_DEVICE_VISION), then the
 *      photo itself goes to the cloud provider, which transcribes it (Mistral: Pixtral), and the cloud capsule
 *      model builds from the transcript (shared-text converters as fallback).
 *   Whenever the cloud is next: mode "on-device-only" stops; allowCloud false returns needsCloud (when a usable
 *   cloud provider is configured) so the app can ask first; nothing has left the device.
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

/** Reads the text in a photo on the device (system OCR). Throws if unavailable. */
export interface DeviceTextReader {
  readText(imagePath: string): Promise<string>;
}

/** The local text pipeline (rules, templates, on-device model; never the cloud) for text read from a photo. */
export type LocalTextPipeline = (text: string) => Promise<GenerateResult>;

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
/**
 * Mistral's vision model reads the photo; the configured model (e.g. ministral-14b) still builds the capsule.
 * Photo eval 2026-10-03: Pixtral reading + ministral building 8/10 correct, ministral doing both 5/10.
 */
export const MISTRAL_VISION_MODEL: string = 'pixtral-12b-latest';

/** The model that reads photos for this provider config. */
export function visionModel(config: ModelConfig): string {
  return config.provider === 'mistral' && !config.model.startsWith('pixtral') ? MISTRAL_VISION_MODEL : config.model;
}
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
      model: visionModel(config), max_tokens: VISION_MAX_TOKENS, messages: [{ role: 'user', content: [
        { type: 'image', source: { type: 'base64', media_type: image.mime, data: data } },
        { type: 'text', text: VISION_PROMPT }
      ] }]
    };
    body = JSON.stringify(b);
  } else {
    url = `${config.baseUrl}/chat/completions`;
    headers['authorization'] = `Bearer ${config.apiKey}`;
    const b: OpenAIVisionBody = {
      model: visionModel(config), max_tokens: VISION_MAX_TOKENS, messages: [{ role: 'user', content: [
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

/** Lines of OCR text joined into one request line for the rules, templates and the on-device model. */
export function oneLine(text: string): string {
  return text.split('\n').map((l: string) => l.trim()).filter((l: string) => l.length > 0).join('. ')
    .replace(/([.!?:;,])\./g, '$1').substring(0, 500);
}

/** OCR text -> capsule without the internet: shared-text converters, then the local text pipeline. */
export async function localFromPhotoText(text: string, localText: LocalTextPipeline | null): Promise<GenerateResult> {
  const shared = capsuleFromSharedText(text.substring(0, MAX_SHARED_TEXT));
  if (shared.ok && shared.capsule !== undefined) {
    return { ok: true, capsule: shared.capsule, origin: 'template', details: [] };
  }
  if (localText === null) {
    return { ok: false, error: IMAGE_NOT_UNDERSTOOD, details: [] };
  }
  const r = await localText(oneLine(text));
  if (r.ok && r.origin === 'rules') {
    return { ok: true, capsule: r.capsule, origin: 'template', details: [] }; // made on the phone, no internet
  }
  return r.ok ? r : { ok: false, error: r.error ?? IMAGE_NOT_UNDERSTOOD, details: r.details };
}

/** Why the cloud cannot be used now, as a failed result; null if it can (then `chosen` is set). */
function cloudBlocked(cloud: CapsuleModel[], chosen: CapsuleModel | null, why: string,
  options?: GenerateOptions): GenerateResult | null {
  const mode: GenerateMode = options?.mode ?? 'smart';
  const reasons: string[] = why.length > 0 ? [why] : [];
  if (mode === 'on-device-only') {
    return { ok: false, error: `${IMAGE_NOT_UNDERSTOOD} ${ON_DEVICE_ONLY}`, details: reasons };
  }
  if (options?.allowCloud === false) {
    return { ok: false, error: `${IMAGE_NOT_UNDERSTOOD} ${CLOUD_OFF}`, details: reasons, needsCloud: chosen !== null };
  }
  if (chosen === null) {
    const outside = cloud.length > 0 ? `The configured cloud provider (${cloud[0].providerName}) is outside the EU.` :
      AI_NOT_CONFIGURED;
    return { ok: false, error: `${IMAGE_NOT_UNDERSTOOD} ${outside}`, details: reasons };
  }
  return null;
}

/**
 * Photo -> validated capsule under the policy above. `ocr`: system OCR, or null. `localText`: the local text
 * pipeline. `cloud` and `configs` are the configured providers in the same order (default first); `transport`
 * is null when no cloud is configured.
 */
export async function generateFromImageWith(image: ImageInput, ocr: DeviceTextReader | null,
  localText: LocalTextPipeline | null, onDevice: OnDeviceImageReader | null, cloud: CapsuleModel[],
  configs: ModelConfig[], transport: HttpTransport | null, options?: GenerateOptions): Promise<GenerateResult> {
  const chosen = pickCloud(cloud, options?.allowNonEu ?? false);
  let localError = '';
  if (options?.cloudOnly !== true) {
    let text = '';
    if (ocr !== null) {
      try {
        text = (await ocr.readText(image.path)).trim();
      } catch (e) {
        localError = e instanceof Error ? e.message : String(e);
      }
    }
    if (text.length > 0) {
      const local = await localFromPhotoText(text, localText);
      if (local.ok) {
        return local;
      }
      const blocked = cloudBlocked(cloud, chosen, local.error ?? '', options);
      if (blocked !== null || chosen === null) {
        return blocked ?? { ok: false, error: IMAGE_NOT_UNDERSTOOD, details: [] };
      }
      return chosen.generate(photoRequest(text.substring(0, MAX_SHARED_TEXT)), MAX_SHARED_TEXT + 200); // text only
    }
    if (onDevice !== null && await onDevice.whenInitialised() && onDevice.isReady()) {
      const local = await onDeviceFromImage(image, onDevice);
      if (local.ok) {
        return local;
      }
      localError = local.error ?? localError;
    }
  }
  const blocked = cloudBlocked(cloud, chosen, localError, options);
  const config = chosen === null ? undefined : configs.find((c: ModelConfig) => c.provider === chosen.providerName);
  if (blocked !== null || chosen === null || config === undefined || transport === null) {
    return blocked ?? { ok: false, error: `${IMAGE_NOT_UNDERSTOOD} ${AI_NOT_CONFIGURED}`, details: [] };
  }
  return cloudFromImage(image, chosen, config, transport);
}
