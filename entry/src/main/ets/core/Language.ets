/**
 * English-only gate. Harmoniser understands English for now: generateCapsule checks this first, so a request
 * in another language never reaches the rules, the on-device model or the cloud.
 *
 * Deliberately simple:
 *  (a) mostly letters of a non-Latin script (CJK, Hangul, Cyrillic, Greek, Arabic, Hebrew, Thai, Devanagari),
 *      weighted 3:1 as one CJK character is about a word, so "在菜店买东西单。let me add items" is caught too;
 *  (b) Latin script with several accented letters (2+ with no common English word, or 3+ making up a fifth of
 *      the letters): "licznik pompek na dziś, żółw" is caught; "café menu", "Zoë's chores" and "naïve crème
 *      brûlée timer" are not;
 *  (c) a common Polish word and no English word ("minutnik 10 minut").
 * Emoji, digits and punctuation are ignored.
 */

const NON_LATIN: RegExp =
  /[\u0370-\u03ff\u0400-\u04ff\u0590-\u05ff\u0600-\u06ff\u0900-\u097f\u0e00-\u0e7f\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\uf900-\ufaff]/g;
const ASCII_LETTER: RegExp = /[A-Za-z]/g;
// Latin-1 Supplement and Latin Extended-A/B letters (not the × and ÷ signs).
const ACCENTED_LETTER: RegExp = /[\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u024f]/g;

const ENGLISH_WORDS: string[] = [
  'a', 'an', 'the', 'and', 'or', 'for', 'to', 'of', 'in', 'on', 'at', 'with', 'my', 'me', 'i', 'is', 'it',
  'every', 'each', 'day', 'today', 'daily', 'week', 'timer', 'timers', 'minute', 'minutes', 'min', 'mins',
  'hour', 'hours', 'counter', 'count', 'list', 'track', 'tracker', 'menu', 'chores', 'shopping', 'water',
  'remind', 'reminder', 'split', 'bill', 'score', 'game', 'goal', 'make', 'app', 'how', 'many'
];

const FOREIGN_WORDS: string[] = [
  'minut', 'minuty', 'minutnik', 'godzina', 'godziny', 'licznik', 'lista', 'zakupy', 'dla', 'mnie',
  'przypomnij', 'podziel', 'wynik', 'gra', 'trening', 'na', 'dziś', 'pompek', 'pompki', 'wody'
];

/** The stable failure code (GenerateResult.failure) for a request that is not in English. */
export const UNSUPPORTED_LANGUAGE: string = 'unsupported-language';
export const UNSUPPORTED_LANGUAGE_MESSAGE: string =
  "Harmoniser understands English for now. Try: 'timer 10 minutes'.";

function count(text: string, pattern: RegExp): number {
  const m = text.match(pattern);
  return m === null ? 0 : m.length;
}

function words(text: string): string[] {
  return text.toLowerCase().split(/[^a-z\u00c0-\u024f']+/).map((w: string) => w.replace(/'s$/, ''))
    .filter((w: string) => w.length > 0);
}

/** True when the request is (very likely) not in English. */
export function isNotEnglish(request: string): boolean {
  const nonLatin = count(request, NON_LATIN);
  const ascii = count(request, ASCII_LETTER);
  const accented = count(request, ACCENTED_LETTER);
  // One CJK character is about a word, so weigh non-Latin letters 3:1 against Latin ones.
  if (nonLatin > 0 && nonLatin * 3 >= ascii + accented) {
    return true;
  }
  const ws = words(request);
  const hasEnglish = ws.some((w: string) => ENGLISH_WORDS.includes(w));
  if ((accented >= 2 && !hasEnglish) || (accented >= 3 && accented * 5 >= ascii + accented)) {
    return true;
  }
  return !hasEnglish && ws.some((w: string) => FOREIGN_WORDS.includes(w));
}
