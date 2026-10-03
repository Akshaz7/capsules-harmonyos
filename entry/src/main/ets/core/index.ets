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
import { AI_NOT_CONFIGURED, generateCapsuleWith } from './CapsuleGenerator';
import { createProvider, HttpResponse, HttpTransport, ModelConfigResult, parseModelConfig } from './ModelProvider';

export * from './CapsuleTypes';
export { validateCapsule, validateCapsuleObject, parseAction, permissionForAction, permissionForComponent,
  componentId } from './CapsuleValidator';
export { parseRequest } from './RuleParser';
export { AI_NOT_CONFIGURED, NO_RULE_MATCH } from './CapsuleGenerator';
export { CapsuleRoute, routeCapsule, MAX_WIDGET_COMPONENTS, MAX_WIDGET_CHECKLIST_ITEMS } from './CapsuleRouter';

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
}

let model: CapsuleModel | null = null;
let modelError: string = 'initCapsuleModel() has not been called';
let status: ModelStatus = { configured: false, source: 'none', message: AI_NOT_CONFIGURED };

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
  model = null;
  const found = await readConfigText(context);
  if (found === null) {
    modelError = '';
    status = { configured: false, source: 'none', message: AI_NOT_CONFIGURED };
    return false;
  }
  const loaded = parseModelConfig(found.text);
  if (loaded.config === undefined) {
    modelError = loaded.error ?? 'unknown config error';
    status = { configured: false, source: found.source, message: `AI fallback unavailable: ${modelError}` };
    return false;
  }
  model = new CapsuleModel(createProvider(loaded.config, new NetworkTransport()));
  modelError = '';
  status = { configured: true, source: found.source, message: 'AI fallback ready.' };
  return true;
}

/** Whether the AI fallback is available, and where its config came from. */
export function getModelStatus(): ModelStatus {
  return status;
}

/** Rule parser first, model as fallback. Returns a validated capsule or a clear error. */
export async function generateCapsule(request: string): Promise<GenerateResult> {
  return generateCapsuleWith(request, model, modelError);
}
