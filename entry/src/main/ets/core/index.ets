/**
 * App-facing entry point of the core. Wires the pure modules to the platform:
 * HTTP via @kit.NetworkKit (needs ohos.permission.INTERNET in module.json5) and the
 * model config file config.local.json (git-ignored, never committed), looked up in order:
 *   1. the app's files dir on the device (not inside the .hap), pushed with
 *      hdc file send -b com.hackyeah.capsules config.local.json data/storage/el2/base/files/
 *   2. resources/rawfile/config.local.json (packed INTO the .hap: dev builds only, never ship it)
 * With no config file the app runs rules-only and reports "AI fallback not configured."
 *
 * Usage:
 *   await initCapsuleModel(context);   // once, e.g. in EntryAbility; rules work even if this fails
 *   const result = await generateCapsule('3 timers pasta 9 sauce 15 bread 6');
 */
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { GenerateResult } from './CapsuleTypes';
import { CapsuleModel } from './CapsuleModel';
import {
  AI_NOT_CONFIGURED, CapsuleSource, GenerateOptions, generateCapsuleWith, generateFromSharedTextWith, LocalSources, pickCloud,
  routesLive
} from './CapsuleGenerator';
import { parseRequest } from './RuleParser';
import {
  createProvider, HttpResponse, HttpTransport, isEuProvider, ModelConfig, ModelConfigResult, parseModelConfig, ProviderName,
  parseModelConfigs
} from './ModelProvider';
import { getMarketOptions, getRequestCache, getTemplateLibrary } from './templates';
import { LiveCapsuleSource } from './LiveCapsule';
import { allowsNonEu, CLOUD_CLAUDE_ONLY, readyMessage, usableConfigs } from './CloudPolicy';
import { WeatherAdapter } from '../adapters/WeatherAdapter';
import { cityName, weatherLabel } from '../capabilities/WeatherData';
import { CactusProvider, DeviceOcr, loadImage, OnDeviceStatus, runPhotoEvalIfRequested } from './providers/CactusProvider';
import { generateFromImageWith } from './providers/CloudVision';
import { runSpeechEvalIfRequested } from './providers/SpeechInput';
export { LIVE_MODEL, needsLiveInfo } from './LiveCapsule';

export * from './CapsuleTypes';
export { validateCapsule, validateCapsuleObject, parseAction, permissionForAction, permissionForComponent,
  componentId } from './CapsuleValidator';
export { parseRequest } from './RuleParser';
export { AI_NOT_CONFIGURED, NO_RULE_MATCH, CLOUD_OFF, ON_DEVICE_ONLY, GenerateMode, GenerateOptions, needsLogic
} from './CapsuleGenerator';
export { BuildStage, BuildStageName, StageListener } from './BuildStage';
export { isEuProvider, cloudOrigin, ProviderName } from './ModelProvider';
export { isNotEnglish, UNSUPPORTED_LANGUAGE, UNSUPPORTED_LANGUAGE_MESSAGE } from './Language';
export {
  DueTriggers, dueTimeTriggers, motionTriggers, nextFireTime, permissionForTrigger, runTrigger, scheduledOn,
  TriggerGuard, triggerKey, TriggerRun
} from './Triggers';
export {
  capsuleFromSharedText, MAX_SHARED_TEXT, SharedKind, SharedTextResult, SHARED_EMPTY, SHARED_NOT_RECOGNISED,
  SHARED_TOO_LONG
} from './SharedText';
export { OnDeviceStatus } from './providers/CactusProvider';
export { initTemplates, matchTemplate, matchTemplateAsync, getTemplateLibrary, getRequestCache, TEMPLATE_BADGE,
  TEMPLATE_ORIGIN } from './templates';
export { cleanTranscript, MIC_OFF, VoiceInput, VOICE_LANGUAGE, VOICE_NOTHING_HEARD, VOICE_PERMISSION,
  VOICE_UNAVAILABLE, voiceErrorMessage } from './providers/SpeechInput';
export { IMAGE_NOT_READABLE, IMAGE_NOT_UNDERSTOOD, IMAGE_TOO_LARGE, IMAGE_UNSUPPORTED, MAX_IMAGE_BYTES
} from './providers/CloudVision';
export { CapsuleRoute, routeCapsule, MAX_WIDGET_COMPONENTS, MAX_WIDGET_CHECKLIST_ITEMS } from './CapsuleRouter';
export { StateValues, EvalResult, ApplyResult, DISPLAY_ERROR, initialState, restoreState, evaluate, computedValues,
  renderTemplate, isShown, isEnabled, listItems, inputText, applyActions, setInput, allComponents } from './CapsuleProgram';
export { formatValue, MAX_EXPR_LENGTH, MAX_TEXT_LENGTH, MAX_LIST_ITEMS } from './Expr';
export { TENNIS_CAPSULE, BILL_SPLIT_CAPSULE } from './V1Fixtures';
export * from './edit';

const CONFIG_FILE: string = 'config.local.json';

class NetworkTransport implements HttpTransport {
  async post(url: string, headers: Record<string, string>, body: string, timeoutMs: number): Promise<HttpResponse> {
    let req: http.HttpRequest | null = null;
    try {
      req = http.createHttp();
      const resp = await req.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING
      });
      const result: HttpResponse = { status: resp.responseCode, body: typeof resp.result === 'string' ? resp.result : '' };
      return result;
    } finally {
      req?.destroy();
    }
  }
}

export type ConfigSource = 'files' | 'rawfile' | 'none';

export interface ModelStatus {
  configured: boolean;
  source: ConfigSource;
  /** User-facing status, e.g. "AI fallback not configured." */
  message: string;
  /** Configured cloud providers, default first, e.g. ["mistral", "anthropic"]. */
  providers: string[];
  /** True if an EU provider is configured, so smart mode can use the cloud without the non-EU setting. */
  euAvailable: boolean;
  /** The config's default provider, or 'none'. Which one a request uses: see activeCloudProvider(). */
  provider: ProviderName | 'none';
}

let models: CapsuleModel[] = [];
let modelConfigs: ModelConfig[] = []; // same order as models; the photo path needs them to send images
let cloudTransport: HttpTransport | null = null;
let modelError: string = 'initCapsuleModel() has not been called';
let status: ModelStatus = {
  configured: false, source: 'none', message: AI_NOT_CONFIGURED, providers: [], euAvailable: false, provider: 'none'
};
const onDevice: CactusProvider = new CactusProvider();
const deviceOcr: DeviceOcr = new DeviceOcr();

interface ConfigText {
  source: ConfigSource;
  text: string;
}

/** Reads config.local.json from the app files dir, then rawfile. Returns null if neither has it. */
async function readConfigText(context: common.Context): Promise<ConfigText | null> {
  const dirs: string[] = [context.getApplicationContext().filesDir, context.filesDir];
  for (const dir of dirs) {
    const path = `${dir}/${CONFIG_FILE}`;
    try {
      if (fileIo.accessSync(path)) {
        const fromFiles: ConfigText = { source: 'files', text: fileIo.readTextSync(path) };
        return fromFiles;
      }
    } catch (e) {
      // unreadable: try the next location
    }
  }
  try {
    const bytes = await context.resourceManager.getRawFileContent(CONFIG_FILE);
    const fromRawfile: ConfigText = { source: 'rawfile', text: util.TextDecoder.create('utf-8').decodeToString(bytes) };
    return fromRawfile;
  } catch (e) {
    return null; // not packed: the normal case for the public .hap
  }
}

/** Loads the model config. `error` is undefined and `config` undefined when no config file exists. */
export async function loadModelConfig(context: common.Context): Promise<ModelConfigResult> {
  const found = await readConfigText(context);
  return found === null ? {} : parseModelConfig(found.text);
}

/**
 * Loads the model config. Returns false and keeps rules-only mode if it is missing or invalid.
 * Never throws.
 */
export async function initCapsuleModel(context: common.Context): Promise<boolean> {
  onDevice.init(context); // loads the on-device model in the background; never throws
  setTimeout(() => { // debug-only phone photo eval; runs only if scripts/phone-photo-eval.sh pushed its marker
    runPhotoEvalIfRequested(context, onDevice, deviceOcr,
      (path: string, allowCloud: boolean) => generateCapsuleFromImage(path, { allowCloud: allowCloud }));
    runSpeechEvalIfRequested(context); // likewise for scripts/phone-speech-eval.sh
  }, 3000);
  models = [];
  modelConfigs = [];
  cloudTransport = null;
  const found = await readConfigText(context);
  if (found === null) {
    modelError = '';
    status = {
      configured: false, source: 'none', message: AI_NOT_CONFIGURED, providers: [], euAvailable: false, provider: 'none'
    };
    return false;
  }
  const loaded = parseModelConfigs(found.text);
  // T4-31: Claude is the only cloud provider; other entries in the config are ignored.
  const usable = usableConfigs(loaded.configs, CLOUD_CLAUDE_ONLY);
  if (loaded.defaultConfig !== undefined && usable.length === 0) {
    modelError = '';
    status = {
      configured: false, source: found.source, message: AI_NOT_CONFIGURED, providers: [], euAvailable: false, provider: 'none'
    };
    return false;
  }
  if (loaded.defaultConfig === undefined) {
    modelError = loaded.error ?? 'unknown config error';
    status = {
      configured: false, source: found.source, message: `AI fallback unavailable: ${modelError}`, providers: [],
      euAvailable: false, provider: 'none'
    };
    return false;
  }
  const chosen = usable.includes(loaded.defaultConfig) ? loaded.defaultConfig : usable[0];
  const ordered: ModelConfig[] = [chosen].concat(usable.filter((c: ModelConfig) => c !== chosen));
  const transport = new NetworkTransport();
  models = ordered.map((c: ModelConfig) => new CapsuleModel(createProvider(c, transport)));
  modelConfigs = ordered;
  cloudTransport = transport;
  modelError = '';
  const names = ordered.map((c: ModelConfig) => c.provider as string);
  const eu = ordered.some((c: ModelConfig) => isEuProvider(c.provider));
  status = {
    configured: true, source: found.source, providers: names, euAvailable: eu, provider: chosen.provider,
    message: readyMessage(names.map((n: string) => isEuProvider(n as ProviderName) ? `${n} (EU)` : n), CLOUD_CLAUDE_ONLY)
  };
  return true;
}

/** Whether the AI fallback is available, and where its config came from. */
export function getModelStatus(): ModelStatus {
  return status;
}

/**
 * The cloud provider generateCapsule would use in smart mode: an EU provider (Mistral) if one is configured,
 * otherwise the default provider only when `allowNonEu` is true; 'none' if the cloud cannot be used.
 */
export function activeCloudProvider(allowNonEu: boolean): ProviderName | 'none' {
  const m = pickCloud(models, allowNonEu);
  return m === null ? 'none' : m.providerName;
}

/** On-device model status: "On-device AI ready", "On-device model not installed", ... */
export function getOnDeviceStatus(): OnDeviceStatus {
  return onDevice.getStatus();
}

/** Waits for the on-device model only when the route actually asks it. */
class LazyOnDevice implements CapsuleSource {
  async generate(request: string): Promise<GenerateResult> {
    await onDevice.whenInitialised();
    if (!onDevice.isReady()) {
      const notReady: GenerateResult = { ok: false, error: '', details: [] };
      return notReady;
    }
    return onDevice.generate(request);
  }
}

const lazyOnDevice: LazyOnDevice = new LazyOnDevice();

// ---- Live capsules (T4-23) ----

const liveWeather: WeatherAdapter = new WeatherAdapter();

/** The forecast line for the live prompt: "14°C, Light rain, wind 12 km/h"; null when offline. */
async function forecastLine(cityId: string): Promise<string | null> {
  const r = await liveWeather.refresh(cityId, Date.now());
  const w = r.reading;
  return w === null ? null : `${Math.round(w.tempC)}°C, ${weatherLabel(w.code)}, wind ${Math.round(w.windKmh)} km/h in ${cityName(cityId)}`;
}

/** Claude with the forecast / web search; with no Anthropic key it returns the rules capsule (see LiveCapsule). */
function liveSource(): CapsuleSource {
  const config = modelConfigs.find((c: ModelConfig) => c.provider === 'anthropic') ?? null;
  return new LiveCapsuleSource(config, cloudTransport ?? new NetworkTransport(), forecastLine);
}

/** The provider live capsules use (its consent key in the app). */
export const LIVE_PROVIDER: string = 'anthropic';

/**
 * True when generateCapsule would build this request live with Claude (T4-28): it needs live information, smart
 * mode, non-EU allowed, and an Anthropic key is configured. The app asks for Claude consent BEFORE building
 * such a request (the rules would otherwise answer it without asking, and live would never run).
 */
export function routesLiveRequest(request: string, smart: boolean, allowNonEu: boolean): boolean {
  return smart && modelConfigs.some((c: ModelConfig) => c.provider === 'anthropic' && c.apiKey.length > 0) &&
    routesLive(request, { mode: 'smart', allowNonEu: allowsNonEu(allowNonEu, CLOUD_CLAUDE_ONLY) });
}

/** T4-31: with Claude only, the provider notice is the consent, so non-EU is allowed (see CloudPolicy). */
function withPolicy(options?: GenerateOptions): GenerateOptions {
  const o: GenerateOptions = options === undefined ? {} : options;
  const out: GenerateOptions = {
    mode: o.mode, allowNonEu: allowsNonEu(o.allowNonEu, CLOUD_CLAUDE_ONLY), allowCloud: o.allowCloud,
    cloudOnly: o.cloudOnly, skipTemplates: o.skipTemplates, onStage: o.onStage
  };
  return out;
}

/** The on-device model fills template slots the rules missed; throws when it is not ready. */
async function onDeviceSlots(prompt: string): Promise<string> {
  await onDevice.whenInitialised();
  if (!onDevice.isReady()) {
    throw new Error(onDevice.getStatus().message);
  }
  return onDevice.completePrompt(prompt, 120);
}

/**
 * Routes a request: the request cache, rules, built-in templates and the live marketplace, then on-device and the cloud as the policy
 * in CapsuleGenerator.ets says (mode "smart" by default; the cloud only with EU providers unless
 * options.allowNonEu). Returns a validated capsule or a clear error. Only the request text is sent to a cloud
 * provider. Model-made capsules are cached for the same request; "Make it smarter" (cloudOnly) skips the cache
 * and replaces the cached capsule.
 */
export async function generateCapsule(request: string, opts?: GenerateOptions): Promise<GenerateResult> {
  const options = withPolicy(opts);
  const cache = getRequestCache();
  const local: LocalSources = {
    cache: cache, library: getTemplateLibrary(), slotModel: onDeviceSlots, market: getMarketOptions(), live: liveSource()
  };
  const r = await generateCapsuleWith(request, models, modelError, lazyOnDevice, options, local);
  if (r.ok && r.capsule !== undefined && r.origin !== undefined && r.origin !== 'rules' && r.origin !== 'template' &&
    !routesLive(request, options)) { // live capsules are never cached
    cache.put(request, r.capsule, r.origin); // async; a failed write only means it is made again next time
  }
  return r;
}

/**
 * Text shared into the app (share sheet) -> capsule: recipes become timers, chats with amounts a live bill
 * split, workouts a checklist with timers, lists a checklist; anything else goes to the cloud under the same
 * policy as generateCapsule. Rejects text over MAX_SHARED_TEXT (2000) characters. Nothing is saved here:
 * show the result on the consent screen like any capsule.
 */
export async function generateCapsuleFromSharedText(text: string, options?: GenerateOptions): Promise<GenerateResult> {
  return generateFromSharedTextWith(text, models, withPolicy(options));
}

/**
 * Photo -> capsule. `imagePath`: a JPEG, PNG or WebP file in the app sandbox (max 5 MB), e.g. a camera or
 * picker photo copied into context.cacheDir. The system OCR reads its text on the phone and the local text pipeline
 * builds it (origin "template": badge "Made on your phone · no internet", or "on-device"). Otherwise the OCR text,
 * or the photo if OCR found none, goes to the cloud provider under the same policy as generateCapsule: never in mode "on-device-only", and with
 * allowCloud false the result has needsCloud true (ask the user, then retry with allowCloud true).
 * The result is validated like any capsule; nothing is saved here.
 */
export async function generateCapsuleFromImage(imagePath: string, options?: GenerateOptions): Promise<GenerateResult> {
  const image = loadImage(imagePath);
  if (typeof image === 'string') {
    const failed: GenerateResult = { ok: false, error: image, details: [] };
    return failed;
  }
  const localText = (text: string): Promise<GenerateResult> => generateCapsuleWith(text, models, modelError, lazyOnDevice,
    { mode: 'on-device-only' }, { library: getTemplateLibrary(), slotModel: onDeviceSlots });
  return generateFromImageWith(image, deviceOcr, localText, onDevice, models, modelConfigs, cloudTransport,
    withPolicy(options));
}
