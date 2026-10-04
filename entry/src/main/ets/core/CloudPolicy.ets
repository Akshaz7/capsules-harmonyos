/**
 * Cloud policy (T4-31, Ash): Claude is the only cloud provider. Mirrors Flags.CLOUD_CLAUDE_ONLY in theme/Flags.ets
 * (core imports nothing from theme/). Provider code for Mistral/OpenAI stays; only the config picks Claude.
 */
import { ModelConfig } from './ModelProvider';

export const CLOUD_CLAUDE_ONLY: boolean = true;

/** The cloud providers the app may use from config.local.json: with Claude only, just the anthropic entry. */
export function usableConfigs(configs: ModelConfig[], claudeOnly: boolean): ModelConfig[] {
  return claudeOnly ? configs.filter((c: ModelConfig) => c.provider === 'anthropic' && c.apiKey.length > 0) : configs;
}

/**
 * Whether a non-EU provider may be used. With Claude only, the provider notice (which names Claude and says it
 * may be outside the EU) is the consent, so the separate non-EU setting no longer gates it.
 */
export function allowsNonEu(setting: boolean | undefined, claudeOnly: boolean): boolean {
  return claudeOnly || setting === true;
}

/** The status line once the cloud is configured; never says "Mistral" or "EU cloud" with Claude only. */
export function readyMessage(providers: string[], claudeOnly: boolean): string {
  if (claudeOnly) {
    return 'Cloud AI ready: Claude.';
  }
  return `Cloud AI ready: ${providers.join(', ')}.`;
}
