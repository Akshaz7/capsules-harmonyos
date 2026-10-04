/**
 * Pure voice-input helpers (no kit imports, so unit tests can load them): messages, transcript clean-up and the
 * error -> message mapping used by components/VoiceButton.ets.
 */

export const VOICE_PERMISSION: string = 'ohos.permission.MICROPHONE';
export const VOICE_UNAVAILABLE: string = 'Voice input is not available on this phone.';
export const VOICE_NOTHING_HEARD: string = 'Nothing was heard. Try again.';
export const MIC_OFF: string = 'Microphone access is off. Turn it on in Settings.';
/** The offline engine only offers zh-CN; it recognises English speech well (emulator eval, 2026-10-03). */
export const VOICE_LANGUAGE: string = 'zh-CN';

/** User-facing message for a voice failure: nothing heard, microphone permission off, or unavailable. */
export function voiceErrorMessage(error: Error | string | null | undefined): string {
  const m = error instanceof Error ? error.message : (error ?? '');
  if (m.startsWith(VOICE_NOTHING_HEARD)) {
    return VOICE_NOTHING_HEARD;
  }
  if (m.startsWith(MIC_OFF) || /permission|denied|201\b/i.test(m)) {
    return MIC_OFF;
  }
  return VOICE_UNAVAILABLE;
}

const UNITS: Record<string, number> = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19
};
const TENS: Record<string, number> = {
  'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90
};

/**
 * Recognizer output -> request text: Chinese punctuation to English, no trailing full stop, number words to digits
 * ("twenty five minutes" -> "25 minutes", "a hundred" -> "100"), "i" -> "I". The rules only read digits.
 */
export function cleanTranscript(raw: string): string {
  let t = raw.replace(/。/g, '. ').replace(/，/g, ', ').replace(/？/g, '? ').replace(/！/g, '! ')
    .replace(/：/g, ': ').replace(/\s+/g, ' ').trim();
  t = t.replace(/\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)[ -](one|two|three|four|five|six|seven|eight|nine)\b/gi,
    (m: string, tens: string, unit: string) => `${TENS[tens.toLowerCase()] + UNITS[unit.toLowerCase()]}`);
  t = t.replace(/\b(a|one) hundred\b/gi, '100');
  t = t.replace(/\b(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)\b/gi,
    (m: string) => `${UNITS[m.toLowerCase()] ?? TENS[m.toLowerCase()]}`);
  t = t.replace(/\bi\b/g, 'I').replace(/[.!]+$/, '').trim();
  return t.length > 0 ? t.charAt(0).toUpperCase() + t.substring(1) : t;
}
