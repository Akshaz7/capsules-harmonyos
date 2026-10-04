/**
 * T3-28: the live step line shown while a capsule is built. Pure, so it is unit-tested. Until core reports
 * stages (T4-25 GenerateOptions.onStage) Index moves the stage from what it already knows.
 */
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
