import { describe, it, expect } from '@ohos/hypium';
import { buildStageIndex, buildStageText } from '../main/ets/pages/BuildStages';

export default function buildStagesTest() {
  describe('T3-28 build step line', () => {
    it('names each stage, with the provider or the phone for the model step', 0, () => {
      expect(buildStageText('reading', '')).assertEqual('Reading your request');
      expect(buildStageText('templates', 'Claude')).assertEqual('Checking built-in templates');
      expect(buildStageText('model', 'Claude')).assertEqual('Asking Claude…');
      expect(buildStageText('model', 'Mistral (EU)')).assertEqual('Asking Mistral (EU)…');
      expect(buildStageText('model', '')).assertEqual('Thinking on your phone…');
      expect(buildStageText('checking', '')).assertEqual("Checking it's safe");
      expect(buildStageText('ready', '')).assertEqual('Ready');
    });

    it('orders the stages', 0, () => {
      expect(buildStageIndex('reading')).assertEqual(0);
      expect(buildStageIndex('model')).assertEqual(2);
      expect(buildStageIndex('ready')).assertEqual(4);
    });
  });
}
