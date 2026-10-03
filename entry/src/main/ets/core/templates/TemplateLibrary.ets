/**
 * Built-in template library: common apps made instantly on the phone, with no model and no internet.
 *
 * A template is a capsule with slots. Slot placeholders are written "@{name}" inside the capsule JSON:
 * - number slot: a whole JSON string "@{work}" becomes the number (e.g. "minutes": "@{work}"); inside a
 *   longer string (an expression, a label) the number is written in place;
 * - text slot: written in place inside any string ("Point @{player1}");
 * - list slot: a whole array element "@{items}" becomes the items; inside a longer string they are joined.
 * Filling replaces every placeholder and the result must pass validateCapsule, like every other source.
 *
 * search(request) scores templates by keywords: name, tags (synonyms included), slot hints and
 * description, with English plurals folded ("scoreboards" = "scoreboard"). Requests are English only.
 * fill(template, request) fills slots by rules: numbers ("pomodoro 50/10", "break 10"), names
 * ("me vs Sam") and items ("shopping: milk, eggs"); slots it could not fill keep their default.
 * Pure logic: loading the rawfile and caching live in index.ets and RequestCache.ets.
 */
import { Capsule } from '../CapsuleTypes';
import { validateCapsule } from '../CapsuleValidator';

export type SlotKind = 'text' | 'number' | 'list';

export type SlotValue = string | number | string[];

export interface TemplateSlot {
  name: string;
  kind: SlotKind;
  default: SlotValue;
  /** Words that tie a number in the request to this slot: "break", "przerwa". Optional. */
  hints?: string[];
}

export interface TemplateEntry {
  id: string;
  name: string;
  description: string;
  /** Search words: English synonyms and the words people type. */
  tags: string[];
  slots: TemplateSlot[];
  /** Capsule JSON object with "@{slot}" placeholders. */
  capsule: Object;
  category?: string;
  language?: string;
}

export interface TemplateHit {
  template: TemplateEntry;
  /** 0..1: share of the request's meaningful words the template explains. */
  score: number;
  /** 0..1: share of the template's name words found in the request; breaks ties between equal scores. */
  nameScore: number;
}

export interface TemplateFill {
  /** Present when the filled capsule passed the validator. */
  capsule?: Capsule;
  /** Every slot's value, filled or default. */
  values: Record<string, SlotValue>;
  /** Slots filled from the request. */
  filled: string[];
  /**
   * Slots left at their default while the request still holds words or numbers the rules did not use:
   * the on-device model may be able to fill these (see SlotFill.ets). Empty when the defaults are fine.
   */
  unclear: string[];
  error?: string;
}

/** Below this score matchTemplate returns null and the request goes on to the models. */
export const TEMPLATE_MATCH_THRESHOLD: number = 0.7;
export const MAX_SLOT_TEXT: number = 40;
export const MAX_SLOT_ITEMS: number = 30;

// ---- Text normalisation ----

const FOLD: Record<string, string> = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'č': 'c', 'ç': 'c', 'ď': 'd', 'é': 'e', 'è': 'e',
  'ê': 'e', 'ë': 'e', 'ě': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ň': 'n', 'ñ': 'n', 'ô': 'o', 'ö': 'o',
  'ò': 'o', 'õ': 'o', 'ř': 'r', 'š': 's', 'ß': 'ss', 'ť': 't', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u',
  'ý': 'y', 'ž': 'z'
};

/** Lower case with accents folded: "Café TIMER" -> "cafe timer". */
export function foldText(text: string): string {
  const lower = text.toLowerCase();
  let out = '';
  for (const ch of lower) {
    const f = FOLD[ch];
    out += f !== undefined ? f : ch;
  }
  return out;
}

/** Words that carry no meaning for matching. */
const STOPWORDS: string[] = [
  'a', 'an', 'the', 'for', 'me', 'my', 'mine', 'i', 'we', 'us', 'our', 'you', 'vs', 'versus', 'against', 'and', 'or',
  'with', 'of', 'to', 'in', 'on', 'at', 'by', 'from', 'that', 'this', 'it', 'is', 'are', 'be', 'some', 'want', 'need',
  'please', 'make', 'create', 'build', 'give', 'get', 'new', 'simple', 'quick', 'little', 'small', 'app', 'apps',
  'application', 'capsule', 'just', 'can', 'could', 'would', 'like', 'let', 'lets', 'help', 'between', 'each', 'one',
  'two', 'min', 'mins', 'minute', 'minutes', 'm', 'x', 'per', 'every', 'all', 'about', 'how', 'many', 'much'
];

function isStopword(token: string): boolean {
  return STOPWORDS.indexOf(token) >= 0;
}

/** Splits folded text into words of letters and digits. */
function words(folded: string): string[] {
  return folded.split(/[^a-z0-9]+/).filter((w: string) => w.length > 0);
}

/** English plural and possessive endings: "scoreboards" -> "scoreboard". */
function stem(word: string): string {
  if (word.length > 4 && word.endsWith('ies')) {
    return word.substring(0, word.length - 3) + 'y';
  }
  if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

/** Same word, or the same word in the plural: "scoreboards" = "scoreboard". */
function similar(a: string, b: string): boolean {
  return a === b || stem(a) === stem(b);
}

// ---- Search ----

interface Keyword {
  word: string;
  weight: number;
}

class IndexedTemplate {
  template: TemplateEntry;
  keywords: Keyword[] = [];
  nameWords: string[] = [];

  constructor(template: TemplateEntry) {
    this.template = template;
    const add = (text: string, weight: number): void => {
      const folded = foldText(text);
      const ws = words(folded).filter((w: string) => !isStopword(w) && !/^\d+$/.test(w));
      ws.forEach((w: string) => this.keywords.push({ word: w, weight: weight }));
      for (let i = 0; i + 1 < ws.length; i++) {
        this.keywords.push({ word: ws[i] + ws[i + 1], weight: weight }); // "push up" also matches "pushup"
      }
    };
    add(template.name, 1);
    this.nameWords = words(foldText(template.name)).filter((w: string) => !isStopword(w) && !/^\d+$/.test(w));
    template.tags.forEach((t: string): void => add(t, 1));
    template.slots.forEach((s: TemplateSlot): void => (s.hints ?? []).forEach((h: string): void => add(h, 1)));
    add(template.description, 0.6);
  }

  /** Weight of a keyword equal to the token (or its plural), no fuzzy endings. */
  exactWeightOf(token: string): number {
    let best = 0;
    for (const k of this.keywords) {
      if (k.weight > best && similar(token, k.word)) {
        best = k.weight;
      }
    }
    return best;
  }

  weightOf(token: string): number {
    let best = 0;
    for (const k of this.keywords) {
      if (k.weight > best && similar(token, k.word)) {
        best = k.weight;
      }
    }
    return best;
  }
}

/** What the rules read out of a request: numbers, names, items, and the words left to match on. */
export interface ParsedRequest {
  folded: string;
  numbers: NumberToken[];
  names: string[];
  items: string[];
  /** Meaningful words: no stopwords, numbers or names. */
  tokens: string[];
  /** The same without the item words, for templates with a list slot. */
  tokensWithoutItems: string[];
}

export interface NumberToken {
  value: number;
  /** Word index in the folded request, to find hints next to it. */
  at: number;
}

function cleanSlotText(text: string): string {
  const t = text.replace(/["'{}\\@`]/g, '').replace(/\s+/g, ' ').trim();
  return t.length > MAX_SLOT_TEXT ? t.substring(0, MAX_SLOT_TEXT).trim() : t;
}

function capitalise(text: string): string {
  return text.length === 0 ? text : text.charAt(0).toUpperCase() + text.substring(1);
}

/** Names in "me vs Sam", "Anna versus Tom vs Ola", "between Ann and Bo", "for Ann, Bo and Cy". */
export function extractNames(request: string): string[] {
  const r = request.trim().replace(/[.!?]+$/, '');
  const vs = r.split(/\s+(?:vs\.?|versus|against|v)\s+/i);
  let parts: string[] = [];
  if (vs.length >= 2) {
    parts = vs;
    // "tennis scoreboard me" -> "me": keep the last word(s) of the first side and the first of the last
    parts[0] = lastWords(parts[0]);
    parts[parts.length - 1] = firstWords(parts[parts.length - 1]);
  } else {
    // "between Ann and Bo", "for Ann, Bo and Cy": capitalised names (or me) only
    const list = r.match(/\b(?:between|for|players?)\s+([^:]+)$/i);
    if (list !== null) {
      const names = list[1].split(/\s*(?:,|;|&|\band\b)\s*/i).map((p: string) => p.trim())
        .filter((p: string) => p.length > 0);
      const isName = (p: string): boolean => /^me$/i.test(p) ||
        (/^[A-Z]/.test(p) && p.charAt(0) !== p.charAt(0).toLowerCase() && p.split(/\s+/).length <= 2 &&
          !/\d/.test(p));
      if (names.length >= 2 && names.length <= 8 && names.every(isName)) {
        parts = names;
      }
    }
  }
  return parts.map((p: string) => cleanSlotText(p)).filter((p: string) => p.length > 0)
    .map((p: string) => capitalise(p));
}

/** "tennis scoreboard me" -> "me"; "volleyball Team A" -> "Team A". */
function lastWords(side: string): string {
  const ws = side.trim().split(/\s+/);
  const n = ws.length;
  return n > 1 && /^[a-z0-9]$/i.test(ws[n - 1]) ? `${ws[n - 2]} ${ws[n - 1]}` : ws[n - 1];
}

/** "Sam with tiebreaks" -> "Sam"; "Team B" -> "Team B". */
function firstWords(side: string): string {
  const ws = side.trim().split(/\s+/).map((w: string) => w.replace(/[,;:]+$/, ''));
  return ws.length > 1 && /^[a-z0-9]$/i.test(ws[1]) ? `${ws[0]} ${ws[1]}` : ws[0];
}

/** Items after a colon ("shopping: milk, eggs and bread") or "with ..."; split on commas and "and". */
export function extractItems(request: string): string[] {
  const colon = request.indexOf(':');
  let rest = '';
  if (colon >= 0) {
    rest = request.substring(colon + 1);
  } else {
    const m = request.match(/\b(?:items?|with|:)\s+(.+,.+)$/i);
    rest = m !== null ? m[1] : '';
  }
  if (rest.trim().length === 0) {
    return [];
  }
  return rest.split(/\s*(?:,|;|\band\b|&|\n)\s*/i).map((s: string) => cleanSlotText(s))
    .filter((s: string) => s.length > 0).slice(0, MAX_SLOT_ITEMS);
}

/** Reads numbers, names and items, and the meaningful words left for matching. */
export function parseTemplateRequest(request: string): ParsedRequest {
  const names = extractNames(request);
  const items = extractItems(request);
  const folded = foldText(request);
  // "50/10", "3x10", "25-5" -> separate numbers
  const ws = numberWords(folded);
  const numbers: NumberToken[] = [];
  const nameWords: string[] = [];
  names.forEach((n: string) => words(foldText(n)).forEach((w: string) => nameWords.push(w)));
  const itemWords: string[] = [];
  items.forEach((n: string) => words(foldText(n)).forEach((w: string) => itemWords.push(w)));
  const tokens: string[] = [];
  ws.forEach((w: string, i: number) => {
    if (/^\d+(\.\d+)?$/.test(w)) {
      numbers.push({ value: Number(w), at: i });
    } else if (w !== ',' && w !== ';' && !isStopword(w) && nameWords.indexOf(w) < 0) {
      tokens.push(w);
    }
  });
  return {
    folded: folded, numbers: numbers, names: names, items: items, tokens: tokens,
    tokensWithoutItems: tokens.filter((t: string) => itemWords.indexOf(t) < 0)
  };
}

/** Pairs of request words that join to one keyword ("push ups" -> "pushups") count as one matched word. */
function scoreTokens(index: IndexedTemplate, tokens: string[]): number {
  let total = 0;
  let i = 0;
  while (i < tokens.length) {
    if (i + 1 < tokens.length) {
      const joined = index.exactWeightOf(tokens[i] + tokens[i + 1]);
      if (joined > 0 && joined >= index.weightOf(tokens[i])) {
        total += 2 * joined;
        i += 2;
        continue;
      }
    }
    total += index.weightOf(tokens[i]);
    i++;
  }
  return total;
}

export class TemplateLibrary {
  private indexed: IndexedTemplate[] = [];

  constructor(templates: TemplateEntry[]) {
    const seen: string[] = [];
    templates.forEach((t: TemplateEntry) => {
      if (seen.indexOf(t.id) < 0) {
        seen.push(t.id);
        this.indexed.push(new IndexedTemplate(t));
      }
    });
  }

  /** Parses library JSON ({ "templates": [...] } or a bare array); malformed entries are skipped. */
  static fromJson(text: string, extra?: TemplateEntry[]): TemplateLibrary {
    const list: TemplateEntry[] = extra !== undefined ? extra.slice() : [];
    try {
      const root = JSON.parse(text) as Object;
      const arr: Object[] = Array.isArray(root) ? root as Object[] :
        ((root as Record<string, Object>)['templates'] as Object[] ?? []);
      arr.forEach((e: Object) => {
        if (isTemplateEntry(e)) {
          list.push(e as TemplateEntry);
        }
      });
    } catch (e) {
      // unreadable library: keep the built-in ones
    }
    return new TemplateLibrary(list);
  }

  get size(): number {
    return this.indexed.length;
  }

  all(): TemplateEntry[] {
    return this.indexed.map((i: IndexedTemplate) => i.template);
  }

  byId(id: string): TemplateEntry | undefined {
    const hit = this.indexed.find((i: IndexedTemplate) => i.template.id === id);
    return hit !== undefined ? hit.template : undefined;
  }

  /** Best matches first, at most `limit`, only templates that match at least one word. */
  search(request: string, limit?: number): TemplateHit[] {
    const parsed = parseTemplateRequest(request);
    // Generic words ("timer", "counter", "scoreboard") match many templates; alone they pick none of them.
    const generic: string[] = parsed.tokens.filter((t: string) =>
      this.indexed.filter((ix: IndexedTemplate) => ix.weightOf(t) > 0).length > Math.max(4, this.indexed.length / 20));
    const hits: TemplateHit[] = [];
    this.indexed.forEach((index: IndexedTemplate) => {
      const hasList = index.template.slots.some((sl: TemplateSlot) => sl.kind === 'list');
      const latin = hasList ? parsed.tokensWithoutItems : parsed.tokens;
      let score = 0;
      // names the template has no text slot for ("cards for Ann, Bo, Cy" with fixed players) count as unmatched
      const textSlots = index.template.slots.filter((sl: TemplateSlot) => sl.kind === 'text').length;
      const lostNames = Math.max(0, parsed.names.length - textSlots);
      if (latin.length > 0) {
        score = scoreTokens(index, latin) / (latin.length + lostNames);
      }
      const specific = latin.some((t: string, i: number) => (generic.indexOf(t) < 0 && index.weightOf(t) > 0) ||
        (i + 1 < latin.length && index.exactWeightOf(t + latin[i + 1]) > 0)); // "times tables" is specific
      if (latin.length > 0 && !specific) {
        score *= 0.5;
      }
      if (score > 0) {
        const named = index.nameWords.filter((w: string) => parsed.tokens.some((t: string) => similar(t, w))).length;
        hits.push({
          template: index.template, score: Math.round(Math.min(1, score) * 1000) / 1000,
          nameScore: index.nameWords.length > 0 ? named / index.nameWords.length : 0
        });
      }
    });
    hits.sort((a: TemplateHit, b: TemplateHit) => b.score - a.score || b.nameScore - a.nameScore ||
      a.template.slots.length - b.template.slots.length || a.template.id.localeCompare(b.template.id));
    return hits.slice(0, limit ?? 5);
  }
}

function isTemplateEntry(e: Object): boolean {
  if (e === null || typeof e !== 'object' || Array.isArray(e)) {
    return false;
  }
  const r = e as Record<string, Object>;
  return typeof r['id'] === 'string' && typeof r['name'] === 'string' && Array.isArray(r['tags']) &&
    Array.isArray(r['slots']) && r['capsule'] !== undefined && r['capsule'] !== null && typeof r['capsule'] === 'object' &&
    (typeof r['description'] === 'string' || r['description'] === undefined);
}

// ---- Fill ----

/** How far a number is from a slot's hint word, counting meaningful words; Infinity across "and" or ",". */
function hintDistance(parsed: ParsedRequest, n: NumberToken, slot: TemplateSlot): number {
  const hints: string[] = [];
  (slot.hints ?? []).concat([slot.name]).forEach((h: string) => words(foldText(h))
    .filter((w: string) => !isStopword(w)).forEach((w: string) => hints.push(w)));
  const ws = numberWords(parsed.folded);
  let best = Infinity;
  for (const dir of [-1, 1]) {
    let steps = 0;
    for (let i = n.at + dir; i >= 0 && i < ws.length && steps < 3; i += dir) {
      const w = ws[i];
      if (w === ',' || w === ';' || w === 'and' || w === 'then' || /^\d/.test(w)) {
        break;
      }
      if (isStopword(w)) {
        continue;
      }
      steps++;
      if (hints.some((h: string) => similar(w, h))) {
        best = Math.min(best, dir < 0 ? steps - 0.5 : steps); // "break 10" beats "10 ... focus"
        break;
      }
    }
  }
  return best;
}

/** Words and numbers ("12.5" stays one number; "50/10", "3x10" split), with commas kept as their own word. */
function numberWords(folded: string): string[] {
  const prepared = folded.replace(/(\d)\s*[x×\/\-]\s*(?=\d)/g, '$1 ').replace(/(\d)([a-z])/g, '$1 $2');
  return prepared.match(/\d+(?:\.\d+)?|[a-z0-9]+|[,;]/g) ?? [];
}

/**
 * For each slot (row of `dist`), the number index it takes or -1. Maximises the pairs with a finite distance,
 * then minimises the total distance. Templates have few number slots, so a full search is cheap.
 */
function bestAssignment(dist: number[][], count: number): number[] {
  let best: number[] = dist.map((): number => -1);
  let bestPairs = 0;
  let bestTotal = 0;
  const current: number[] = [];
  const taken: boolean[] = [];
  for (let k = 0; k < count; k++) {
    taken.push(false);
  }
  const visit = (j: number, pairs: number, total: number): void => {
    if (j === dist.length) {
      if (pairs > bestPairs || (pairs === bestPairs && pairs > 0 && total < bestTotal)) {
        best = current.slice();
        bestPairs = pairs;
        bestTotal = total;
      }
      return;
    }
    current.push(-1);
    visit(j + 1, pairs, total);
    current.pop();
    for (let k = 0; k < count; k++) {
      if (!taken[k] && dist[j][k] < Infinity) {
        taken[k] = true;
        current.push(k);
        visit(j + 1, pairs + 1, total + dist[j][k]);
        current.pop();
        taken[k] = false;
      }
    }
  };
  if (dist.length <= 6 && count <= 8) {
    visit(0, 0, 0);
  }
  return best;
}

/** Slot values from the request by rules. Returns the filled slot names. */
export function slotValuesFromRequest(template: TemplateEntry, request: string): Record<string, SlotValue> {
  const parsed = parseTemplateRequest(request);
  const values: Record<string, SlotValue> = {};
  const numberSlots = template.slots.filter((s: TemplateSlot) => s.kind === 'number');
  const used: boolean[] = parsed.numbers.map((): boolean => false);
  // 1. numbers next to a slot's hint word ("break 10", "40 work 20 rest"): the assignment that ties the most
  //    numbers to hints, then the closest ones
  const dist: number[][] = numberSlots.map((s: TemplateSlot) =>
    parsed.numbers.map((n: NumberToken) => hintDistance(parsed, n, s)));
  const best = bestAssignment(dist, parsed.numbers.length);
  best.forEach((k: number, j: number) => {
    if (k >= 0) {
      used[k] = true;
      values[numberSlots[j].name] = parsed.numbers[k].value;
    }
  });
  // 2. the rest in order: "pomodoro 50/10" -> work 50, break 10
  numberSlots.filter((s: TemplateSlot) => values[s.name] === undefined).forEach((s: TemplateSlot) => {
    const i = used.indexOf(false);
    if (i >= 0) {
      used[i] = true;
      values[s.name] = parsed.numbers[i].value;
    }
  });
  const textSlots = template.slots.filter((s: TemplateSlot) => s.kind === 'text');
  parsed.names.slice(0, textSlots.length).forEach((name: string, i: number) => {
    values[textSlots[i].name] = name;
  });
  const listSlot = template.slots.find((s: TemplateSlot) => s.kind === 'list');
  if (listSlot !== undefined && parsed.items.length > 0) {
    values[listSlot.name] = parsed.items;
  }
  return values;
}

function formatNumber(n: number): string {
  return Number.isInteger(n) ? String(n) : String(Math.round(n * 1000) / 1000);
}

function jsonInner(text: string): string {
  const s = JSON.stringify(text);
  return s.substring(1, s.length - 1);
}

function inlineText(v: SlotValue): string {
  if (typeof v === 'number') {
    return formatNumber(v as number);
  }
  if (Array.isArray(v)) {
    return (v as string[]).map((s: string) => cleanSlotText(s)).join(', ');
  }
  return cleanSlotText(v as string);
}

function sanitise(slot: TemplateSlot, v: SlotValue): SlotValue {
  if (slot.kind === 'number') {
    const n = typeof v === 'number' ? v as number : Number(v);
    return Number.isFinite(n) && n > 0 ? n : (slot.default as number);
  }
  if (slot.kind === 'list') {
    const items = Array.isArray(v) ? (v as string[]) : [String(v)];
    const clean = items.map((s: string) => cleanSlotText(String(s))).filter((s: string) => s.length > 0)
      .slice(0, MAX_SLOT_ITEMS);
    return clean.length > 0 ? clean : (slot.default as string[]);
  }
  const t = cleanSlotText(String(v));
  return t.length > 0 ? t : (slot.default as string);
}

/** Replaces every "@{slot}" in the capsule JSON. Unknown placeholders are left (and fail validation). */
export function applySlots(template: TemplateEntry, values: Record<string, SlotValue>): string {
  let json = JSON.stringify(template.capsule);
  template.slots.forEach((slot: TemplateSlot) => {
    const v = sanitise(slot, values[slot.name] !== undefined ? values[slot.name] : slot.default);
    const ph = `@{${slot.name}}`;
    let whole = '';
    if (slot.kind === 'number') {
      whole = formatNumber(v as number);
    } else if (slot.kind === 'list') {
      whole = (v as string[]).map((s: string) => JSON.stringify(s)).join(',');
    } else {
      whole = JSON.stringify(v as string);
    }
    json = json.split(`"${ph}"`).join(whole);
    json = json.split(ph).join(jsonInner(inlineText(v)));
  });
  return json;
}

/**
 * Fills a template from the request by rules, then validates. `unclear` lists slots left at their default
 * while the request has words or numbers the template and the rules did not use.
 */
export function fillTemplate(template: TemplateEntry, request: string, given?: Record<string, SlotValue>): TemplateFill {
  const fromRules = slotValuesFromRequest(template, request);
  const values: Record<string, SlotValue> = {};
  const filled: string[] = [];
  template.slots.forEach((s: TemplateSlot) => {
    const g = given !== undefined ? given[s.name] : undefined;
    const r = fromRules[s.name];
    if (g !== undefined) {
      values[s.name] = sanitise(s, g);
      filled.push(s.name);
    } else if (r !== undefined) {
      values[s.name] = sanitise(s, r);
      filled.push(s.name);
    } else {
      values[s.name] = s.default;
    }
  });
  const unexplained = leftovers(template, request) > 0;
  const unclear = template.slots.map((s: TemplateSlot) => s.name)
    .filter((n: string) => unexplained && filled.indexOf(n) < 0);
  const v = validateCapsule(applySlots(template, values));
  if (!v.ok) {
    return { values: values, filled: filled, unclear: unclear, error: v.errors.join('; ') };
  }
  return { capsule: v.capsule, values: values, filled: filled, unclear: unclear };
}

/** Request words and numbers the template's keywords and the rules did not account for. */
function leftovers(template: TemplateEntry, request: string): number {
  const parsed = parseTemplateRequest(request);
  const index = new IndexedTemplate(template);
  const numberSlots = template.slots.filter((s: TemplateSlot) => s.kind === 'number').length;
  const extraNumbers = Math.max(0, parsed.numbers.length - numberSlots);
  const hasList = template.slots.some((sl: TemplateSlot) => sl.kind === 'list');
  return (hasList ? parsed.tokensWithoutItems : parsed.tokens).filter((t: string) => index.weightOf(t) === 0).length +
    extraNumbers;
}

/** What matchTemplate returns: a validated capsule from the best template, or null. */
export interface TemplateMatch {
  capsule: Capsule;
  score: number;
  /** Slots the rules could not fill although the request seems to say more (see SlotFill.ets). */
  unfilledSlots: string[];
  template: TemplateEntry;
  values: Record<string, SlotValue>;
}

/**
 * The best template for the request, filled and validated, if it scores at least `threshold`
 * (default TEMPLATE_MATCH_THRESHOLD). Tries the next hits if the best one fails to fill.
 */
export function matchTemplateIn(library: TemplateLibrary, request: string, threshold?: number): TemplateMatch | null {
  const min = threshold ?? TEMPLATE_MATCH_THRESHOLD;
  if (request.trim().length === 0) {
    return null;
  }
  for (const hit of library.search(request, 3)) {
    if (hit.score < min) {
      break;
    }
    const f = fillTemplate(hit.template, request);
    if (f.capsule !== undefined) {
      return { capsule: f.capsule, score: hit.score, unfilledSlots: f.unclear, template: hit.template, values: f.values };
    }
  }
  return null;
}
