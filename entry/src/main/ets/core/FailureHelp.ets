/**
 * Failure card help (T4-30): when a request can't be built, one line saying why, and one buildable request
 * related to it. Pure; pages/Index shows it on the failure card.
 */

/** A request the app can build, offered instead of one it can't. */
export interface Alternative {
  label: string;
  request: string;
}

/** Why a request can't be built, and what to offer instead. */
export interface FailureHelp {
  /** One line, e.g. "Capsules can't fetch live news yet."; empty when nothing rules the request out. */
  reason: string;
  alternative: Alternative | null;
}

/** The failure card's line about where requests are built (Ash's wording). */
export const CLOUD_EXPLAINER: string =
  'Most requests are built on the phone. When one needs a cloud model, the app names the provider first, ' +
  'which may be outside the EU.';

/** The failure card's button that asks for the cloud (through the existing provider notice). */
export const TRY_CLOUD_LABEL: string = 'Try with cloud AI';

interface Limit {
  pattern: RegExp;
  /** Refused before any model is asked (no capsule can do it, and a model would only make a hollow one). */
  early: boolean;
  reason: string;
  alternative: Alternative;
}

const LIMITS: Limit[] = [
  {
    pattern: /\b(news|headlines?)\b/i,
    early: true,
    reason: "Capsules can't fetch live news yet.",
    alternative: { label: 'Task list with the weather for Kraków',
      request: 'a task list and the weather for Krakow' }
  },
  {
    early: false,
    pattern: /\b(pay|payments?|send money|transfer money|bank(ing)?|paypal|venmo|blik|revolut)\b/i,
    reason: "Capsules can't make payments.",
    alternative: { label: 'Split a bill between 4', request: 'split the bill 120 among 4 people' }
  },
  {
    early: false,
    pattern: /\b(whatsapp|instagram|spotify|facebook|tiktok|youtube|netflix|messenger|telegram|uber|other apps?|another app|open (the )?app)\b/i,
    reason: "Capsules can't control other apps.",
    alternative: { label: 'Daily reminder at 18:00', request: 'check messages at 6pm' }
  },
  {
    pattern: /\b(stock (prices?|market)|crypto(currency)?|bitcoin|exchange rates?)\b/i,
    early: true,
    reason: "Capsules can't fetch live prices yet.",
    alternative: { label: 'Shopping list', request: 'shopping list: milk, bread, eggs' }
  }
];

/** Help for a failed request: the first limit it hits, else no reason and no alternative. */
export function failureHelp(request: string): FailureHelp {
  const hit = LIMITS.find((l: Limit) => l.pattern.test(request));
  if (hit === undefined) {
    const none: FailureHelp = { reason: '', alternative: null };
    return none;
  }
  const help: FailureHelp = { reason: hit.reason, alternative: hit.alternative };
  return help;
}

/** The failure for a request no capsule can do (live news, live prices): nothing is sent to any model. */
export const CANT_BUILD_MESSAGE: string = 'Capsules cannot do this yet.';

/** Whether the request is refused before the rules and every model (see Limit.early). */
export function cantBuild(request: string): boolean {
  return LIMITS.some((l: Limit) => l.early && l.pattern.test(request));
}

/** Every alternative the card can offer (tests check each one builds on the phone). */
export function allAlternatives(): Alternative[] {
  return LIMITS.map((l: Limit) => l.alternative);
}
