import { describe, it, expect } from '@ohos/hypium';
import { buildStageIndex, buildStageText, stageFromCore, StageUpdate } from '../main/ets/pages/BuildStages';
import { Flags } from '../main/ets/theme/Flags';

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

    it('maps core stage events onto the step line (T3-32)', 0, () => {
      const at = (name: string, provider?: string): string => {
        const u: StageUpdate | null = stageFromCore(name, provider);
        return u === null ? 'null' : `${u.stage}/${u.cloud}`;
      };
      expect(at('cache')).assertEqual('reading/');
      expect(at('rules')).assertEqual('reading/');
      expect(at('template')).assertEqual('templates/');
      expect(at('marketplace')).assertEqual('templates/');
      expect(at('on-device')).assertEqual('model/');
      expect(at('cloud', 'anthropic')).assertEqual('model/Claude');
      expect(at('cloud', 'mistral')).assertEqual(Flags.CLOUD_CLAUDE_ONLY ? 'model/cloud AI' : 'model/Mistral (EU)');
      expect(at('validating')).assertEqual('checking/');
      expect(at('retrying')).assertEqual('checking/');
      expect(at('done')).assertEqual('ready/');
      expect(at('failed')).assertEqual('null');
      const u = stageFromCore('cloud', 'openai') as StageUpdate;
      expect(buildStageText(u.stage, u.cloud)).assertEqual('Asking OpenAI…');
    });

    it('orders the stages', 0, () => {
      expect(buildStageIndex('reading')).assertEqual(0);
      expect(buildStageIndex('model')).assertEqual(2);
      expect(buildStageIndex('ready')).assertEqual(4);
    });
  });
}
