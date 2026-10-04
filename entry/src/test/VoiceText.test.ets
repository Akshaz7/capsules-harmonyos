import { describe, it, expect } from '@ohos/hypium';
import {
  cleanTranscript, MIC_OFF, VOICE_NOTHING_HEARD, VOICE_UNAVAILABLE, voiceErrorMessage
} from '../main/ets/core/providers/VoiceText';

export default function voiceTextTest() {
  describe('voiceErrorMessage', () => {
    it('nothing heard stays nothing heard', 0, () => {
      expect(voiceErrorMessage(new Error(VOICE_NOTHING_HEARD))).assertEqual(VOICE_NOTHING_HEARD);
    });
    it('engine errors (with a code) become unavailable', 0, () => {
      expect(voiceErrorMessage(new Error(`${VOICE_UNAVAILABLE} (1002200001)`))).assertEqual(VOICE_UNAVAILABLE);
    });
    it('permission problems become the Settings hint', 0, () => {
      expect(voiceErrorMessage(MIC_OFF)).assertEqual(MIC_OFF);
      expect(voiceErrorMessage(new Error('Permission denied'))).assertEqual(MIC_OFF);
    });
    it('unknown or missing errors become unavailable', 0, () => {
      expect(voiceErrorMessage(new Error('boom'))).assertEqual(VOICE_UNAVAILABLE);
      expect(voiceErrorMessage(undefined)).assertEqual(VOICE_UNAVAILABLE);
    });
  });

  describe('cleanTranscript', () => {
    it('turns number words into digits and drops the Chinese full stop', 0, () => {
      expect(cleanTranscript('Pasta timers nine minutes for pasta and fifteen for the sauce。'))
        .assertEqual('Pasta timers 9 minutes for pasta and 15 for the sauce');
    });
    it('joins compound numbers', 0, () => {
      expect(cleanTranscript('A twenty five minute focus timer')).assertEqual('A 25 minute focus timer');
      expect(cleanTranscript('split a hundred euros')).assertEqual('Split 100 euros');
    });
    it('capitalises I and the first letter, keeps commas', 0, () => {
      expect(cleanTranscript('count the glasses of water i drink today，please。'))
        .assertEqual('Count the glasses of water I drink today, please');
    });
    it('leaves words that only contain number words alone', 0, () => {
      expect(cleanTranscript('Someone at the station')).assertEqual('Someone at the station');
    });
    it('empty stays empty', 0, () => {
      expect(cleanTranscript('  。 ')).assertEqual('');
    });
  });
}
