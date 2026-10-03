/**
 * App-facing entry point of the core. Wires the pure modules to the platform:
 * HTTP via @kit.NetworkKit (needs ohos.permission.INTERNET in module.json5) and the
 * API key from rawfile/config.local.json (git-ignored, never committed).
 *
 * Usage:
 *   await initCapsuleModel(context);   // once, e.g. in EntryAbility; rules work even if this fails
 *   const result = await generateCapsule('3 timers pasta 9 sauce 15 bread 6');
 */
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { GenerateResult } from './CapsuleTypes';
import { CapsuleModel } from './CapsuleModel';
import { generateCapsuleWith } from './CapsuleGenerator';
import { createProvider, HttpResponse, HttpTransport, ModelConfigResult, parseModelConfig } from './ModelProvider';

export * from './CapsuleTypes';
export { validateCapsule, validateCapsuleObject, parseAction, permissionForAction, permissionForComponent,
  componentId } from './CapsuleValidator';
export { parseRequest } from './RuleParser';

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

let model: CapsuleModel | null = null;
let modelError: string = 'initCapsuleModel() has not been called';

export async function loadModelConfig(context: common.Context): Promise<ModelConfigResult> {
  let bytes: Uint8Array;
  try {
    bytes = await context.resourceManager.getRawFileContent(CONFIG_FILE);
  } catch (e) {
    return { error: `${CONFIG_FILE} not found in resources/rawfile` };
  }
  return parseModelConfig(util.TextDecoder.create('utf-8').decodeToString(bytes));
}

/** Loads the model config. Returns false (and keeps rules-only mode) if it is missing or invalid. */
export async function initCapsuleModel(context: common.Context): Promise<boolean> {
  const loaded = await loadModelConfig(context);
  if (loaded.config === undefined) {
    model = null;
    modelError = loaded.error ?? 'unknown config error';
    return false;
  }
  model = new CapsuleModel(createProvider(loaded.config, new NetworkTransport()));
  modelError = '';
  return true;
}

/** Rule parser first, model as fallback. Returns a validated capsule or a clear error. */
export async function generateCapsule(request: string): Promise<GenerateResult> {
  return generateCapsuleWith(request, model, modelError);
}
