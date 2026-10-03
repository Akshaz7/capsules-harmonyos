/**
 * Rule parser first, then the on-device model, then the cloud model (if configured and allowed).
 * Every capsule returned has passed the validator.
 * Pure logic; the app-facing generateCapsule(request) lives in index.ets.
 */
import { GenerateResult } from './CapsuleTypes';
import { validateCapsule } from './CapsuleValidator';
import { parseRequest } from './RuleParser';
import { CapsuleModel } from './CapsuleModel';

export const NO_RULE_MATCH: string = 'No built-in rule understands this request.';
export const AI_NOT_CONFIGURED: string = 'AI fallback not configured.';

/** Anything that turns a request into a validated capsule (CapsuleModel, CactusProvider). */
export interface CapsuleSource {
  generate(request: string): Promise<GenerateResult>;
}

export interface GenerateOptions {
  /** When false the cloud model is never called. Default true (it still needs a config). */
  allowCloud: boolean;
}

/**
 * `modelUnavailableReason`: empty or omitted means no config was found (the normal state for the
 * public .hap); otherwise it explains why a config that exists could not be used.
 */
export async function generateCapsuleWith(request: string, model: CapsuleModel | null,
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
    // A rule produced an invalid capsule (a bug); fall through to the model rather than return it.
  }
  let onDeviceError = '';
  if (onDevice !== undefined && onDevice !== null) {
    const local = await onDevice.generate(request);
    if (local.ok) {
      return local;
    }
    onDeviceError = local.error ?? '';
  }
  if (options !== undefined && !options.allowCloud) {
    const why = onDeviceError.length > 0 ? onDeviceError : 'Cloud AI is turned off.';
    return { ok: false, error: `${NO_RULE_MATCH} ${why}`, details: [] };
  }
  if (model === null) {
    const cloudWhy = modelUnavailableReason !== undefined && modelUnavailableReason.length > 0 ?
      `AI fallback unavailable: ${modelUnavailableReason}` : AI_NOT_CONFIGURED;
    const why = onDeviceError.length > 0 ? onDeviceError : cloudWhy;
    return { ok: false, error: `${NO_RULE_MATCH} ${why}`, details: [] };
  }
  return model.generate(request);
}
