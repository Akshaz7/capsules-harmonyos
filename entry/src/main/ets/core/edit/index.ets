/**
 * App-facing editCapsule. Uses the same model config (config.local.json in the app's files dir, then rawfile)
 * and the same providers as generateCapsule; the routing policy is in EditCapsule.ets.
 *
 * Usage:
 *   const r = await editCapsule(context, entry.capsule, 'make the timer 1 minute', { allowCloud: consented });
 *   // show r.summary; on Apply: consent again if r.needsConsent, save r.capsule, carryState(...)
 */
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { Capsule } from '../CapsuleTypes';
import { GenerateOptions } from '../CapsuleGenerator';
import { createProvider, HttpResponse, HttpTransport, ModelConfig, ModelProvider, parseModelConfigs } from '../ModelProvider';
import { editCapsuleWith, EditResult } from './EditCapsule';

export {
  carryState, carryValues, EDIT_EMPTY, EDIT_NEEDS_CLOUD, EDIT_NO_CHANGE, EDIT_TOO_LONG, editCapsuleWith, EditResult,
  editSummary, MAX_INSTRUCTION_LENGTH, minutesText, needsNewConsent
} from './EditCapsule';
export { ruleEdit } from './EditRules';

const CONFIG_FILE: string = 'config.local.json';

class EditTransport implements HttpTransport {
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

interface Loaded {
  providers: ModelProvider[];
  error: string;
}

let loaded: Loaded | null = null;

async function configText(context: common.Context): Promise<string | null> {
  const dirs: string[] = [context.getApplicationContext().filesDir, context.filesDir];
  for (const dir of dirs) {
    const path = `${dir}/${CONFIG_FILE}`;
    try {
      if (fileIo.accessSync(path)) {
        return fileIo.readTextSync(path);
      }
    } catch (e) {
      // unreadable: try the next location
    }
  }
  try {
    const bytes = await context.resourceManager.getRawFileContent(CONFIG_FILE);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  } catch (e) {
    return null;
  }
}

/** The configured providers, default first; read once. */
async function providersFor(context: common.Context): Promise<Loaded> {
  if (loaded !== null) {
    return loaded;
  }
  const text = await configText(context);
  if (text === null) {
    loaded = { providers: [], error: '' };
    return loaded;
  }
  const parsed = parseModelConfigs(text);
  const chosen = parsed.defaultConfig;
  if (chosen === undefined) {
    loaded = { providers: [], error: parsed.error ?? 'unknown config error' };
    return loaded;
  }
  const transport = new EditTransport();
  const ordered: ModelConfig[] = [chosen].concat(parsed.configs.filter((c: ModelConfig) => c !== chosen));
  loaded = { providers: ordered.map((c: ModelConfig) => createProvider(c, transport)), error: '' };
  return loaded;
}

/**
 * Changes `capsule` as the English `instruction` says. Rules first (nothing leaves the phone); the cloud
 * only under `options` (mode, allowNonEu, allowCloud) like generateCapsule. Never throws; nothing is saved.
 */
export async function editCapsule(context: common.Context, capsule: Capsule, instruction: string,
  options?: GenerateOptions): Promise<EditResult> {
  try {
    const found = await providersFor(context);
    return await editCapsuleWith(capsule, instruction, found.providers, options, found.error);
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    const r: EditResult = {
      ok: false, previous: capsule, summary: [], needsConsent: false, error: `The change failed: ${reason}`, details: []
    };
    return r;
  }
}
