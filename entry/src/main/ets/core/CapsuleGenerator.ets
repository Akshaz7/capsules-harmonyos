/**
 * Routes a request to the source that should build it. Every capsule returned has passed the validator.
 * Pure logic; the app-facing generateCapsule(request) lives in index.ets.
 *
 * Policy (mode "smart", the default):
 *   1. A built-in rule matches: use it. Nothing leaves the device.
 *   2. The request needs schema v1 logic (maths, scoring, converting, conditions, inputs, lists; see
 *      needsLogic) and a cloud provider may be used: ask the cloud first, since the on-device model
 *      only fills v0 slots. If the cloud fails, try on-device.
 *   3. Otherwise the on-device model; if it fails or is ungrounded, the cloud.
 * A cloud provider may be used only if it is in the EU (Mistral), or the caller allows non-EU providers.
 * Mode "on-device-only" never calls the cloud. Only the request text is ever sent to the cloud.
 */
import { GenerateResult } from './CapsuleTypes';
import { validateCapsule } from './CapsuleValidator';
import { parseRequest } from './RuleParser';
import { CapsuleModel } from './CapsuleModel';

export const NO_RULE_MATCH: string = 'No built-in rule understands this request.';
export const AI_NOT_CONFIGURED: string = 'AI fallback not configured.';
export const CLOUD_OFF: string = 'Cloud AI is turned off.';
export const ON_DEVICE_ONLY: string = 'On-device only mode is on.';

/** Anything that turns a request into a validated capsule (CapsuleModel, CactusProvider). */
export interface CapsuleSource {
  generate(request: string): Promise<GenerateResult>;
}

export type GenerateMode = 'smart' | 'on-device-only';

export interface GenerateOptions {
  /** "smart" (default): rules, then on-device and cloud as the policy says. "on-device-only": never the cloud. */
  mode?: GenerateMode;
  /** Allow providers outside the EU (Anthropic, OpenAI). Default false. */
  allowNonEu?: boolean;
  /** False blocks the cloud for this request, e.g. until the user has accepted the cloud notice. Default true. */
  allowCloud?: boolean;
}

/**
 * Words and patterns that need schema v1 (state, expressions, inputs, lists), which the on-device
 * slot-filler cannot build: maths, scoring, converting, conditions, inputs and lists.
 */
const LOGIC_PATTERNS: RegExp[] = [
  /\b(calculat\w*|comput\w*|maths?|sum|total|average|percent\w*|split|tip|tips|bmi|each|per person)\b/i,
  /\b(scor\w*|scoreboard|points?|darts|tennis|ping ?pong|leaderboard|tally of|quiz\w*)\b/i,
  /\b(convert\w*|km|kilomet\w*|miles?|celsius|fahrenheit|kg|lbs?|pounds?|currency|exchange rate)\b/i,
  /\b(if|unless|otherwise|when)\b/i,
  /\b(type|enter|input)\b/i,
  /\b(add (items?|things|it) to|shopping list|to-?do list|list (that|where|of things))\b/i,
  /%|\d\s*[-+*/x×]\s*\d/
];

export function needsLogic(request: string): boolean {
  return LOGIC_PATTERNS.some((p: RegExp) => p.test(request));
}

/** The cloud model to use under the policy: the first EU provider, else a non-EU one only if allowed. */
function pickCloud(models: CapsuleModel[], allowNonEu: boolean): CapsuleModel | null {
  const eu = models.find((m: CapsuleModel) => m.isEu);
  if (eu !== undefined) {
    return eu;
  }
  return allowNonEu && models.length > 0 ? models[0] : null;
}

function failure(why: string[]): GenerateResult {
  const reasons = why.filter((w: string) => w.length > 0);
  return { ok: false, error: `${NO_RULE_MATCH} ${reasons.length > 0 ? reasons.join(' ') : AI_NOT_CONFIGURED}`,
    details: [] };
}

/**
 * `cloud`: the configured cloud models, default provider first. `modelUnavailableReason`: empty or
 * omitted means no config was found (the normal state for the public .hap); otherwise it explains why a
 * config that exists could not be used.
 */
export async function generateCapsuleWith(request: string, cloud: CapsuleModel[],
  modelUnavailableReason?: string, onDevice?: CapsuleSource | null, options?: GenerateOptions): Promise<GenerateResult> {
  if (request.trim().length === 0) {
    return { ok: false, error: 'The request is empty.', details: [] };
  }
  const fromRules = parseRequest(request);
  if (fromRules !== null) {
    const v = validateCapsule(JSON.stringify(fromRules));
    if (v.ok) {
      return { ok: true, capsule: v.capsule, origin: 'rules', details: [] };
    }
    // A rule produced an invalid capsule (a bug); fall through to the models rather than return it.
  }

  const mode: GenerateMode = options?.mode ?? 'smart';
  const allowNonEu = options?.allowNonEu ?? false;
  const cloudBlocked = mode === 'on-device-only' || options?.allowCloud === false;
  const chosen = cloudBlocked ? null : pickCloud(cloud, allowNonEu);
  let cloudWhy = '';
  if (mode === 'on-device-only') {
    cloudWhy = ON_DEVICE_ONLY;
  } else if (options?.allowCloud === false) {
    cloudWhy = CLOUD_OFF;
  } else if (chosen === null && cloud.length > 0) {
    cloudWhy = `The configured cloud provider (${cloud[0].providerName}) is outside the EU; ` +
      'allow non-EU providers in settings to use it.';
  } else if (chosen === null) {
    cloudWhy = modelUnavailableReason !== undefined && modelUnavailableReason.length > 0 ?
      `AI fallback unavailable: ${modelUnavailableReason}` : AI_NOT_CONFIGURED;
  }

  let cloudResult: GenerateResult | null = null;
  if (chosen !== null && needsLogic(request)) {
    cloudResult = await chosen.generate(request);
    if (cloudResult.ok) {
      return cloudResult;
    }
  }

  let onDeviceError = '';
  if (onDevice !== undefined && onDevice !== null) {
    const local = await onDevice.generate(request);
    // Re-check here so the "always validated" promise holds whatever source is plugged in.
    const checked = local.ok && local.capsule !== undefined ? validateCapsule(JSON.stringify(local.capsule)) : null;
    if (checked !== null && checked.ok) {
      return { ok: true, capsule: checked.capsule, origin: 'on-device', details: [] };
    }
    onDeviceError = checked !== null ? 'The on-device model produced an invalid capsule.' : (local.error ?? '');
  }

  if (cloudResult !== null) {
    return cloudResult; // the cloud already tried and failed; on-device could not help either
  }
  if (chosen !== null) {
    return chosen.generate(request);
  }
  return failure([onDeviceError, cloudWhy]);
}
