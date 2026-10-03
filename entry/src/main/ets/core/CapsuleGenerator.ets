/**
 * Routes a request to the source that should build it. Every capsule returned has passed the validator.
 * Pure logic; the app-facing generateCapsule(request) lives in index.ets.
 *
 * Policy (mode "smart", the default):
 *   0. The same request made a capsule before (request cache): reuse it.
 *   1. A built-in rule matches: use it. Nothing leaves the device.
 *   1b. A built-in template explains the request (core/templates): fill it on the phone (origin "template"),
 *       or a better-scoring live marketplace capsule (origin "community"; 1.5 s budget, skipped offline).
 *   2. The request implies logic the on-device templates cannot express (scoring, converters, calculators,
 *      quizzes, streaks, conditions, inputs, lists; see needsLogic) and a cloud provider may be used: ask
 *      the cloud first. If the cloud fails, try on-device. If the cloud is configured but this call does
 *      not allow it (allowCloud false), return needsCloud instead of a simplified on-device capsule.
 *   3. Otherwise the on-device model; if it fails or is ungrounded, the cloud.
 * A cloud provider may be used only if it is in the EU (Mistral), or the caller allows non-EU providers.
 * Mode "on-device-only" never calls the cloud. Option cloudOnly skips rules and on-device (same cloud
 * policy). Only the request text is ever sent to the cloud.
 */
import { CapsuleOrigin, GenerateResult } from './CapsuleTypes';
import { validateCapsule } from './CapsuleValidator';
import { parseRequest } from './RuleParser';
import { CapsuleModel } from './CapsuleModel';
import { isNotEnglish, UNSUPPORTED_LANGUAGE_MESSAGE } from './Language';
import { TemplateLibrary, TemplateMatch } from './templates/TemplateLibrary';
import { MarketOptions, matchTemplateAsync } from './templates/MarketMatch';
import { fillUnclearSlots, SlotModel } from './templates/SlotFill';
import { RequestCache } from './templates/RequestCache';
import { capsuleFromSharedText, MAX_SHARED_TEXT, SHARED_EMPTY, SHARED_NOT_RECOGNISED, SHARED_TOO_LONG } from './SharedText';

export const NO_RULE_MATCH: string = 'No built-in rule understands this request.';
export const AI_NOT_CONFIGURED: string = 'AI fallback not configured.';
export const CLOUD_OFF: string = 'Cloud AI is turned off.';
export const ON_DEVICE_ONLY: string = 'On-device only mode is on.';

/** Anything that turns a request into a validated capsule (CapsuleModel, CactusProvider). */
export interface CapsuleSource {
  generate(request: string): Promise<GenerateResult>;
}

export type GenerateMode = 'smart' | 'on-device-only';

/** Local sources tried before the models (all optional): the request cache, then built-in templates. */
export interface LocalSources {
  cache?: RequestCache;
  library?: TemplateLibrary;
  /** The on-device model, to fill template slots the rules missed. */
  slotModel?: SlotModel;
  /** The live marketplace, searched with the templates (1.5 s budget; skipped offline or without a base URL). */
  market?: MarketOptions;
}

export interface GenerateOptions {
  /** "smart" (default): rules, then on-device and cloud as the policy says. "on-device-only": never the cloud. */
  mode?: GenerateMode;
  /** Allow providers outside the EU (Anthropic, OpenAI). Default false. */
  allowNonEu?: boolean;
  /** False blocks the cloud for this request, e.g. until the user has accepted the cloud notice. Default true. */
  allowCloud?: boolean;
  /**
   * Skip the rules and the on-device model and ask the cloud directly (e.g. "Make it smarter").
   * Still respects mode, allowNonEu and allowCloud: if the cloud may not be used, it fails with the reason.
   */
  cloudOnly?: boolean;
}

/**
 * Requests that imply rules or logic the on-device templates (plain timers, counters, checklists)
 * cannot express, so smart mode sends them to the cloud first: sports and game scoring, converters,
 * calculators, quizzes, streaks, conditions ("if", "per", "%", "track ... and tell me"), inputs and lists.
 */
const LOGIC_PATTERNS: RegExp[] = [
  // calculators and maths
  /\b(calculat\w*|comput\w*|maths?|sum|total|average|percent\w*|split|tips?|bmi|each|per|budget|discount|tax|interest|loan|price|cost)\b/i,
  // sports and game scoring
  /\b(scor\w*|points?|players?|teams?|leaderboard|winner|tennis|darts|golf|bowling|cricket|football|soccer|basketball|volleyball|badminton|squash|padel|ping ?pong|chess|poker|cards|board ?game|match|tally of)\b/i,
  /\bgames?\b.*\b(track\w*|keep\w*|count\w*|record\w*)\b/i,
  // converters
  /\b(convert\w*|km|kilomet\w*|miles?|celsius|fahrenheit|kg|lbs?|pounds?|inch(es)?|cm|feet|litres?|liters?|gallons?|ounces?|currency|exchange rate)\b/i,
  // quizzes
  /\b(quiz\w*|trivia|flash ?cards?|test me|guess)\b/i,
  // streaks and records
  /\b(streaks?|in a row|consecutive|personal best|record)\b/i,
  // conditions and feedback
  /\b(if|unless|otherwise|warn me|alert me)\b/i,
  /\btrack\w*\b.*\b(tell|show|warn|alert|let) me\b/i,
  // inputs and lists
  /\b(type|enter|input)\b/i,
  /\b(add (items?|things|it) to|shopping list|to-?do list|list (that|where|of things))\b/i,
  /%|\d\s*[-+*/x×]\s*\d/,
  // runtime actions capsules cannot perform: the cloud plan step reports them instead of a weaker capsule.
  // Only clear actions: photos, cameras, recipes from the web or files in a request are fine (they go to the
  // vision path or just describe the app).
  /\b(send (an? )?(sms|texts?|text messages?|e-?mails?|money)|sms|text (my|them|everyone|all)|(make|place) (a )?(phone )?calls?|phone calls?|call (my|them|everyone|all)|read (my |all )?contacts|my contacts|e-?mail (me|them|my|people)|browse|websites?|web pages?|payments?|pay (for|my|bills?)|transfer money)\b/i
];

export function needsLogic(request: string): boolean {
  return LOGIC_PATTERNS.some((p: RegExp) => p.test(request));
}

/** Smart mode asks the cloud before the on-device templates: logic they cannot express. */
export function cloudFirst(request: string): boolean {
  return needsLogic(request);
}

/** The failure for a request that is not in English (see Language.ets). */
export function unsupportedLanguage(): GenerateResult {
  return { ok: false, failure: 'unsupported-language', error: UNSUPPORTED_LANGUAGE_MESSAGE, details: [] };
}

/** The cloud model to use under the policy: the first EU provider, else a non-EU one only if allowed. */
export function pickCloud(models: CapsuleModel[], allowNonEu: boolean): CapsuleModel | null {
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
  modelUnavailableReason?: string, onDevice?: CapsuleSource | null, options?: GenerateOptions,
  local?: LocalSources): Promise<GenerateResult> {
  if (request.trim().length === 0) {
    return { ok: false, error: 'The request is empty.', details: [] };
  }
  if (isNotEnglish(request)) {
    return unsupportedLanguage(); // before the rules and every model: nothing is sent anywhere
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

  if (options?.cloudOnly === true) {
    return chosen !== null ? chosen.generate(request) : { ok: false, error: cloudWhy, details: [] };
  }

  const cached = local?.cache !== undefined ? local.cache.get(request) : null;
  if (cached !== null) {
    return { ok: true, capsule: cached.capsule, origin: cached.origin as CapsuleOrigin, details: [] };
  }

  const fromRules = parseRequest(request);
  if (fromRules !== null) {
    const v = validateCapsule(JSON.stringify(fromRules));
    if (v.ok) {
      return { ok: true, capsule: v.capsule, origin: 'rules', details: [] };
    }
    // A rule produced an invalid capsule (a bug); fall through to the models rather than return it.
  }

  // A built-in template or a marketplace capsule that explains the whole request, without a model.
  let template: TemplateMatch | null = local?.library !== undefined ?
    await matchTemplateAsync(local.library, request, local.market) : null;
  if (template !== null) {
    if (template.unfilledSlots.length > 0 && local?.slotModel !== undefined) {
      template = await fillUnclearSlots(template, request, local.slotModel); // never worse than the rules' values
    }
    return { ok: true, capsule: template.capsule, origin: template.origin, details: [] };
  }

  const logic = cloudFirst(request);
  if (logic && mode === 'smart' && options?.allowCloud === false) {
    // The on-device templates would build a wrong, simplified capsule (e.g. two counters for tennis).
    // If an EU provider could do it, say so instead, so the app can ask and retry with the cloud.
    const eu = pickCloud(cloud, allowNonEu);
    if (eu !== null) {
      return {
        ok: false, needsCloud: true, details: [],
        error: `${NO_RULE_MATCH} This request needs Cloud AI (${eu.providerName}${eu.isEu ? ', EU' : ''}). ${CLOUD_OFF}`
      };
    }
  }

  let cloudResult: GenerateResult | null = null;
  if (chosen !== null && logic) {
    cloudResult = await chosen.generate(request);
    if (cloudResult.ok || cloudResult.failure !== undefined) {
      return cloudResult; // a refusal (nonsense, unsupported) must not become a weaker on-device capsule
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

/** What the cloud model is asked when shared text matches no built-in kind. */
export function sharedTextRequest(text: string): string {
  return `Make a capsule from this text the user shared with the app:\n"""\n${text.trim()}\n"""`;
}

/**
 * Shared text (share sheet) -> capsule: the built-in recipe, bill, workout and list extractors first
 * (origin "rules"), then the cloud under the same policy as generateCapsuleWith (mode, allowNonEu,
 * allowCloud). Text over MAX_SHARED_TEXT characters is rejected before anything else.
 */
export async function generateFromSharedTextWith(text: string, cloud: CapsuleModel[],
  options?: GenerateOptions): Promise<GenerateResult> {
  const t = text.trim();
  if (t.length === 0) {
    return { ok: false, error: SHARED_EMPTY, details: [] };
  }
  if (t.length > MAX_SHARED_TEXT) {
    return { ok: false, error: SHARED_TOO_LONG, details: [] };
  }
  if (isNotEnglish(t)) {
    return unsupportedLanguage();
  }
  const local = capsuleFromSharedText(t);
  if (local.ok && local.capsule !== undefined) {
    return { ok: true, capsule: local.capsule, origin: 'rules', details: [] };
  }
  const mode: GenerateMode = options?.mode ?? 'smart';
  if (mode === 'on-device-only') {
    return { ok: false, error: `${SHARED_NOT_RECOGNISED} ${ON_DEVICE_ONLY}`, details: [] };
  }
  if (options?.allowCloud === false) {
    return { ok: false, error: `${SHARED_NOT_RECOGNISED} ${CLOUD_OFF}`, details: [], needsCloud: pickCloud(cloud,
      options?.allowNonEu ?? false) !== null };
  }
  const chosen = pickCloud(cloud, options?.allowNonEu ?? false);
  if (chosen === null) {
    const why = cloud.length > 0 ? `The configured cloud provider (${cloud[0].providerName}) is outside the EU.` :
      AI_NOT_CONFIGURED;
    return { ok: false, error: `${SHARED_NOT_RECOGNISED} ${why}`, details: [] };
  }
  return chosen.generate(sharedTextRequest(t), MAX_SHARED_TEXT + 100);
}
