/**
 * T3-28: the live step line shown while a capsule is built. Pure, so it is unit-tested. Until core reports
 * stages (T4-25 GenerateOptions.onStage) Index moves the stage from what it already knows.
 */
import { Flags } from '../theme/Flags';

export type BuildStage = 'reading' | 'templates' | 'model' | 'checking' | 'ready';

export const BUILD_STAGES: BuildStage[] = ['reading', 'templates', 'model', 'checking', 'ready'];

/** `cloudName` is the provider as users know it ("Claude", "Mistral (EU)"); '' means the phone's own model. */
export function buildStageText(stage: BuildStage, cloudName: string): string {
  switch (stage) {
    case 'reading':
      return 'Reading your request';
    case 'templates':
      return 'Checking built-in templates';
    case 'model':
      return cloudName.length > 0 ? `Asking ${cloudName}…` : 'Thinking on your phone…';
    case 'checking':
      return "Checking it's safe";
    default:
      return 'Ready';
  }
}

/** 0-based position of a stage on the step line. */
export function buildStageIndex(stage: BuildStage): number {
  return BUILD_STAGES.indexOf(stage);
}

/** One step-line update from a core stage event (T4-25 GenerateOptions.onStage). */
export interface StageUpdate {
  stage: BuildStage;
  /** The provider as users know it for the model step ("Claude"); '' for the phone's own model. */
  cloud: string;
}

/** "anthropic" -> "Claude", the way Settings names it. */
export function providerDisplayName(provider: string): string {
  switch (provider) {
    case 'anthropic':
      return 'Claude';
    case 'openai':
      return 'OpenAI';
    case 'mistral':
      return Flags.CLOUD_CLAUDE_ONLY ? 'cloud AI' : 'Mistral (EU)';
    default:
      return 'cloud AI';
  }
}

/**
 * T3-32: core's stage names on the five-step line. 'failed' returns null: the step line stays where it was
 * and the failure card takes over.
 */
export function stageFromCore(name: string, provider?: string): StageUpdate | null {
  switch (name) {
    case 'cache':
    case 'rules':
      return { stage: 'reading', cloud: '' };
    case 'template':
    case 'marketplace':
      return { stage: 'templates', cloud: '' };
    case 'on-device':
      return { stage: 'model', cloud: '' };
    case 'cloud':
      return { stage: 'model', cloud: providerDisplayName(provider ?? '') };
    case 'validating':
    case 'retrying':
      return { stage: 'checking', cloud: '' };
    case 'done':
      return { stage: 'ready', cloud: '' };
    default:
      return null;
  }
}
