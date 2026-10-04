import { GenerateResult, getModelStatus, UNSUPPORTED_LANGUAGE } from '../core';

/** "a", "a and b", "a, b and c". */
export function joinWords(words: string[]): string {
  return words.length <= 1 ? words.join('') :
    `${words.slice(0, words.length - 1).join(', ')} and ${words[words.length - 1]}`;
}

/**
 * What the "can't do X by design" card names, or [] when the failure is not a refusal. Only non-empty strings
 * survive, whatever shape the model's reply had, so the card can always render (any language, emoji included).
 */
export function refusalWords(result: GenerateResult): string[] {
  if (result.failure !== 'unsupported') {
    return [];
  }
  const raw: Object[] = Array.isArray(result.unsupported) ? result.unsupported as Object[] : [];
  const words = raw.filter((w: Object) => typeof w === 'string' && (w as string).trim().length > 0)
    .map((w: Object) => (w as string).trim());
  return words.length > 0 ? words : ['that'];
}

/** The failure's details for the log; never throws when `details` is missing. */
export function failureDetail(result: GenerateResult): string {
  return Array.isArray(result.details) ? result.details.join('; ') : '';
}

/** What works without the cloud, shown in Settings and on the failure card (wording fixed by T3-8). */
export const LIMITS_TEXT = 'Common apps are made on your phone. Unusual ones need cloud AI (Mistral EU).';

/** The provider smart mode uses, as users know it (same rule as Index.cloudName: an EU provider first). */
export function cloudProviderName(): string {
  const status = getModelStatus();
  if (status.euAvailable) {
    return 'Mistral EU';
  }
  const p = status.providers.length > 0 ? status.providers[0] : '';
  return p === 'anthropic' ? 'Claude' : p === 'openai' ? 'OpenAI' : 'cloud AI';
}

/** LIMITS_TEXT naming the provider actually in use (T4-23). */
export function limitsText(): string {
  const name = cloudProviderName();
  return `Common apps are made on your phone. Unusual ones need cloud AI${name === 'cloud AI' ? '' : ` (${name})`}.`;
}

/** T3-13: shown instead of any other card when core's English-only gate (T4-11) refuses a request. */
export const LANGUAGE_MESSAGE = 'Harmoniser understands English for now. Try: ';
export const LANGUAGE_EXAMPLE = 'timer 10 minutes';

/** Did core's English-only gate (T4-11) refuse this request? */
export function isUnsupportedLanguage(result: GenerateResult): boolean {
  return result.failure === UNSUPPORTED_LANGUAGE;
}
