/**
 * Failure card help (T4-30): when a request can't be built, one line saying why, and 2-3 buildable requests
 * related to it. Pure; pages/Index shows it on the failure card.
 */

import { parseRequest } from './RuleParser';

/** A request the app can build, offered instead of one it can't. */
export interface Alternative {
  label: string;
  request: string;
}

/** Why a request can't be built, and what to offer instead. */
export interface FailureHelp {
  /** One line, e.g. "Capsules can't fetch live news yet."; empty when nothing rules the request out. */
  reason: string;
  /** 2-3 requests related to this one that build on the phone (never generic examples). */
  alternatives: Alternative[];
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
  alternatives: Alternative[];
}

function alt(label: string, request: string): Alternative {
  const a: Alternative = { label: label, request: request };
  return a;
}

const LIMITS: Limit[] = [
  {
    pattern: /\b(news|headlines?)\b/i,
    early: true,
    reason: "Capsules can't fetch live news yet.",
    alternatives: [alt('Task list with the weather for Kraków', 'a task list and the weather for Krakow'),
      alt('Morning checklist', 'checklist for morning: coffee, stretch, plan the day'),
      alt('Daily reading timer 15 min', 'reading timer 15 min')]
  },
  {
    early: false,
    pattern: /\b(pay|payments?|send money|transfer money|bank(ing)?|paypal|venmo|blik|revolut)\b/i,
    reason: "Capsules can't make payments.",
    alternatives: [alt('Split a bill between 4', 'split the bill 120 among 4 people'),
      alt('Bills checklist', 'checklist for bills: rent, phone, internet'),
      alt('Rent reminder at 9:00', 'rent reminder at 9am')]
  },
  {
    early: false,
    pattern: /\b(whatsapp|instagram|spotify|facebook|tiktok|youtube|netflix|messenger|telegram|uber|other apps?|another app|open (the )?app)\b/i,
    reason: "Capsules can't control other apps.",
    alternatives: [alt('Daily reminder at 18:00', 'check messages at 6pm'),
      alt('Screen break timer 20 min', 'screen break timer 20 min')]
  },
  {
    pattern: /\b(stock (prices?|market)|crypto(currency)?|bitcoin|exchange rates?)\b/i,
    early: true,
    reason: "Capsules can't fetch live prices yet.",
    alternatives: [alt('Shopping list', 'shopping list: milk, bread, eggs'),
      alt('Savings counter', 'count my savings')]
  }
];

const FILLER: RegExp = /\b(build|make|create|give|show|me|my|i|want|need|please|can|you|a|an|the|that|which|to|for|of|in|on|with|and|or|it|widget|app|capsule|something|thing|simple|little|every|each|day|daily|morning|mornings|evening|me|gives|latest|info)\b/gi;

/** Words the phone's rules leave to the models (RuleParser LOGIC): dropped from the topic. */
const LOGIC_WORDS: RegExp = /\b(scor\w*|games?|players?|quiz\w*|trivia|convert\w*|calculat\w*|streaks?|about|track\w*|if|per)\b/gi;

/** The request's own topic in 1-3 words, e.g. "quiz about dinosaurs" -> "Quiz about dinosaurs"; '' if none. */
export function topicOf(request: string): string {
  const words = request.toLowerCase().replace(/[^a-z\u00c0-\u024f\s-]/g, ' ').replace(FILLER, ' ').replace(LOGIC_WORDS, ' ')
    .split(/\s+/).filter((w: string) => w.length > 1);
  const topic = words.slice(0, 3).join(' ');
  return topic.length === 0 ? '' : `${topic.charAt(0).toUpperCase()}${topic.substring(1)}`;
}

/**
 * Help for a failed request: the first limit it hits (its reason and alternatives), else alternatives made
 * from the request's own words (a counter, a timer and a checklist for its topic).
 */
export function failureHelp(request: string): FailureHelp {
  const hit = LIMITS.find((l: Limit) => l.pattern.test(request));
  if (hit !== undefined) {
    const help: FailureHelp = { reason: hit.reason, alternatives: hit.alternatives };
    return help;
  }
  const topic = topicOf(request);
  if (topic.length === 0) {
    const none: FailureHelp = { reason: '', alternatives: [] };
    return none;
  }
  const t = topic.toLowerCase();
  // Only what the phone's rules really build from these words.
  const own: FailureHelp = { reason: '', alternatives: [
    alt(`${topic} counter`, `count ${t}`),
    alt(`${topic} timer 10 min`, `${t} timer 10 min`),
    alt(`${topic} checklist`, `checklist for ${t}: first, second, third`)
  ].filter((a: Alternative) => parseRequest(a.request) !== null) };
  return own;
}

/** The failure for a request no capsule can do (live news, live prices): nothing is sent to any model. */
export const CANT_BUILD_MESSAGE: string = 'Capsules cannot do this yet.';

/** Whether the request is refused before the rules and every model (see Limit.early). */
export function cantBuild(request: string): boolean {
  return LIMITS.some((l: Limit) => l.early && l.pattern.test(request));
}

/** Every alternative the card can offer (tests check each one builds on the phone). */
export function allAlternatives(): Alternative[] {
  const out: Alternative[] = [];
  LIMITS.forEach((l: Limit) => l.alternatives.forEach((a: Alternative) => out.push(a)));
  return out;
}
