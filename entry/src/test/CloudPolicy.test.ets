import { describe, it, expect } from '@ohos/hypium';
import { allowsNonEu, CLOUD_CLAUDE_ONLY, readyMessage, usableConfigs } from '../main/ets/core/CloudPolicy';
import { ModelConfig, parseModelConfigs } from '../main/ets/core/ModelProvider';

const BOTH: string = '{"default":"mistral","providers":{"mistral":{"apiKey":"m"},"anthropic":{"apiKey":"a"}}}';

export default function cloudPolicyTest() {
  describe('Claude is the only cloud provider (T4-31)', () => {
    it('keeps only the anthropic entry, even when Mistral is the config default', 0, () => {
      expect(parseModelConfigs(BOTH).configs.length).assertEqual(2);
      expect(CLOUD_CLAUDE_ONLY).assertTrue();
      const configs = parseModelConfigs(BOTH).configs;
      expect(usableConfigs(configs, true).map((c: ModelConfig) => c.provider as string).join()).assertEqual('anthropic');
      expect(usableConfigs(configs, false).length).assertEqual(2); // flag off: the old provider choice
      const mistralOnly = parseModelConfigs('{"providers":{"mistral":{"apiKey":"m"}},"default":"mistral"}').configs;
      expect(usableConfigs(mistralOnly, true).length).assertEqual(0); // -> "AI fallback not configured."
    });

    it('the notice is the consent: non-EU allowed; status never says Mistral or EU cloud', 0, () => {
      expect(allowsNonEu(false, true)).assertTrue();
      expect(allowsNonEu(undefined, false)).assertFalse();
      const msg = readyMessage(['anthropic'], true);
      expect(msg).assertEqual('Cloud AI ready: Claude.');
      expect(msg.includes('Mistral') || msg.includes('EU')).assertFalse();
    });
  });
}
