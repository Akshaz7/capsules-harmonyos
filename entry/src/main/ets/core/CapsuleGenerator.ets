/**
 * Rule parser first, model as fallback. Every capsule returned has passed the validator.
 * Pure logic; the app-facing generateCapsule(request) lives in index.ets.
 */
import { GenerateResult } from './CapsuleTypes';
import { validateCapsule } from './CapsuleValidator';
import { parseRequest } from './RuleParser';
import { CapsuleModel } from './CapsuleModel';

export const NO_RULE_MATCH: string = 'No built-in rule understands this request.';
export const AI_NOT_CONFIGURED: string = 'AI fallback not configured.';

/**
 * `modelUnavailableReason`: empty or omitted means no config was found (the normal state for the
 * public .hap); otherwise it explains why a config that exists could not be used.
 */
export async function generateCapsuleWith(request: string, model: CapsuleModel | null,
  modelUnavailableReason?: string): Promise<GenerateResult> {
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
  if (model === null) {
    const why = modelUnavailableReason !== undefined && modelUnavailableReason.length > 0 ?
      `AI fallback unavailable: ${modelUnavailableReason}` : AI_NOT_CONFIGURED;
    return { ok: false, error: `${NO_RULE_MATCH} ${why}`, details: [] };
  }
  return model.generate(request);
}
