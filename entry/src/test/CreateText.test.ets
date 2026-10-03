import { describe, it, expect } from '@ohos/hypium';
import {
  failureDetail, isUnsupportedLanguage, joinWords, LANGUAGE_EXAMPLE, LANGUAGE_MESSAGE, refusalWords, UNSUPPORTED_LANGUAGE
} from '../main/ets/pages/CreateText';
import { generateCapsuleWith } from '../main/ets/core/CapsuleGenerator';
import { GenerateResult } from '../main/ets/core/CapsuleTypes';

const NON_ENGLISH: string[] = [
  '用照片教我做饭，上网找菜谱', // Chinese: cook from a photo, find recipes online (Lewis's crash report)
  '在菜店买东西单。let me add items',
  'licznik pompek na dziś, żółw', // Polish
  'minutnik 10 minut',
  '💧 water 8 glasses 🥤',
  '🍝🍝🍝',
  'تذكير بشرب الماء', // Arabic, right to left
  '​‍', // zero-width only
];

export default function createTextTest() {
  describe('CreateText (T3-5: non-English input never crashes create)', () => {
    it('joinWords handles 0, 1, 2 and 3 words, any script', 0, () => {
      expect(joinWords([])).assertEqual('');
      expect(joinWords(['相机'])).assertEqual('相机');
      expect(joinWords(['camera', '照片'])).assertEqual('camera and 照片');
      expect(joinWords(['camera', 'photos', 'internet'])).assertEqual('camera, photos and internet');
    });

    it('refusalWords keeps only non-empty strings and falls back to "that"', 0, () => {
      const r: GenerateResult = { ok: false, failure: 'unsupported', unsupported: ['相机', ' ', '网络 '], details: [] };
      expect(refusalWords(r).join('|')).assertEqual('相机|网络');
      const empty: GenerateResult = { ok: false, failure: 'unsupported', unsupported: [], details: [] };
      expect(refusalWords(empty).join('|')).assertEqual('that');
      const missing: GenerateResult = { ok: false, failure: 'unsupported', details: [] };
      expect(refusalWords(missing).join('|')).assertEqual('that');
      const notRefusal: GenerateResult = { ok: false, unsupported: ['x'], details: [] };
      expect(refusalWords(notRefusal).length).assertEqual(0);
    });

    it('language card text is exact and only the English-only failure triggers it (T3-13)', 0, () => {
      expect(`${LANGUAGE_MESSAGE}'${LANGUAGE_EXAMPLE}'.`)
        .assertEqual("Harmoniser understands English for now. Try: 'timer 10 minutes'.");
      const lang: GenerateResult = { ok: false, error: UNSUPPORTED_LANGUAGE, details: [] };
      expect(isUnsupportedLanguage(lang)).assertTrue();
      const refusal: GenerateResult = { ok: false, failure: 'unsupported', unsupported: ['SMS'], details: [] };
      expect(isUnsupportedLanguage(refusal)).assertFalse();
      const plain: GenerateResult = { ok: false, error: 'No built-in rule understands this request.', details: [] };
      expect(isUnsupportedLanguage(plain)).assertFalse();
    });

        it('failureDetail joins details', 0, () => {
      const r: GenerateResult = { ok: false, details: ['a', '因为'] };
      expect(failureDetail(r)).assertEqual('a; 因为');
    });

    it('generation without models returns a result (never throws) for non-English input', 0, async () => {
      for (const text of NON_ENGLISH) {
        let threw = '';
        let r: GenerateResult | undefined = undefined;
        try {
          r = await generateCapsuleWith(text, []);
        } catch (e) {
          threw = `${text}: ${(e as Error).message}`;
        }
        expect(threw).assertEqual('');
        expect(r !== undefined).assertTrue();
        if (r !== undefined && r.ok) {
          expect((r.capsule?.id ?? '').length > 0).assertTrue();
          expect((r.capsule?.name ?? '').length > 0).assertTrue();
        }
      }
    });
  });
}
