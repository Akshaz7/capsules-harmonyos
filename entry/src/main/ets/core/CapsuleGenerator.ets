/**
 * Rule parser first, model as fallback. Every capsule returned has passed the validator.
 * Pure logic; the app-facing generateCapsule(request) lives in index.ets.
 */
import { GenerateResult } from './CapsuleTypes';
import { validateCapsule } from './CapsuleValidator';
import { parseRequest } from './RuleParser';
import { CapsuleModel } from './CapsuleModel';

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
      ` The AI model is not available: ${modelUnavailableReason}` : ' The AI model is not configured.';
    return { ok: false, error: `No built-in rule understands this request.${why}`, details: [] };
  }
  return model.generate(request);
}
